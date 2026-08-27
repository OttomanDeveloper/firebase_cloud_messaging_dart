import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'fcm_options.g.dart';

/// Cross-platform FCM options that apply regardless of the target channel
/// (Android, iOS, or Web).
///
/// FCM Reference:
/// https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#fcmoptions
@JsonSerializable()
final class FirebaseFcmOptions {
  const FirebaseFcmOptions({this.analyticsLabel});

  factory FirebaseFcmOptions.fromJson(Map<String, dynamic> json) =>
      _$FirebaseFcmOptionsFromJson(json);

  /// A label associated with the message for use in Firebase Analytics.
  ///
  /// The label may only contain ASCII letters, numbers, and underscores;
  /// maximum length is 50 characters.
  @JsonKey(name: 'analytics_label')
  final String? analyticsLabel;

  List<String> validate() {
    if (analyticsLabel == null ||
        RegExp(r'^[A-Za-z0-9_]{1,50}$').hasMatch(analyticsLabel!)) {
      return <String>[];
    }
    return <String>[
      'analyticsLabel must contain only ASCII letters, numbers, and '
          'underscores and be at most 50 characters.',
    ];
  }

  Map<String, dynamic> toJson() => pruneNulls(_$FirebaseFcmOptionsToJson(this));
}
