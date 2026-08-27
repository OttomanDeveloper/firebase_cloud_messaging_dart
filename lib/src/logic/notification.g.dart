// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FirebaseNotification _$FirebaseNotificationFromJson(
  Map<String, dynamic> json,
) => FirebaseNotification(
  title: json['title'] as String?,
  body: json['body'] as String?,
  image: json['image'] as String?,
);

Map<String, dynamic> _$FirebaseNotificationToJson(
  FirebaseNotification instance,
) => <String, dynamic>{
  'title': instance.title,
  'body': instance.body,
  'image': instance.image,
};
