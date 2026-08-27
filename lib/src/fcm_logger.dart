// ignore_for_file: constant_identifier_names

// Logging support for FirebaseCloudMessagingServer.
//
// Pass an [FcmLogger] callback to [FirebaseCloudMessagingServer] to receive
// structured log output. This replaces the old commented-out `print()` calls
// with a proper, opt-in logging interface.

// ---------------------------------------------------------------------------
// Log level
// ---------------------------------------------------------------------------

/// Severity levels for FCM log messages, ordered from least to most severe.
enum FcmLogLevel {
  /// Fine-grained diagnostic information (e.g., token expiry checks).
  debug,

  /// General informational messages (e.g., "message sent successfully").
  info,

  /// Potentially harmful situations that are recoverable (e.g., retry attempt).
  warning,

  /// Errors that prevented an operation from completing.
  error,
}

// ---------------------------------------------------------------------------
// Logger typedef
// ---------------------------------------------------------------------------

/// A callback that receives structured log output from [FirebaseCloudMessagingServer].
///
/// Example — pipe logs to `dart:developer`:
/// ```dart
/// import 'dart:developer' as dev;
///
/// final server = FirebaseCloudMessagingServer(
///   credentials,
///   logger: (level, message, {error, stackTrace}) {
///     dev.log(message, name: 'FCM', level: level.index * 300, error: error);
///   },
/// );
/// ```
typedef FcmLogger =
    void Function(
      FcmLogLevel level,
      String message, {
      Object? error,
      StackTrace? stackTrace,
    });

// ---------------------------------------------------------------------------
// Registration Callback
// ---------------------------------------------------------------------------

/// Status of a device token after an FCM attempt.
enum FcmRegistrationStatus {
  /// The token is no longer valid or has been unregistered from the project.
  /// You should remove this token from your database.
  unregistered,

  /// The token is valid and successfully received the message.
  active,
}

/// A callback triggered when a specific device token's registration status changes.
///
/// This is highly recommended for keeping your device database synchronized.
/// If you receive an [FcmRegistrationStatus.unregistered], you should delete
/// the [token] from your persistent storage.
typedef FcmRegistrationCallback =
    void Function(String token, FcmRegistrationStatus status);

// ---------------------------------------------------------------------------
// No-op default logger (used internally when user does not supply one)
// ---------------------------------------------------------------------------

/// A do-nothing logger that silences all output from the server.
/// This is the default when no [FcmLogger] is supplied.
void fcmSilentLogger(
  FcmLogLevel level,
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  // Intentionally empty — no output.
}
