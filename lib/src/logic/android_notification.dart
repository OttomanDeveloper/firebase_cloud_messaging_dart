import 'package:json_annotation/json_annotation.dart';

part 'android_notification.g.dart';

/// Android-specific notification content for FCM messages.
///
/// These fields control how the notification is displayed on Android devices.
/// Many fields require specific API levels; see the FCM v1 reference for details.
///
/// FCM Reference:
/// https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#androidnotification
@JsonSerializable()
final class FirebaseAndroidNotification {

  const FirebaseAndroidNotification({
    this.title,
    this.body,
    this.icon,
    this.color,
    this.sound,
    this.tag,
    this.ticker,
    this.sticky,
    this.visibility,
    this.image,
    this.clickAction,
    this.bodyLocKey,
    this.bodyLocArgs,
    this.titleLocKey,
    this.titleLocArgs,
    this.channelID,
    this.eventTime,
    this.localOnly,
    this.notificationPriority,
    this.defaultSound,
    this.defaultVibrateTimings,
    this.defaultLightSettings,
    this.vibrateTimings,
    this.notificationCount,
    this.lightSettings,
    this.proxy,
  });

  factory FirebaseAndroidNotification.fromJson(Map<String, dynamic> json) =>
      _$FirebaseAndroidNotificationFromJson(json);
  /// The notification's title. Overrides [FirebaseNotification.title].
  final String? title;

  /// The notification's body text. Overrides [FirebaseNotification.body].
  final String? body;

  /// Drawable resource name for the notification icon (without extension).
  ///
  /// Defaults to the launcher icon if not set.
  final String? icon;

  /// Icon tint colour in `#rrggbb` hex format.
  final String? color;

  /// Sound to play when the notification arrives.
  ///
  /// Use `"default"` or a filename from `res/raw/` (without extension).
  final String? sound;

  /// Tag for replacing existing notifications with the same tag value.
  final String? tag;

  /// Intent filter action triggered when the user taps the notification.
  @JsonKey(name: 'click_action')
  final String? clickAction;

  /// Localisation key for the notification body string.
  @JsonKey(name: 'body_loc_key')
  final String? bodyLocKey;

  /// Arguments to substitute into the [bodyLocKey] format string.
  @JsonKey(name: 'body_loc_args')
  final List<String>? bodyLocArgs;

  /// Localisation key for the notification title string.
  @JsonKey(name: 'title_loc_key')
  final String? titleLocKey;

  /// Arguments to substitute into the [titleLocKey] format string.
  @JsonKey(name: 'title_loc_args')
  final List<String>? titleLocArgs;

  /// Android notification channel ID (required on Android 8+).
  ///
  /// The app must create a channel with this ID before any notification using
  /// it is received.
  @JsonKey(name: 'channel_id')
  final String? channelID;

  /// Text delivered to accessibility services and shown in the status bar
  /// on pre-Lollipop devices.
  final String? ticker;

  /// When `true`, the notification persists in the drawer after the user taps it.
  final bool? sticky;

  /// The time at which the event described by this notification occurred.
  ///
  /// RFC 3339 UTC "Zulu" format: e.g. `"2014-10-02T15:01:23.045123456Z"`.
  @JsonKey(name: 'event_time')
  final String? eventTime;

  /// When `true`, hints that this notification should not be bridged to
  /// paired Wear OS devices.
  @JsonKey(name: 'local_only')
  final bool? localOnly;

  /// Display priority for the notification once delivered.
  ///
  /// This is a post-delivery concept and is independent of
  /// [AndroidMessagePriority] which controls FCM transport priority.
  @JsonKey(name: 'notification_priority')
  final NotificationPriority? notificationPriority;

  /// Use the Android framework's default sound.
  @JsonKey(name: 'default_sound')
  final bool? defaultSound;

  /// Use the Android framework's default vibrate pattern.
  @JsonKey(name: 'default_vibrate_timings')
  final bool? defaultVibrateTimings;

  /// Use the Android framework's default LED light settings.
  @JsonKey(name: 'default_light_settings')
  final bool? defaultLightSettings;

  /// Custom vibration pattern — alternating on/off durations as protobuf
  /// Duration strings (e.g., `["0s", "0.5s", "0.5s"]`).
  @JsonKey(name: 'vibrate_timings')
  final List<String>? vibrateTimings;

  /// Lock-screen visibility of the notification.
  final Visibility? visibility;

  /// Badge count for launcher icons that support badging.
  @JsonKey(name: 'notification_count')
  final int? notificationCount;

  /// LED blinking rate and colour settings.
  @JsonKey(name: 'light_settings')
  final LightSettings? lightSettings;

