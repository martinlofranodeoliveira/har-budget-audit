import 'dart:convert';

import 'package:har_budget_audit/har_budget_audit.dart';
import 'package:test/test.dart';

List<int> encode(Object? value) => utf8.encode(jsonEncode(value));

Map<String, Object?> sampleEntry({
  String url = 'https://example.test/a',
  Object? time = 10,
  Object? body = 100,
  Object? headers = 20,
}) => {
  'request': {'url': url},
  'time': time,
  'response': {'bodySize': body, 'headersSize': headers},
};

List<int> harBytes(List<Object?> entries) => encode({
  'log': {'version': '1.2', 'entries': entries},
});

Budget budgetFor(Map<String, Object?> rules) =>
    parseBudgetBytes(encode({'version': 1, 'origins': rules}));

Matcher failsCode(String code, {int? index}) {
  var matcher = isA<AuditException>().having((e) => e.code, 'code', code);
  if (index != null) {
    matcher = matcher.having((e) => e.entryIndex, 'entryIndex', index);
  }
  return throwsA(matcher);
}
