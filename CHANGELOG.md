# Changelog

## 4.0.0 (Current FCM API and Reliability Hardening)

### Breaking changes

* Raised the minimum Dart SDK to 3.10.0.
* `FirebaseMessage` now supports the current FCM `fid` target. The legacy `token` target remains available for migration compatibility and is deprecated for new integrations.
* Web Push timestamps use numeric values, matching the Web Notification API.
* Topic-management methods are marked deprecated because they use the legacy Instance ID batch API.

### API and wire-format fixes

* APNs typed title, subtitle, localization, and body fields now serialize under `payload.aps.alert`, matching Apple’s remote-notification payload structure.
* APNs typed fields are deep-merged with raw `payload.aps` values instead of replacing the caller’s raw APS dictionary.
* Web Push `requireInteraction` now uses the browser-standard camelCase wire key.
* Web Push supports numeric timestamps, scalar or array vibration values, arbitrary data, and preserved extension properties.
* Output-only FCM `Message.name` is stripped from outbound requests.
* FCM errors retain structured `details[]`, including field violations and quota metadata.

### Reliability and validation

* HTTP 429, 500, and 503 responses retry even when the body is empty or not JSON.
* Integer and HTTP-date `Retry-After` values are honored; quota retries use a one-minute initial delay by default and retries use bounded jitter.
* Third-party APNs/Web Push authentication errors are not incorrectly replayed as OAuth refresh failures.
* Generic `NOT_FOUND` no longer invalidates registration tokens; only FCM-specific `UNREGISTERED` does.
* Expected transport failures in bulk sends are returned as item-local failures while preserving order and cardinality.
* Topic-management responses preserve one result per requested token and flag malformed response arrays.
* Public validation no longer depends only on assertions; target, data-key, topic, URL, and action checks run in release builds.
* Topic operations now share retry, timeout, OAuth refresh, and lifecycle callback behavior with message sends while remaining explicitly legacy-compatible.

### Tests and maintenance

* Added regression fixtures for FID, APNs nesting/merging, Web Push key casing, empty-body retries, structured errors, batch isolation, quota delays, and malformed topic responses.
* Raised dependency versions, aligned the SDK constraint, refreshed generated serializers, and removed tracked generated environment state.
* Updated documentation and examples to state the pure-Dart server scope and current FCM migration guidance.



## 3.1.0 (Correctness Fixes)

### Bug Fixes

* **Fix (Critical)**: `FcmError` now reads the authoritative error code from `error.details[]` (the entry typed `google.firebase.fcm.v1.FcmError`) instead of relying solely on the top-level `error.status`. The two do not always agree — a quota failure arrives as `RESOURCE_EXHAUSTED` and an invalid token as `NOT_FOUND`. Previously both fell through to `FcmErrorCode.unknown`, which meant **`QUOTA_EXCEEDED` was never retried** and **`UNREGISTERED` never reached `onRegistrationChange`**, so stale tokens were never cleaned up. `RESOURCE_EXHAUSTED` and `NOT_FOUND` are now also mapped when no details block is present.
* **Fix (Critical)**: Input validation no longer relies on `assert`. Asserts are stripped from release and AOT builds (`dart compile exe`) — exactly how a server package ships — so malformed requests were silently forwarded to FCM in production. The "exactly one of token/topic/condition" rule, empty token/message lists, the `/topics/` prefix rule, and a missing `project_id` now throw `ArgumentError` in every build mode.
* **Fix (Critical)**: `ApnsConfig` no longer serialises a `notification` key. `ApnsConfig` has no such field on the wire (it belongs under `payload.aps`), and FCM rejects the whole request with `Invalid JSON payload received. Unknown name "notification"`. This affected every message that set `apns` without a typed `notification`.
* **Fix**: `toJson()` now omits unset fields instead of emitting them as explicit `null`s, matching what the FCM v1 API expects.
* **Fix**: `TopicManagementResult.fromJson` no longer throws a `TypeError` when the Instance ID API returns a `google.rpc` error envelope (`{"error": {"code": 401, ...}}`) rather than a per-token error string. Auth and quota failures on `subscribeTokensToTopic` / `unsubscribeTokensFromTopic` now surface as failed results. A non-JSON body (e.g. a proxy error page) is reported as `HTTP_<status>`.
* **Fix**: A `401` from FCM now triggers one forced token refresh and a replay, instead of being returned to the caller as a permanent failure. The cached token is additionally treated as expired 60 seconds before its stated expiry to absorb clock skew and in-flight time.
* **Fix**: HTTP requests are now bounded by `requestTimeout` (default 30 seconds). A hung connection previously blocked forever.
* **Fix**: Transport failures (`SocketException`, timeouts, connection resets) are retried under `retryConfig` instead of being rethrown on the first occurrence.
* **Fix**: `sendToMultiple` and `sendMessages` no longer open one socket per message. At most `maxConcurrency` (default 50) requests are in flight at a time; result ordering still matches the input.
* **Fix**: `subscribeTokensToTopic` / `unsubscribeTokensFromTopic` now split lists longer than 1,000 tokens into sequential batches and return one combined result, rather than sending an over-sized request that the API rejects.
* **Fix**: `FcmError` and `FirebaseMessage` implement value equality, so `ServerResult ==` compares content rather than object identity.
* **Fix**: Topic management now honours the disposed state and throws a clear `StateError`, matching `send()`.

