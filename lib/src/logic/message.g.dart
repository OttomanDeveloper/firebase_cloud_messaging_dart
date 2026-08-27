// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FirebaseMessage _$FirebaseMessageFromJson(
  Map<String, dynamic> json,
) => FirebaseMessage(
  name: json['name'] as String?,
  data: (json['data'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  ),
  notification: json['notification'] == null
      ? null
      : FirebaseNotification.fromJson(
          json['notification'] as Map<String, dynamic>,
        ),
  android: json['android'] == null
      ? null
      : FirebaseAndroidConfig.fromJson(json['android'] as Map<String, dynamic>),
  webpush: json['webpush'] == null
      ? null
      : FirebaseWebpushConfig.fromJson(json['webpush'] as Map<String, dynamic>),
  apns: json['apns'] == null
      ? null
      : FirebaseApnsConfig.fromJson(json['apns'] as Map<String, dynamic>),
  fcmOptions: json['fcm_options'] == null
      ? null
      : FirebaseFcmOptions.fromJson(
          json['fcm_options'] as Map<String, dynamic>,
        ),
  fid: json['fid'] as String?,
  token: json['token'] as String?,
  topic: json['topic'] as String?,
  condition: json['condition'] as String?,
);

Map<String, dynamic> _$FirebaseMessageToJson(FirebaseMessage instance) =>
    <String, dynamic>{
      'name': instance.name,
      'data': instance.data,
      'notification': instance.notification,
      'android': instance.android,
      'webpush': instance.webpush,
      'apns': instance.apns,
      'fcm_options': instance.fcmOptions,
      'fid': instance.fid,
      'token': instance.token,
      'topic': instance.topic,
      'condition': instance.condition,
    };