  /// URL of an image to display inside the notification.
  /// Overrides [FirebaseNotification.image].
  final String? image;

  /// Controls whether the notification is proxied through a trusted application
  /// (e.g., the Android Wear companion app).
  ///
  /// Available on Android 12+ when the app targets API 31+.
  final AndroidNotificationProxy? proxy;

  Map<String, dynamic> toJson() => _$FirebaseAndroidNotificationToJson(this);
}

// ---------------------------------------------------------------------------
// NotificationPriority enum
// ---------------------------------------------------------------------------

/// Display priority of a notification on the device (client-side concept).
///
/// This is distinct from [AndroidMessagePriority] which is the FCM transport
/// priority deciding *when* the message is delivered.
enum NotificationPriority {
  /// Unspecified priority — let the system decide.
  @JsonValue('PRIORITY_UNSPECIFIED')
  priorityUnspecified,

  /// Lowest priority — may not be shown to the user at all.
  @JsonValue('PRIORITY_MIN')
  priorityMin,

  /// Low priority — shown in shade only, no sound or vibration.
  @JsonValue('PRIORITY_LOW')
  priorityLow,

  /// Default priority.
  @JsonValue('PRIORITY_DEFAULT')
  priorityDefault,

  /// High priority — may make a sound.
  @JsonValue('PRIORITY_HIGH')
  priorityHigh,

  /// Highest priority — full-screen intent for incoming calls.
  @JsonValue('PRIORITY_MAX')
  priorityMax,
}

// ---------------------------------------------------------------------------
// Visibility enum
// ---------------------------------------------------------------------------

/// Controls how much of the notification is visible on the lock screen.
enum Visibility {
  /// Default visibility — the system decides based on user settings.
  @JsonValue('VISIBILITY_UNSPECIFIED')
  visibilityUnspecified,

  /// Show only the notification's icon on the lock screen.
  @JsonValue('PRIVATE')
  private,

  /// Show the full notification on the lock screen.
  @JsonValue('PUBLIC')
  public,

  /// Hide the notification completely on the lock screen.
  @JsonValue('SECRET')
  secret,
}

// ---------------------------------------------------------------------------
// AndroidNotificationProxy enum (NEW in this upgrade)
// ---------------------------------------------------------------------------

/// Controls proxy behaviour for notifications through trusted applications.
///
/// Requires Android 12+ (API level 31+) and targeting API 31+.
enum AndroidNotificationProxy {
  /// Proxy state is not specified — use the system default.
  @JsonValue('PROXY_UNSPECIFIED')
  proxyUnspecified,

  /// Always proxy this notification.
  @JsonValue('ALLOW')
  allow,

  /// Never proxy this notification.
  @JsonValue('DENY')
  deny,

  /// Proxy if the delivery priority was lowered by the system.
  @JsonValue('IF_PRIORITY_LOWERED')
  ifPriorityLowered,
}

// ---------------------------------------------------------------------------
// LightSettings
// ---------------------------------------------------------------------------

/// Controls the notification LED blinking rate and colour.
@JsonSerializable()
final class LightSettings {

  const LightSettings({
    this.color,
    this.lightOnDuration,
    this.lightOffDuration,
  });

  factory LightSettings.fromJson(Map<String, dynamic> json) =>
      _$LightSettingsFromJson(json);
  /// The LED colour as an RGBA value.
  final FCMColor? color;

  /// Duration to keep the LED on (protobuf Duration string, e.g., `"0.5s"`).
  @JsonKey(name: 'light_on_duration')
  final String? lightOnDuration;

  /// Duration to keep the LED off (protobuf Duration string, e.g., `"0.5s"`).
  @JsonKey(name: 'light_off_duration')
  final String? lightOffDuration;

  Map<String, dynamic> toJson() => _$LightSettingsToJson(this);
}

// ---------------------------------------------------------------------------
// FCMColor
// ---------------------------------------------------------------------------

/// An RGBA colour value used in FCM notification models.
///
/// Each component is a float in the range 0.0–1.0.
@JsonSerializable()
final class FCMColor {

  const FCMColor({this.red, this.green, this.blue, this.alpha});

  factory FCMColor.fromJson(Map<String, dynamic> json) =>
      _$FCMColorFromJson(json);
  /// Red component (0.0–1.0).
  final double? red;

  /// Green component (0.0–1.0).
  final double? green;

  /// Blue component (0.0–1.0).
  final double? blue;

  /// Alpha (opacity) component (0.0–1.0). `1.0` is fully opaque.
  final double? alpha;

  Map<String, dynamic> toJson() => _$FCMColorToJson(this);
}
