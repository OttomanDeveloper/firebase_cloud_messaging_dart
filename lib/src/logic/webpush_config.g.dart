// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'webpush_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FirebaseWebpushConfig _$FirebaseWebpushConfigFromJson(
  Map<String, dynamic> json,
) => FirebaseWebpushConfig(
  headers: (json['headers'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  ),
  data: (json['data'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  ),
  notification: json['notification'] == null
      ? null
      : FirebaseWebpushNotification.fromJson(
          json['notification'] as Map<String, dynamic>,
        ),
  fcmOptions: json['fcm_options'] == null
      ? null
      : WebpushFcmOptions.fromJson(json['fcm_options'] as Map<String, dynamic>),
);

Map<String, dynamic> _$FirebaseWebpushConfigToJson(
  FirebaseWebpushConfig instance,
) => <String, dynamic>{
  'headers': instance.headers,
  'data': instance.data,
  'notification': instance.notification,
  'fcm_options': instance.fcmOptions,
};
