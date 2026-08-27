/// Firebase Cloud Messaging for Dart & Flutter — Server-side SDK
///
/// Sends FCM messages directly via the HTTP v1 REST API without requiring an
/// external server. Supports Android, iOS (APNs), and Web (WebPush) targets.
///
/// ## Getting started
/// ```dart
/// import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
/// ```
///
/// See [FirebaseCloudMessagingServer] for the primary entry point.
library;

// ---------------------------------------------------------------------------
// Logger
// ---------------------------------------------------------------------------
export 'src/fcm_logger.dart';
// ---------------------------------------------------------------------------
// Server entry point & result types
// ---------------------------------------------------------------------------
export 'src/firebase_cloud_messaging_server.dart';
// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------
export 'src/logic/android_config.dart';
export 'src/logic/android_notification.dart';
// ---------------------------------------------------------------------------
// Apple (APNs)
// ---------------------------------------------------------------------------
export 'src/logic/apns_config.dart';
export 'src/logic/apns_notification.dart';
export 'src/logic/batch_result.dart';
// ---------------------------------------------------------------------------
// Error handling & retry
// ---------------------------------------------------------------------------
export 'src/logic/fcm_error.dart';
// ---------------------------------------------------------------------------
// Core message models
// ---------------------------------------------------------------------------
export 'src/logic/fcm_options.dart';
export 'src/logic/fcm_retry.dart';
export 'src/logic/firebase_service_model.dart';
export 'src/logic/message.dart';
export 'src/logic/notification.dart';
export 'src/logic/send.dart';
export 'src/logic/topic_management_result.dart';
// ---------------------------------------------------------------------------
// Web Push
// ---------------------------------------------------------------------------
export 'src/logic/webpush_config.dart';
export 'src/logic/webpush_notification.dart';
