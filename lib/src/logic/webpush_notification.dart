import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'webpush_notification.g.dart';

/// Direction values from the Web Notification API.
///
/// FCM Web Push model: https://firebase.google.com/docs/reference/admin/node/firebase-admin.messaging.webpushnotification
enum WebpushDirection {
  @JsonValue('auto')
  auto,
  @JsonValue('ltr')
  ltr,
  @JsonValue('rtl')
  rtl,
}

/// A Web Notification action button.
///
/// Reference: https://firebase.google.com/docs/reference/admin/node/firebase-admin.messaging.webpushnotification#WebpushNotification.actions
@JsonSerializable()
final class WebpushAction {
  const WebpushAction({this.action, this.title, this.icon});

  factory WebpushAction.fromJson(Map<String, dynamic> json) =>
      _$WebpushActionFromJson(json);

  /// Action identifier delivered to the service worker.
  final String? action;

  /// Action label shown to the user.
  final String? title;

  /// Optional action icon URL.
  final String? icon;

  /// Returns local validation errors for this action.
  List<String> validate() {
    final List<String> errors = <String>[];
    if (action == null || action!.trim().isEmpty) {
      errors.add('Web Push action must have a non-blank action value.');
    }
    if (title == null || title!.trim().isEmpty) {
      errors.add('Web Push action must have a non-blank title value.');
    }
    return errors;
  }

  Map<String, dynamic> toJson() => pruneNulls(_$WebpushActionToJson(this));
}

/// A typed Web Notification object for FCM Web Push.
///
/// Reference: https://firebase.google.com/docs/reference/admin/node/firebase-admin.messaging.webpushnotification
@JsonSerializable()
final class FirebaseWebpushNotification {
  const FirebaseWebpushNotification({
    this.title,
    this.body,
    this.icon,
    this.badge,
    this.image,
    this.tag,
    this.vibrate,
    this.requireInteraction,
    this.silent,
    this.actions,
    this.dir,
    this.lang,
    this.renotify,
    this.timestamp,
    this.data,
    this.extra,
  });

  factory FirebaseWebpushNotification.fromJson(Map<String, dynamic> json) {
    return FirebaseWebpushNotification(
      title: json['title'] as String?,
      body: json['body'] as String?,
      icon: json['icon'] as String?,
      badge: json['badge'] as String?,
      image: json['image'] as String?,
      tag: json['tag'] as String?,
      vibrate: json['vibrate'],
      requireInteraction: json['requireInteraction'] as bool?,
      silent: json['silent'] as bool?,
      actions: (json['actions'] as List<dynamic>?)
          ?.map(
            (dynamic item) =>
                WebpushAction.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      dir: _directionFromJson(json['dir']),
      lang: json['lang'] as String?,
      renotify: json['renotify'] as bool?,
      timestamp: json['timestamp'] as num?,
      data: json['data'],
      // Preserve unknown browser properties for forward-compatible round trips.
      extra: <String, dynamic>{
        for (final MapEntry<String, dynamic> entry in json.entries)
          if (!_knownKeys.contains(entry.key))
            entry.key: _cloneValue(entry.value),
      },
    );
  }

  final String? title;
  final String? body;
  final String? icon;
  final String? badge;
  final String? image;
  final String? tag;

  /// A vibration duration or an alternating vibration pattern.
  final Object? vibrate;

  /// Uses the Web Notification API camelCase key `requireInteraction`.
  final bool? requireInteraction;
  final bool? silent;
  final List<WebpushAction>? actions;
  final WebpushDirection? dir;
  final String? lang;
  final bool? renotify;

  /// Notification timestamp as a numeric value, normally milliseconds since epoch.
  final num? timestamp;

  /// Arbitrary notification data accepted by the Web Notification API.
  final Object? data;

  /// Additional future Web Notification properties preserved verbatim.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Map<String, dynamic>? extra;

  /// Returns local validation errors for deterministic Web Push constraints.
  List<String> validate() {
    final List<String> errors = <String>[];
    if (actions != null) {
      for (final WebpushAction action in actions!) {
        errors.addAll(action.validate());
      }
    }
    if (silent == true && (actions?.isNotEmpty ?? false)) {
      errors.add('A silent Web Push notification should not define actions.');
    }
    return errors;
  }

  Map<String, dynamic> toJson() {
    // Start with extensions, then let typed fields override matching keys.
    final Map<String, dynamic> json = cloneJsonMap(
      extra ?? <String, dynamic>{},
    );
    _put(json, 'title', title);
    _put(json, 'body', body);
    _put(json, 'icon', icon);
    _put(json, 'badge', badge);
    _put(json, 'image', image);
    _put(json, 'tag', tag);
    _put(json, 'vibrate', vibrate);
    _put(json, 'requireInteraction', requireInteraction);
    _put(json, 'silent', silent);
    _put(
      json,
      'actions',
      actions?.map((WebpushAction action) => action.toJson()).toList(),
    );
    _put(json, 'dir', dir == null ? null : _directionToJson(dir!));
    _put(json, 'lang', lang);
    _put(json, 'renotify', renotify);
    _put(json, 'timestamp', timestamp);
    _put(json, 'data', data);
    return pruneNulls(json);
  }

  // These keys are emitted from typed fields rather than stored in extra.
  static const Set<String> _knownKeys = <String>{
    'title',
    'body',
    'icon',
    'badge',
    'image',
    'tag',
    'vibrate',
    'requireInteraction',
    'silent',
    'actions',
    'dir',
    'lang',
    'renotify',
    'timestamp',
    'data',
  };

  static void _put(Map<String, dynamic> json, String key, dynamic value) {
    if (value != null) json[key] = value;
  }

  static WebpushDirection? _directionFromJson(dynamic value) {
    return switch (value) {
      'auto' => WebpushDirection.auto,
      'ltr' => WebpushDirection.ltr,
      'rtl' => WebpushDirection.rtl,
      _ => null,
    };
  }

  static String _directionToJson(WebpushDirection value) {
    return switch (value) {
      WebpushDirection.auto => 'auto',
      WebpushDirection.ltr => 'ltr',
      WebpushDirection.rtl => 'rtl',
    };
  }

  static dynamic _cloneValue(dynamic value) {
    if (value is Map<String, dynamic>) return cloneJsonMap(value);
    if (value is List) {
      return <dynamic>[for (final dynamic item in value) _cloneValue(item)];
    }
    return value;
  }
}

/// FCM-specific Web Push options.
///
/// FCM schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#WebpushFcmOptions
@JsonSerializable()
final class WebpushFcmOptions {
  const WebpushFcmOptions({this.link, this.analyticsLabel});

  factory WebpushFcmOptions.fromJson(Map<String, dynamic> json) =>
      _$WebpushFcmOptionsFromJson(json);

  /// HTTPS URL opened when the notification is clicked.
  final String? link;

  @JsonKey(name: 'analytics_label')
  final String? analyticsLabel;

  /// Returns local validation errors for Web Push FCM options.
  List<String> validate() {
    final List<String> errors = <String>[];
    if (link != null && Uri.tryParse(link!)?.scheme.toLowerCase() != 'https') {
      errors.add('Web Push link must be an HTTPS URL.');
    }
    return errors;
  }

  Map<String, dynamic> toJson() => pruneNulls(_$WebpushFcmOptionsToJson(this));
}
