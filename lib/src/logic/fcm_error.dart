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
///     "status": "INVALID_ARGUMENT"
///   }
/// }
/// ```
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

    return FcmError(
      code: httpCode,
      message: msg,
      status: status,
      errorCode: _parseErrorCode(status),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Maps a raw FCM status string to a typed [FcmErrorCode].
  static FcmErrorCode _parseErrorCode(String? status) => switch (status) {
        'UNREGISTERED' => FcmErrorCode.unregistered,
        'SENDER_ID_MISMATCH' => FcmErrorCode.senderIdMismatch,
        'INVALID_ARGUMENT' => FcmErrorCode.invalidArgument,
        'QUOTA_EXCEEDED' => FcmErrorCode.quotaExceeded,
        'UNAVAILABLE' => FcmErrorCode.unavailable,
        'INTERNAL' => FcmErrorCode.internal,
        'THIRD_PARTY_AUTH_ERROR' => FcmErrorCode.thirdPartyAuthError,
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
}