### New Features

* **Feat**: `requestTimeout` and `maxConcurrency` parameters on every constructor.
* **Feat**: `obtainCredentials()` is exposed as a `@protected` `@visibleForTesting` seam, allowing the send path to be tested without contacting Google.

### Improvements

* **Test**: Added 43 tests covering the send path, retry and backoff behaviour, 401 recovery, concurrency limits, topic batching, payload serialisation, and argument validation — none of which had coverage before.
* **Chore**: Added a direct dependency on `meta`.

## 3.0.2 (FCM v1 API Compliance & Bug Fixes)

### Bug Fixes

* **Fix (Critical)**: `onRegistrationChange` callback no longer fires on transient errors (`QUOTA_EXCEEDED`, `UNAVAILABLE`, `INTERNAL`). Previously it marked valid tokens as unregistered on any failure, causing premature token deletion. Now only fires on `UNREGISTERED` and `SENDER_ID_MISMATCH`.
* **Fix (Critical)**: `AndroidNotificationProxy.ifPriorityDegraded` renamed to `ifPriorityLowered` — the previous value `IF_PRIORITY_DEGRADED` does not exist in the FCM v1 API. Corrected to `IF_PRIORITY_LOWERED` per the official spec.
* **Fix (Critical)**: `FCMColor` fields changed from `int` (0–255) to `double` (0.0–1.0). The FCM v1 API defines color components as floats in the range `[0, 1]`, not integers.
* **Fix**: `INTERNAL` (HTTP 500) errors are now correctly marked as retryable, matching the official FCM error documentation.
* **Fix**: Removed phantom `image` field from `FirebaseFcmOptions`. The top-level `FcmOptions` in the FCM v1 API only contains `analyticsLabel` — the `image` field never had any effect.

### New Features

* **Feat**: Added `AndroidFcmOptions` class with `analyticsLabel` field and `fcmOptions` on `FirebaseAndroidConfig`, enabling per-platform analytics labels for Android.
* **Feat**: Added `bandwidthConstrainedOk` and `restrictedSatelliteOk` fields to `FirebaseAndroidConfig` per the FCM v1 API spec.
* **Feat**: `sendMessages()` now executes in **parallel** via `Future.wait`, matching the official Admin SDK `sendEach()` behavior. Previously sent sequentially.
* **Feat**: `sendToTopic()` and `sendToCondition()` now accept an optional `validateOnly` parameter for dry-run validation.
* **Feat**: Added `liveActivityToken` field to `FirebaseApnsConfig` for Apple Live Activity updates (iOS 16.1+).
* **Feat**: `_send()` now asserts that exactly one of `token`, `topic`, or `condition` is set on the message, catching misuse early.

### Improvements

