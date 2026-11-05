import 'dart:convert';

import 'package:har_budget_audit/har_budget_audit.dart';
import 'package:har_budget_audit/src/json_input.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('UTF-8 errors and JSON syntax failures are sanitized', () {
    for (final bytes in <List<int>>[
      [0xc3, 0x28],
      [256],
      [-1],
    ]) {
      expect(() => analyzeHarBytes(bytes), failsCode('invalid_utf8'));
    }
    for (final text in [
      '',
      '{',
      '[] secret-sentinel',
      '{"secret-sentinel":}',
      '{"a":"\\x"}',
      '{"a":true,}',
      '[1,]',
      '{"a":01}',
    ]) {
      expect(
        () => analyzeHarBytes(utf8.encode(text)),
        failsCode('invalid_json'),
      );
    }
  });

  test(
    'duplicate keys are rejected even when escaped or in ignored metadata',
    () {
      for (final text in [
        '{"a":1,"a":2}',
        r'{"a":1,"\u0061":2}',
        '{"log":{"version":"1.2","entries":[]},"extra":{"x":1,"x":2}}',
        '{"version":1,"origins":{"https://example.test":{"max_requests":1,"max_requests":2}}}',
      ]) {
        expect(
          () => decodeDocument(utf8.encode(text)),
          failsCode('duplicate_json_key'),
        );
      }
      expect(
        decodeDocument(utf8.encode('{"a":{"x":1},"b":{"x":2}}')),
        isA<Map<String, dynamic>>(),
      );
    },
  );

  test(
    '8 MiB includes UTF-8 encoding; exact bound accepted, next byte rejected',
    () {
      const prefix = '{"log":{"version":"1.2","entries":[]},"padding":"';
      const suffix = '"}';
      final count = AuditLimits.inputBytes - prefix.length - suffix.length;
      final text = '$prefix${List.filled(count, 'x').join()}$suffix';
      expect(utf8.encode(text).length, AuditLimits.inputBytes);
      expect(analyzeHarBytes(utf8.encode(text)).requests, 0);
      expect(
        () => analyzeHarBytes([...utf8.encode(text), 32]),
        failsCode('input_too_large'),
      );
      final multibyte =
          '$prefix${List.filled(count ~/ 2 + 1, 'é').join()}$suffix';
      expect(multibyte.length, lessThan(AuditLimits.inputBytes));
      expect(
        () => analyzeHarBytes(utf8.encode(multibyte)),
        failsCode('input_too_large'),
      );
    },
  );

  test('URL code-unit boundary accepts 8192 and rejects 8193', () {
    const prefix = 'https://example.test/';
    final url =
        '$prefix${List.filled(AuditLimits.urlCodeUnits - prefix.length, 'a').join()}';
    expect(analyzeHarBytes(harBytes([sampleEntry(url: url)])).requests, 1);
    expect(
      () => analyzeHarBytes(harBytes([sampleEntry(url: '${url}a')])),
      failsCode('url_too_long', index: 0),
    );
  });

  test('entry count boundary is enforced independently of byte size', () {
    final entries = List<Object?>.generate(
      AuditLimits.entries,
      (_) => sampleEntry(body: 0, headers: 0),
    );
    expect(analyzeHarBytes(harBytes(entries)).requests, AuditLimits.entries);
    entries.add(sampleEntry());
    expect(
      () => analyzeHarBytes(harBytes(entries)),
      failsCode('entries_limit'),
    );
  });

  test('observed-origin and configured-origin boundaries are independent', () {
    final entries = List<Object?>.generate(
      AuditLimits.origins,
      (i) => sampleEntry(url: 'https://h$i.example.test'),
    );
    expect(
      analyzeHarBytes(harBytes(entries)).origins.length,
      AuditLimits.origins,
    );
    entries.add(sampleEntry(url: 'https://overflow.example.test'));
    expect(
      () => analyzeHarBytes(harBytes(entries)),
      failsCode('origins_limit'),
    );
    final rules = <String, Object?>{
      for (var i = 0; i < AuditLimits.origins; i++)
        'https://h$i.example.test': {'max_requests': 1},
    };
    expect(budgetFor(rules).origins.length, AuditLimits.origins);
    rules['https://overflow.example.test'] = {'max_requests': 1};
    expect(() => budgetFor(rules), failsCode('budget_origins_limit'));
  });

  test(
    'JSON nesting limit counts containers and ignores brackets in strings',
    () {
      String nested(int depth) =>
          '${List.filled(depth, '[').join()}0${List.filled(depth, ']').join()}';
      expect(
        () => decodeDocument(utf8.encode(nested(AuditLimits.jsonDepth))),
        returnsNormally,
      );
      expect(
        () => decodeDocument(utf8.encode(nested(AuditLimits.jsonDepth + 1))),
        failsCode('json_depth_limit'),
      );
      expect(
        decodeDocument(encode({'text': '[{]}' * 100})),
        isA<Map<String, dynamic>>(),
      );
    },
  );

  test(
    'JSON value amplification boundary includes root but excludes object keys',
    () {
      String many(int children) => '[${List.filled(children, '0').join(',')}]';
      expect(
        (decodeDocument(
          utf8.encode(many(AuditLimits.jsonValues - 1)),
        ) as List<dynamic>).length,
        AuditLimits.jsonValues - 1,
      );
      expect(
        () => decodeDocument(utf8.encode(many(AuditLimits.jsonValues))),
        failsCode('json_values_limit'),
      );
    },
  );
}
