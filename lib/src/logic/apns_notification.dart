import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'apns_notification.g.dart';

/// Typed models for the FCM APNs payload.
///
/// FCM schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#ApnsConfig
/// Apple APS rules: https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification
///
/// APNs alert text belongs under `aps.alert`; this serializer preserves that
/// nesting instead of treating title and body as peer keys of `aps`.
/// The interruption level that determines iOS notification presentation.
enum InterruptionLevel {
  @JsonValue('active')
  active,
  @JsonValue('critical')
  critical,
  @JsonValue('passive')
  passive,
  @JsonValue('time-sensitive')
  timeSensitive,
}

/// APNs critical-alert sound dictionary.
///
/// Reference: https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification#Sound
@JsonSerializable()
final class CriticalSound {
  const CriticalSound({this.critical = 1, this.name, this.volume});

  factory CriticalSound.fromJson(Map<String, dynamic> json) =>
      _$CriticalSoundFromJson(json);

  /// Must be `1` to enable a critical alert sound.
  final int? critical;

  /// Sound filename or `default`.
  final String? name;

  /// Critical sound volume from `0` to `1`.
  final double? volume;

  Map<String, dynamic> toJson() => pruneNulls(_$CriticalSoundToJson(this));
}

/// The APNs `aps.alert` dictionary.
///
/// Reference: https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification#Alert
@JsonSerializable()
final class ApnsAlert {
  const ApnsAlert({
    this.title,
    this.titleLocKey,
    this.titleLocArgs,
    this.subtitle,
    this.subtitleLocKey,
    this.subtitleLocArgs,
    this.body,
    this.locKey,
    this.locArgs,
    this.launchImage,
  });

  factory ApnsAlert.fromJson(Map<String, dynamic> json) =>
      _$ApnsAlertFromJson(json);

  final String? title;

  @JsonKey(name: 'title-loc-key')
  final String? titleLocKey;

  @JsonKey(name: 'title-loc-args')
  final List<String>? titleLocArgs;

  final String? subtitle;

  @JsonKey(name: 'subtitle-loc-key')
  final String? subtitleLocKey;

  @JsonKey(name: 'subtitle-loc-args')
  final List<String>? subtitleLocArgs;

  final String? body;

  @JsonKey(name: 'loc-key')
  final String? locKey;

  @JsonKey(name: 'loc-args')
  final List<String>? locArgs;

  @JsonKey(name: 'launch-image')
  final String? launchImage;

  Map<String, dynamic> toJson() => pruneNulls(_$ApnsAlertToJson(this));
}

/// Typed APNs `aps` dictionary.
///
/// Reference: https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification#Payload-key-reference
///
/// The [title] and [body] fields are convenience shorthands. They are merged
/// into [alert] and serialized below `aps.alert`, as required by Apple.
@JsonSerializable()
final class FirebaseApnsNotification {
  const FirebaseApnsNotification({
    this.alert,
    this.title,
    this.body,
    this.sound,
    this.criticalSound,
    this.badge,
    this.category,
    this.threadId,
    this.contentAvailable,
    this.mutableContent,
    this.targetContentId,
    this.interruptionLevel,
    this.relevanceScore,
    this.staleDate,
    this.contentState,
    this.timestamp,
    this.event,
    this.dismissalDate,
    this.attributesType,
    this.attributes,
  });

  factory FirebaseApnsNotification.fromJson(Map<String, dynamic> json) {
    final dynamic sound = json['sound'];
    return FirebaseApnsNotification(
      alert: json['alert'] is Map<String, dynamic>
          ? ApnsAlert.fromJson(json['alert'] as Map<String, dynamic>)
          : null,
      title: json['title'] as String?,
      body: json['body'] as String?,
      sound: sound is String ? sound : null,
      criticalSound: sound is Map<String, dynamic>
          ? CriticalSound.fromJson(sound)
          : null,
      badge: (json['badge'] as num?)?.toInt(),
      category: json['category'] as String?,
      threadId: json['thread-id'] as String?,
      contentAvailable: (json['content-available'] as num?)?.toInt(),
      mutableContent: (json['mutable-content'] as num?)?.toInt(),
      targetContentId: json['target-content-id'] as String?,
      interruptionLevel: _interruptionLevelFromJson(json['interruption-level']),
      relevanceScore: (json['relevance-score'] as num?)?.toDouble(),
      staleDate: (json['stale-date'] as num?)?.toDouble(),
      contentState: json['content-state'] as Map<String, dynamic>?,
      timestamp: (json['timestamp'] as num?)?.toDouble(),
      event: json['event'] as String?,
      dismissalDate: (json['dismissal-date'] as num?)?.toDouble(),
      attributesType: json['attributes-type'] as String?,
      attributes: json['attributes'] as Map<String, dynamic>?,
    );
  }

