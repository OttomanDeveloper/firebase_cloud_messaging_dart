// Structured FCM API error representation.
//
// When FCM returns a non-200 response, the body contains a JSON error object.
// This file exposes [FcmError] and [FcmErrorCode] so callers can react to
// specific failure reasons without string-matching raw error messages.

// ---------------------------------------------------------------------------
// FCM error codes (HTTP v1 API)
// See: https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode
// ---------------------------------------------------------------------------

/// Known error codes returned by the FCM HTTP v1 API.
///
/// Map an unknown code to [FcmErrorCode.unknown] so callers always get a typed
/// value even when Google adds new codes in the future.
enum FcmErrorCode {
  /// The device token is no longer valid — remove it from your database.
  unregistered,

  /// The device token does not match the sender ID / project.
  senderIdMismatch,

  /// The request was invalid (bad payload, wrong JSON, etc.).
  invalidArgument,

  /// The app quota for messages has been exceeded. Back off and retry.
  quotaExceeded,

  /// The FCM service is temporarily unavailable. Retry with back-off.
  unavailable,

  /// An internal error occurred on the FCM server side.
  internal,

  /// A third-party authentication error occurred (e.g., APN certificate).
  thirdPartyAuthError,

  /// Catch-all for any future or unrecognised FCM error codes.
  unknown,
}

// ---------------------------------------------------------------------------
// Error model
// ---------------------------------------------------------------------------

/// A structured representation of an error returned by the FCM HTTP v1 API.
///
/// Example JSON body from FCM on failure:
/// ```json
/// {
///   "error": {
///     "code": 400,
///     "message": "The registration token is not a valid FCM registration token",
///     "status": "INVALID_ARGUMENT",
///     "details": [
///       {
///         "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
///         "errorCode": "INVALID_ARGUMENT"
///       }
///     ]
///   }
/// }
/// ```
///
/// The authoritative FCM code lives in the `details` entry typed as
/// `google.firebase.fcm.v1.FcmError`. The top-level `status` is a generic
/// `google.rpc.Code` name which does not always match — a quota failure, for
/// example, arrives as `RESOURCE_EXHAUSTED`. [errorCode] prefers the `details`
/// entry and falls back to `status`.
final class FcmError {

  const FcmError({
    required this.code,
    required this.message,
    this.status,
    required this.errorCode,
  });
  /// The HTTP status code returned by FCM (e.g., 400, 401, 500).
  final int code;

  /// The human-readable error message from FCM.
  final String message;

  /// The FCM-specific error status string as received (e.g., `"INVALID_ARGUMENT"`).
  final String? status;

  /// Typed representation of [status] for easy programmatic handling.
  final FcmErrorCode errorCode;

  // ---------------------------------------------------------------------------
  // Factory: parse from a decoded FCM response body
  // ---------------------------------------------------------------------------

  /// Creates an [FcmError] by extracting the `error` field from a decoded
  /// FCM response body [Map].
  ///
  /// Returns `null` if the map does not contain a recognisable error structure.
  static FcmError? fromResponseBody(Map<String, dynamic> body) {
    // FCM v1 errors live under a top-level "error" key.
    final dynamic errorMap = body['error'];
    if (errorMap == null || errorMap is! Map<String, dynamic>) return null;

    final int httpCode = (errorMap['code'] as num?)?.toInt() ?? 0;
    final String msg = (errorMap['message'] as String?) ?? 'Unknown FCM error';
    final String? status = errorMap['status'] as String?;

    // Prefer the typed FcmError detail — it carries the real FCM code.
    // Fall back to the generic google.rpc status when no detail is present.
    final String? detailCode = _extractDetailErrorCode(errorMap['details']);

    return FcmError(
      code: httpCode,
      message: msg,
      status: status,
      errorCode: detailCode != null
          ? _parseErrorCode(detailCode)
          : _parseStatusCode(status),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Pulls `errorCode` out of the `details` entry whose `@type` is
  /// `type.googleapis.com/google.firebase.fcm.v1.FcmError`.
  ///
  /// Returns `null` when the array is absent, malformed, or carries only
  /// other detail types (e.g. `google.rpc.BadRequest`).
  static String? _extractDetailErrorCode(Object? details) {
    if (details is! List) return null;

    for (final Object? detail in details) {
      if (detail is! Map<String, dynamic>) continue;

      final Object? type = detail['@type'];
      if (type is! String ||
          !type.endsWith('google.firebase.fcm.v1.FcmError')) {
        continue;
      }

      final Object? errorCode = detail['errorCode'];
      if (errorCode is String) return errorCode;
    }
    return null;
  }

  /// Maps an authoritative FCM error code string to a typed [FcmErrorCode].
  static FcmErrorCode _parseErrorCode(String code) => switch (code) {
        'UNREGISTERED' => FcmErrorCode.unregistered,
        'SENDER_ID_MISMATCH' => FcmErrorCode.senderIdMismatch,
        'INVALID_ARGUMENT' => FcmErrorCode.invalidArgument,
        'QUOTA_EXCEEDED' => FcmErrorCode.quotaExceeded,
        'UNAVAILABLE' => FcmErrorCode.unavailable,
        'INTERNAL' => FcmErrorCode.internal,
        'THIRD_PARTY_AUTH_ERROR' ||
        'APNS_AUTH_ERROR' =>
          FcmErrorCode.thirdPartyAuthError,
        _ => FcmErrorCode.unknown,
      };

  /// Fallback mapping from the generic `google.rpc.Code` name in `status`.
  ///
  /// Only unambiguous mappings are applied. `PERMISSION_DENIED` and
  /// `UNAUTHENTICATED` are deliberately left as [FcmErrorCode.unknown]: they
  /// are equally consistent with a service-account/IAM misconfiguration, and
  /// mapping them to a token-invalidating code would make
  /// `onRegistrationChange` delete every token in the caller's database on a
  /// credential problem.
  static FcmErrorCode _parseStatusCode(String? status) => switch (status) {
        // On messages:send a 404 can only refer to the target registration.
        'UNREGISTERED' || 'NOT_FOUND' => FcmErrorCode.unregistered,
        'SENDER_ID_MISMATCH' => FcmErrorCode.senderIdMismatch,
        'INVALID_ARGUMENT' => FcmErrorCode.invalidArgument,
        'QUOTA_EXCEEDED' ||
        'RESOURCE_EXHAUSTED' =>
          FcmErrorCode.quotaExceeded,
        'UNAVAILABLE' => FcmErrorCode.unavailable,
        'INTERNAL' => FcmErrorCode.internal,
        'THIRD_PARTY_AUTH_ERROR' ||
        'APNS_AUTH_ERROR' =>
          FcmErrorCode.thirdPartyAuthError,
        _ => FcmErrorCode.unknown,
      };

  // ---------------------------------------------------------------------------
  // Whether this error is considered retryable
  // ---------------------------------------------------------------------------

  /// Returns `true` when retrying the same request might eventually succeed.
  ///
  /// `quotaExceeded`, `unavailable`, and `internal` are the three retryable
  /// FCM error codes per the official FCM error documentation.
  bool get isRetryable =>
      errorCode == FcmErrorCode.quotaExceeded ||
      errorCode == FcmErrorCode.unavailable ||
      errorCode == FcmErrorCode.internal;

  @override
  String toString() =>
      'FcmError{code: $code, status: $status, errorCode: $errorCode, message: $message}';

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
