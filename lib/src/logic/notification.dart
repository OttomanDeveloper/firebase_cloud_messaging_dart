import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'notification.g.dart';

@JsonSerializable()
final class FirebaseNotification {

  factory FirebaseNotification.fromJson(Map<String, dynamic> json) =>
      _$FirebaseNotificationFromJson(json);

  const FirebaseNotification({this.title, this.body, this.image});
  ///The notification's title.
  final String? title;

  ///The notification's body text.
  final String? body;

  ///Contains the URL of an image that is going to be downloaded on the device and displayed in a notification. JPEG, PNG, BMP have full support across platforms. Animated GIF and video only work on iOS. WebP and HEIF have varying levels of support across platforms and platform versions. Android has 1MB image size limit. Quota usage and implications/costs for hosting image on Firebase Storage: https://firebase.google.com/pricing
  final String? image;

  Map<String, dynamic> toJson() => pruneNulls(_$FirebaseNotificationToJson(this));
}
