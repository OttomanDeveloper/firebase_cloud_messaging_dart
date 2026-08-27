import 'package:json_annotation/json_annotation.dart';

part 'firebase_service_model.g.dart';

/// Fields from a Google service-account JSON credential.
///
/// Credential setup: https://firebase.google.com/docs/admin/setup
@JsonSerializable()
final class FirebaseServiceModel {
  factory FirebaseServiceModel.fromJson(Map<String, dynamic> json) =>
      _$FirebaseServiceModelFromJson(json);

  const FirebaseServiceModel({
    this.clientX509Certurl,
    this.type,
    this.projectID,
    this.privateKeyId,
    this.privateKey,
    this.clientEmail,
    this.clientId,
    this.authUri,
    this.tokenUri,
    this.authProviderX509CertUrl,
  });
  @JsonKey(name: 'client_x509_cert_url')
  final String? clientX509Certurl;

  @JsonKey(name: 'type')
  final String? type;

  @JsonKey(name: 'project_id')
  final String? projectID;

  @JsonKey(name: 'private_key_id')
  final String? privateKeyId;

  @JsonKey(name: 'private_key')
  final String? privateKey;

  @JsonKey(name: 'client_email')
  final String? clientEmail;

  @JsonKey(name: 'client_id')
  final String? clientId;

  @JsonKey(name: 'auth_uri')
  final String? authUri;

  @JsonKey(name: 'token_uri')
  final String? tokenUri;

  @JsonKey(name: 'auth_provider_x509_cert_url')
  final String? authProviderX509CertUrl;

  Map<String, dynamic> toJson() => _$FirebaseServiceModelToJson(this);
}
