import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'notification.g.dart';

/// Cross-platform FCM notification template.
///
/// FCM schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#Notification
@JsonSerializable()
final class FirebaseNotification {
  factory FirebaseNotification.fromJson(Map<String, dynamic> json) =>
      _$FirebaseNotificationFromJson(json);

  const FirebaseNotification({this.title, this.body, this.image});

  /// The notification's title.

  final String? title;

  /// The notification's body text.

  final String? body;

  /// URL of an image downloaded and displayed by the platform notification.
  ///
  /// FCM field reference: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#Notification

  final String? image;

  Map<String, dynamic> toJson() =>
      pruneNulls(_$FirebaseNotificationToJson(this));
}
