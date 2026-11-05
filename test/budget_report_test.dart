import 'dart:convert';
import 'dart:io';

import 'package:har_budget_audit/har_budget_audit.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('fixture equality passes every explicit threshold', () {
    final report = audit(
      analyzeHarBytes(File('examples/site.har').readAsBytesSync()),
      parseBudgetBytes(File('examples/budgets.json').readAsBytesSync()),
    );
    expect(report.status, 'passed');
    expect(report.exitCode, 0);
    expect(report.toJsonString(), contains('"threshold": 350'));
    expect(
      report.toMarkdown(),
      contains('| max_known_response_bytes | 350 | passed | within_limit |'),
    );
  });

  test('unknown bytes cannot pass a byte threshold, including exact known equality', () {
    final summary = analyzeHarBytes(
      harBytes([sampleEntry(body: 100, headers: 0), sampleEntry(body: -1)]),
    );
    for (final limit in [100, 1000]) {
      final report = audit(
        summary,
        budgetFor({
          'https://example.test': {'max_known_response_bytes': limit},
        }),
      );
      expect(report.status, 'indeterminate');
      expect(report.exitCode, 3);
      expect(report.toJsonString(), contains('unknown_response_bytes'));
    }
    final exceeded = audit(
      summary,
      budgetFor({
        'https://example.test': {'max_known_response_bytes': 99},
      }),
    );
    expect(exceeded.status, 'exceeded');
    expect(exceeded.exitCode, 1);
    expect(exceeded.toJsonString(), contains('limit_exceeded'));
  });

  test('unknown sizes do not invalidate duration/request-only rules', () {
    final summary = analyzeHarBytes(
      harBytes([sampleEntry(body: -1, time: 7.5)]),
    );
    final report = audit(
      summary,
      budgetFor({
        'https://example.test': {'max_requests': 1, 'max_p95_ms': 7.5},
      }),
    );
    expect(report.status, 'passed');
    expect(report.exitCode, 0);
  });

  test(
    'conclusive failure beats unknown bytes within an origin and globally',
    () {
      final summary = analyzeHarBytes(
        harBytes([
          sampleEntry(body: -1, time: 100),
          sampleEntry(url: 'https://other.test', body: -1),
        ]),
      );
      final report = audit(
        summary,
        budgetFor({
          'https://example.test': {
            'max_known_response_bytes': 0,
            'max_p95_ms': 99,
          },
          'https://other.test': {'max_known_response_bytes': 0},
        }),
      );
      expect(report.status, 'exceeded');
      expect(report.exitCode, 1);
      expect(report.toJsonString(), contains('unknown_response_bytes'));
      expect(report.toJsonString(), contains('limit_exceeded'));
      final requestFailure = audit(
        summary,
        budgetFor({
          'https://example.test': {'max_requests': 0},
        }),
      );
      expect(requestFailure.status, 'exceeded');
      expect(requestFailure.toJsonString(), contains('no_budget_rule'));
    },
  );

  test('missing rules are indeterminate; absent configured origins have no requests', () {
    final budget = budgetFor({
      'https://configured.test': {
        'max_requests': 0,
        'max_known_response_bytes': 0,
        'max_p95_ms': 0,
      },
    });
    final empty = audit(analyzeHarBytes(harBytes([])), budget);
    expect(empty.status, 'passed');
    expect(empty.toJsonString(), contains('"p95_ms": null'));
    expect(empty.toJsonString(), contains('no_requests'));
    final unruled = audit(analyzeHarBytes(harBytes([sampleEntry()])), budget);
    expect(unruled.status, 'indeterminate');
    expect(unruled.toJsonString(), contains('no_budget_rule'));
  });

  test('JSON/Markdown share all decisions, counts, reasons and thresholds', () {
    final report = audit(
      analyzeHarBytes(
        harBytes([
          sampleEntry(body: 3, headers: 4, time: 2),
          sampleEntry(body: -1, time: 9),
        ]),
      ),
      budgetFor({
        'https://example.test': {
          'max_requests': 1,
          'max_known_response_bytes': 7,
          'max_p95_ms': 9,
        },
      }),
    );
    final data = jsonDecode(report.toJsonString()) as Map<String, dynamic>;
    final rows = data['origins'] as List<dynamic>;
    final row = rows.single as Map<String, dynamic>;
    final markdown = report.toMarkdown();
    expect(data['status'], 'exceeded');
    expect(row['status'], 'exceeded');
    expect(markdown, contains('Status: **exceeded**'));
    expect(
      markdown,
      contains(
        'Requests: 2 (count); known response bytes: 7 (bytes); unknown response entries: 1 (count)',
      ),
    );
    expect(markdown, contains('| requests | 2 | count |'));
    expect(markdown, contains('| known_response_bytes | 7 | bytes |'));
    expect(markdown, contains('| unknown_response_entries | 1 | count |'));
    expect(markdown, contains('| p50_ms | 2 | ms |'));
    expect(markdown, contains('| p95_ms | 9 | ms |'));
    for (final Object? item in row['checks'] as List<dynamic>) {
      final check = item as Map<String, dynamic>;
      expect(
        markdown,
        contains(
          '| ${check['dimension']} | ${check['threshold']} | '
          '${check['status']} | ${check['reason']} |',
        ),
      );
    }
    final fresh = report.toJson();
    fresh.clear();
    expect(report.status, 'exceeded');
    expect(report.toJsonString(), isNotEmpty);
  });

  test('stable lexical origin order is independent of entry/rule order', () {
    final first = sampleEntry(url: 'https://z.test/a');
    final second = sampleEntry(url: 'https://a.test/a');
    final rules = budgetFor({
      'https://z.test': {'max_requests': 1},
      'https://a.test': {'max_requests': 1},
    });
    final a = audit(analyzeHarBytes(harBytes([first, second])), rules);
    final b = audit(analyzeHarBytes(harBytes([second, first])), rules);
    expect(a.toJsonString(), b.toJsonString());
    expect(a.toMarkdown(), b.toMarkdown());
    expect(
      a.toJsonString().indexOf('https://a.test'),
      lessThan(a.toJsonString().indexOf('https://z.test')),
    );
  });

  test(
    'strict budget rejects typo keys, empty rules, nulls and numeric impostors',
    () {
      for (final value in <Object?>[
        null,
        true,
        -1,
        0.5,
        1.0,
        AuditLimits.maxSafeInteger + 1,
      ]) {
        for (final field in ['max_requests', 'max_known_response_bytes']) {
          expect(
            () => budgetFor({
              'https://example.test': {field: value},
            }),
            failsCode('invalid_budget_threshold'),
          );
        }
      }
      for (final value in <Object?>[null, true, -0.5, '1']) {
        expect(
          () => budgetFor({
            'https://example.test': {'max_p95_ms': value},
          }),
          failsCode('invalid_budget_threshold'),
        );
      }
      expect(
        () => budgetFor({
          'https://example.test': {'max_request': 1},
        }),
        failsCode('invalid_budget_rule'),
      );
      expect(
        () => budgetFor({'https://example.test': <String, Object?>{}}),
        failsCode('invalid_budget_rule'),
      );
      expect(
        () => budgetFor(<String, Object?>{}),
        failsCode('invalid_budget_rules'),
      );
      expect(
        () => parseBudgetBytes(
          encode({
            'version': 1,
            'origins': <String, Object?>{},
            'typo': 'secret-sentinel',
          }),
        ),
        failsCode('invalid_budget'),
      );
      expect(
        () => parseBudgetBytes(
          encode({'version': 1.0, 'origins': <String, Object?>{}}),
        ),
        failsCode('invalid_budget'),
      );
      expect(
        () => parseBudgetBytes(
          utf8.encode(
            '{"version":1,"origins":{"https://example.test":{"max_p95_ms":1e400}}}',
          ),
        ),
        throwsA(isA<AuditException>()),
      );
      final valid = budgetFor({
        'https://example.test': {'max_p95_ms': 0.25, 'max_requests': 0},
      });
      expect(valid.origins.values.single.maxP95Ms, 0.25);
      expect(() => valid.origins.clear(), throwsUnsupportedError);
    },
  );

  test('budget keys must already be canonical origins, with no URL extras', () {
    for (final key in [
      'HTTPS://EXAMPLE.TEST',
      'https://example.test:443',
      'https://example.test/',
      'https://user:password-sentinel@example.test',
      'https://example.test?query-sentinel',
      'https://example.test#fragment-sentinel',
    ]) {
      expect(
        () => budgetFor({
          key: {'max_requests': 1},
        }),
        failsCode('noncanonical_budget_origin'),
      );
    }
    expect(
      () => budgetFor({
        'file:///secret-sentinel': {'max_requests': 1},
      }),
      failsCode('invalid_budget_origin'),
    );
    expect(
      () => budgetFor({
        'https://${'9' * 63}.1.1.1': {'max_requests': 1},
      }),
      failsCode('invalid_budget_origin'),
    );
    expect(
      budgetFor({
        'http://[::1]:8080': {'max_requests': 1},
      }).origins.keys,
      ['http://[::1]:8080'],
    );
  });
}
