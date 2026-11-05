import 'dart:convert';

import 'package:har_budget_audit/har_budget_audit.dart';

/// All data is synthetic and constructed in memory; no fixture files are read.
String demoOutput(String format) {
  const origin = 'https://demo.example.test';
  Map<String, Object?> entry(int body) => {
    'request': {'url': '$origin/asset?synthetic=not-reported'},
    'time': 12.5,
    'response': {'bodySize': body, 'headersSize': 0},
  };
  final budget = parseBudgetBytes(
    utf8.encode(
      jsonEncode({
        'version': 1,
        'origins': {
          origin: {
            'max_requests': 1,
            'max_known_response_bytes': 128,
            'max_p95_ms': 12.5,
          },
        },
      }),
    ),
  );
  final cases = <Map<String, Object?>>[];
  final markdown = StringBuffer('# Offline synthetic demo\n');
  final scenarios = <String, List<Map<String, Object?>>>{
    'passing': [entry(128)],
    'violation': [entry(128), entry(128)],
    'unknown_transfer': [entry(-1)],
  };
  const expected = {
    'passing': 'passed',
    'violation': 'exceeded',
    'unknown_transfer': 'indeterminate',
  };
  for (final scenario in scenarios.entries) {
    final summary = analyzeHarBytes(
      utf8.encode(
        jsonEncode({
          'log': {'version': '1.2', 'entries': scenario.value},
        }),
      ),
    );
    final report = audit(summary, budget);
    if (report.status != expected[scenario.key]) {
      throw const AuditException('demo_expectation_failed');
    }
    cases.add({
      'name': scenario.key,
      'expected': expected[scenario.key],
      'report': report.toJson(),
    });
    markdown
      ..writeln()
      ..writeln(
        'Scenario: ${scenario.key}; expected: ${expected[scenario.key]}.',
      )
      ..writeln()
      ..writeln(report.toMarkdown());
  }
  if (format == 'json') {
    return const JsonEncoder.withIndent('  ')
        .convert({'demo_status': 'passed', 'cases': cases});
  }
  return '${markdown.toString().trimRight()}\n\nDemo expectations: passed.';
}
