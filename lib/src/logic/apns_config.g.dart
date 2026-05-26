// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apns_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FirebaseApnsConfig _$FirebaseApnsConfigFromJson(Map<String, dynamic> json) =>
    FirebaseApnsConfig(
      headers: (json['headers'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      notification: json['notification'] == null
          ? null
          : FirebaseApnsNotification.fromJson(
              json['notification'] as Map<String, dynamic>),
      fcmOptions: json['fcm_options'] == null
          ? null
          : ApnsFcmOptions.fromJson(
              json['fcm_options'] as Map<String, dynamic>),
      payload: json['payload'] as Map<String, dynamic>?,
      liveActivityToken: json['live_activity_token'] as String?,
    );

Map<String, dynamic> _$FirebaseApnsConfigToJson(FirebaseApnsConfig instance) =>
    <String, dynamic>{
      'headers': instance.headers,
      'notification': instance.notification,
      'fcm_options': instance.fcmOptions,
      'payload': instance.payload,
      'live_activity_token': instance.liveActivityToken,
    };
