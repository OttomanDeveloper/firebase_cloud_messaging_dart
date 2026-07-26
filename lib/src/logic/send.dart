import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';
import 'message.dart';

part 'send.g.dart';

/// The top-level request wrapper sent to the FCM HTTP v1 API.
///
/// Wraps a [FirebaseMessage] along with an optional [validateOnly] flag that
/// lets you test your payload without actually delivering the notification.
///
/// Usage example:
/// ```dart
/// final request = FirebaseSend(
///   message: FirebaseMessage(
///     token: deviceToken,
///     notification: FirebaseNotification(title: 'Hello', body: 'World'),
///   ),
/// );
/// final result = await server.send(request);
/// ```
@JsonSerializable()
final class FirebaseSend {

  const FirebaseSend({
    this.validateOnly = false,
    this.message,
  }) : assert(
          message != null,
          'FirebaseSend.message must not be null — '
          'set a message before calling send()',
        );

  factory FirebaseSend.fromJson(Map<String, dynamic> json) =>
      _$FirebaseSendFromJson(json);
  /// When `true`, validates the request without sending the message.
  ///
  /// The API will process the request and return the result as if the message
  /// was sent, but it will not actually be delivered. Useful for testing
  /// payloads before going live.
  @JsonKey(name: 'validate_only')
  final bool? validateOnly;

  /// The message to send. Must not be null when actually sending.
  final FirebaseMessage? message;

  Map<String, dynamic> toJson() => pruneNulls(_$FirebaseSendToJson(this));

  /// Creates a copy of this [FirebaseSend] with the given fields replaced.
  FirebaseSend copyWith({
    bool? validateOnly,
    FirebaseMessage? message,
  }) {
    return FirebaseSend(
      validateOnly: validateOnly ?? this.validateOnly,
      message: message ?? this.message,
    );
  }
}
