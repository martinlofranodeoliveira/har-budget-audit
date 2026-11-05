import 'error.dart';
import 'json_input.dart';
import 'url_origin.dart';

class OriginMetrics {
  final int requests;
  final int knownResponseBytes;
  final int unknownResponseEntries;
  final num? p50Ms;
  final num? p95Ms;

  const OriginMetrics._(
    this.requests,
    this.knownResponseBytes,
    this.unknownResponseEntries,
    this.p50Ms,
    this.p95Ms,
  );

  static const empty = OriginMetrics._(0, 0, 0, null, null);

  Map<String, Object?> toJson() => {
    'requests': requests,
    'known_response_bytes': knownResponseBytes,
    'unknown_response_entries': unknownResponseEntries,
    'p50_ms': p50Ms,
    'p95_ms': p95Ms,
  };
}

class HarSummary {
  final Map<String, OriginMetrics> origins;
  final int requests;
  final int knownResponseBytes;
  final int unknownResponseEntries;

  HarSummary._(
    Map<String, OriginMetrics> origins,
    this.requests,
    this.knownResponseBytes,
    this.unknownResponseEntries,
  ) : origins = Map.unmodifiable(origins);
}

class _Accumulator {
  final durations = <num>[];
  int bytes = 0;
  int unknown = 0;

  OriginMetrics finish() {
    durations.sort((a, b) => a.compareTo(b));
    num rank(int percent) =>
        durations[((durations.length * percent + 99) ~/ 100) - 1];
    return OriginMetrics._(
      durations.length,
      bytes,
      unknown,
      rank(50),
      rank(95),
    );
  }
}

HarSummary analyzeHarBytes(List<int> bytes) {
  final root = decodeDocument(bytes);
  if (root is! Map<String, dynamic>) reject('invalid_har');
  final Object? log = root['log'];
  if (log is! Map<String, dynamic> || log['version'] != '1.2') {
    reject('invalid_har_version');
  }
  final Object? entries = log['entries'];
  if (entries is! List<dynamic>) reject('invalid_entries');
  if (entries.length > AuditLimits.entries) reject('entries_limit');
  final groups = <String, _Accumulator>{};
  var totalBytes = 0;
  var totalUnknown = 0;
  for (var index = 0; index < entries.length; index++) {
    final Object? entry = entries[index];
    if (entry is! Map<String, dynamic>) {
      reject('invalid_entry', entryIndex: index);
    }
    final Object? request = entry['request'];
    if (request is! Map<String, dynamic> || request['url'] is! String) {
      reject('invalid_url', entryIndex: index);
    }
    final url = request['url'] as String;
    if (url.length > AuditLimits.urlCodeUnits) {
      reject('url_too_long', entryIndex: index);
    }
    final origin = originOf(url, errorCode: 'invalid_url', entryIndex: index);
    final Object? duration = entry['time'];
    if (duration is! num || !duration.isFinite || duration < 0) {
      reject('invalid_time', entryIndex: index);
    }
    final Object? response = entry['response'];
    if (response is! Map<String, dynamic>) {
      reject('invalid_response', entryIndex: index);
    }
    final body = _size(response['bodySize'], index);
    final headers = _size(response['headersSize'], index);
    var group = groups[origin];
    if (group == null) {
      if (groups.length == AuditLimits.origins) reject('origins_limit');
      group = _Accumulator();
      groups[origin] = group;
    }
    group.durations.add(duration);
    if (body == -1 || headers == -1) {
      group.unknown++;
      totalUnknown++;
    } else {
      final known = checkedAdd(body, headers, entryIndex: index);
      group.bytes = checkedAdd(group.bytes, known, entryIndex: index);
      totalBytes = checkedAdd(totalBytes, known, entryIndex: index);
    }
  }
  final origins = <String, OriginMetrics>{};
  final names = groups.keys.toList()..sort();
  for (final name in names) {
    origins[name] = groups[name]!.finish();
  }
  return HarSummary._(origins, entries.length, totalBytes, totalUnknown);
}

int _size(Object? value, int index) {
  if (value is! int || value < -1 || value > AuditLimits.maxSafeInteger) {
    reject('invalid_response_size', entryIndex: index);
  }
  return value;
}