  /// A nested APNs alert object.
  final ApnsAlert? alert;

  /// Convenience title merged into [alert].
  final String? title;

  /// Convenience body merged into [alert].
  final String? body;

  /// A sound filename or `default`.
  final String? sound;

  /// A critical alert sound dictionary. Takes precedence over [sound].
  final CriticalSound? criticalSound;

  final int? badge;
  final String? category;

  @JsonKey(name: 'thread-id')
  final String? threadId;

  @JsonKey(name: 'content-available')
  final int? contentAvailable;

  @JsonKey(name: 'mutable-content')
  final int? mutableContent;

  @JsonKey(name: 'target-content-id')
  final String? targetContentId;

  /// The iOS 15+ interruption level.
  final InterruptionLevel? interruptionLevel;

  final double? relevanceScore;

  /// Live Activity stale timestamp.
  @JsonKey(name: 'stale-date')
  final double? staleDate;

  /// Live Activity content state.
  @JsonKey(name: 'content-state')
  final Map<String, dynamic>? contentState;

  /// Live Activity update timestamp.
  final double? timestamp;

  /// Live Activity event: `start`, `update`, or `end`.
  final String? event;

  /// Live Activity dismissal timestamp.
  @JsonKey(name: 'dismissal-date')
  final double? dismissalDate;

  /// Live Activity attributes type.
  @JsonKey(name: 'attributes-type')
  final String? attributesType;

  /// Live Activity start attributes.
  final Map<String, dynamic>? attributes;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> aps = <String, dynamic>{};
    final Map<String, dynamic> alertJson =
        alert?.toJson() ?? <String, dynamic>{};
    if (title != null) alertJson['title'] = title;
    if (body != null) alertJson['body'] = body;
    if (alertJson.isNotEmpty) aps['alert'] = alertJson;
    if (criticalSound != null) {
      aps['sound'] = criticalSound!.toJson();
    } else if (sound != null) {
      aps['sound'] = sound;
    }
    if (badge != null) aps['badge'] = badge;
    if (category != null) aps['category'] = category;
    if (threadId != null) aps['thread-id'] = threadId;
    if (contentAvailable != null) aps['content-available'] = contentAvailable;
    if (mutableContent != null) aps['mutable-content'] = mutableContent;
    if (targetContentId != null) aps['target-content-id'] = targetContentId;
    if (interruptionLevel != null) {
      aps['interruption-level'] = _interruptionLevelToJson(interruptionLevel!);
    }
    if (relevanceScore != null) aps['relevance-score'] = relevanceScore;
    if (staleDate != null) aps['stale-date'] = staleDate;
    if (contentState != null) aps['content-state'] = contentState;
    if (timestamp != null) aps['timestamp'] = timestamp;
    if (event != null) aps['event'] = event;
    if (dismissalDate != null) aps['dismissal-date'] = dismissalDate;
    if (attributesType != null) aps['attributes-type'] = attributesType;
    if (attributes != null) aps['attributes'] = attributes;
    return pruneNulls(aps);
  }

  static InterruptionLevel? _interruptionLevelFromJson(dynamic value) {
    return switch (value) {
      'active' => InterruptionLevel.active,
      'critical' => InterruptionLevel.critical,
      'passive' => InterruptionLevel.passive,
      'time-sensitive' => InterruptionLevel.timeSensitive,
      _ => null,
    };
  }

  static String _interruptionLevelToJson(InterruptionLevel value) {
    return switch (value) {
      InterruptionLevel.active => 'active',
      InterruptionLevel.critical => 'critical',
      InterruptionLevel.passive => 'passive',
      InterruptionLevel.timeSensitive => 'time-sensitive',
    };
  }
}

/// FCM-specific APNs options.
///
/// FCM schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#ApnsFcmOptions
@JsonSerializable()
final class ApnsFcmOptions {
  const ApnsFcmOptions({this.analyticsLabel, this.image});

  factory ApnsFcmOptions.fromJson(Map<String, dynamic> json) =>
      _$ApnsFcmOptionsFromJson(json);

  @JsonKey(name: 'analytics_label')
  final String? analyticsLabel;

  final String? image;

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

  Map<String, dynamic> toJson() => pruneNulls(_$ApnsFcmOptionsToJson(this));
}
