import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import 'android_config.dart';
import 'apns_config.dart';
import 'fcm_options.dart';
import 'json_utils.dart';
import 'notification.dart';
import 'webpush_config.dart';

part 'message.g.dart';

class _Unset {
  const _Unset();
}

const _Unset _unset = _Unset();

/// The FCM HTTP v1 `Message` object.
///
/// Reference: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#Message
/// Send guide: https://firebase.google.com/docs/cloud-messaging/send/v1-api
///
/// A send request must supply exactly one of [fid], [token], [topic], or
/// [condition]. The legacy [token] target is retained for compatibility, but
/// FCM now recommends Firebase Installation IDs through [fid].
@JsonSerializable()
final class FirebaseMessage {
  const FirebaseMessage({
    this.name,
    this.data,
    this.notification,
    this.android,
    this.webpush,
    this.apns,
    this.fcmOptions,
    this.fid,
    this.token,
    this.topic,
    this.condition,
  });

  factory FirebaseMessage.fromJson(Map<String, dynamic> json) =>
      _$FirebaseMessageFromJson(json);

  /// Output-only identifier returned by FCM after a successful send.
  final String? name;

  /// Arbitrary key/value payload delivered alongside the notification.
  ///
  /// FCM requires top-level data values to be strings and rejects reserved
  /// keys. Use [validateForSend] or the server's strict validation before
  /// sending untrusted maps.
  final Map<String, String>? data;

  /// Cross-platform notification content.
  final FirebaseNotification? notification;

  /// Android-specific message configuration.
  final FirebaseAndroidConfig? android;

  /// Web Push-specific message configuration.
  final FirebaseWebpushConfig? webpush;

  /// Apple Push Notification Service configuration.
  final FirebaseApnsConfig? apns;

  /// Cross-platform FCM options.
  @JsonKey(name: 'fcm_options')
  final FirebaseFcmOptions? fcmOptions;

  // -- Target fields ---------------------------------------------------------

  /// Firebase Installation ID target recommended by the current FCM API.
  final String? fid;

  /// Legacy device registration-token target.
  ///
  /// FCM currently accepts this during the transition to [fid], but marks it
  /// deprecated in the HTTP v1 schema.
  @Deprecated('FCM recommends fid for new integrations.')
  final String? token;

  /// FCM topic name without the `/topics/` prefix.
  final String? topic;

  /// Boolean topic expression, for example `"'news' in topics"`.
  final String? condition;

  /// Returns deterministic local validation errors for a send operation.
  ///
  /// This does not replace FCM validation. It catches deterministic issues
  /// before network I/O and is also used by the server's strict validation.
  List<String> validateForSend() {
    final List<String> errors = <String>[];
    final List<String?> targets = <String?>[fid, token, topic, condition];
    final int targetCount = targets
        .where((String? value) => value != null)
        .length;
    if (targetCount != 1) {
      errors.add('Exactly one of fid, token, topic, or condition is required.');
    }
    if (targetCount == 1 &&
        targets.singleWhere((String? value) => value != null)!.trim().isEmpty) {
      errors.add('The selected target must not be blank.');
    }
    if (data != null) {
      for (final String key in data!.keys) {
        if (_reservedDataKey(key)) {
          errors.add('Data key "$key" is reserved by FCM.');
        }
      }
      final int dataLimit = topic != null || condition != null ? 2048 : 4096;
      final int dataBytes = utf8.encode(jsonEncode(data)).length;
      if (dataBytes > dataLimit) {
        errors.add(
          'FCM data payload is $dataBytes bytes; the limit is $dataLimit bytes '
          'for this target.',
        );
      }
    }
    if (topic != null && !_validTopicName(topic!)) {
      errors.add('Topic must be a valid bare FCM topic name.');
    }
    if (fcmOptions != null) errors.addAll(fcmOptions!.validate());
    if (android != null) errors.addAll(android!.validate());
    if (webpush != null) errors.addAll(webpush!.validate());
    if (apns != null) errors.addAll(apns!.validate());
    return errors;
  }

  /// Returns a wire-safe outbound representation.
  ///
  /// [name] is output-only in FCM and is therefore removed before sending.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = pruneNulls(_$FirebaseMessageToJson(this));
    json.remove('name');
    return json;
  }

  /// Creates a copy with the specified fields replaced.
  ///
  /// Supplying any target argument makes it the sole target and clears the
  /// other target fields. Supplying an explicit `null` clears that target.
  FirebaseMessage copyWith({
    Object? name = _unset,
    Object? data = _unset,
    Object? notification = _unset,
    Object? android = _unset,
    Object? webpush = _unset,
    Object? apns = _unset,
    Object? fcmOptions = _unset,
    Object? fid = _unset,
    Object? token = _unset,
    Object? topic = _unset,
    Object? condition = _unset,
  }) {
    final bool targetChanged =
        !identical(fid, _unset) ||
        !identical(token, _unset) ||
        !identical(topic, _unset) ||
        !identical(condition, _unset);

    return FirebaseMessage(
      name: identical(name, _unset) ? this.name : name as String?,
      data: identical(data, _unset) ? this.data : data as Map<String, String>?,
      notification: identical(notification, _unset)
          ? this.notification
          : notification as FirebaseNotification?,
      android: identical(android, _unset)
          ? this.android
          : android as FirebaseAndroidConfig?,
      webpush: identical(webpush, _unset)
          ? this.webpush
          : webpush as FirebaseWebpushConfig?,
      apns: identical(apns, _unset) ? this.apns : apns as FirebaseApnsConfig?,
      fcmOptions: identical(fcmOptions, _unset)
          ? this.fcmOptions
          : fcmOptions as FirebaseFcmOptions?,
      fid: targetChanged
          ? (identical(fid, _unset) ? null : fid as String?)
          : this.fid,
      token: targetChanged
          ? (identical(token, _unset) ? null : token as String?)
          : this.token,
      topic: targetChanged
          ? (identical(topic, _unset) ? null : topic as String?)
          : this.topic,
      condition: targetChanged
          ? (identical(condition, _unset) ? null : condition as String?)
          : this.condition,
    );
  }

  /// Returns a copy targeted to one FID.
  FirebaseMessage withFid(String value) => copyWith(fid: value);

  /// Returns a copy targeted to one legacy registration token.
  @Deprecated('FCM recommends fid for new integrations.')
  FirebaseMessage withToken(String value) => copyWith(token: value);

  /// Returns a copy targeted to one topic.
  FirebaseMessage withTopic(String value) => copyWith(topic: value);

  /// Returns a copy targeted to one condition.
  FirebaseMessage withCondition(String value) => copyWith(condition: value);

  @override
  String toString() {
    return 'FirebaseMessage{name: $name, data: $data, '
        'notification: $notification, android: $android, webpush: $webpush, '
        'apns: $apns, fcm_options: $fcmOptions, fid: $fid, token: $token, '
        'topic: $topic, condition: $condition}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FirebaseMessage &&
        jsonEncode(other.toJson()) == jsonEncode(toJson());
  }

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  static bool _reservedDataKey(String key) {
    final String lower = key.toLowerCase();
    return lower == 'from' ||
        lower == 'message_type' ||
        lower.startsWith('google.') ||
        lower.startsWith('gcm.notification.');
  }

  static bool _validTopicName(String value) {
    final RegExp pattern = RegExp(r'^[a-zA-Z0-9-_.~%]{1,900}$');
    return pattern.hasMatch(value);
  }
}
