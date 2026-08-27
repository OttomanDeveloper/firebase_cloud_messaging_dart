import 'dart:convert';

import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
import 'package:http/http.dart' as http;

/// Compatibility transport for the deprecated Instance ID topic API.
///
/// FCM guide: https://firebase.google.com/docs/cloud-messaging/manage-topic-subscriptions
/// Legacy API reference: https://developers.google.com/instance-id/reference
/// Keep isolated until a supported Dart Admin topic API is selected.
final class FcmTopicManagement {
  static const String iidBatchAddEndpoint =
      'https://iid.googleapis.com/iid/v1:batchAdd';
  static const String iidBatchRemoveEndpoint =
      'https://iid.googleapis.com/iid/v1:batchRemove';

  /// Performs one legacy batch subscribe or unsubscribe operation.
  ///
  /// The legacy request accepts at most 1,000 registration tokens.
  ///
  /// The transport remains available for compatibility, but new integrations
  /// should use a supported Firebase Admin topic-management implementation.
  static Future<TopicManagementResult> performBatchOperation({
    required String topic,
    required List<String> tokens,
    required String accessToken,
    required http.Client client,
    required bool isSubscription,
    FcmLogger? logger,
    Duration timeout = const Duration(seconds: 30),
    FcmRetryConfig retryConfig = const FcmRetryConfig(),
    Future<String> Function()? refreshAccessToken,
  }) async {
    final String action = isSubscription ? 'batchAdd' : 'batchRemove';
    final Uri url = Uri.parse(
      isSubscription ? iidBatchAddEndpoint : iidBatchRemoveEndpoint,
    );
    String currentAccessToken = accessToken;
    int attempt = 0;
    // A stale OAuth token gets one dedicated refresh before normal retries.
    bool authRefreshed = false;

    logger?.call(
      FcmLogLevel.warning,
      'Topic management uses the deprecated Instance ID REST API.',
    );

    while (true) {
      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $currentAccessToken',
        'access_token_auth': 'true',
      };
      final String body = json.encode(<String, Object>{
        'to': '/topics/$topic',
        'registration_tokens': tokens,
      });

      logger?.call(
        FcmLogLevel.debug,
        'Topic Management: $action for ${tokens.length} tokens on topic: $topic '
        '(attempt ${attempt + 1})',
      );

      http.Response response;
      try {
        response = await client
            .post(url, headers: headers, body: body)
            .timeout(timeout);
      } on Exception catch (error, stackTrace) {
        if (attempt < retryConfig.maxRetries) {
          final Duration delay = retryConfig.delayForAttempt(
            attempt,
            applyJitter: true,
          );
          logger?.call(
            FcmLogLevel.warning,
            'Topic Management transport failure; retrying in '
            '${delay.inMilliseconds}ms',
            error: error,
            stackTrace: stackTrace,
          );
          await Future<void>.delayed(delay);
          attempt++;
          if (refreshAccessToken != null) {
            currentAccessToken = await refreshAccessToken();
          }
          continue;
        }
        rethrow;
      }

      final Map<String, dynamic> bodyMap = _decodeMap(response.body);
      final FcmError? fcmError = response.statusCode == 401
          ? FcmError.fromResponseBody(bodyMap)
          : null;
      if (response.statusCode == 401 &&
          !authRefreshed &&
          refreshAccessToken != null &&
          (fcmError == null || fcmError.isOAuthAuthenticationError)) {
        authRefreshed = true;
        currentAccessToken = await refreshAccessToken();
        continue;
      }

      // Retry only transport-level transient statuses; response parsing remains
      // responsible for preserving per-token failures in all other cases.
      final bool retryable =
          response.statusCode == 429 ||
          response.statusCode == 500 ||
          response.statusCode == 503;
      if (retryable && attempt < retryConfig.maxRetries) {
        final Duration delay = _retryDelay(response, retryConfig, attempt);
        logger?.call(
          FcmLogLevel.warning,
          'Topic Management returned ${response.statusCode}; retrying in '
          '${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
        attempt++;
        if (refreshAccessToken != null) {
          currentAccessToken = await refreshAccessToken();
        }
        continue;
      }

      if (response.statusCode != 200) {
        logger?.call(
          FcmLogLevel.warning,
          'Topic Management: $action failed [${response.statusCode}] '
          'on topic: $topic',
        );
      }
      return TopicManagementResult.fromJson(
        bodyMap,
        tokens,
        statusCode: response.statusCode,
      );
    }
  }

  static Map<String, dynamic> _decodeMap(String body) {
    try {
      final dynamic decoded = json.decode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  // Honor the server’s Retry-After value before applying local backoff.
  static Duration _retryDelay(
    http.Response response,
    FcmRetryConfig config,
    int attempt,
  ) {
    final String? retryAfter = response.headers['retry-after']?.trim();
    if (retryAfter != null && retryAfter.isNotEmpty) {
      final int? seconds = int.tryParse(retryAfter);
      if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
      final DateTime? date = DateTime.tryParse(retryAfter);
      if (date != null) {
        final Duration delay = date.toUtc().difference(DateTime.now().toUtc());
        return delay.isNegative ? Duration.zero : delay;
      }
    }
    return response.statusCode == 429
        ? config.quotaDelayForAttempt(attempt, applyJitter: true)
        : config.delayForAttempt(attempt, applyJitter: true);
  }
}
