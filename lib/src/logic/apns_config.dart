import 'package:json_annotation/json_annotation.dart';

import 'apns_notification.dart';
import 'json_utils.dart';

part 'apns_config.g.dart';

/// FCM HTTP v1 APNs configuration.
///
/// FCM schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#ApnsConfig
/// Apple payload rules: https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification
@JsonSerializable()
final class FirebaseApnsConfig {
  const FirebaseApnsConfig({
    this.headers,
    this.notification,
    this.fcmOptions,
    this.payload,
    this.liveActivityToken,
  });

  factory FirebaseApnsConfig.fromJson(Map<String, dynamic> json) {
    final FirebaseApnsConfig config = _$FirebaseApnsConfigFromJson(json);
    // Rehydrate typed APS fields when input contains only the raw payload form.
    final dynamic payload = json['payload'];
    final dynamic aps = payload is Map<String, dynamic> ? payload['aps'] : null;
    if (config.notification == null && aps is Map<String, dynamic>) {
      return FirebaseApnsConfig(
        headers: config.headers,
        fcmOptions: config.fcmOptions,
        payload: config.payload,
        liveActivityToken: config.liveActivityToken,
        notification: FirebaseApnsNotification.fromJson(aps),
      );
    }
    return config;
  }

  /// HTTP request headers defined in the APNs request.
  final Map<String, String>? headers;

  /// Typed APS dictionary. Alert text is serialized below `aps.alert`.
  final FirebaseApnsNotification? notification;

  /// FCM-specific options for APNs delivery.
  @JsonKey(name: 'fcm_options')
  final ApnsFcmOptions? fcmOptions;

  /// Raw APNs payload containing an `aps` dictionary and custom peer keys.
  ///
  /// When [notification] is also supplied, raw keys are preserved and typed
  /// values take precedence only where they overlap.
  final Map<String, dynamic>? payload;

  /// Token for an Apple Live Activity or push-to-start operation.
  @JsonKey(name: 'live_activity_token')
  final String? liveActivityToken;

  List<String> validate() {
    final List<String> errors = <String>[];
    if (fcmOptions != null) errors.addAll(fcmOptions!.validate());
    final FirebaseApnsNotification? aps = notification;
    if (aps?.relevanceScore != null &&
        (aps!.relevanceScore! < 0 || aps.relevanceScore! > 1)) {
      errors.add('APNs relevanceScore must be between 0 and 1.');
    }
    if (aps?.contentAvailable != null &&
        aps!.contentAvailable != 0 &&
        aps.contentAvailable != 1) {
      errors.add('APNs contentAvailable must be 0 or 1.');
    }
    if (aps?.mutableContent != null &&
        aps!.mutableContent != 0 &&
        aps.mutableContent != 1) {
      errors.add('APNs mutableContent must be 0 or 1.');
    }
    if (liveActivityToken != null && liveActivityToken!.trim().isEmpty) {
      errors.add('APNs liveActivityToken must not be blank.');
    }
    return errors;
  }

  /// Returns a JSON payload valid for the FCM v1 `ApnsConfig` schema.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = _$FirebaseApnsConfigToJson(this);
    json.remove('notification');

    if (notification != null) {
      // Preserve custom APS keys while letting typed fields override overlaps.
      final Map<String, dynamic> mergedPayload = cloneJsonMap(
        payload ?? <String, dynamic>{},
      );
      final dynamic rawAps = mergedPayload['aps'];
      final Map<String, dynamic> rawApsMap = rawAps is Map<String, dynamic>
          ? rawAps
          : <String, dynamic>{};
      // Merge recursively because alert and other APS values are nested maps.
      mergedPayload['aps'] = deepMergeJsonMaps(
        rawApsMap,
        notification!.toJson(),
      );
      json['payload'] = mergedPayload;
    }

    return pruneNulls(json);
  }
}