* **Feat**: `Retry-After` header is now honored when present on 429/503 responses, falling back to exponential backoff otherwise. Per FCM best practices.
* **Refactor**: `performAuth()` deprecated — token management is now fully internal via `_performAuth()`.
* **Refactor**: `fromServiceAccountFile()` now throws a clear `ArgumentError` instead of a `CastError` when given an invalid type.
* **Refactor**: Removed unused `collection` dependency.
* **Refactor**: Cleaned up orphaned comments and stale doc references.
* **Refactor**: Calling any method after `dispose()` now throws a clear `StateError` instead of an opaque HTTP client error.

### Breaking Changes

* `AndroidNotificationProxy.ifPriorityDegraded` → `AndroidNotificationProxy.ifPriorityLowered`
* `FCMColor` fields changed from `int?` to `double?`
* `FirebaseFcmOptions.image` removed (was never part of the FCM v1 API)
* `performAuth()` deprecated in favor of automatic token management

## 3.0.1 (Deep Hardening & Optimization)

* **Records for Performance**: Integrated Dart 3 Records in `sendToMultiple` for efficient intermediate data mapping, reducing object allocation overhead during large fan-outs.
* **Pattern Destructuring**: Modernized HTTP response handling and JSON parsing using pattern matching for cleaner, type-safe logic.
* **Architectural Hardening**: Applied strict class modifiers (`final`, `base`) project-wide and resolved all 89 analysis violations including unsafe `dynamic` calls.
* **Strict Quality**: Enabled `avoid_dynamic_calls`, `prefer_final_locals`, and `strict-inference` analysis flags for enterprise-grade safety.
* **Backward Compatibility**: Optimized dependency constraints (`json_annotation: ^4.9.0`) to maintain full support for Dart 3.0.0 and resolve build-time SDK warnings.
* **Memory Efficiency**: Enforced `const` constructors across all data models to minimize runtime memory footprint.
* **Code Hygiene**: Refactored internal result handling and improved error extraction logic.

## 3.0.0 (Dart 3 Modernization)

**Major Breaking Change**: Renamed package from `firebase_cloud_messaging_flutter` to `firebase_cloud_messaging_dart`.

This update accurately reflects the library's status as a pure Dart package, suitable for both Flutter and server-side environments like **Serverpod**.

### 🚀 Key Improvements (Dart 3)

* **Sealed Results**: `ServerResult` is now a `sealed` class hierarchy (`ServerSuccess`, `ServerFailure`). This allows for type-safe exhaustive pattern matching when handling send outcomes.
* **Switch Expressions**: Refactored internal error parsing logic to use concise Dart 3 switch expressions.
* **Class Modifiers**: Applied `final` class modifiers to core data models (e.g., `FirebaseAndroidConfig`, `FirebaseApnsConfig`, `FcmError`) to improve architectural integrity and compiler optimization.
* **SDK Alignment**: Bumped minimum SDK constraint to `^3.0.0`.

### ⚠️ Breaking Changes

* **Package Rename**: All imports must now use `package:firebase_cloud_messaging_dart/`.
* **Main Entry Point**: Renamed from `firebase_cloud_messaging_server.dart` to `firebase_cloud_messaging_dart.dart`.
* **Result Matching**: Since `ServerResult` is now sealed, users should switch to type-safe pattern matching or check for `ServerSuccess`/`ServerFailure` concrete types. Legacy properties (`messageSent`, `fcmError`, `errorBody`) are preserved on the base class for backward compatibility but using the subclasses is recommended.

## 2.1.0

This release elevates the package to a production-hardened server-side SDK by introducing native ambient credentials and dedicated topic management.

* **Feat (Auth)**: Introduced `FirebaseCloudMessagingServer.applicationDefault({ required String projectId })`. Supports Google Application Default Credentials (ADC) for seamless authentication in Cloud Run, App Engine, and Firebase Functions.
* **Feat (Topic Management)**: Added `subscribeTokensToTopic()` and `unsubscribeTokensFromTopic()`. These utilize the Firebase Instance ID API for efficient batch management (up to 1,000 tokens per request).
* **Refactor (Architecture)**: Introduced `FcmTopicManagement` internal class to centralize topic lifecycle logic.
* **Refactor (Breaking)**: Migrated project-wide filename convention to standard Dart snake_case (e.g., `android_config.dart`). All internal imports and public exports have been updated.
* **Hardening**: Consolidated network logic into a shared, reusable `http.Client` to prevent socket leaks.
* **Typing**: Added missing priority and visibility fields to platform-specific configs.

