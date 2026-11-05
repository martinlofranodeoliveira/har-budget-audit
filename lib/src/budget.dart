import 'error.dart';
import 'json_input.dart';
import 'url_origin.dart';

class OriginBudget {
  final int? maxRequests;
  final int? maxKnownResponseBytes;
  final num? maxP95Ms;

  const OriginBudget._(
    this.maxRequests,
    this.maxKnownResponseBytes,
    this.maxP95Ms,
  );

  Map<String, Object?> toJson() => {
    if (maxRequests != null) 'max_requests': maxRequests,
    if (maxKnownResponseBytes != null)
      'max_known_response_bytes': maxKnownResponseBytes,
    if (maxP95Ms != null) 'max_p95_ms': maxP95Ms,
  };
}

class Budget {
  final Map<String, OriginBudget> origins;

  Budget._(Map<String, OriginBudget> origins)
    : origins = Map.unmodifiable(origins);
}

Budget parseBudgetBytes(List<int> bytes) {
  final root = decodeDocument(bytes);
  if (root is! Map<String, dynamic> ||
      root.keys.any((key) => key != 'version' && key != 'origins') ||
      root['version'] is! int ||
      root['version'] != 1) {
    reject('invalid_budget');
  }
  final Object? rules = root['origins'];
  if (rules is! Map<String, dynamic> || rules.isEmpty) {
    reject('invalid_budget_rules');
  }
  if (rules.length > AuditLimits.origins) reject('budget_origins_limit');
  final parsed = <String, OriginBudget>{};
  final names = rules.keys.toList()..sort();
  for (final name in names) {
    final canonical = originOf(name, errorCode: 'invalid_budget_origin');
    if (name != canonical) reject('noncanonical_budget_origin');
    final Object? rule = rules[name];
    if (rule is! Map<String, dynamic> ||
        rule.isEmpty ||
        rule.keys.any(
          (key) =>
              key != 'max_requests' &&
              key != 'max_known_response_bytes' &&
              key != 'max_p95_ms',
        )) {
      reject('invalid_budget_rule');
    }
    int? integer(String key) {
      if (!rule.containsKey(key)) return null;
      final Object? value = rule[key];
      if (value is! int || value < 0 || value > AuditLimits.maxSafeInteger) {
        reject('invalid_budget_threshold');
      }
      return value;
    }

    final requests = integer('max_requests');
    final transferred = integer('max_known_response_bytes');
    num? p95;
    if (rule.containsKey('max_p95_ms')) {
      final Object? value = rule['max_p95_ms'];
      if (value is! num || !value.isFinite || value < 0) {
        reject('invalid_budget_threshold');
      }
      p95 = value;
    }
    parsed[name] = OriginBudget._(requests, transferred, p95);
  }
  return Budget._(parsed);
}
