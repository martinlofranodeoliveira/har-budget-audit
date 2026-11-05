import 'dart:convert';

import 'error.dart';

/// Internal shared decoder: validate resource limits before recursive decoding.
Object? decodeDocument(List<int> bytes) {
  if (bytes.length > AuditLimits.inputBytes) reject('input_too_large');
  if (bytes.any((byte) => byte < 0 || byte > 255)) reject('invalid_utf8');
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    reject('invalid_utf8');
  }
  _JsonGuard(text).check();
  try {
    return jsonDecode(text);
  } on FormatException {
    reject('invalid_json');
  }
}

// This guard is not a second data model. It limits nesting/value amplification
// and rejects duplicate decoded object keys before dart:convert builds a tree.
class _JsonGuard {
  final String text;
  int offset = 0;
  int values = 0;

  _JsonGuard(this.text);

  void check() {
    _space();
    _value(0);
    _space();
    if (offset != text.length) reject('invalid_json');
  }

  void _space() {
    while (offset < text.length) {
      final c = text.codeUnitAt(offset);
      if (c != 32 && c != 9 && c != 10 && c != 13) break;
      offset++;
    }
  }

  bool _take(int c) {
    if (offset < text.length && text.codeUnitAt(offset) == c) {
      offset++;
      return true;
    }
    return false;
  }

  void _value(int depth) {
    if (++values > AuditLimits.jsonValues) reject('json_values_limit');
    _space();
    if (offset >= text.length) reject('invalid_json');
    final c = text.codeUnitAt(offset);
    if (c == 123 || c == 91) {
      if (depth >= AuditLimits.jsonDepth) reject('json_depth_limit');
      offset++;
      _space();
      if (c == 123) {
        final keys = <String>{};
        if (_take(125)) return;
        while (true) {
          _space();
          if (offset >= text.length || text.codeUnitAt(offset) != 34) {
            reject('invalid_json');
          }
          final start = offset;
          _string();
          final String key;
          try {
            key = jsonDecode(text.substring(start, offset)) as String;
          } on FormatException {
            reject('invalid_json');
          }
          if (!keys.add(key)) reject('duplicate_json_key');
          _space();
          if (!_take(58)) reject('invalid_json');
          _value(depth + 1);
          _space();
          if (_take(125)) return;
          if (!_take(44)) reject('invalid_json');
        }
      }
      if (_take(93)) return;
      while (true) {
        _value(depth + 1);
        _space();
        if (_take(93)) return;
        if (!_take(44)) reject('invalid_json');
      }
    }
    if (c == 34) {
      _string();
      return;
    }
    final start = offset;
    while (offset < text.length) {
      final c = text.codeUnitAt(offset);
      if (c == 44 ||
          c == 93 ||
          c == 125 ||
          c == 32 ||
          c == 9 ||
          c == 10 ||
          c == 13) {
        break;
      }
      offset++;
    }
    if (offset == start) reject('invalid_json');
    // dart:convert subsequently validates scalar spelling and number syntax.
  }

  void _string() {
    offset++;
    while (offset < text.length) {
      final c = text.codeUnitAt(offset++);
      if (c == 34) return;
      if (c < 32) reject('invalid_json');
      if (c == 92) {
        if (offset >= text.length) reject('invalid_json');
        offset++;
      }
    }
    reject('invalid_json');
  }
}