## 2.0.0

### Breaking Changes

* `AndroidMessagePriority.normal` and `.high` now serialize to `"NORMAL"` and `"HIGH"` respectively.
* `FirebaseWebpushConfig.notification` changed to typed `FirebaseWebpushNotification`.
* `FirebaseWebpushConfig.webPushFcmOptions` renamed to `fcmOptions`.
* `ServerResult.messageSent` is now nullable.
* `json_serializable` moved to `dev_dependencies`.

### New Features

* **`sendToMultiple()`** — sends to many tokens in parallel.
* **`sendToTopic()`** — targeted topic messages.
* **`sendToCondition()`** — targeted condition messages.
* **`validateMessage()`** — dry-run support.
* **`onRegistrationChange`** — registration status callback.
* **`FcmLogger`** — structured logging.
* **`FcmRetryConfig`** — exponential back-off retries.
* **`FirebaseCloudMessagingServer.fromServiceAccountJson()`** — load from JSON string.
* **`FirebaseCloudMessagingServer.fromServiceAccountFile()`** — load from File.
* **`dispose()`** — clean resource cleanup.
* **`FcmError`** + **`FcmErrorCode`** — typed FCM error extracted from failed requests.
  responses. Use `isRetryable` to decide whether to back off.
* **`BatchResult`** / **`TokenResult`** — aggregated result from `sendToMultiple`.

### API Completeness

* `FirebaseApnsConfig` — added typed `notification` (`FirebaseApnsNotification`)
  and `fcmOptions` (`ApnsFcmOptions`). Raw `payload` map preserved for
  advanced APS dictionary use.
* New `apns.notification.dart` — `FirebaseApnsNotification`, `ApnsAlert`, `ApnsFcmOptions`.
* `FirebaseWebpushConfig` — replaced raw `Map` fields with typed
  `FirebaseWebpushNotification` and `WebpushFcmOptions`.
* New `webpush.notification.dart` — `FirebaseWebpushNotification`, `WebpushAction`, `WebpushFcmOptions`.
* `FirebaseFcmOptions` — added missing `image` field.
* `FirebaseAndroidConfig` — added `directBootOk` (`direct_boot_ok`) field.
* `FirebaseAndroidNotification` — added `proxy` field with `AndroidNotificationProxy` enum.

### Bug Fixes

* Fixed HTTP client leak: a single `http.Client` is now reused across all
  send calls and closed via `dispose()`. Previously a new client was created
  (and leaked) on every `send()` invocation.
* Fixed `projectID` being re-parsed from JSON on every request; now cached at
  construction time.

### Quality

* Added `copyWith()` to `FirebaseMessage`, `FirebaseSend`, and `ServerResult`.
* Added `ServerResult.errorBody` (raw response body on failure) and
  `ServerResult.fcmError` (typed error).
* `FirebaseSend` now asserts that `message` is non-null at construction time.
* Added full unit test suite in `test/`.
* Updated all dev dependencies to latest versions.
* Updated minimum SDK to `>=2.17.0`.

---

## 1.0.6

* Updated dependencies
* Thanks to [@dsyrstad](https://github.com/dsyrstad)
* Made fixes to .gitignore and removed pubspec.lock to make it conform to a standard Dart package project.
* Upgraded to support Dart 3.0+.
* Fixed commenting — replacing /// with // where appropriate.
* Support Webpush fcm_options and support proper notification object.

## 1.0.5

* Improved code structure and quality

## 1.0.4

* Updated dependencies
* Improved code structure and quality

## 1.0.3

* Improved code structure and quality

## 1.0.2

* Updated Dependencies

## 1.0.1

* Improved Example and Document File

## 1.0.0

* Initial version, minor things missing
