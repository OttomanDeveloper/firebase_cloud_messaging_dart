import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';

/// Example file demonstrating the firebase_cloud_messaging_dart v4.0.0 API.
///
/// This example leverages Dart 3 features such as sealed classes and pattern
/// matching for robust FCM result handling.
///
/// Replace every placeholder before running: this sample makes authenticated
/// FCM requests, including a live topic-management request.
///
/// Obtain service account credentials from:
///   Firebase Console → Settings → Service Accounts → Generate new private key
void main() async {
  // 1. Initialize the Server
  // Option A: Using a service account file directly (easiest)
  final FirebaseCloudMessagingServer server =
      FirebaseCloudMessagingServer.fromServiceAccountFile(
        'serviceAccountKey.json',
        logger:
            (
              FcmLogLevel level,
              String message, {
              Object? error,
              StackTrace? stackTrace,
            }) {
              print('[FCM ${level.name.toUpperCase()}] $message');
              if (error != null) print('  Error: $error');
            },
      );

  // Option B: To use pre-parsed JSON, add dart:convert and dart:io imports,
  // then replace the initialization above with:
  /*
  final credentials = jsonDecode(
    File('serviceAccountKey.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final FirebaseCloudMessagingServer server =
      FirebaseCloudMessagingServer(credentials);
  */

  // Alternatively, use Application Default Credentials (ADC), recommended for
  // Google Cloud Run or Firebase Functions. Replace the initialization above:
  /*
  final FirebaseCloudMessagingServer server =
      FirebaseCloudMessagingServer.applicationDefault(
    projectId: 'my-project-id',
    logger: (FcmLogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
      print('[FCM ${level.name.toUpperCase()}] $message');
      if (error != null) print('  Error: $error');
    },
  );
  */

  // --------------------------------------------------------------------------
  // 2. Send to a Firebase Installation ID (current FCM target)
  // --------------------------------------------------------------------------
  const String firebaseInstallationId = 'REPLACE_WITH_YOUR_FID';

  final ServerResult result = await server.send(
    const FirebaseSend(
      message: FirebaseMessage(
        fid: firebaseInstallationId,
        notification: FirebaseNotification(
          title: 'Hello from FCM HTTP v1',
          body: 'Current FCM HTTP v1 sample message.',
          image: 'https://example.com/banner.png',
        ),
        android: FirebaseAndroidConfig(
          ttl: '86400s', // 24 hours
          priority: AndroidMessagePriority.high,
          directBootOk: false,
          notification: FirebaseAndroidNotification(
            icon: 'ic_notification',
            color: '#FF6D00',
            channelID: 'default_channel',
            notificationPriority: NotificationPriority.priorityHigh,
            proxy: AndroidNotificationProxy.allow,
          ),
        ),
        apns: FirebaseApnsConfig(
          headers: <String, String>{'apns-priority': '10'},
          notification: FirebaseApnsNotification(
            title: 'Hello!',
            body: 'iOS-specific notification body.',
            badge: 1,
            sound: 'default',
          ),
          fcmOptions: ApnsFcmOptions(
            analyticsLabel: 'v2_launch',
            image: 'https://example.com/ios-banner.png',
          ),
        ),
        webpush: FirebaseWebpushConfig(
          notification: FirebaseWebpushNotification(
            title: 'Hello!',
            body: 'Web-specific notification body.',
            icon: 'https://example.com/icon.png',
            requireInteraction: true,
            actions: <WebpushAction>[
              WebpushAction(action: 'open_app', title: 'Open'),
              WebpushAction(action: 'dismiss', title: 'Dismiss'),
            ],
          ),
          fcmOptions: WebpushFcmOptions(
            link: 'https://example.com',
            analyticsLabel: 'web_push',
          ),
        ),
        fcmOptions: FirebaseFcmOptions(analyticsLabel: 'example'),
      ),
    ),
  );

  print('Single send result: $result');

  // Dart 3 Exhaustive Pattern Matching for handling send outcomes
  switch (result) {
    case ServerSuccess(:final FirebaseMessage messageSent):
      print('✅ Message sent successfully! ID: ${messageSent.name}');
    case ServerFailure(:final FcmError? fcmError):
      print('❌ FCM Error: ${fcmError?.errorCode}');
      print('   Summary: ${fcmError?.message}');
      print('   Is Retryable: ${fcmError?.isRetryable}');
  }

  // --------------------------------------------------------------------------
  // 3. Send to multiple tokens in parallel
  // --------------------------------------------------------------------------
  final List<String> tokens = <String>['token_a', 'token_b', 'token_c'];

  final BatchResult batchResult = await server.sendToMultiple(
    tokens: tokens,
    messageTemplate: const FirebaseMessage(
      notification: FirebaseNotification(
        title: 'Batch notification',
        body: 'Sent to all users in parallel.',
      ),
    ),
  );

  print('Batch result: $batchResult');
  print('  Succeeded: ${batchResult.successCount}');
  print('  Failed:    ${batchResult.failureCount}');

  // Remove stale tokens from your database
  for (final TokenResult r in batchResult.failedResults) {
    if (r.serverResult.fcmError?.errorCode == FcmErrorCode.unregistered) {
      print('  Stale token (remove from DB): ${r.token}');
    }
  }

  // --------------------------------------------------------------------------
  // 4. Topic Subscriptions & Topic Messaging
  // --------------------------------------------------------------------------

  // A. Subscribe tokens to a topic (legacy IID compatibility API;
  // use a supported Admin SDK topic implementation for new systems).
  // This call is included for API reference and performs a real request.

  final TopicManagementResult topicResult = await server.subscribeTokensToTopic(
    topic: 'sports',
    tokens: <String>['fake-token-4', 'fake-token-5'],
  );
  print(
    'Topic subscription result: ${topicResult.successCount} success, ${topicResult.failureCount} failed',
  );

  // B. Send message to the topic
  final ServerResult topicSendResult = await server.sendToTopic(
    'sports',
    const FirebaseMessage(
      notification: FirebaseNotification(
        title: 'Goal!',
        body: 'The local team scored.',
      ),
    ),
  );
  print('Topic send successful: ${topicSendResult.successful}');

  // --------------------------------------------------------------------------
  // 5. Send to a condition
  // --------------------------------------------------------------------------
  await server.sendToCondition(
    "'sports' in topics || 'news' in topics",
    const FirebaseMessage(
      notification: FirebaseNotification(
        title: 'Sports & News Alert',
        body: 'Something for both audiences.',
      ),
    ),
  );

  // --------------------------------------------------------------------------
  // 6. Validate a message without sending it
  // --------------------------------------------------------------------------
  final ServerResult validationResult = await server.validateMessage(
    const FirebaseSend(
      message: FirebaseMessage(
        fid: firebaseInstallationId,
        notification: FirebaseNotification(title: 'Test'),
      ),
    ),
  );
  print('Validation passed: ${validationResult.successful}');

  // --------------------------------------------------------------------------
  // 7. Always dispose the server when done
  // --------------------------------------------------------------------------
  server.dispose();
}
