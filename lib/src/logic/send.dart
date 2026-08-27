import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';
import 'message.dart';

part 'send.g.dart';

/// The top-level request wrapper sent to the FCM HTTP v1 API.
///
/// Reference: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#SendMessageRequest
///
/// Wraps a [FirebaseMessage] along with an optional [validateOnly] flag that
/// lets you test your payload without actually delivering the notification.
///
/// Usage example:
/// ```dart
/// final request = FirebaseSend(
///   message: FirebaseMessage(
///     fid: firebaseInstallationId,
///     notification: FirebaseNotification(title: 'Hello', body: 'World'),
///   ),
/// );
/// final result = await server.send(request);
/// ```
@JsonSerializable()
final class FirebaseSend {
  const FirebaseSend({this.validateOnly = false, this.message});

  factory FirebaseSend.fromJson(Map<String, dynamic> json) =>
      _$FirebaseSendFromJson(json);

  /// When `true`, validates the request without sending the message.
  ///
  /// FCM reference: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#SendMessageRequest

  @JsonKey(name: 'validate_only')
  final bool? validateOnly;

  /// The message to send. Must not be null when actually sending.
  final FirebaseMessage? message;

  /// Returns deterministic validation errors without performing network I/O.
  List<String> validate() {
    if (message == null) {
      return <String>['FirebaseSend.message must not be null.'];
    }
    return message!.validateForSend();
  }

  Map<String, dynamic> toJson() => pruneNulls(_$FirebaseSendToJson(this));

  /// Creates a copy of this [FirebaseSend] with the given fields replaced.
  FirebaseSend copyWith({bool? validateOnly, FirebaseMessage? message}) {
    return FirebaseSend(
      validateOnly: validateOnly ?? this.validateOnly,
      message: message ?? this.message,
    );
  }
}
