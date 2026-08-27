// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'firebase_service_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FirebaseServiceModel _$FirebaseServiceModelFromJson(
  Map<String, dynamic> json,
) => FirebaseServiceModel(
  clientX509Certurl: json['client_x509_cert_url'] as String?,
  type: json['type'] as String?,
  projectID: json['project_id'] as String?,
  privateKeyId: json['private_key_id'] as String?,
  privateKey: json['private_key'] as String?,
  clientEmail: json['client_email'] as String?,
  clientId: json['client_id'] as String?,
  authUri: json['auth_uri'] as String?,
  tokenUri: json['token_uri'] as String?,
  authProviderX509CertUrl: json['auth_provider_x509_cert_url'] as String?,
);

Map<String, dynamic> _$FirebaseServiceModelToJson(
  FirebaseServiceModel instance,
) => <String, dynamic>{
  'client_x509_cert_url': instance.clientX509Certurl,
  'type': instance.type,
  'project_id': instance.projectID,
  'private_key_id': instance.privateKeyId,
  'private_key': instance.privateKey,
  'client_email': instance.clientEmail,
  'client_id': instance.clientId,
  'auth_uri': instance.authUri,
  'token_uri': instance.tokenUri,
  'auth_provider_x509_cert_url': instance.authProviderX509CertUrl,
};
