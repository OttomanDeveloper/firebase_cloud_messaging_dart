import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'apns_notification.g.dart';

/// Typed model for Apple Push Notification Service (APNs) notifications.
///
/// This file contains:
/// - [ApnsAlert]       — the visual alert body (title, subtitle, body text)
/// - [FirebaseApnsNotification] — the full APNs-specific notification envelope
/// - [ApnsFcmOptions]  — FCM-specific options that apply on top of APNs delivery
///
/// FCM Reference:
/// https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#apnsconfig
///
/// APNs APS Reference:
/// https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/generating_a_remote_notification

// ---------------------------------------------------------------------------
// APNs Interruption Level (iOS 15+)
// ---------------------------------------------------------------------------

/// The interruption level that determines the priority and delivery behaviour
/// of a notification on iOS 15.0 and later.
enum InterruptionLevel {
  /// The system presents the notification immediately and lights up the screen.
  @JsonValue('active')
  active,

  /// The system presents the notification immediately, lights up the screen,
  /// and can bypass a Focus or Do Not Disturb.
  @JsonValue('critical')
  critical,

  /// The system adds the notification to the notification list without
  /// lighting up the screen or playing a sound.
  @JsonValue('passive')
  passive,

  /// The system presents the notification immediately, lights up the screen,
  /// and can be delivered during a Focus.
  @JsonValue('time-sensitive')
  timeSensitive,
}

// ---------------------------------------------------------------------------
// APNs Alert
// ---------------------------------------------------------------------------

/// The structured alert body displayed by iOS for a notification.
///
/// You can use this instead of flat strings when you need subtitle support or
/// APS localisation keys.
@JsonSerializable()
final class ApnsAlert {

  const ApnsAlert({
    this.title,
    this.titleLocKey,
    this.titleLocArgs,
    this.subtitle,
    this.body,
    this.locKey,
    this.locArgs,
  });

  factory ApnsAlert.fromJson(Map<String, dynamic> json) =>
      _$ApnsAlertFromJson(json);
  /// The alert title shown in bold at the top of the notification banner.
  final String? title;

  /// A shorter version of [title], shown in place of it when space is limited
  /// (e.g., Apple Watch).
  @JsonKey(name: 'title-loc-key')
  final String? titleLocKey;

  /// Variable parts for the localised title string.
  @JsonKey(name: 'title-loc-args')
  final List<String>? titleLocArgs;

  /// A secondary line shown below [title] in expanded notifications (iOS 10+).
  final String? subtitle;

  /// The main body text of the notification.
  final String? body;

  /// A key in your app's `Localizable.strings` file used to localise [body].
  @JsonKey(name: 'loc-key')
  final String? locKey;

  /// Variable parts substituted into the [locKey] format string.
  @JsonKey(name: 'loc-args')
  final List<String>? locArgs;

  Map<String, dynamic> toJson() => pruneNulls(_$ApnsAlertToJson(this));
}

// ---------------------------------------------------------------------------
// APNs Notification
// ---------------------------------------------------------------------------

/// Typed APNs notification that replaces the raw `payload` Map in
/// [FirebaseApnsConfig].
///
/// Fields map directly to APNs APS dictionary keys. For the full APS
/// dictionary reference, see Apple's UserNotifications documentation.
@JsonSerializable()
final class FirebaseApnsNotification {

  const FirebaseApnsNotification({
    this.alert,
    this.title,
    this.body,
    this.sound,
    this.badge,
    this.category,
    this.threadId,
    this.contentAvailable,
    this.mutableContent,
    this.targetContentId,
    this.interruptionLevel,
    this.relevanceScore,
  });

  factory FirebaseApnsNotification.fromJson(Map<String, dynamic> json) =>
      _$FirebaseApnsNotificationFromJson(json);
  /// Structured visual alert object.
  ///
  /// Use this for subtitle support or localisation. If you only need
  /// title + body, prefer the flat [title] / [body] fields on
  /// [FirebaseNotification] instead.
  final ApnsAlert? alert;

  /// The notification's title — shorthand if you don't need [alert].
  final String? title;

  /// The notification's body text — shorthand if you don't need [alert].
  final String? body;

  /// The name of a sound file in the app's main bundle or a system sound.
  /// Use `"default"` for the system default alert sound.
  final String? sound;

  /// The badge number to display on the app icon. Set to `0` to remove any
  /// existing badge.
  final int? badge;

  /// A category identifier that matches a `UNNotificationCategory` registered
  /// by the app. Used to show notification action buttons.
  final String? category;

  /// An identifier for grouping related notifications in the Notification Centre.
  @JsonKey(name: 'thread-id')
  final String? threadId;

  /// Set to `1` to deliver a silent (background) notification that wakes
  /// the app without showing a banner.
  @JsonKey(name: 'content-available')
  final int? contentAvailable;

  /// Set to `1` to allow the app's notification service extension to modify
  /// the notification payload before delivery (e.g., to download media).
  @JsonKey(name: 'mutable-content')
  final int? mutableContent;

  /// An identifier used by the system to group related notifications.
  /// (iOS 13+).
  @JsonKey(name: 'target-content-id')
  final String? targetContentId;

  /// The interruption level for the notification (iOS 15+).
  @JsonKey(name: 'interruption-level')
  final InterruptionLevel? interruptionLevel;

  /// A number between 0 and 1 that determines how the system sorts the
  /// notification in the user's notification list (iOS 15+).
  @JsonKey(name: 'relevance-score')
  final double? relevanceScore;

  Map<String, dynamic> toJson() => pruneNulls(_$FirebaseApnsNotificationToJson(this));
}

// ---------------------------------------------------------------------------
// APNs FCM Options
// ---------------------------------------------------------------------------

/// FCM-specific options that overlay on top of the APNs delivery channel.
@JsonSerializable()
final class ApnsFcmOptions {

  const ApnsFcmOptions({this.analyticsLabel, this.image});

  factory ApnsFcmOptions.fromJson(Map<String, dynamic> json) =>
      _$ApnsFcmOptionsFromJson(json);
  /// A label for analytics event tracking, associated with this notification.
  ///
  /// The label may only contain ASCII letters, numbers, and underscores.
  @JsonKey(name: 'analytics_label')
  final String? analyticsLabel;

  /// A URL to an image to be displayed in the notification.
  ///
  /// On iOS this shows as the notification attachment thumbnail.
  final String? image;

  Map<String, dynamic> toJson() => pruneNulls(_$ApnsFcmOptionsToJson(this));
}
