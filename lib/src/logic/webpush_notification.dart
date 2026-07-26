import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'webpush_notification.g.dart';

/// Typed models for Web Push notifications delivered through FCM.
///
/// This file contains:
/// - [WebpushAction]           — a notification action button
/// - [FirebaseWebpushNotification] — the full Web Notification spec object
/// - [WebpushFcmOptions]       — FCM-specific options for the webpush channel
///
/// FCM Reference:
/// https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#webpushconfig
///
/// Web Notification Spec:
/// https://developer.mozilla.org/en-US/docs/Web/API/Notification

// ---------------------------------------------------------------------------
// Webpush Direction
// ---------------------------------------------------------------------------

/// The direction in which to display the notification.
enum WebpushDirection {
  /// The system chooses the direction based on the language.
  @JsonValue('auto')
  auto,

  /// Left to right.
  @JsonValue('ltr')
  ltr,

  /// Right to left.
  @JsonValue('rtl')
  rtl,
}

// ---------------------------------------------------------------------------
// Webpush Action
// ---------------------------------------------------------------------------

/// A button that appears in an expanded web push notification.
///
/// Corresponds to the [NotificationAction] dictionary in the
/// Web Notifications specification.
@JsonSerializable()
final class WebpushAction {

  const WebpushAction({this.action, this.title, this.icon});

  factory WebpushAction.fromJson(Map<String, dynamic> json) =>
      _$WebpushActionFromJson(json);
  /// An identifier for the action. Provided to the service worker when the
  /// button is clicked.
  final String? action;

  /// The label text displayed on the action button.
  final String? title;

  /// A URL pointing to an icon image to display alongside the action button.
  final String? icon;

  Map<String, dynamic> toJson() => pruneNulls(_$WebpushActionToJson(this));
}

// ---------------------------------------------------------------------------
// Webpush Notification
// ---------------------------------------------------------------------------

/// A typed [Web Notification](https://developer.mozilla.org/en-US/docs/Web/API/Notification)
/// object for the webpush channel.
///
/// All fields are optional; set only what you need. Fields here override
/// the top-level [FirebaseNotification] values for browsers.
@JsonSerializable()
final class FirebaseWebpushNotification {

  const FirebaseWebpushNotification({
    this.title,
    this.body,
    this.icon,
    this.badge,
    this.image,
    this.tag,
    this.vibrate,
    this.requireInteraction,
    this.silent,
    this.actions,
    this.dir,
    this.lang,
    this.renotify,
    this.timestamp,
    this.data,
  });

  factory FirebaseWebpushNotification.fromJson(Map<String, dynamic> json) =>
      _$FirebaseWebpushNotificationFromJson(json);
  /// The title shown in the notification banner.
  final String? title;

  /// The body text shown below [title].
  final String? body;

  /// URL of the icon image shown in the notification banner.
  final String? icon;

  /// URL of a badge image displayed in the notification tray on Android Chrome.
  final String? badge;

  /// URL of a large image displayed inside the notification body on Chrome.
  final String? image;

  /// A tag string that identifies this notification. Notifications with the
  /// same tag replace each other rather than stacking.
  final String? tag;

  /// Vibration pattern in milliseconds (on/off alternating). Only honoured
  /// on devices with vibration support.
  final List<int>? vibrate;

  /// Whether the notification should remain visible until the user explicitly
  /// interacts with it (not auto-dismissed).
  @JsonKey(name: 'require_interaction')
  final bool? requireInteraction;

  /// When `true`, no visual or audible alert is shown — the notification is
  /// created silently (e.g., for badge updates).
  final bool? silent;

  /// Action buttons to show in the expanded notification.
  final List<WebpushAction>? actions;

  /// The direction in which to display the notification.
  final WebpushDirection? dir;

  /// The notification's language (BCP 47 language tag).
  final String? lang;

  /// Whether the user should be notified after a new notification replaces
  /// an old one.
  final bool? renotify;

  /// A timestamp value for the notification (milliseconds since epoch).
  ///
  /// Represented as a string in Protobuf (Int64).
  final String? timestamp;

  /// Arbitrary data payload for the notification (distinct from top-level data).
  final Map<String, dynamic>? data;

  Map<String, dynamic> toJson() => pruneNulls(_$FirebaseWebpushNotificationToJson(this));
}

// ---------------------------------------------------------------------------
// Webpush FCM Options
// ---------------------------------------------------------------------------

/// FCM-specific options that apply on top of the webpush delivery channel.
@JsonSerializable()
final class WebpushFcmOptions {

  const WebpushFcmOptions({this.link, this.analyticsLabel});

  factory WebpushFcmOptions.fromJson(Map<String, dynamic> json) =>
      _$WebpushFcmOptionsFromJson(json);
  /// The link to open when the user clicks the notification.
  ///
  /// Must be an HTTPS URL. If not set, the app's manifest start URL is used.
  final String? link;

  /// A label for analytics event tracking, associated with this message.
  @JsonKey(name: 'analytics_label')
  final String? analyticsLabel;

  Map<String, dynamic> toJson() => pruneNulls(_$WebpushFcmOptionsToJson(this));
}
