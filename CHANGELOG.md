# Changelog

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
