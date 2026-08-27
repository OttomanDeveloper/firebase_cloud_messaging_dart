// Internal JSON helpers shared by the serialisable models.

/// Removes every entry with a `null` value from [map].
///
/// FCM REST schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages
/// Every model's `toJson()` funnels through this helper so unset fields are not
/// sent on the wire.
Map<String, dynamic> pruneNulls(Map<String, dynamic> map) {
  map.removeWhere((String _, dynamic value) => value == null);
  return map;
}

/// Returns a recursively copied JSON map.
///
/// This prevents custom serializers from mutating caller-owned payload maps.
Map<String, dynamic> cloneJsonMap(Map<String, dynamic> source) {
  return <String, dynamic>{
    for (final MapEntry<String, dynamic> entry in source.entries)
      entry.key: _cloneJsonValue(entry.value),
  };
}

dynamic _cloneJsonValue(dynamic value) {
  if (value is Map<String, dynamic>) return cloneJsonMap(value);
  if (value is Map) {
    return <String, dynamic>{
      for (final MapEntry<dynamic, dynamic> entry in value.entries)
        entry.key.toString(): _cloneJsonValue(entry.value),
    };
  }
  if (value is List) {
    return <dynamic>[for (final dynamic item in value) _cloneJsonValue(item)];
  }
  return value;
}

/// Deep-merges [overlay] on top of [base] and returns a new JSON map.
///
/// Used for APNs `payload.aps` and other platform override dictionaries.
///
/// Nested maps are merged recursively; scalar and list values from [overlay]
/// replace values from [base]. This is used for typed platform overrides so
/// raw extension fields are retained without allowing stale typed values to
/// win over explicit caller input.
Map<String, dynamic> deepMergeJsonMaps(
  Map<String, dynamic> base,
  Map<String, dynamic> overlay,
) {
  final Map<String, dynamic> result = cloneJsonMap(base);
  for (final MapEntry<String, dynamic> entry in overlay.entries) {
    final dynamic existing = result[entry.key];
    final dynamic incoming = entry.value;
    if (existing is Map<String, dynamic> && incoming is Map<String, dynamic>) {
      result[entry.key] = deepMergeJsonMaps(existing, incoming);
    } else {
      result[entry.key] = _cloneJsonValue(incoming);
    }
  }
  return result;
}
