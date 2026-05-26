// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'android_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FirebaseAndroidConfig _$FirebaseAndroidConfigFromJson(
        Map<String, dynamic> json) =>
    FirebaseAndroidConfig(
      collapseKey: json['collapse_key'] as String?,
      priority: $enumDecodeNullable(
          _$AndroidMessagePriorityEnumMap, json['priority']),
      ttl: json['ttl'] as String?,
      restrictedPackageName: json['restricted_package_name'] as String?,
      data: (json['data'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      notification: json['notification'] == null
          ? null
          : FirebaseAndroidNotification.fromJson(
              json['notification'] as Map<String, dynamic>),
      directBootOk: json['direct_boot_ok'] as bool?,
      fcmOptions: json['fcm_options'] == null
          ? null
          : AndroidFcmOptions.fromJson(
              json['fcm_options'] as Map<String, dynamic>),
      bandwidthConstrainedOk: json['bandwidth_constrained_ok'] as bool?,
      restrictedSatelliteOk: json['restricted_satellite_ok'] as bool?,
    );

Map<String, dynamic> _$FirebaseAndroidConfigToJson(
        FirebaseAndroidConfig instance) =>
    <String, dynamic>{
      'collapse_key': instance.collapseKey,
      'priority': _$AndroidMessagePriorityEnumMap[instance.priority],
      'ttl': instance.ttl,
      'restricted_package_name': instance.restrictedPackageName,
      'data': instance.data,
      'notification': instance.notification,
      'direct_boot_ok': instance.directBootOk,
      'fcm_options': instance.fcmOptions,
      'bandwidth_constrained_ok': instance.bandwidthConstrainedOk,
      'restricted_satellite_ok': instance.restrictedSatelliteOk,
    };

const _$AndroidMessagePriorityEnumMap = {
  AndroidMessagePriority.normal: 'NORMAL',
  AndroidMessagePriority.high: 'HIGH',
};

AndroidFcmOptions _$AndroidFcmOptionsFromJson(Map<String, dynamic> json) =>
    AndroidFcmOptions(
      analyticsLabel: json['analytics_label'] as String?,
    );

Map<String, dynamic> _$AndroidFcmOptionsToJson(AndroidFcmOptions instance) =>
    <String, dynamic>{
      'analytics_label': instance.analyticsLabel,
    };
