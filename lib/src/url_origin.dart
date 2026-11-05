import 'error.dart';

final _scheme = RegExp(r'^https?://', caseSensitive: false);
final _digits = RegExp(r'^[0-9]+$');
final _label = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');

/// Uses Uri.origin, after restricting authorities to an unambiguous host subset.
String originOf(String raw, {required String errorCode, int? entryIndex}) {
  Never bad() => reject(errorCode, entryIndex: entryIndex);
  if (raw.isEmpty ||
      raw.length > AuditLimits.urlCodeUnits ||
      !_scheme.hasMatch(raw)) {
    bad();
  }
  for (final c in raw.codeUnits) {
    if (c <= 32 || c == 127 || c == 92) bad();
  }
  final start = raw.indexOf('://') + 3;
  var end = raw.length;
  for (final delimiter in ['/', '?', '#']) {
    final index = raw.indexOf(delimiter, start);
    if (index >= 0 && index < end) end = index;
  }
  final authority = raw.substring(start, end);
  final endpoint = authority.substring(authority.lastIndexOf('@') + 1);
  if (endpoint.isEmpty) bad();
  String host;
  String suffix;
  if (endpoint.startsWith('[')) {
    final close = endpoint.indexOf(']');
    if (close < 0) bad();
    host = endpoint.substring(1, close);
    suffix = endpoint.substring(close + 1);
    if (host.contains('%')) bad();
    try {
      Uri.parseIPv6Address(host);
    } on FormatException {
      bad();
    }
  } else {
    final colon = endpoint.indexOf(':');
    host = colon < 0 ? endpoint : endpoint.substring(0, colon);
    suffix = colon < 0 ? '' : endpoint.substring(colon);
    if (host.isEmpty || host.length > 253) bad();
    final dns = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    final labels = dns.split('.');
    if (labels.any((label) => !_label.hasMatch(label))) bad();
    if (labels.length == 4 && labels.every(_digits.hasMatch)) {
      if (labels.any((label) {
        final value = int.tryParse(label);
        return value == null || value > 255;
      }))
        bad();
    }
  }
  if (suffix.isNotEmpty) {
    if (!suffix.startsWith(':') || !_digits.hasMatch(suffix.substring(1))) {
      bad();
    }
    final port = int.tryParse(suffix.substring(1));
    if (port == null || port > 65535) bad();
  }
  try {
    final uri = Uri.parse(raw);
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      bad();
    }
    return uri.origin.toLowerCase();
  } on FormatException {
    bad();
  }
}
