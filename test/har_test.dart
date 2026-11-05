import 'dart:convert';
import 'dart:io';

import 'package:har_budget_audit/har_budget_audit.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('hand-calculated fixture totals and two-sample nearest ranks', () {
    final summary = analyzeHarBytes(
      File('examples/site.har').readAsBytesSync(),
    );
    expect(summary.requests, 3);
    expect(summary.knownResponseBytes, 420);
    expect(summary.unknownResponseEntries, 0);
    expect(summary.origins.keys, [
      'https://app.example.test',
      'https://cdn.example.test',
    ]);
    final app = summary.origins['https://app.example.test']!;
    expect(app.requests, 2);
    expect(app.knownResponseBytes, 350);
    expect(app.p50Ms, 10);
    expect(app.p95Ms, 30);
    final cdn = summary.origins['https://cdn.example.test']!;
    expect(cdn.p50Ms, 50);
    expect(cdn.p95Ms, 50);
  });

  test('nearest rank has no interpolation and uses ceil at 20/21 samples', () {
    final twenty = analyzeHarBytes(
      harBytes([for (var i = 20; i >= 1; i--) sampleEntry(time: i)]),
    ).origins.values.single;
    expect(twenty.p50Ms, 10);
    expect(twenty.p95Ms, 19);
    final twentyOne = analyzeHarBytes(
      harBytes([for (var i = 21; i >= 1; i--) sampleEntry(time: i)]),
    ).origins.values.single;
    expect(twentyOne.p50Ms, 11);
    expect(twentyOne.p95Ms, 20);
  });

  test(
    'Uri.origin grouping normalizes case/default ports; preserves others',
    () {
      final urls = [
        'HTTP://EXAMPLE.TEST:80/a',
        'http://example.test/b',
        'http://example.test:8080/a',
        'HTTPS://EXAMPLE.TEST:443/a',
        'https://example.test/b',
        'https://example.test:8443/a',
        'http://[2001:DB8::1]:80/a',
        'http://[2001:db8::1]/b',
        'https://[2001:DB8::1]:443/a',
        'https://[2001:db8::1]:8443/a',
      ];
      final summary = analyzeHarBytes(
        harBytes([for (final url in urls) sampleEntry(url: url)]),
      );
      expect(
        summary.origins.map((key, value) => MapEntry(key, value.requests)),
        {
          'http://example.test': 2,
          'http://example.test:8080': 1,
          'https://example.test': 2,
          'https://example.test:8443': 1,
          'http://[2001:db8::1]': 2,
          'https://[2001:db8::1]': 1,
          'https://[2001:db8::1]:8443': 1,
        },
      );
    },
  );

  test(
    'sensitive metadata and all non-origin URL components never survive',
    () {
      const url =
          'https://user-sentinel:password-sentinel@EXAMPLE.TEST:443/'
          'path-sentinel?token=query-sentinel#fragment-sentinel';
      final entry = sampleEntry(url: url);
      entry['request'] = {
        'url': url,
        'headers': [
          {'name': 'Cookie', 'value': 'cookie-sentinel'},
        ],
        'cookies': [
          {'name': 'session', 'value': 'cookie-value-sentinel'},
        ],
        'postData': {'text': 'body-sentinel'},
      };
      entry['response'] = {
        'bodySize': 100,
        'headersSize': 20,
        'content': {'size': 999999, 'text': 'content-sentinel'},
        'headers': [
          {'name': 'Set-Cookie', 'value': 'response-sentinel'},
        ],
      };
      final summary = analyzeHarBytes(harBytes([entry]));
      final report = audit(
        summary,
        budgetFor({
          'https://example.test': {'max_known_response_bytes': 120},
        }),
      );
      expect(summary.knownResponseBytes, 120);
      for (final text in [report.toJsonString(), report.toMarkdown()]) {
        expect(text, contains('https://example.test'));
        expect(text, isNot(contains('sentinel')));
        expect(text, isNot(contains(url)));
      }
    },
  );

  test('malformed/unsupported URLs fail with index only, never URL text', () {
    final urls = [
      '',
      'relative/path?secret-sentinel',
      '//example.test/secret-sentinel',
      'ftp://example.test/secret-sentinel',
      'https:///secret-sentinel',
      'https://:443/secret-sentinel',
      'https://bad host/secret-sentinel',
      'https://-bad.test/secret-sentinel',
      'https://bad_.test/secret-sentinel',
      'https://example.test:/secret-sentinel',
      'https://example.test:65536/secret-sentinel',
      'https://example.test:-1/secret-sentinel',
      'https://example.test:abc/secret-sentinel',
      'https://[not-ip]/secret-sentinel',
      'https://::1/secret-sentinel',
      'https://[fe80::1%25zone]/secret-sentinel',
      'https://999.1.1.1/secret-sentinel',
      'https://${'9' * 63}.1.1.1/secret-sentinel',
      'https://%65xample.test/secret-sentinel',
      'https://example.test\\evil/secret-sentinel',
      'https://example.test/\nsecret-sentinel',
    ];
    for (final url in urls) {
      try {
        analyzeHarBytes(harBytes([sampleEntry(), sampleEntry(url: url)]));
        fail('URL case should have failed');
      } on AuditException catch (error) {
        expect(error.code, 'invalid_url');
        expect(error.entryIndex, 1);
        expect(error.toString(), 'audit: entry[1]: invalid_url');
        expect(error.toString(), isNot(contains('sentinel')));
      }
    }
  });

  test('zero and either unknown size; content.size is not a fallback', () {
    final unknown = sampleEntry(body: -1, headers: 20);
    unknown['response'] = {
      'bodySize': -1,
      'headersSize': 20,
      'content': {'size': 999999},
    };
    final summary = analyzeHarBytes(
      harBytes([
        sampleEntry(body: 0, headers: 0, time: 0),
        unknown,
        sampleEntry(body: 50, headers: -1),
        sampleEntry(body: -1, headers: -1),
        sampleEntry(body: 2, headers: 3),
      ]),
    );
    expect(summary.knownResponseBytes, 5);
    expect(summary.unknownResponseEntries, 3);
    expect(summary.requests, 5);
  });

  test(
    'invalid sizes include fractional, boolean, null and unsafe integers',
    () {
      for (final value in <Object?>[
        -2,
        0.5,
        1.0,
        true,
        null,
        AuditLimits.maxSafeInteger + 1,
      ]) {
        for (final bodySide in [true, false]) {
          expect(
            () => analyzeHarBytes(
              harBytes([
                sampleEntry(
                  body: bodySide ? value : -1,
                  headers: bodySide ? -1 : value,
                ),
              ]),
            ),
            failsCode('invalid_response_size', index: 0),
          );
        }
      }
      expect(
        () => analyzeHarBytes(
          utf8.encode(
            '{"log":{"version":"1.2","entries":[{"request":{"url":'
            '"https://example.test"},"time":0,"response":{"bodySize":'
            '18446744073709551617,"headersSize":0}}]}}',
          ),
        ),
        failsCode('invalid_response_size', index: 0),
      );
    },
  );

  test('safe integer boundary and pair/per-origin/global overflow', () {
    final safe = AuditLimits.maxSafeInteger;
    expect(
      analyzeHarBytes(harBytes([sampleEntry(body: safe, headers: 0)]))
          .knownResponseBytes,
      safe,
    );
    expect(
      () => analyzeHarBytes(harBytes([sampleEntry(body: safe, headers: 1)])),
      failsCode('integer_overflow', index: 0),
    );
    expect(
      () => analyzeHarBytes(
        harBytes([
          sampleEntry(body: safe, headers: 0),
          sampleEntry(body: 1, headers: 0),
        ]),
      ),
      failsCode('integer_overflow', index: 1),
    );
    expect(
      () => analyzeHarBytes(
        harBytes([
          sampleEntry(body: safe, headers: 0),
          sampleEntry(url: 'https://other.test', body: 1, headers: 0),
        ]),
      ),
      failsCode('integer_overflow', index: 1),
    );
  });

  test('missing fields and nonfinite/negative/boolean times are rejected', () {
    for (final value in <Object?>[-1, true, null, '10']) {
      expect(
        () => analyzeHarBytes(harBytes([sampleEntry(time: value)])),
        failsCode('invalid_time', index: 0),
      );
    }
    for (final literal in ['1e400', '-1e400', 'NaN', 'Infinity']) {
      final text = jsonEncode({
        'log': {
          'version': '1.2',
          'entries': [sampleEntry(time: 'REPLACE')],
        },
      }).replaceFirst('"REPLACE"', literal);
      expect(
        () => analyzeHarBytes(utf8.encode(text)),
        throwsA(isA<AuditException>()),
      );
    }
    for (final field in ['time', 'request', 'response']) {
      final entry = sampleEntry()..remove(field);
      expect(
        () => analyzeHarBytes(harBytes([entry])),
        throwsA(isA<AuditException>()),
      );
    }
    final responseMissingSize = sampleEntry();
    responseMissingSize['response'] = {'bodySize': 0};
    expect(
      () => analyzeHarBytes(harBytes([responseMissingSize])),
      failsCode('invalid_response_size', index: 0),
    );
    expect(
      () => analyzeHarBytes(harBytes([null])),
      failsCode('invalid_entry', index: 0),
    );
    expect(
      () => analyzeHarBytes(
        encode({
          'log': {'entries': <Object?>[]},
        }),
      ),
      failsCode('invalid_har_version'),
    );
    expect(
      () => analyzeHarBytes(
        encode({
          'log': {'version': '1.1', 'entries': <Object?>[]},
        }),
      ),
      failsCode('invalid_har_version'),
    );
    expect(
      () => analyzeHarBytes(
        encode({
          'log': {'version': '1.2'},
        }),
      ),
      failsCode('invalid_entries'),
    );
  });

  test('empty exports and immutable summaries', () {
    final summary = analyzeHarBytes(harBytes([]));
    expect(summary.requests, 0);
    expect(summary.knownResponseBytes, 0);
    expect(summary.origins, isEmpty);
    expect(
      () => summary.origins['x'] = OriginMetrics.empty,
      throwsUnsupportedError,
    );
  });
}
