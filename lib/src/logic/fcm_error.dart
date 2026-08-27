/// Structured error returned by the FCM HTTP v1 API.
///
/// Reference: https://firebase.google.com/docs/cloud-messaging/error-codes
/// FCM REST schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages
enum FcmErrorCode {
  unregistered,
  installationIdNotRegistered,
  senderIdMismatch,
  invalidArgument,
  quotaExceeded,
  unavailable,
  internal,
  thirdPartyAuthError,
  unknown,
}

/// A structured representation of an FCM HTTP v1 error.
final class FcmError {
  const FcmError({
    required this.code,
    required this.message,
    this.status,
    required this.errorCode,
    this.details,
  });

  /// HTTP status code returned by FCM.
  final int code;

  /// Human-readable FCM error message.
  final String message;

  /// Generic Google RPC status, if supplied.
  final String? status;

  /// Typed FCM-specific error classification.
  final FcmErrorCode errorCode;

  /// Structured error details retained for diagnostics and quota handling.
  final List<Map<String, dynamic>>? details;

  /// Parses a decoded FCM response body.
  static FcmError? fromResponseBody(Map<String, dynamic> body) {
    final dynamic errorValue = body['error'];
    if (errorValue is! Map<String, dynamic>) return null;

    final int httpCode = (errorValue['code'] as num?)?.toInt() ?? 0;
    final String message =
        errorValue['message'] as String? ?? 'Unknown FCM error';
    final String? status = errorValue['status'] as String?;
    // Clone details so callers can inspect diagnostics without sharing decoded
    // response state with the parser.
    final List<Map<String, dynamic>> details = <Map<String, dynamic>>[
      if (errorValue['details'] is List)
        for (final dynamic item in errorValue['details'] as List<dynamic>)
          if (item is Map<String, dynamic>) cloneMap(item),
    ];
    // FCM-specific detail codes are more precise than generic RPC statuses.
    final String? detailCode = _extractDetailErrorCode(details);

    return FcmError(
      code: httpCode,
      message: message,
      status: status,
      errorCode: detailCode == null
          ? _parseStatusCode(status)
          : _parseErrorCode(detailCode),
      details: details.isEmpty ? null : details,
    );
  }

  /// True when the error is safe to retry with backoff.
  bool get isRetryable =>
      errorCode == FcmErrorCode.quotaExceeded ||
      errorCode == FcmErrorCode.unavailable ||
      errorCode == FcmErrorCode.internal;

  /// True when a 401 likely represents a stale OAuth credential.
  bool get isOAuthAuthenticationError =>
      code == 401 && errorCode != FcmErrorCode.thirdPartyAuthError;

  /// Field-level validation details returned by `google.rpc.BadRequest`.
  /// See https://firebase.google.com/docs/cloud-messaging/error-codes#rest_error_codes_for_the_http_v1_api.
  List<Map<String, dynamic>> get fieldViolations {
    // BadRequest details are optional and may be mixed with other detail types.
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> detail
        in details ?? <Map<String, dynamic>>[]) {
      final dynamic type = detail['@type'];
      if (type is! String || !type.endsWith('google.rpc.BadRequest')) {
        continue;
      }
      final dynamic rawViolations = detail['fieldViolations'];
      if (rawViolations is List) {
        for (final dynamic violation in rawViolations) {
          if (violation is Map<String, dynamic>) {
            result.add(cloneMap(violation));
          }
        }
      }
    }
    return result;
  }

  /// Quota subjects returned by `google.rpc.QuotaFailure`.
  /// See https://firebase.google.com/docs/cloud-messaging/error-codes#quota_exceeded.
  List<String> get quotaSubjects {
    // QuotaFailure subjects identify which server-side limit was exceeded.
    final List<String> result = <String>[];
    for (final Map<String, dynamic> detail
        in details ?? <Map<String, dynamic>>[]) {
      final dynamic type = detail['@type'];
      if (type is! String || !type.endsWith('google.rpc.QuotaFailure')) {
        continue;
      }
      final dynamic rawViolations = detail['violations'];
      if (rawViolations is List) {
        for (final dynamic violation in rawViolations) {
          if (violation is Map<String, dynamic> &&
              violation['subject'] is String) {
            result.add(violation['subject'] as String);
          }
        }
      }
    }
    return result;
  }

  /// Extracts the FCM-specific detail code from `details[]`.
  static String? _extractDetailErrorCode(List<Map<String, dynamic>>? details) {
    if (details == null) return null;
    for (final Map<String, dynamic> detail in details) {
      final dynamic type = detail['@type'];
      if (type is String && type.endsWith('google.firebase.fcm.v1.FcmError')) {
        final dynamic errorCode = detail['errorCode'];
        if (errorCode is String) return errorCode;
      }
    }
    return null;
  }

  static FcmErrorCode _parseErrorCode(String code) => switch (code) {
    'UNREGISTERED' => FcmErrorCode.unregistered,
    'INSTALLATION_ID_NOT_REGISTERED' =>
      FcmErrorCode.installationIdNotRegistered,
    'SENDER_ID_MISMATCH' => FcmErrorCode.senderIdMismatch,
    'INVALID_ARGUMENT' => FcmErrorCode.invalidArgument,
    'QUOTA_EXCEEDED' => FcmErrorCode.quotaExceeded,
    'UNAVAILABLE' => FcmErrorCode.unavailable,
    'INTERNAL' => FcmErrorCode.internal,
    'THIRD_PARTY_AUTH_ERROR' ||
    'APNS_AUTH_ERROR' => FcmErrorCode.thirdPartyAuthError,
    _ => FcmErrorCode.unknown,
  };

  // Generic statuses are intentionally conservative: they do not prove a
  // registration token is invalid.
  static FcmErrorCode _parseStatusCode(String? status) => switch (status) {
    'UNREGISTERED' => FcmErrorCode.unregistered,
    'INSTALLATION_ID_NOT_REGISTERED' =>
      FcmErrorCode.installationIdNotRegistered,
    'SENDER_ID_MISMATCH' => FcmErrorCode.senderIdMismatch,
    'INVALID_ARGUMENT' => FcmErrorCode.invalidArgument,
    'QUOTA_EXCEEDED' || 'RESOURCE_EXHAUSTED' => FcmErrorCode.quotaExceeded,
    'UNAVAILABLE' => FcmErrorCode.unavailable,
    'INTERNAL' => FcmErrorCode.internal,
    'THIRD_PARTY_AUTH_ERROR' ||
    'APNS_AUTH_ERROR' => FcmErrorCode.thirdPartyAuthError,
    _ => FcmErrorCode.unknown,
  };

  @override
  String toString() =>
      'FcmError{code: $code, status: $status, errorCode: $errorCode, '
      'message: $message, details: $details}';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FcmError &&
        other.code == code &&
        other.message == message &&
        other.status == status &&
        other.errorCode == errorCode;
  }

  @override
  int get hashCode => Object.hash(code, message, status, errorCode);
}

Map<String, dynamic> cloneMap(Map<String, dynamic> source) => <String, dynamic>{
  for (final MapEntry<String, dynamic> entry in source.entries)
    entry.key: entry.value,
};
