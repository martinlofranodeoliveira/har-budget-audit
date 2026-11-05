/// A sanitized diagnostic. Input values and filesystem paths are never included.
class AuditException implements Exception {
  final String code;
  final int? entryIndex;

  const AuditException(this.code, {this.entryIndex});

  @override
  String toString() =>
      entryIndex == null ? 'audit: $code' : 'audit: entry[$entryIndex]: $code';
}

abstract final class AuditLimits {
  static const int inputBytes = 8 * 1024 * 1024;
  static const int entries = 20000;
  static const int origins = 1000;
  static const int urlCodeUnits = 8192;
  static const int jsonDepth = 64;
  static const int jsonValues = 500000;
  static const int maxSafeInteger = 9007199254740991;
}

Never reject(String code, {int? entryIndex}) =>
    throw AuditException(code, entryIndex: entryIndex);

int checkedAdd(int a, int b, {int? entryIndex}) {
  if (b > AuditLimits.maxSafeInteger - a) {
    reject('integer_overflow', entryIndex: entryIndex);
  }
  return a + b;
}
