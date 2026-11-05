import 'dart:convert';

import 'budget.dart';
import 'har.dart';

class _Check {
  final String dimension;
  final Object? threshold;
  final String status;
  final String reason;

  const _Check(this.dimension, this.threshold, this.status, this.reason);

  Map<String, Object?> toJson() => {
    'dimension': dimension,
    'threshold': threshold,
    'status': status,
    'reason': reason,
  };
}

class _Row {
  final String origin;
  final OriginMetrics metrics;
  final OriginBudget? budget;
  final List<_Check> checks;

  _Row(this.origin, this.metrics, this.budget, List<_Check> checks)
    : checks = List.unmodifiable(checks);

  String get status => _combine(checks.map((check) => check.status));

  Map<String, Object?> toJson() => {
    'origin': origin,
    'status': status,
    'metrics': metrics.toJson(),
    'thresholds': budget?.toJson() ?? <String, Object?>{},
    'checks': checks.map((check) => check.toJson()).toList(),
  };
}

String _combine(Iterable<String> statuses) {
  var result = 'passed';
  for (final status in statuses) {
    if (status == 'exceeded') return 'exceeded';
    if (status == 'indeterminate') result = 'indeterminate';
  }
  return result;
}

class AuditReport {
  final HarSummary _summary;
  final List<_Row> _rows;

  AuditReport._(this._summary, List<_Row> rows)
    : _rows = List.unmodifiable(rows);

  String get status => _combine(_rows.map((row) => row.status));

  int get exitCode => switch (status) {
    'passed' => 0,
    'exceeded' => 1,
    _ => 3,
  };

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'status': status,
    'units': {'requests': 'count', 'response_bytes': 'bytes', 'latency': 'ms'},
    'totals': {
      'requests': _summary.requests,
      'known_response_bytes': _summary.knownResponseBytes,
      'unknown_response_entries': _summary.unknownResponseEntries,
      'observed_origins': _summary.origins.length,
    },
    'origins': _rows.map((row) => row.toJson()).toList(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('# HAR Budget Audit')
      ..writeln()
      ..writeln('Status: **$status**')
      ..writeln()
      ..writeln(
        'Requests: ${_summary.requests} (count); known response bytes: '
        '${_summary.knownResponseBytes} (bytes); unknown response entries: '
        '${_summary.unknownResponseEntries} (count); observed origins: '
        '${_summary.origins.length} (count).',
      );
    for (final row in _rows) {
      final m = row.metrics;
      out
        ..writeln()
        ..writeln('## `${row.origin}`')
        ..writeln()
        ..writeln('Status: **${row.status}**')
        ..writeln()
        ..writeln('| Metric | Value | Unit |')
        ..writeln('| --- | ---: | --- |')
        ..writeln('| requests | ${m.requests} | count |')
        ..writeln('| known_response_bytes | ${m.knownResponseBytes} | bytes |')
        ..writeln(
          '| unknown_response_entries | ${m.unknownResponseEntries} | count |',
        )
        ..writeln('| p50_ms | ${m.p50Ms ?? "n/a"} | ms |')
        ..writeln('| p95_ms | ${m.p95Ms ?? "n/a"} | ms |')
        ..writeln()
        ..writeln('| Dimension | Threshold | Status | Reason |')
        ..writeln('| --- | ---: | --- | --- |');
      for (final check in row.checks) {
        out.writeln(
          '| ${check.dimension} | ${check.threshold ?? "n/a"} | '
          '${check.status} | ${check.reason} |',
        );
      }
    }
    return out.toString().trimRight();
  }
}

AuditReport audit(HarSummary summary, Budget budget) {
  final names = {...summary.origins.keys, ...budget.origins.keys}.toList()
    ..sort();
  final rows = <_Row>[];
  for (final origin in names) {
    final metrics = summary.origins[origin] ?? OriginMetrics.empty;
    final rule = budget.origins[origin];
    final checks = <_Check>[];
    if (rule == null) {
      checks.add(
        const _Check('coverage', null, 'indeterminate', 'no_budget_rule'),
      );
    } else {
      final requests = rule.maxRequests;
      if (requests != null) {
        checks.add(_numeric('max_requests', metrics.requests, requests));
      }
      final bytes = rule.maxKnownResponseBytes;
      if (bytes != null) {
        if (metrics.knownResponseBytes > bytes) {
          checks.add(
            _Check(
              'max_known_response_bytes',
              bytes,
              'exceeded',
              'limit_exceeded',
            ),
          );
        } else if (metrics.unknownResponseEntries > 0) {
          checks.add(
            _Check(
              'max_known_response_bytes',
              bytes,
              'indeterminate',
              'unknown_response_bytes',
            ),
          );
        } else {
          checks.add(
            _Check('max_known_response_bytes', bytes, 'passed', 'within_limit'),
          );
        }
      }
      final p95 = rule.maxP95Ms;
      if (p95 != null) {
        if (metrics.p95Ms == null) {
          checks.add(_Check('max_p95_ms', p95, 'passed', 'no_requests'));
        } else {
          checks.add(_numeric('max_p95_ms', metrics.p95Ms!, p95));
        }
      }
    }
    rows.add(_Row(origin, metrics, rule, checks));
  }
  return AuditReport._(summary, rows);
}

_Check _numeric(String dimension, num value, num threshold) => value > threshold
    ? _Check(dimension, threshold, 'exceeded', 'limit_exceeded')
    : _Check(dimension, threshold, 'passed', 'within_limit');
