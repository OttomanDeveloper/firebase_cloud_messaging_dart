import 'package:json_annotation/json_annotation.dart';

import 'android_notification.dart';

import 'json_utils.dart';

part 'android_config.g.dart';

/// Android-specific configuration for an FCM HTTP v1 message.
///
/// FCM schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#AndroidConfig
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

  List<String> validate() {
    final List<String> errors = <String>[];
    if (ttl != null) {
      final String rawSeconds = ttl!.endsWith('s')
          ? ttl!.substring(0, ttl!.length - 1)
          : '';
      final double? seconds = double.tryParse(rawSeconds);
      if (seconds == null || seconds < 0 || seconds > 2419200) {
        errors.add('Android ttl must be a duration from 0s through 2419200s.');
      }
    }
    if (restrictedPackageName != null &&
        restrictedPackageName!.trim().isEmpty) {
      errors.add('Android restrictedPackageName must not be blank.');
    }
    if (data != null) {
      for (final String key in data!.keys) {
        final String lower = key.toLowerCase();
        if (lower == 'from' ||
            lower == 'message_type' ||
            lower.startsWith('google.') ||
            lower.startsWith('gcm.notification.')) {
          errors.add('Android data key "$key" is reserved by FCM.');
        }
      }
    }
    if (fcmOptions != null) errors.addAll(fcmOptions!.validate());
    return errors;
  }

  Map<String, dynamic> toJson() =>
      pruneNulls(_$FirebaseAndroidConfigToJson(this));
}

// ---------------------------------------------------------------------------
// Android FCM options
// ---------------------------------------------------------------------------

/// Android-specific FCM options.
///
/// FCM schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#AndroidFcmOptions

@JsonSerializable()
final class AndroidFcmOptions {
  const AndroidFcmOptions({this.analyticsLabel});

  factory AndroidFcmOptions.fromJson(Map<String, dynamic> json) =>
      _$AndroidFcmOptionsFromJson(json);

  /// An analytics label associated with this message for Android.
  @JsonKey(name: 'analytics_label')
  final String? analyticsLabel;

  List<String> validate() {
    if (analyticsLabel == null ||
        RegExp(r'^[A-Za-z0-9_]{1,50}$').hasMatch(analyticsLabel!)) {
      return <String>[];
    }
    return <String>[
      'analyticsLabel must contain only ASCII letters, numbers, and '
          'underscores and be at most 50 characters.',
    ];
  }

  Map<String, dynamic> toJson() => pruneNulls(_$AndroidFcmOptionsToJson(this));
}

// ---------------------------------------------------------------------------
// Android message priority enum
// ---------------------------------------------------------------------------

/// Delivery priority for an Android FCM message.
///
/// FCM values: `NORMAL` or `HIGH`; see https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#AndroidConfig

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
