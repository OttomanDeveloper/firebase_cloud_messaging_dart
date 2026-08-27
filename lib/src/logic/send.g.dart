// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'send.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FirebaseSend _$FirebaseSendFromJson(Map<String, dynamic> json) => FirebaseSend(
  validateOnly: json['validate_only'] as bool? ?? false,
  message: json['message'] == null
      ? null
      : FirebaseMessage.fromJson(json['message'] as Map<String, dynamic>),
);

Map<String, dynamic> _$FirebaseSendToJson(FirebaseSend instance) =>
    <String, dynamic>{
      'validate_only': instance.validateOnly,
      'message': instance.message,
    };
