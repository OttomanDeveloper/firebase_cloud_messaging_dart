import 'package:json_annotation/json_annotation.dart';

import 'android_notification.dart';

part 'android_config.g.dart';

/// Android-specific configuration for an FCM message.
///
/// FCM Reference:
/// https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#androidconfig
@JsonSerializable()
final class FirebaseAndroidConfig {

  const FirebaseAndroidConfig({
    this.collapseKey,
    this.priority,
    this.ttl,
    this.restrictedPackageName,
    this.data,
    this.notification,
    this.directBootOk,
    this.fcmOptions,
    this.bandwidthConstrainedOk,
    this.restrictedSatelliteOk,
  });

  factory FirebaseAndroidConfig.fromJson(Map<String, dynamic> json) =>
      _$FirebaseAndroidConfigFromJson(json);
  /// An identifier for a group of messages that can be collapsed so that only
  /// the most recent message is delivered when the device comes online.
  ///
  /// A maximum of 4 different collapse keys is allowed at any given time.
  @JsonKey(name: 'collapse_key')
  final String? collapseKey;

  /// Message priority for delivery on Android.
  ///
  /// [AndroidMessagePriority.high] wakes a sleeping device; use sparingly.
  final AndroidMessagePriority? priority;

  /// How long (in seconds with nanosecond precision) the message is kept in
  /// FCM storage when the device is offline. Maximum is 4 weeks.
  ///
  /// Format: a duration string ending in `"s"` — e.g., `"86400s"` for one day.
  /// Use `"0s"` to not store the message at all.
  final String? ttl;

  /// Package name the registration token must match to receive this message.
  ///
  /// Useful when multiple apps share the same project.
  @JsonKey(name: 'restricted_package_name')
  final String? restrictedPackageName;

  /// Arbitrary key/value data payload.
  ///
  /// If present, overrides [FirebaseMessage.data] for Android recipients.
  /// Keys must not be reserved words from the FCM spec.
  final Map<String, String>? data;

  /// Android-specific visual notification content.
  final FirebaseAndroidNotification? notification;

  /// When `true`, the message is allowed to be delivered to the app while
  /// the device is in [Direct Boot](https://developer.android.com/training/articles/direct-boot)
  /// mode (before the user has unlocked the device after a restart).
  ///
  /// Requires the `RECEIVE_BOOT_COMPLETED` permission and the target activity
  /// to be declared as `directBootAware`.
  @JsonKey(name: 'direct_boot_ok')
  final bool? directBootOk;

  /// Android-specific FCM options (analytics label).
  @JsonKey(name: 'fcm_options')
  final AndroidFcmOptions? fcmOptions;

  /// When `true`, messages are allowed to be delivered while the device is
  /// in bandwidth-constrained mode.
  @JsonKey(name: 'bandwidth_constrained_ok')
  final bool? bandwidthConstrainedOk;

  /// When `true`, messages are allowed to be delivered while the device is
  /// connected over a restricted satellite network.
  @JsonKey(name: 'restricted_satellite_ok')
  final bool? restrictedSatelliteOk;

  Map<String, dynamic> toJson() => _$FirebaseAndroidConfigToJson(this);
}

// ---------------------------------------------------------------------------
// Android FCM options
// ---------------------------------------------------------------------------

/// Android-specific FCM options.
@JsonSerializable()
final class AndroidFcmOptions {

  const AndroidFcmOptions({this.analyticsLabel});

  factory AndroidFcmOptions.fromJson(Map<String, dynamic> json) =>
      _$AndroidFcmOptionsFromJson(json);

  /// An analytics label associated with this message for Android.
  @JsonKey(name: 'analytics_label')
  final String? analyticsLabel;

  Map<String, dynamic> toJson() => _$AndroidFcmOptionsToJson(this);
}

// ---------------------------------------------------------------------------
// Android message priority enum
// ---------------------------------------------------------------------------

/// Delivery priority for an Android FCM message.
///
/// Note: this controls **when** FCM delivers the message (transport priority),
/// not how prominently the notification is displayed once received (that is
/// [NotificationPriority] inside [FirebaseAndroidNotification]).
enum AndroidMessagePriority {
  /// Default priority for data messages.
  ///
  /// Normal priority messages are not guaranteed to wake a sleeping device and
  /// may be delayed to preserve battery. Choose this for non-time-sensitive
  /// content such as new-email badges or background sync.
  @JsonValue('NORMAL')
  normal,

  /// Default priority for notification messages.
  ///
  /// FCM tries to deliver high-priority messages immediately and may wake the
  /// device. Use this only for time-critical alerts such as incoming calls or
  /// chat messages; overuse drains users' batteries.
  @JsonValue('HIGH')
  high,
}
