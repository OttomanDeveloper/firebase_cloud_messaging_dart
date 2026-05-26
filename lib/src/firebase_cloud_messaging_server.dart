import 'dart:convert';
import 'dart:io';

import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
import 'package:firebase_cloud_messaging_dart/src/logic/fcm_topic_management.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

/// A server-side client for sending Firebase Cloud Messages via the
/// FCM HTTP v1 API directly from Dart or Flutter.
///
/// The default base endpoint used is [_fcmApiEndpoint].
///
/// ## Quick start
/// ```dart
/// import 'dart:convert';
/// import 'dart:io';
/// import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
///
/// void main() async {
///   final credentials = jsonDecode(
///     File('serviceAccountKey.json').readAsStringSync(),
///   ) as Map<String, dynamic>;
///
///   final server = FirebaseCloudMessagingServer(credentials);
///
///   final result = await server.send(
///     FirebaseSend(
///       message: FirebaseMessage(
///         token: '<device-token>',
///         notification: FirebaseNotification(
///           title: 'Hello!',
///           body: 'Message from the server.',
///         ),
///       ),
///     ),
///   );
///
///   print(result);
///   server.dispose(); // Always dispose when done.
/// }
/// ```
///
/// ## Authentication
/// [FirebaseCloudMessagingServer] authenticates with FCM using a
/// [Google Service Account](https://firebase.google.com/docs/admin/setup#initialize_the_sdk_in_non-google_environments).
/// Open **Firebase Console → Settings → Service Accounts → Generate new private key**
/// and pass the contents of the downloaded JSON file to this constructor.
///
/// ## Caching & disposal
/// By default ([cacheAuth] = `true`) the OAuth 2.0 access token is reused
/// until it expires (≈1 hour), then refreshed automatically. Call [dispose]
/// when you are done with the server to close the underlying HTTP client.
class FirebaseCloudMessagingServer {

  // ---------------------------------------------------------------------------
  // Constructors
  // ---------------------------------------------------------------------------

