import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';

/// Result types returned by [FirebaseCloudMessagingServer.sendToMultiple].
///
/// [BatchResult] aggregates per-token send outcomes, while [TokenResult]
/// holds the result for a single device token.

// ---------------------------------------------------------------------------
// Per-token result
// ---------------------------------------------------------------------------

/// The outcome of sending a message to a single device [token].
final class TokenResult {
  const TokenResult({required this.token, required this.serverResult});

  /// The device registration token this result applies to.
  final String token;

  /// The underlying server response for this token.
  final ServerResult serverResult;

  /// Whether the message was delivered successfully to this token.
  bool get successful => serverResult.successful;

  @override
  String toString() =>
      'TokenResult{token: $token, successful: $successful, '
      'statusCode: ${serverResult.statusCode}}';
}

// ---------------------------------------------------------------------------
// Batch result
// ---------------------------------------------------------------------------

/// Aggregated result from [FirebaseCloudMessagingServer.sendToMultiple].
///
/// Iterate [results] for per-token outcomes, or use [successCount] /
/// [failureCount] for a quick summary.
///
/// Example:
/// ```dart
/// final batch = await server.sendToMultiple(
///   tokens: myTokenList,
///   messageTemplate: FirebaseMessage(notification: n),
/// );
///
/// print('Sent: ${batch.successCount}, Failed: ${batch.failureCount}');
///
/// // Remove stale tokens
/// for (final r in batch.failedResults) {
///   if (r.serverResult.fcmError?.errorCode == FcmErrorCode.unregistered) {
///     db.removeToken(r.token);
///   }
/// }
/// ```
final class BatchResult {
  const BatchResult({required this.results});

  /// Individual outcome for every token in the batch, in the same order
  /// as the input token list.
  final List<TokenResult> results;

  /// Number of tokens to which the message was delivered successfully.
  int get successCount => results.where((TokenResult r) => r.successful).length;

  /// Number of tokens for which delivery failed.
  int get failureCount =>
      results.where((TokenResult r) => !r.successful).length;

  /// Subset of [results] where [TokenResult.successful] is `true`.
  List<TokenResult> get successfulResults =>
      results.where((TokenResult r) => r.successful).toList();

  /// Subset of [results] where [TokenResult.successful] is `false`.
  List<TokenResult> get failedResults =>
      results.where((TokenResult r) => !r.successful).toList();

  /// Returns `true` if every token received the message successfully.
  bool get allSuccessful => failureCount == 0;

  /// Returns `true` if at least one token received the message.
  bool get anySuccessful => successCount > 0;

  @override
  String toString() =>
      'BatchResult{total: ${results.length}, '
      'success: $successCount, failure: $failureCount}';
}
