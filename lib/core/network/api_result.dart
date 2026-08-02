/// Mirrors the server envelope defined in
/// `edupulse_core/api/v1/utils.py`.
///
///   `{"ok": true,  "data": <payload>, "meta": {...}}`
///   `{"ok": false, "error": {"code": "...", "message": "...", "field": null}}`
library;

/// Error codes — keep in sync with the constants in `api/v1/utils.py`.
enum ApiErrorCode {
  notAuthenticated('NOT_AUTHENTICATED'),
  permissionDenied('PERMISSION_DENIED'),
  contentLocked('CONTENT_LOCKED'),
  attemptsExhausted('ATTEMPTS_EXHAUSTED'),
  validationError('VALIDATION_ERROR'),
  notFound('NOT_FOUND'),
  appUpgradeRequired('APP_UPGRADE_REQUIRED'),
  serverError('SERVER_ERROR'),
  network('NETWORK_ERROR'),
  unknown('UNKNOWN');

  const ApiErrorCode(this.wire);

  /// The literal string the backend sends.
  final String wire;

  static ApiErrorCode fromWire(String? value) {
    return ApiErrorCode.values.firstWhere(
      (c) => c.wire == value,
      orElse: () => ApiErrorCode.unknown,
    );
  }
}

class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.field,
    this.statusCode,
  });

  final ApiErrorCode code;
  final String message;
  final String? field;
  final int? statusCode;

  /// True when the session is gone and the app must bounce to login.
  bool get isAuthFailure => code == ApiErrorCode.notAuthenticated;

  /// True when the user hit a pedagogical gate rather than a real error —
  /// the UI should explain, not apologise.
  bool get isGate =>
      code == ApiErrorCode.contentLocked ||
      code == ApiErrorCode.attemptsExhausted;

  factory ApiException.fromEnvelope(
    Map<String, dynamic> error, {
    int? statusCode,
  }) {
    return ApiException(
      code: ApiErrorCode.fromWire(error['code'] as String?),
      message: (error['message'] as String?) ?? 'Unexpected error.',
      field: error['field'] as String?,
      statusCode: statusCode,
    );
  }

  @override
  String toString() => 'ApiException(${code.wire}): $message';
}

/// Unwrapped successful payload plus any envelope metadata.
class ApiResult<T> {
  const ApiResult({required this.data, this.meta = const {}});

  final T data;
  final Map<String, dynamic> meta;
}
