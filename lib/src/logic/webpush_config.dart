import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';
import 'webpush_notification.dart';

part 'webpush_config.g.dart';

/// Configuration for messages delivered through the Web Push protocol.
///
/// Fields here override the top-level [FirebaseMessage] values for browsers.
/// All fields are optional; only set what you need.
///
/// FCM Reference:
/// https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#webpushconfig
@JsonSerializable()
final class FirebaseWebpushConfig {
  const FirebaseWebpushConfig({
    this.headers,
    this.data,
    this.notification,
    this.fcmOptions,
  });

  factory FirebaseWebpushConfig.fromJson(Map<String, dynamic> json) =>
      _$FirebaseWebpushConfigFromJson(json);

  /// HTTP headers defined in the Web Push protocol.
  ///
  /// Refer to the Web Push specification for supported header keys.
  /// Example: `{'TTL': '86400', 'Urgency': 'high'}`.
  final Map<String, String>? headers;

  /// Arbitrary key/value data payload delivered to the service worker.
  ///
  /// Overrides [FirebaseMessage.data] for web recipients.
  final Map<String, String>? data;

  /// Typed Web Notification object.
  ///
  /// Replaces the previous raw [Map] — use this for full IDE autocomplete
  /// and type safety for all notification fields including action buttons.
  final FirebaseWebpushNotification? notification;

  /// FCM-specific options for the webpush channel (link and analytics label).
  @JsonKey(name: 'fcm_options')
  final WebpushFcmOptions? fcmOptions;

  List<String> validate() {
    return <String>[
      if (notification != null) ...notification!.validate(),
      if (fcmOptions != null) ...fcmOptions!.validate(),
    ];
  }

  Map<String, dynamic> toJson() =>
      pruneNulls(_$FirebaseWebpushConfigToJson(this));
}
