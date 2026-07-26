// Internal JSON helpers shared by the serialisable models.

/// Removes every entry with a `null` value from [map].
///
/// The FCM HTTP v1 API is a protobuf-backed service that rejects unknown
/// field names, and `json_serializable` emits *all* declared keys — including
/// the ones left unset. Sending `{"apns": {"notification": null, ...}}`, for
/// example, is rejected with
/// `Invalid JSON payload received. Unknown name "notification"`, because
/// `ApnsConfig` has no such field on the wire (it lives under `payload.aps`).
///
/// Every model's `toJson()` funnels through here so the serialised request
/// contains only the fields the caller actually set. Nested models are pruned
/// by their own `toJson()` as the encoder walks the tree.
///
/// This is done by hand rather than with `@JsonSerializable(includeIfNull:
/// false)` because current `json_serializable` versions generate null-aware
/// elements for that option, which require a newer language version than this
/// package's SDK floor allows.
Map<String, dynamic> pruneNulls(Map<String, dynamic> map) {
  map.removeWhere((String _, dynamic value) => value == null);
  return map;
}
