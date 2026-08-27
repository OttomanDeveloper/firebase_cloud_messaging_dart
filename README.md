# firebase_cloud_messaging_dart

[![pub package](https://img.shields.io/pub/v/firebase_cloud_messaging_dart.svg)](https://pub.dev/packages/firebase_cloud_messaging_dart)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](LICENSE)

A pure Dart **server-side** library for sending Firebase Cloud Messages via the [FCM HTTP v1 API](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages). It works in backend servers, CLI tools, Serverpod, and Flutter server isolates. It does **not** implement native Flutter registration, device-token acquisition, foreground/background handlers, or message receiving.

> [!TIP]
> Found an issue? Please [open an issue on GitHub](https://github.com/OttomanDeveloper/firebase_cloud_messaging_dart/issues).

---

## Features

- **Pure Dart** — no Firebase SDK dependency, works anywhere Dart runs
- **FCM HTTP v1 API** — current target and platform-schema support, verified against the official discovery document
- **All platforms** — typed configs for Android, APNs (iOS/macOS), and Web Push
- **Application Default Credentials (ADC)** — seamless auth on Cloud Run, App Engine, Firebase Functions
- **Topic management** — compatibility support for the deprecated Instance ID batch API; use a supported Admin SDK implementation for new systems
- **Parallel delivery** — `sendToMultiple`, `sendToFids`, and `sendMessages` use bounded concurrency and preserve result order
- **Automatic retries** — status-aware exponential backoff, quota-safe delay, jitter, and integer/HTTP-date `Retry-After` handling
- **Typed error handling** — `FcmError` with `FcmErrorCode` enum for programmatic error handling
- **Dart 3.10+** — sealed classes, records, pattern matching, and exhaustive switch

---

## Getting Started

### 1. Install

```yaml
dependencies:
  firebase_cloud_messaging_dart: ^4.0.0
```

### 2. Get credentials

1. Go to **Firebase Console > Project Settings > Service Accounts > Generate new private key**.
2. Save the downloaded file as `serviceAccountKey.json` in your **project root** (next to `pubspec.yaml`):

```
my_app/
├── lib/
├── pubspec.yaml
├── serviceAccountKey.json   <-- place it here
└── .gitignore
```

3. Add it to `.gitignore` immediately:

```
# .gitignore
serviceAccountKey.json
```

> [!CAUTION]
> **Never** commit `serviceAccountKey.json` to version control. It grants full admin access to your Firebase project.

---

## Initialization

```dart
import 'dart:convert';
import 'dart:io';

import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
```

Five ways to create a server instance (choose one). These snippets are intended
for use inside an `async` function; create only the server instance you need:

```dart
// From a file path (simplest)
final serverFromPath = FirebaseCloudMessagingServer.fromServiceAccountFile(
  'serviceAccountKey.json',
);

// From a File object
final serverFromFile = FirebaseCloudMessagingServer.fromServiceAccountFile(
  File('serviceAccountKey.json'),
);

// From a JSON string
final serverFromJson = FirebaseCloudMessagingServer.fromServiceAccountJson(
  await File('serviceAccountKey.json').readAsString(),
);

// From a parsed Map
final serverFromMap = FirebaseCloudMessagingServer(
  jsonDecode(await File('serviceAccountKey.json').readAsString())
      as Map<String, dynamic>,
);

// Application Default Credentials (Cloud Run, App Engine, Firebase Functions)
final serverFromAdc = FirebaseCloudMessagingServer.applicationDefault(
  projectId: 'my-project-id',
);
```

All constructors accept these optional parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `cacheAuth` | `bool` | `true` | Reuse OAuth token until it expires (~1 hour) |
| `logger` | `FcmLogger` | `fcmSilentLogger` | Logging callback |
| `retryConfig` | `FcmRetryConfig` | 3 retries, 1s initial delay | Retry behavior for transient errors |
| `requestTimeout` | `Duration` | 30s | Per-request HTTP timeout; a timeout is retried like any transport failure |
| `maxConcurrency` | `int` | `50` | Cap on simultaneous requests in `sendToMultiple` / `sendToFids` / `sendMessages` |
| `onRegistrationChange` | `FcmRegistrationCallback?` | `null` | Fires when a registration token is confirmed active or explicitly unregistered |
| `httpClient` | `http.Client?` | `null` | Custom HTTP client (useful for testing) |
| `closeHttpClient` | `bool` | `true` | Whether `dispose()` closes the supplied client |

Invalid arguments throw `ArgumentError` — including a message that does not set exactly one of `fid`, `token`, `topic`, or `condition`, an empty token list, blank targets, reserved data keys, or a topic name carrying the `/topics/` prefix.

---

## Sending Messages

### Single installation

```dart
final result = await server.send(
  FirebaseSend(
    message: FirebaseMessage(
      fid: 'firebase-installation-id',
      notification: FirebaseNotification(
        title: 'Hello',
        body: 'World',
        image: 'https://example.com/image.png',
      ),
    ),
  ),
);

switch (result) {
  case ServerSuccess(:final messageSent):
    print('Sent: ${messageSent.name}');
  case ServerFailure(:final fcmError):
    print('Error: ${fcmError?.errorCode}');
}
```

### Firebase Installation ID helpers

FCM’s current HTTP v1 schema exposes `fid` as the preferred installation target and marks the legacy `token` target deprecated. Use `sendToFid` for one installation or `sendToFids` for bounded bulk delivery:

```dart
final result = await server.sendToFid(
  'firebase-installation-id',
  const FirebaseMessage(notification: FirebaseNotification(title: 'Hello')),
);

final batch = await server.sendToFids(
  fids: ['fid-a', 'fid-b'],
  messageTemplate: const FirebaseMessage(
    notification: FirebaseNotification(title: 'Update'),
  ),
);
```

`token` remains available for migration compatibility. New code should store and send FIDs where the client architecture provides them.

### Multiple registration tokens (same message, parallel)

This method targets legacy registration tokens for migration compatibility. FCM’s current schema recommends FIDs where the client architecture provides them. Equivalent to the Admin SDK's `sendEachForMulticast`. Fans out in parallel, with at most `maxConcurrency` requests in flight at a time. `batch.results` preserves the order of the input tokens.

```dart
final batch = await server.sendToMultiple(
  tokens: ['token_a', 'token_b', 'token_c'],
  messageTemplate: FirebaseMessage(
    notification: FirebaseNotification(title: 'Update available'),
  ),
);

print('${batch.successCount} succeeded, ${batch.failureCount} failed');

// Clean up stale tokens
for (final res in batch.failedResults) {
  if (res.serverResult.fcmError?.errorCode == FcmErrorCode.unregistered) {
    await db.removeToken(res.token);
  }
}
```

`BatchResult` provides: `successCount`, `failureCount`, `successfulResults`, `failedResults`, `allSuccessful`, `anySuccessful`.

### Multiple distinct messages (parallel)

Equivalent to the Admin SDK's `sendEach`. Each message can have a different target and payload. The example uses FIDs; legacy `token` targets remain available for migration. Requests are capped at `maxConcurrency` in flight, and results come back in input order.

```dart
final results = await server.sendMessages([
  FirebaseSend(
    message: FirebaseMessage(
      fid: 'fid-a',
      notification: FirebaseNotification(title: 'Message for A'),
    ),
  ),
  FirebaseSend(
    message: FirebaseMessage(
      fid: 'fid-b',
      data: {'action': 'sync'},
    ),
  ),
]);

for (final result in results) {
  print('${result.successful ? "OK" : "FAIL"}: ${result.statusCode}');
}
```

### Send to topic

```dart
final result = await server.sendToTopic(
  'breaking-news',
  FirebaseMessage(
    notification: FirebaseNotification(title: 'Breaking News!'),
  ),
);
```

### Send to condition

```dart
final result = await server.sendToCondition(
  "'sports' in topics || 'news' in topics",
  FirebaseMessage(
    notification: FirebaseNotification(title: 'Sports & News'),
  ),
);
```

Both `sendToTopic` and `sendToCondition` accept an optional `validateOnly` parameter for dry-run validation.

### Validate without sending

```dart
final result = await server.validateMessage(
  FirebaseSend(
    message: FirebaseMessage(
      fid: 'firebase-installation-id',
      notification: FirebaseNotification(title: 'Test'),
    ),
  ),
);

if (!result.successful) {
  print('Invalid payload: ${result.fcmError?.message}');
}
```

---

## Topic Management

Subscribe and unsubscribe tokens using the **deprecated Firebase Instance ID batch API** for compatibility. The endpoint accepts 1,000 tokens per call — longer lists are split into sequential batches automatically and returned as one combined result. New systems should use a supported Firebase Admin topic-management implementation instead.

```dart
// Subscribe
final subResult = await server.subscribeTokensToTopic(
  topic: 'news',
  tokens: ['token1', 'token2', 'token3'],
);
print('Subscribed: ${subResult.successCount}/${subResult.results.length}');

// Unsubscribe
final unsubResult = await server.unsubscribeTokensFromTopic(
  topic: 'news',
  tokens: ['token1'],
);
```

`TopicManagementResult` provides: `successCount`, `failureCount`, `results` (per-token), `allSuccessful`, `failedResults`.

Each `TopicManagementTokenResult` has: `token`, `successful`, `error`.

---

## Platform-Specific Configuration

### Android

```dart
FirebaseMessage(
  fid: 'firebase-installation-id',
  notification: FirebaseNotification(title: 'Hello'),
  android: FirebaseAndroidConfig(
    priority: AndroidMessagePriority.high,
    ttl: '86400s',
    collapseKey: 'updates',
    directBootOk: true,
    bandwidthConstrainedOk: true,
    restrictedSatelliteOk: false,
    fcmOptions: AndroidFcmOptions(analyticsLabel: 'android_campaign'),
    notification: FirebaseAndroidNotification(
      channelID: 'high_priority',
      icon: 'ic_notification',
      color: '#FF5733',
      sound: 'default',
      tag: 'message-group-1',
      clickAction: 'OPEN_CHAT',
      image: 'https://example.com/banner.png',
      notificationPriority: NotificationPriority.priorityHigh,
      visibility: Visibility.public,
      sticky: false,
      notificationCount: 3,
      lightSettings: LightSettings(
        color: FCMColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
        lightOnDuration: '0.5s',
        lightOffDuration: '1.0s',
      ),
      proxy: AndroidNotificationProxy.ifPriorityLowered,
    ),
  ),
)
```

**`AndroidMessagePriority`** — `normal`, `high`

**`NotificationPriority`** — `priorityUnspecified`, `priorityMin`, `priorityLow`, `priorityDefault`, `priorityHigh`, `priorityMax`

**`Visibility`** — `visibilityUnspecified`, `private`, `public`, `secret`

**`AndroidNotificationProxy`** — `proxyUnspecified`, `allow`, `deny`, `ifPriorityLowered`

### APNs (iOS / macOS)

```dart
FirebaseMessage(
  fid: 'firebase-installation-id',
  apns: FirebaseApnsConfig(
    headers: {'apns-priority': '10'},
    notification: FirebaseApnsNotification(
      title: 'New Message',
      body: 'You have a new message',
      sound: 'default',
      badge: 1,
      category: 'MESSAGE',
      threadId: 'chat-123',
      contentAvailable: 1,
      mutableContent: 1,
      interruptionLevel: InterruptionLevel.timeSensitive,
      relevanceScore: 0.8,
      alert: ApnsAlert(
        title: 'Structured Alert',
        subtitle: 'With subtitle',
        body: 'Full alert body',
        titleLocKey: 'TITLE_KEY',
        titleLocArgs: ['arg1'],
        locKey: 'BODY_KEY',
        locArgs: ['arg1', 'arg2'],
      ),
    ),
    fcmOptions: ApnsFcmOptions(
      analyticsLabel: 'ios_campaign',
      image: 'https://example.com/ios-image.png',
    ),
    payload: {'custom_key': 'custom_value'},
  ),
)
```

**`InterruptionLevel`** — `active`, `critical`, `passive`, `timeSensitive`

### Web Push

```dart
FirebaseMessage(
  fid: 'firebase-installation-id',
  webpush: FirebaseWebpushConfig(
    headers: {'Urgency': 'high', 'TTL': '86400'},
    data: {'click_url': 'https://example.com/page'},
    notification: FirebaseWebpushNotification(
      title: 'New Update',
      body: 'Check it out',
      icon: 'https://example.com/icon.png',
      badge: 'https://example.com/badge.png',
      image: 'https://example.com/banner.png',
      tag: 'update-1',
      requireInteraction: true,
      silent: false,
      renotify: true,
      dir: WebpushDirection.ltr,
      lang: 'en',
      vibrate: [200, 100, 200],
      actions: [
        WebpushAction(
          action: 'open',
          title: 'Open',
          icon: 'https://example.com/open.png',
        ),
        WebpushAction(
          action: 'dismiss',
          title: 'Dismiss',
        ),
      ],
    ),
    fcmOptions: WebpushFcmOptions(
      link: 'https://example.com',
      analyticsLabel: 'web_campaign',
    ),
  ),
)
```

**`WebpushDirection`** — `auto`, `ltr`, `rtl`

### Cross-Platform Options

```dart
FirebaseMessage(
  fid: 'firebase-installation-id',
  notification: FirebaseNotification(
    title: 'Cross-Platform Title',
    body: 'Applies to all platforms',
    image: 'https://example.com/image.png',
  ),
  data: {'key': 'value'},
  fcmOptions: FirebaseFcmOptions(analyticsLabel: 'campaign_v2'),
)
```

---

## Error Handling

Every send returns a `ServerResult` — a sealed class with two subtypes:

```dart
switch (result) {
  case ServerSuccess(:final messageSent):
    print('Message ID: ${messageSent.name}');
  case ServerFailure(:final fcmError, :final statusCode):
    print('HTTP $statusCode: ${fcmError?.message}');
    print('Retryable: ${fcmError?.isRetryable}');
}
```

### FCM Error Codes

| Code | HTTP | Retryable | Meaning |
|------|------|-----------|---------|
| `unregistered` | 404 | No | Registration token is no longer valid — remove it from the database |
| `installationIdNotRegistered` | 404 | No | Firebase Installation ID is no longer registered |
| `senderIdMismatch` | 403 | No | Token doesn't match this project |
| `invalidArgument` | 400 | No | Bad payload or invalid JSON |
| `quotaExceeded` | 429 | Yes | Rate limit hit — backoff and retry |
| `unavailable` | 503 | Yes | FCM temporarily unavailable |
| `internal` | 500 | Yes | FCM server error — retry with backoff |
| `thirdPartyAuthError` | 401 | No | APNs cert or web push auth key invalid |
| `unknown` | — | No | Unrecognized error code |

The code is read from the `google.firebase.fcm.v1.FcmError` entry in `error.details[]`, falling back to the top-level `error.status` when no such entry is present. The complete structured `details` list is retained on `FcmError` for field-level and quota diagnostics. A bare `PERMISSION_DENIED` or `UNAUTHENTICATED` status stays `unknown` on purpose: those are equally consistent with a service-account misconfiguration, and treating them as token failures would wipe healthy tokens from your database.

An expired or revoked access token (HTTP 401) is handled internally — the token is refreshed and the request replayed once before any result is returned.

### Token Registration Callback

Automatically detect invalid tokens without checking every result:

```dart
final serverWithCallback = FirebaseCloudMessagingServer.fromServiceAccountFile(
  'serviceAccountKey.json',
  onRegistrationChange: (String token, FcmRegistrationStatus status) {
    switch (status) {
      case FcmRegistrationStatus.active:
        print('$token confirmed active');
      case FcmRegistrationStatus.unregistered:
        print('$token is invalid — remove it from your token store');
    }
  },
);
```

The callback only fires `unregistered` for an FCM-specific `UNREGISTERED` token error. Generic project/resource errors, `SENDER_ID_MISMATCH`, quota errors, and transient failures do not trigger token deletion.

---

## Retry Configuration

Retryable HTTP statuses (`429`, `500`, and `503`), recognized FCM transient errors, and transport failures are automatically retried with exponential backoff. `Retry-After` integer seconds and HTTP-date values take precedence. Quota retries default to a one-minute initial delay, while generic transient retries use the configured initial delay; equal jitter is applied unless disabled.

```dart
final serverWithRetry = FirebaseCloudMessagingServer.fromServiceAccountFile(
  'serviceAccountKey.json',
  retryConfig: FcmRetryConfig(
    maxRetries: 5,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 60),
  ),
);
```

Backoff formula: `2^attempt * initialDelay`, capped at `maxDelay`.

| Attempt | Delay (with defaults) |
|---------|----------------------|
| 0 | 1s |
| 1 | 2s |
| 2 | 4s |
| 3 | 8s |

To disable retries, pass the preset when constructing the server:

```dart
final serverWithoutRetries =
    FirebaseCloudMessagingServer.fromServiceAccountFile(
  'serviceAccountKey.json',
  retryConfig: FcmRetryConfig.none,
);
```

---

## Logging

Integrate with any logging framework:

```dart
final serverWithLogging = FirebaseCloudMessagingServer.fromServiceAccountFile(
  'serviceAccountKey.json',
  logger: (FcmLogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    print('[FCM ${level.name}] $message');
    if (error != null) print('  Error: $error');
  },
);
```

Log levels: `debug`, `info`, `warning`, `error`.

---

## Data-Only Messages

Send silent background data without showing a notification:

```dart
final result = await server.send(
  FirebaseSend(
    message: FirebaseMessage(
      fid: 'firebase-installation-id',
      data: {
        'action': 'sync',
        'timestamp': DateTime.now().toIso8601String(),
      },
    ),
  ),
);
```

---

## Resource Cleanup

Always dispose the server instance you created. By default this closes the underlying HTTP client; pass `closeHttpClient: false` when the client is owned by the caller:

```dart
serverFromPath.dispose();
```

---

## Complete API Reference

### FirebaseCloudMessagingServer

| Method | Returns | Description |
|--------|---------|-------------|
| `send(FirebaseSend)` | `Future<ServerResult>` | Send a single message |
| `sendToFid(fid, message, {validateOnly})` | `Future<ServerResult>` | Send to a Firebase Installation ID |
| `sendToFids(fids, messageTemplate, {validateOnly})` | `Future<BatchResult>` | Same message to multiple FIDs (bounded parallel) |
| `sendToMultiple(tokens, messageTemplate, {validateOnly})` | `Future<BatchResult>` | Same message to many tokens (parallel) |
| `sendMessages(List<FirebaseSend>)` | `Future<List<ServerResult>>` | Distinct messages (parallel) |
| `sendToTopic(topic, message, {validateOnly})` | `Future<ServerResult>` | Send to topic subscribers |
| `sendToCondition(condition, message, {validateOnly})` | `Future<ServerResult>` | Send to condition match |
| `validateMessage(FirebaseSend)` | `Future<ServerResult>` | Dry-run validation |
| `subscribeTokensToTopic(topic, tokens)` | `Future<TopicManagementResult>` | Deprecated legacy API; subscribe up to 1,000 tokens per request |
| `unsubscribeTokensFromTopic(topic, tokens)` | `Future<TopicManagementResult>` | Deprecated legacy API; unsubscribe up to 1,000 tokens per request |
| `dispose()` | `void` | Close HTTP client |

### Message Models

| Class | Purpose |
|-------|---------|
| `FirebaseSend` | Request wrapper with `validateOnly` flag |
| `FirebaseMessage` | Core message: target + notification + data + platform configs |
| `FirebaseNotification` | Cross-platform title, body, image |
| `FirebaseFcmOptions` | Cross-platform analytics label |

### Platform Configs

| Class | Platform |
|-------|----------|
| `FirebaseAndroidConfig` | Android delivery settings |
| `AndroidFcmOptions` | Android analytics label |
| `FirebaseAndroidNotification` | Android visual notification (42 fields) |
| `LightSettings` | Android LED configuration |
| `FCMColor` | RGBA color (0.0-1.0 floats) |
| `FirebaseApnsConfig` | APNs delivery settings |
| `FirebaseApnsNotification` | APNs APS dictionary |
| `ApnsAlert` | Structured iOS alert |
| `CriticalSound` | APNs critical sound dictionary |
| `ApnsFcmOptions` | APNs analytics label + image |
| `FirebaseWebpushConfig` | Web Push delivery settings |
| `FirebaseWebpushNotification` | Web Notification API fields |
| `WebpushAction` | Web notification action button |
| `WebpushFcmOptions` | Web Push analytics label + click link |

### Result Types

| Class | Purpose |
|-------|---------|
| `ServerResult` | Sealed base: `ServerSuccess` or `ServerFailure`, including response headers and attempt count |
| `BatchResult` | Aggregated multi-token result |
| `TokenResult` | Single token outcome within a batch |
| `TopicManagementResult` | Aggregated topic operation result |
| `TopicManagementTokenResult` | Single token outcome within a topic operation |
| `FcmError` | Structured FCM error with typed `FcmErrorCode` and retained details |

### Configuration

| Class | Purpose |
|-------|---------|
| `FcmRetryConfig` | Retry behavior (max retries, delays) |
| `FirebaseServiceModel` | Parsed service account JSON fields |

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

BSD 3-Clause License. See [LICENSE](LICENSE) for details.