  /// Creates a server instance from a pre-parsed service-account [Map].
  ///
  /// [firebaseServiceCredentials] — the full content of the Firebase service
  /// account JSON as a [Map<String, dynamic>].
  ///
  /// [cacheAuth] — whether to reuse the OAuth token until it expires.
  ///
  /// [logger] — optional logging callback (default: silent).
  ///
  /// [retryConfig] — retry behaviour for retryable FCM errors
  /// (default: 3 retries with exponential back-off).
  ///
  /// [projectId] — required ONLY if [firebaseServiceCredentials] is `null` (ADC mode).
  FirebaseCloudMessagingServer(
    this.firebaseServiceCredentials, {
    String? projectId,
    this.cacheAuth = true,
    this.logger = fcmSilentLogger,
    this.retryConfig = const FcmRetryConfig(),
    this.onRegistrationChange,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client() {
    if (firebaseServiceCredentials != null) {
      // Cache the projectId so we don't re-parse the entire JSON on every send.
      final FirebaseServiceModel model =
          FirebaseServiceModel.fromJson(firebaseServiceCredentials!);
      _projectId = model.projectID ?? '';
      assert(
        _projectId.isNotEmpty,
        'Service account JSON is missing the "project_id" field.',
      );
    } else {
      assert(
        projectId != null,
        'Project ID must be provided when using ADC mode.',
      );
      _projectId = projectId!;
    }
  }

  /// Creates a server instance that authenticates using Google Application
  /// Default Credentials (ADC).
  ///
  /// This is the recommended approach for serverless environments like
  /// Google Cloud Run, App Engine, or Firebase Cloud Functions, as it securely
  /// detects the ambient Google Cloud service account identity automatically.
  /// No static JSON file is required.
  ///
  /// Because ADC does not supply the `project_id` upfront, you must provide
  /// your Firebase [projectId] manually.
  factory FirebaseCloudMessagingServer.applicationDefault({
    required String projectId,
    bool cacheAuth = true,
    FcmLogger? logger,
    FcmRetryConfig retryConfig = const FcmRetryConfig(),
    FcmRegistrationCallback? onRegistrationChange,
    http.Client? httpClient,
  }) {
    return FirebaseCloudMessagingServer(
      null,
      projectId: projectId,
      cacheAuth: cacheAuth,
      logger: logger ?? fcmSilentLogger,
      retryConfig: retryConfig,
      onRegistrationChange: onRegistrationChange,
      httpClient: httpClient,
    );
  }

  /// Creates a server instance from a service-account JSON [String].
  ///
  /// This is a convenience for loading the file content directly.
  ///
  /// ```dart
  /// final json = await File('key.json').readAsString();
  /// final server = FirebaseCloudMessagingServer.fromServiceAccountJson(json);
  /// ```
  factory FirebaseCloudMessagingServer.fromServiceAccountJson(
    String jsonString, {
    bool cacheAuth = true,
    FcmLogger? logger,
    FcmRetryConfig retryConfig = const FcmRetryConfig(),
    FcmRegistrationCallback? onRegistrationChange,
    http.Client? httpClient,
  }) {
    final Map<String, dynamic> credentials =
        json.decode(jsonString) as Map<String, dynamic>;
    return FirebaseCloudMessagingServer(
      credentials,
      cacheAuth: cacheAuth,
      logger: logger ?? fcmSilentLogger,
      retryConfig: retryConfig,
      onRegistrationChange: onRegistrationChange,
      httpClient: httpClient,
    );
  }

  /// Creates a server instance by reading a service-account JSON file.
  ///
  /// The [serviceAccountFile] can be a [File] object or a [String] path.
  ///
  /// ```dart
  /// final server = FirebaseCloudMessagingServer.fromServiceAccountFile(
  ///   'serviceAccountKey.json',
  /// );
  /// ```
  factory FirebaseCloudMessagingServer.fromServiceAccountFile(
    Object serviceAccountFile, {
    bool cacheAuth = true,
    FcmLogger? logger,
    FcmRetryConfig retryConfig = const FcmRetryConfig(),
    FcmRegistrationCallback? onRegistrationChange,
    http.Client? httpClient,
  }) {
    final File file;
    if (serviceAccountFile is String) {
      file = File(serviceAccountFile);
    } else if (serviceAccountFile is File) {
      file = serviceAccountFile;
    } else {
      throw ArgumentError.value(
        serviceAccountFile,
        'serviceAccountFile',
        'Must be a File object or a String path.',
      );
    }

    return FirebaseCloudMessagingServer.fromServiceAccountJson(
      file.readAsStringSync(),
      cacheAuth: cacheAuth,
      logger: logger ?? fcmSilentLogger,
      retryConfig: retryConfig,
      onRegistrationChange: onRegistrationChange,
      httpClient: httpClient,
    );
  }
  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  /// The base URL path for the FCM HTTP v1 API.
  static const String _fcmApiEndpoint =
      'https://fcm.googleapis.com/v1/projects';

  // ---------------------------------------------------------------------------
  // Constructor & fields
  // ---------------------------------------------------------------------------

  /// The service account credentials loaded from Firebase Console.
  ///
  /// This is the entire JSON map from the downloaded service-account file.
  /// If `null`, the server expects to authenticate using Google Application
  /// Default Credentials (ADC).
  final Map<String, dynamic>? firebaseServiceCredentials;

  /// When `true` (default), the OAuth access token is cached and reused until
  /// it expires. Set to `false` to force a fresh token on every request.
  final bool cacheAuth;

  /// Optional logger for diagnostic output.
  ///
  /// Defaults to [fcmSilentLogger] which discards all messages.
  /// Supply your own callback to integrate with your logging framework.
  final FcmLogger logger;

  /// Controls automatic retry for retryable FCM errors
  /// (`QUOTA_EXCEEDED`, `UNAVAILABLE`, and `INTERNAL`).
  ///
  /// Defaults to [FcmRetryConfig] (3 retries, exponential back-off).
  final FcmRetryConfig retryConfig;

  /// Optional callback triggered when a token registration becomes invalid.
  final FcmRegistrationCallback? onRegistrationChange;

  /// The FCM project ID extracted from [firebaseServiceCredentials].
  /// Cached at construction time to avoid repeated JSON parsing.
  late final String _projectId;

  /// The cached OAuth 2.0 access token.
  AccessCredentials? _accessCredentials;

  /// Shared HTTP client reused across all send operations.
  /// Closed by [dispose].
  final http.Client _httpClient;

  /// Prevents multiple simultaneous authentication refreshes when
  /// many requests are fired in parallel.
  Future<AccessCredentials>? _authFuture;

  /// Whether [dispose] has been called.
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Public send API
  // ---------------------------------------------------------------------------

  /// Sends a single FCM message.
  ///
  /// Returns a [ServerResult] containing the delivery outcome.
  ///
  /// ```dart
  /// final result = await server.send(
  ///   FirebaseSend(
  ///     message: FirebaseMessage(
  ///       token: deviceToken,
  ///       notification: FirebaseNotification(title: 'Hi', body: 'Hello'),
  ///     ),
  ///   ),
  /// );
  /// if (!result.successful) print(result.fcmError);
  /// ```
  Future<ServerResult> send(FirebaseSend sendObject) => _send(sendObject);

  /// Sends the same notification to [tokens] in **parallel** and returns an
  /// aggregated [BatchResult].
  ///
  /// Internally this creates one [FirebaseSend] per token and fires all
  /// requests concurrently with [Future.wait]. Inspect [BatchResult.failedResults]
  /// to detect stale tokens (e.g., `FcmErrorCode.unregistered`).
  ///
  /// ```dart
  /// final batch = await server.sendToMultiple(
  ///   tokens: allDeviceTokens,
  ///   messageTemplate: FirebaseMessage(
  ///     notification: FirebaseNotification(title: 'Update!', body: 'New version.'),
  ///   ),
  /// );
  /// print('Success: ${batch.successCount} / ${batch.results.length}');
  /// ```
  Future<BatchResult> sendToMultiple({
    required List<String> tokens,
    required FirebaseMessage messageTemplate,
    bool validateOnly = false,
  }) async {
    assert(tokens.isNotEmpty, 'tokens list must not be empty');

    logger(
        FcmLogLevel.info, 'sendToMultiple: sending to ${tokens.length} tokens');

    // Fan out all requests in parallel with Record-based intermediate results.
    final List<Future<(String, ServerResult)>> futures =
        tokens.map((String token) async {
      final ServerResult serverResult = await _send(
        FirebaseSend(
          validateOnly: validateOnly,
          message: messageTemplate.copyWith(token: token),
        ),
      );
      return (token, serverResult);
    }).toList();

    final List<(String, ServerResult)> records = await Future.wait(futures);
    final List<TokenResult> results = records
        .map(((String, ServerResult) r) =>
            TokenResult(token: r.$1, serverResult: r.$2))
        .toList();

    final BatchResult batch = BatchResult(results: results);

    logger(
      FcmLogLevel.info,
      'sendToMultiple: done — ${batch.successCount} succeeded, '
      '${batch.failureCount} failed',
    );
    return batch;
  }

  /// Convenience method to send a message to an FCM **topic**.
  ///
  /// Note: the `"/topics/"` prefix must NOT be included in [topic].
  ///
  /// ```dart
  /// await server.sendToTopic(
  ///   'breaking-news',
  ///   FirebaseMessage(notification: FirebaseNotification(title: '🔥 Breaking')),
  /// );
  /// ```
  Future<ServerResult> sendToTopic(
    String topic,
    FirebaseMessage message, {
    bool validateOnly = false,
  }) {
    return _send(
      FirebaseSend(
        validateOnly: validateOnly,
        message: message.copyWith(
          topic: topic,
        ),
      ),
    );
  }

  /// Convenience method to send a message to devices matching a **condition**.
  ///
  /// Condition syntax: `"'topic1' in topics && 'topic2' in topics"`.
  ///
  /// ```dart
  /// await server.sendToCondition(
  ///   "'sports' in topics || 'news' in topics",
  ///   FirebaseMessage(notification: FirebaseNotification(title: 'Alert')),
  /// );
  /// ```
  Future<ServerResult> sendToCondition(
    String condition,
    FirebaseMessage message, {
    bool validateOnly = false,
  }) {
    return _send(
      FirebaseSend(
        validateOnly: validateOnly,
        message: message.copyWith(
          condition: condition,
        ),
      ),
    );
  }

  /// Validates a message payload without actually delivering it.
  ///
  /// FCM processes the request and returns errors if the payload is invalid,
  /// but the message is never sent.
  ///
  /// ```dart
  /// final result = await server.validateMessage(
  ///   FirebaseSend(message: myMessage),
  /// );
  /// if (!result.successful) print('Payload error: ${result.fcmError}');
  /// ```
  Future<ServerResult> validateMessage(FirebaseSend sendObject) {
    return _send(sendObject.copyWith(validateOnly: true));
  }

  /// Sends multiple pre-built [FirebaseSend] objects in **parallel**.
  ///
  /// Use this when each message is distinct (different payloads, different
  /// targets). For sending the same message to many tokens, prefer
  /// [sendToMultiple].
  ///
  /// Returns a [List<ServerResult>] in the same order as [sendObjects].
  Future<List<ServerResult>> sendMessages(
    List<FirebaseSend> sendObjects,
  ) async {
    assert(sendObjects.isNotEmpty, 'sendObjects list must not be empty');

    logger(
      FcmLogLevel.info,
      'sendMessages: sending ${sendObjects.length} messages',
    );

    final List<ServerResult> results =
        await Future.wait(sendObjects.map(_send));

    final int successCount =
        results.where((ServerResult r) => r.successful).length;
    logger(
      FcmLogLevel.info,
      'sendMessages: done — $successCount succeeded, '
      '${results.length - successCount} failed',
    );

    return results;
  }

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Fetches a fresh OAuth 2.0 access token from Google and caches it.
  ///
  /// Token management is handled automatically — prefer calling [send] directly.
  /// Use this only to explicitly pre-warm credentials before the first send.
  @Deprecated(
    'Token management is automatic. '
    'Call send() directly; auth is handled internally.',
  )
  Future<AccessCredentials> performAuth() => _performAuth();

  Future<AccessCredentials> _performAuth() async {
    logger(FcmLogLevel.debug, 'Requesting new OAuth access token from Google');

    const List<String> scopes = <String>[
      'https://www.googleapis.com/auth/firebase.messaging',
    ];

    if (firebaseServiceCredentials != null) {
      final ServiceAccountCredentials accountCredentials =
          ServiceAccountCredentials.fromJson(firebaseServiceCredentials!);

      // Use the shared client for auth.
      _accessCredentials = await obtainAccessCredentialsViaServiceAccount(
        accountCredentials,
        scopes,
        _httpClient,
      );
    } else {
      // Application Default Credentials (ADC)
      // clientViaApplicationDefaultCredentials creates its own AuthClient
      // wrapping a default inner HTTP client, which we then close after grabbing
      // the token, avoiding resource leaks.
      final AutoRefreshingAuthClient authClient =
          await clientViaApplicationDefaultCredentials(scopes: scopes);
      try {
        _accessCredentials = authClient.credentials;
      } finally {
        authClient.close();
      }
    }

    logger(
      FcmLogLevel.debug,
      'Access token obtained. Expires: ${_accessCredentials!.accessToken.expiry}',
    );

    return _accessCredentials!;
  }

  // ---------------------------------------------------------------------------
  // Core send implementation
  // ---------------------------------------------------------------------------

  /// Sends [sendObject] to FCM, handling auth refresh and retries.
  Future<ServerResult> _send(FirebaseSend sendObject) async {
    if (_disposed) {
      throw StateError(
        'FirebaseCloudMessagingServer has been disposed. '
        'Create a new instance to continue sending messages.',
      );
    }
    assert(
      sendObject.message != null,
      'FirebaseSend.message must not be null.',
    );
    assert(
      <String?>[
        sendObject.message?.token,
        sendObject.message?.topic,
        sendObject.message?.condition,
      ].where((String? v) => v != null).length == 1,
      'FirebaseMessage must have exactly one of token, topic, or condition set.',
    );

    // Ensure we have a valid, non-expired access token.
    await _ensureValidToken();

    return _sendWithRetry(sendObject, attempt: 0);
  }

  /// Performs the actual HTTP POST, retrying on retryable failures.
  Future<ServerResult> _sendWithRetry(
    FirebaseSend sendObject, {
    required int attempt,
  }) async {
    final Uri url = Uri.parse(
      '$_fcmApiEndpoint/$_projectId/messages:send',
    );

    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_accessCredentials!.accessToken.data}',
    };

    logger(
      FcmLogLevel.debug,
      'Sending FCM request (attempt ${attempt + 1})',
    );

    final http.Response response;
    try {
      response = await _httpClient.post(
        url,
        headers: headers,
        body: json.encode(sendObject.toJson()),
      );
    } catch (e, st) {
      logger(FcmLogLevel.error, 'HTTP request failed',
          error: e, stackTrace: st);
      rethrow;
    }

    // Use pattern destructuring to handle status and body parsing.
    final (bool successful, Map<String, dynamic>? bodyMap) = (
      response.statusCode == 200,
      _tryParseJson(response.body),
    );

    // Extract a typed FCM error when the request was not successful.
    FcmError? fcmError;
    if (!successful && bodyMap != null) {
      fcmError = FcmError.fromResponseBody(bodyMap);
    }

    final String? targetToken = sendObject.message?.token;

    if (successful) {
      final FirebaseMessage messageSent = bodyMap != null
          ? FirebaseMessage.fromJson(bodyMap)
          : const FirebaseMessage();

      final ServerSuccess result = ServerSuccess(
        statusCode: response.statusCode,
        messageSent: messageSent,
      );

      logger(FcmLogLevel.info, 'Message sent: ${result.messageSent.name}');
      if (targetToken != null) {
        onRegistrationChange?.call(targetToken, FcmRegistrationStatus.active);
      }
      return result;
    }

    final ServerFailure result = ServerFailure(
      statusCode: response.statusCode,
      errorPhrase: response.reasonPhrase,
      errorBody: response.body,
      fcmError: fcmError,
    );

    logger(
      FcmLogLevel.warning,
      'FCM request failed [${response.statusCode}]: '
      '${fcmError?.status ?? response.reasonPhrase}',
    );

    // Only mark a token as invalid when FCM explicitly rejects it as such.
    // Transient errors (quota, unavailable) do not invalidate the token.
    if (targetToken != null &&
        (fcmError?.errorCode == FcmErrorCode.unregistered ||
            fcmError?.errorCode == FcmErrorCode.senderIdMismatch)) {
      onRegistrationChange?.call(
          targetToken, FcmRegistrationStatus.unregistered);
    }

    // Retry if the error is transient and we have retries remaining.
    if (fcmError != null &&
        fcmError.isRetryable &&
        attempt < retryConfig.maxRetries) {
      final Duration delay =
          _retryDelay(response, attempt);
      logger(
        FcmLogLevel.warning,
        'Retrying in ${delay.inMilliseconds}ms '
        '(attempt ${attempt + 1}/${retryConfig.maxRetries})',
      );
      await Future<void>.delayed(delay);
      // Refresh token before retry in case it expired during the wait.
      await _ensureValidToken();
      return _sendWithRetry(sendObject, attempt: attempt + 1);
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Topic Management
  // ---------------------------------------------------------------------------

  /// Subscribes a list of registration [tokens] to an FCM [topic].
  ///
  /// This utilizes the Firebase Instance ID API `batchAdd` endpoint.
  /// You can subscribe up to 1,000 tokens in a single request.
  /// The [topic] should not include the `"/topics/"` prefix.
  Future<TopicManagementResult> subscribeTokensToTopic({
    required String topic,
    required List<String> tokens,
  }) async {
    return _modifyTopicSubscription(
      topic: topic,
      tokens: tokens,
      isSubscription: true,
    );
  }

  /// Unsubscribes a list of registration [tokens] from an FCM [topic].
  ///
  /// This utilizes the Firebase Instance ID API `batchRemove` endpoint.
  /// You can unsubscribe up to 1,000 tokens in a single request.
  /// The [topic] should not include the `"/topics/"` prefix.
  Future<TopicManagementResult> unsubscribeTokensFromTopic({
    required String topic,
    required List<String> tokens,
  }) async {
    return _modifyTopicSubscription(
      topic: topic,
      tokens: tokens,
      isSubscription: false,
    );
  }

  /// Internal driver for the Firebase Instance ID API since the `messages:send`
  /// endpoint only _sends_ to topics but doesn't _manage_ them.
  Future<TopicManagementResult> _modifyTopicSubscription({
    required String topic,
    required List<String> tokens,
    required bool isSubscription,
  }) async {
    assert(
      tokens.isNotEmpty && tokens.length <= 1000,
      'Topic management supports between 1 and 1000 tokens per request.',
    );
    assert(
      !topic.contains('/'),
      'Topic string should not contain the `/topics/` prefix — simply provide the name (e.g. "news").',
    );

    // Topic management uses the exact same OAuth 2.0 access token as message delivery.
    await _ensureValidToken();

    return FcmTopicManagement.performBatchOperation(
      topic: topic,
      tokens: tokens,
      accessToken: _accessCredentials!.accessToken.data,
      client: _httpClient,
      isSubscription: isSubscription,
      logger: logger,
    );
  }

  // ---------------------------------------------------------------------------
  // Token validation helper
  // ---------------------------------------------------------------------------

  /// Ensures [_accessCredentials] is populated and non-expired.
  Future<void> _ensureValidToken() async {
    final bool hasCredentials = _accessCredentials != null;
    final bool isExpired = hasCredentials &&
        DateTime.now().isAfter(_accessCredentials!.accessToken.expiry);
    final bool forceRefresh = !cacheAuth;

    if (!hasCredentials || isExpired || forceRefresh) {
      // If an auth request is already in progress, wait for it.
      if (_authFuture != null) {
        await _authFuture;
        return;
      }

      // Capture the future to prevent duplicate triggers.
      _authFuture = _performAuth();
      try {
        await _authFuture;
      } finally {
        _authFuture = null;
      }
    }
  }

  /// Attempts to parse response body as JSON, returning `null` on failure.
  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return json.decode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Returns the retry delay, honoring the `Retry-After` header if present,
  /// otherwise falling back to exponential backoff from [retryConfig].
  Duration _retryDelay(http.Response response, int attempt) {
    final String? retryAfter = response.headers['retry-after'];
    if (retryAfter != null) {
      final int? seconds = int.tryParse(retryAfter);
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
    }
    return retryConfig.delayForAttempt(attempt);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Closes the underlying HTTP client and releases resources.
  ///
  /// Call this when the server is no longer needed (e.g., in `dispose()` of
  /// a widget or service locator cleanup). After calling [dispose], the server
  /// instance should not be used again.
  void dispose() {
    _disposed = true;
    _httpClient.close();
    logger(FcmLogLevel.debug, 'FirebaseCloudMessagingServer disposed');
  }
}

// ---------------------------------------------------------------------------
// ServerResult
// ---------------------------------------------------------------------------

/// Holds the outcome of a single FCM send request.
///
/// Use a `switch` statement for exhaustive handling:
/// ```dart
/// switch (result) {
///   case ServerSuccess(:final messageSent):
///     print('Sent: ${messageSent.name}');
///   case ServerFailure(:final fcmError):
///     print('Error: ${fcmError?.errorCode}');
/// }
/// ```
sealed class ServerResult {

  const ServerResult({
    required this.successful,
    required this.statusCode,
    this.messageSent,
    this.errorPhrase,
    this.errorBody,
    this.fcmError,
  });
  /// Whether FCM accepted and will deliver the message.
  final bool successful;

  /// The HTTP status code returned by FCM (200 on success).
  final int statusCode;

  /// The [FirebaseMessage] identifier returned by FCM on success.
  ///
  /// This field is only guaranteed to be non-null in [ServerSuccess].
  final FirebaseMessage? messageSent;

  /// The HTTP reason phrase (e.g., `"Bad Request"`).
  final String? errorPhrase;

  /// The raw response body on failure, for advanced debugging.
  final String? errorBody;

  /// Structured FCM error extracted from [errorBody], when available.
  final FcmError? fcmError;

  @override
  String toString() {
    return 'ServerResult{successful: $successful, statusCode: $statusCode, '
        'messageSent: $messageSent, errorPhrase: $errorPhrase, '
        'fcmError: $fcmError}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerResult &&
        other.successful == successful &&
        other.statusCode == statusCode &&
        other.messageSent == messageSent &&
        other.errorPhrase == errorPhrase &&
        other.errorBody == errorBody &&
        other.fcmError == fcmError;
  }

  @override
  int get hashCode {
    return Object.hash(
      successful,
      statusCode,
      messageSent,
      errorPhrase,
      errorBody,
      fcmError,
    );
  }
}

/// Represents a successful FCM send outcome.
final class ServerSuccess extends ServerResult {

  const ServerSuccess({
    required super.statusCode,
    required FirebaseMessage messageSent,
  }) : super(successful: true, messageSent: messageSent);
  @override
  FirebaseMessage get messageSent => super.messageSent!;
}

/// Represents a failed FCM send outcome.
final class ServerFailure extends ServerResult {
  const ServerFailure({
    required super.statusCode,
    super.fcmError,
    super.errorPhrase,
    super.errorBody,
  }) : super(successful: false);
}
