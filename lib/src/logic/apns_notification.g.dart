// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apns_notification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CriticalSound _$CriticalSoundFromJson(Map<String, dynamic> json) =>
    CriticalSound(
      critical: (json['critical'] as num?)?.toInt() ?? 1,
      name: json['name'] as String?,
      volume: (json['volume'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$CriticalSoundToJson(CriticalSound instance) =>
    <String, dynamic>{
      'critical': instance.critical,
      'name': instance.name,
      'volume': instance.volume,
    };

ApnsAlert _$ApnsAlertFromJson(Map<String, dynamic> json) => ApnsAlert(
  title: json['title'] as String?,
  titleLocKey: json['title-loc-key'] as String?,
  titleLocArgs: (json['title-loc-args'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  subtitle: json['subtitle'] as String?,
  subtitleLocKey: json['subtitle-loc-key'] as String?,
  subtitleLocArgs: (json['subtitle-loc-args'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  body: json['body'] as String?,
  locKey: json['loc-key'] as String?,
  locArgs: (json['loc-args'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  launchImage: json['launch-image'] as String?,
);

Map<String, dynamic> _$ApnsAlertToJson(ApnsAlert instance) => <String, dynamic>{
  'title': instance.title,
  'title-loc-key': instance.titleLocKey,
  'title-loc-args': instance.titleLocArgs,
  'subtitle': instance.subtitle,
  'subtitle-loc-key': instance.subtitleLocKey,
  'subtitle-loc-args': instance.subtitleLocArgs,
  'body': instance.body,
  'loc-key': instance.locKey,
  'loc-args': instance.locArgs,
  'launch-image': instance.launchImage,
};

FirebaseApnsNotification _$FirebaseApnsNotificationFromJson(
  Map<String, dynamic> json,
) => FirebaseApnsNotification(
  alert: json['alert'] == null
      ? null
      : ApnsAlert.fromJson(json['alert'] as Map<String, dynamic>),
  title: json['title'] as String?,
  body: json['body'] as String?,
  sound: json['sound'] as String?,
  criticalSound: json['criticalSound'] == null
      ? null
      : CriticalSound.fromJson(json['criticalSound'] as Map<String, dynamic>),
  badge: (json['badge'] as num?)?.toInt(),
  category: json['category'] as String?,
  threadId: json['thread-id'] as String?,
  contentAvailable: (json['content-available'] as num?)?.toInt(),
  mutableContent: (json['mutable-content'] as num?)?.toInt(),
  targetContentId: json['target-content-id'] as String?,
  interruptionLevel: $enumDecodeNullable(
    _$InterruptionLevelEnumMap,
    json['interruptionLevel'],
  ),
  relevanceScore: (json['relevanceScore'] as num?)?.toDouble(),
  staleDate: (json['stale-date'] as num?)?.toDouble(),
  contentState: json['content-state'] as Map<String, dynamic>?,
  timestamp: (json['timestamp'] as num?)?.toDouble(),
  event: json['event'] as String?,
  dismissalDate: (json['dismissal-date'] as num?)?.toDouble(),
  attributesType: json['attributes-type'] as String?,
  attributes: json['attributes'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$FirebaseApnsNotificationToJson(
  FirebaseApnsNotification instance,
) => <String, dynamic>{
  'alert': instance.alert,
  'title': instance.title,
  'body': instance.body,
  'sound': instance.sound,
  'criticalSound': instance.criticalSound,
  'badge': instance.badge,
  'category': instance.category,
  'thread-id': instance.threadId,
  'content-available': instance.contentAvailable,
  'mutable-content': instance.mutableContent,
  'target-content-id': instance.targetContentId,
  'interruptionLevel': _$InterruptionLevelEnumMap[instance.interruptionLevel],
  'relevanceScore': instance.relevanceScore,
  'stale-date': instance.staleDate,
  'content-state': instance.contentState,
  'timestamp': instance.timestamp,
  'event': instance.event,
  'dismissal-date': instance.dismissalDate,
  'attributes-type': instance.attributesType,
  'attributes': instance.attributes,
};

const _$InterruptionLevelEnumMap = {
  InterruptionLevel.active: 'active',
  InterruptionLevel.critical: 'critical',
  InterruptionLevel.passive: 'passive',
  InterruptionLevel.timeSensitive: 'time-sensitive',
};

ApnsFcmOptions _$ApnsFcmOptionsFromJson(Map<String, dynamic> json) =>
    ApnsFcmOptions(
      analyticsLabel: json['analytics_label'] as String?,
      image: json['image'] as String?,
    );

Map<String, dynamic> _$ApnsFcmOptionsToJson(ApnsFcmOptions instance) =>
    <String, dynamic>{
      'analytics_label': instance.analyticsLabel,
      'image': instance.image,
    };
