import 'dart:convert';
import 'dart:io';

import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
import 'package:firebase_cloud_messaging_dart/src/logic/fcm_topic_management.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

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
  /// [requestTimeout] — per-request HTTP timeout (default: 30 seconds).
  ///
  /// [maxConcurrency] — cap on simultaneous in-flight requests for the
  /// fan-out methods [sendToMultiple] and [sendMessages] (default: 50).
  ///
  /// [projectId] — required ONLY if [firebaseServiceCredentials] is `null` (ADC mode).
  ///
  /// Throws an [ArgumentError] if the project ID cannot be determined, or if
  /// [maxConcurrency] / [requestTimeout] are not positive.
  FirebaseCloudMessagingServer(
    this.firebaseServiceCredentials, {
    String? projectId,
    this.cacheAuth = true,
    this.logger = fcmSilentLogger,
    this.retryConfig = const FcmRetryConfig(),
    this.requestTimeout = const Duration(seconds: 30),
    this.maxConcurrency = 50,
    this.onRegistrationChange,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client() {
    if (maxConcurrency < 1) {
      throw ArgumentError.value(
        maxConcurrency,
        'maxConcurrency',
        'must be at least 1',
      );
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be greater than zero',
      );
    }

    if (firebaseServiceCredentials != null) {
      // Cache the projectId so we don't re-parse the entire JSON on every send.
      final FirebaseServiceModel model =
          FirebaseServiceModel.fromJson(firebaseServiceCredentials!);
      final String? parsedProjectId = model.projectID;
      if (parsedProjectId == null || parsedProjectId.isEmpty) {
        throw ArgumentError.value(
          firebaseServiceCredentials,
          'firebaseServiceCredentials',
          'Service account JSON is missing the "project_id" field.',
        );
      }
      _projectId = parsedProjectId;
    } else {
      if (projectId == null || projectId.isEmpty) {
        throw ArgumentError.value(
          projectId,
          'projectId',
          'A project ID is required when no service account is supplied '
              '(ADC mode).',
        );
      }
      _projectId = projectId;
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
    Duration requestTimeout = const Duration(seconds: 30),
    int maxConcurrency = 50,
    FcmRegistrationCallback? onRegistrationChange,
    http.Client? httpClient,
  }) {
    return FirebaseCloudMessagingServer(
      null,
      projectId: projectId,
      cacheAuth: cacheAuth,
      logger: logger ?? fcmSilentLogger,
      retryConfig: retryConfig,
      requestTimeout: requestTimeout,
      maxConcurrency: maxConcurrency,
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
    Duration requestTimeout = const Duration(seconds: 30),
    int maxConcurrency = 50,
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
      requestTimeout: requestTimeout,
      maxConcurrency: maxConcurrency,
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
    Duration requestTimeout = const Duration(seconds: 30),
    int maxConcurrency = 50,
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
      requestTimeout: requestTimeout,
      maxConcurrency: maxConcurrency,
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

  /// Safety margin applied when deciding whether the cached access token is
  /// still usable. Covers clock skew between this host and Google, plus the
  /// time the request itself spends in flight.
  static const Duration _tokenExpiryMargin = Duration(seconds: 60);

  /// Maximum number of tokens the Instance ID batch endpoints accept per call.
  static const int _topicBatchLimit = 1000;

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

  /// Maximum time to wait for a single HTTP response before the attempt is
  /// abandoned. A timed-out attempt is retried like any other transport
  /// failure, subject to [retryConfig].
  ///
  /// Defaults to 30 seconds.
  final Duration requestTimeout;

  /// Upper bound on simultaneously in-flight requests in [sendToMultiple] and
  /// [sendMessages].
  ///
  /// Without a cap, a large token list opens one socket per token, which
  /// exhausts file descriptors and triggers `QUOTA_EXCEEDED` from FCM.
  /// Defaults to 50.
  final int maxConcurrency;

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
  /// Internally this creates one [FirebaseSend] per token and sends them
  /// concurrently, with at most [maxConcurrency] requests in flight at a time.
  /// [BatchResult.results] preserves the order of [tokens]. Inspect
  /// [BatchResult.failedResults] to detect stale tokens
  /// (e.g., `FcmErrorCode.unregistered`).
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
    if (tokens.isEmpty) {
      throw ArgumentError.value(tokens, 'tokens', 'must not be empty');
    }

    logger(
        FcmLogLevel.info, 'sendToMultiple: sending to ${tokens.length} tokens');

    // Fan out with a bounded number of simultaneous requests, preserving the
    // order of the input tokens in the results.
    final List<TokenResult> results = await _runBounded<TokenResult>(
      tokens.length,
      (int index) async {
        final String token = tokens[index];
        final ServerResult serverResult = await _send(
          FirebaseSend(
            validateOnly: validateOnly,
            message: messageTemplate.copyWith(token: token),
          ),
        );
        return TokenResult(token: token, serverResult: serverResult);
      },
    );

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

  /// Sends multiple pre-built [FirebaseSend] objects in **parallel**, with at
  /// most [maxConcurrency] requests in flight at a time.
  ///
  /// Use this when each message is distinct (different payloads, different
  /// targets). For sending the same message to many tokens, prefer
  /// [sendToMultiple].
  ///
  /// Returns a [List<ServerResult>] in the same order as [sendObjects].
  Future<List<ServerResult>> sendMessages(
    List<FirebaseSend> sendObjects,
  ) async {
    if (sendObjects.isEmpty) {
      throw ArgumentError.value(
        sendObjects,
        'sendObjects',
        'must not be empty',
      );
    }

    logger(
      FcmLogLevel.info,
      'sendMessages: sending ${sendObjects.length} messages',
    );

    final List<ServerResult> results = await _runBounded<ServerResult>(
      sendObjects.length,
      (int index) => _send(sendObjects[index]),
    );

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
    _accessCredentials = await obtainCredentials();

    logger(
      FcmLogLevel.debug,
      'Access token obtained. Expires: ${_accessCredentials!.accessToken.expiry}',
    );

    return _accessCredentials!;
  }

  /// Obtains OAuth 2.0 credentials scoped to FCM, either from the configured
  /// service account or from Application Default Credentials.
  ///
  /// Override in a subclass to supply credentials without contacting Google —
  /// this is the seam that makes the send path testable.
  @protected
  @visibleForTesting
  Future<AccessCredentials> obtainCredentials() async {
    logger(FcmLogLevel.debug, 'Requesting new OAuth access token from Google');

    const List<String> scopes = <String>[
      'https://www.googleapis.com/auth/firebase.messaging',
    ];

    if (firebaseServiceCredentials != null) {
      final ServiceAccountCredentials accountCredentials =
          ServiceAccountCredentials.fromJson(firebaseServiceCredentials!);

      // Use the shared client for auth.
      return obtainAccessCredentialsViaServiceAccount(
        accountCredentials,
        scopes,
        _httpClient,
      );
    }

    // Application Default Credentials (ADC)
    // clientViaApplicationDefaultCredentials creates its own AuthClient
    // wrapping a default inner HTTP client, which we then close after grabbing
    // the token, avoiding resource leaks.
    final AutoRefreshingAuthClient authClient =
        await clientViaApplicationDefaultCredentials(scopes: scopes);
    try {
      return authClient.credentials;
    } finally {
      authClient.close();
    }
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
    // Validated with real throws rather than asserts: asserts are stripped
    // from release/AOT builds, which is exactly how this package is deployed.
    final FirebaseMessage? message = sendObject.message;
    if (message == null) {
      throw ArgumentError.value(
        sendObject,
        'sendObject',
        'FirebaseSend.message must not be null.',
      );
    }

    final int targetCount = <String?>[
      message.token,
      message.topic,
      message.condition,
    ].where((String? v) => v != null).length;
    if (targetCount != 1) {
      throw ArgumentError.value(
        message,
        'sendObject.message',
        'must have exactly one of token, topic, or condition set '
            '(found $targetCount).',
      );
    }

    // Ensure we have a valid, non-expired access token.
    await _ensureValidToken();

    return _sendWithRetry(sendObject, attempt: 0);
  }

  /// Performs the actual HTTP POST, retrying on retryable failures.
  ///
  /// [authRefreshed] tracks whether a forced token refresh has already been
  /// attempted for this request, so a stale-credential 401 is retried exactly
  /// once without consuming the [retryConfig] budget.
  Future<ServerResult> _sendWithRetry(
    FirebaseSend sendObject, {
    required int attempt,
    bool authRefreshed = false,
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
      response = await _httpClient
          .post(
            url,
            headers: headers,
            body: json.encode(sendObject.toJson()),
          )
          .timeout(requestTimeout);
    } on Exception catch (e, st) {
      // Connection resets, DNS failures and timeouts are transient: spend a
      // retry on them rather than surfacing them to the caller immediately.
      if (attempt < retryConfig.maxRetries) {
        final Duration delay = retryConfig.delayForAttempt(attempt);
        logger(
          FcmLogLevel.warning,
          'HTTP request failed (${e.runtimeType}) — retrying in '
          '${delay.inMilliseconds}ms '
          '(attempt ${attempt + 1}/${retryConfig.maxRetries})',
          error: e,
        );
        await Future<void>.delayed(delay);
        await _ensureValidToken();
        return _sendWithRetry(
          sendObject,
          attempt: attempt + 1,
          authRefreshed: authRefreshed,
        );
      }

      logger(FcmLogLevel.error, 'HTTP request failed',
          error: e, stackTrace: st);
      rethrow;
    }

    // A 401 after a locally-valid token means the credential was revoked or
    // expired early. Force one refresh and replay before giving up.
    if (response.statusCode == 401 && !authRefreshed) {
      logger(
        FcmLogLevel.warning,
        'FCM returned 401 — refreshing access token and retrying once',
      );
      await _ensureValidToken(forceRefresh: true);
      return _sendWithRetry(
        sendObject,
        attempt: attempt,
        authRefreshed: true,
      );
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
      return _sendWithRetry(
        sendObject,
        attempt: attempt + 1,
        authRefreshed: authRefreshed,
      );
    }

    return result;
  }

  /// Runs [task] for every index in `0..count-1`, keeping at most
  /// [maxConcurrency] futures in flight, and returns the results in index
  /// order.
  Future<List<T>> _runBounded<T>(
    int count,
    Future<T> Function(int index) task,
  ) async {
    final List<T?> results = List<T?>.filled(count, null);
    int cursor = 0;

    // Each worker pulls the next index off the shared cursor. Dart's single
    // isolate event loop makes the read-then-increment atomic.
    Future<void> worker() async {
      while (true) {
        final int index = cursor++;
        if (index >= count) return;
        results[index] = await task(index);
      }
    }

    final int workerCount = count < maxConcurrency ? count : maxConcurrency;
    await Future.wait(<Future<void>>[
      for (int i = 0; i < workerCount; i++) worker(),
    ]);

    return results.cast<T>();
  }

  // ---------------------------------------------------------------------------
  // Topic Management
  // ---------------------------------------------------------------------------

  /// Subscribes a list of registration [tokens] to an FCM [topic].
  ///
  /// This utilizes the Firebase Instance ID API `batchAdd` endpoint, which
  /// accepts 1,000 tokens per call — longer lists are split into sequential
  /// batches automatically and reported as one combined result.
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
  /// This utilizes the Firebase Instance ID API `batchRemove` endpoint, which
  /// accepts 1,000 tokens per call — longer lists are split into sequential
  /// batches automatically and reported as one combined result.
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
    if (_disposed) {
      throw StateError(
        'FirebaseCloudMessagingServer has been disposed. '
        'Create a new instance to continue managing topics.',
      );
    }
    if (tokens.isEmpty) {
      throw ArgumentError.value(tokens, 'tokens', 'must not be empty');
    }
    if (topic.isEmpty || topic.contains('/')) {
      throw ArgumentError.value(
        topic,
        'topic',
        'must be a bare topic name without the "/topics/" prefix '
            '(e.g. "news").',
      );
    }

    // Topic management uses the exact same OAuth 2.0 access token as message delivery.
    await _ensureValidToken();

    // The IID endpoints cap each call at 1000 tokens, so split longer lists
    // into sequential batches and stitch the results back together in order.
    final List<TopicManagementTokenResult> allResults =
        <TopicManagementTokenResult>[];

    for (int start = 0; start < tokens.length; start += _topicBatchLimit) {
      final int end = start + _topicBatchLimit < tokens.length
          ? start + _topicBatchLimit
          : tokens.length;
      final List<String> chunk = tokens.sublist(start, end);

      // Re-check the token between batches: a long run can outlive it.
      await _ensureValidToken();

      final TopicManagementResult chunkResult =
          await FcmTopicManagement.performBatchOperation(
        topic: topic,
        tokens: chunk,
        accessToken: _accessCredentials!.accessToken.data,
        client: _httpClient,
        isSubscription: isSubscription,
        logger: logger,
        timeout: requestTimeout,
      );

      allResults.addAll(chunkResult.results);
    }

    final int successCount = allResults
        .where((TopicManagementTokenResult r) => r.successful)
        .length;

    return TopicManagementResult(
      successCount: successCount,
      failureCount: allResults.length - successCount,
      results: allResults,
    );
  }

  // ---------------------------------------------------------------------------
  // Token validation helper
  // ---------------------------------------------------------------------------

  /// Ensures [_accessCredentials] is populated and non-expired.
  ///
  /// A token is treated as expired [_tokenExpiryMargin] before its stated
  /// expiry, so a token that would lapse mid-flight is replaced up front
  /// instead of producing a 401.
  Future<void> _ensureValidToken({bool forceRefresh = false}) async {
    final bool hasCredentials = _accessCredentials != null;
    final bool isExpired = hasCredentials &&
        DateTime.now()
            .toUtc()
            .add(_tokenExpiryMargin)
            .isAfter(_accessCredentials!.accessToken.expiry);
    final bool mustRefresh = forceRefresh || !cacheAuth;

    if (!hasCredentials || isExpired || mustRefresh) {
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
