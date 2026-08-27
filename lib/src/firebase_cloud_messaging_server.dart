import 'dart:convert';
import 'dart:io';

import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
import 'package:firebase_cloud_messaging_dart/src/logic/fcm_topic_management.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// A server-side client for sending Firebase Cloud Messages via FCM HTTP v1.
///
/// FCM send guide: https://firebase.google.com/docs/cloud-messaging/send/v1-api
/// REST reference: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages
/// Error guidance: https://firebase.google.com/docs/cloud-messaging/error-codes
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
///         fid: '<firebase-installation-id>',
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
  /// See https://firebase.google.com/docs/cloud-messaging/error-codes.
  ///
  /// [requestTimeout] — per-request HTTP timeout (default: 30 seconds).
  ///
  /// `Retry-After` is parsed according to https://www.rfc-editor.org/rfc/rfc9110.html#field.retry-after.
  ///
  /// [maxConcurrency] — cap on simultaneous in-flight requests for the
  /// fan-out methods [sendToMultiple], [sendToFids], and [sendMessages]
  /// (default: 50).
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
    this.closeHttpClient = true,
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
    retryConfig.validate();

    if (firebaseServiceCredentials != null) {
      // Cache the projectId so we don't re-parse the entire JSON on every send.
      final FirebaseServiceModel model = FirebaseServiceModel.fromJson(
        firebaseServiceCredentials!,
      );
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
    bool closeHttpClient = true,
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
      closeHttpClient: closeHttpClient,
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
    bool closeHttpClient = true,
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
      closeHttpClient: closeHttpClient,
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
    bool closeHttpClient = true,
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
      closeHttpClient: closeHttpClient,
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

  /// Whether [dispose] closes the HTTP client supplied to this server.
  final bool closeHttpClient;

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

  /// Sends a message to one Firebase Installation ID.
  Future<ServerResult> sendToFid(
    String fid,
    FirebaseMessage message, {
    bool validateOnly = false,
  }) {
    if (fid.trim().isEmpty) {
      throw ArgumentError.value(fid, 'fid', 'must not be blank');
    }
    // copyWith makes the FID the only active target on the message.
    return _send(
      FirebaseSend(
        validateOnly: validateOnly,
        message: message.copyWith(fid: fid),
      ),
    );
  }

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
      FcmLogLevel.info,
      'sendToMultiple: sending to ${tokens.length} tokens',
    );

    // Fan out with a bounded number of simultaneous requests, preserving the
    // order of the input tokens in the results.
    final List<TokenResult> results = await _runBounded<TokenResult>(
      tokens.length,
      (int index) async {
        final String token = tokens[index];
        try {
          final ServerResult serverResult = await _send(
            FirebaseSend(
              validateOnly: validateOnly,
              message: messageTemplate.copyWith(token: token),
            ),
          );
          return TokenResult(token: token, serverResult: serverResult);
        } catch (error, stackTrace) {
          logger(
            FcmLogLevel.error,
            'Token send failed',
            error: error,
            stackTrace: stackTrace,
          );
          return TokenResult(
            token: token,
            serverResult: ServerFailure(
              statusCode: 0,
              errorPhrase: 'Transport or local validation failure',
              errorBody: error.toString(),
            ),
          );
        }
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

  /// Sends the same message to multiple Firebase Installation IDs.
  ///
  /// FCM target schema: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#Message
  Future<BatchResult> sendToFids({
    required List<String> fids,
    required FirebaseMessage messageTemplate,
    bool validateOnly = false,
  }) async {
    if (fids.isEmpty) {
      throw ArgumentError.value(fids, 'fids', 'must not be empty');
    }
    if (fids.any((String fid) => fid.trim().isEmpty)) {
      throw ArgumentError.value(fids, 'fids', 'must not contain blank FIDs');
    }

    // Keep one result per input FID and isolate failures to that item.
    final List<TokenResult> results = await _runBounded<TokenResult>(
      fids.length,
      (int index) async {
        final String fid = fids[index];
        try {
          final ServerResult serverResult = await _send(
            FirebaseSend(
              validateOnly: validateOnly,
              message: messageTemplate.copyWith(fid: fid),
            ),
          );
          return TokenResult(token: fid, serverResult: serverResult);
        } catch (error, stackTrace) {
          logger(
            FcmLogLevel.error,
            'FID send failed',
            error: error,
            stackTrace: stackTrace,
          );
          return TokenResult(
            token: fid,
            serverResult: ServerFailure(
              statusCode: 0,
              errorPhrase: 'Transport or local validation failure',
              errorBody: error.toString(),
            ),
          );
        }
      },
    );
    return BatchResult(results: results);
  }

  /// Convenience method to send a message to an FCM **topic**.
  ///
  /// FCM target reference: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#Message
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
        message: message.copyWith(topic: topic),
      ),
    );
  }

  /// Convenience method to send a message to devices matching a **condition**.
  ///
  /// FCM target reference: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#Message

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
        message: message.copyWith(condition: condition),
      ),
    );
  }

  /// Validates a message payload without actually delivering it.
  ///
  /// FCM `validateOnly` reference: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#SendMessageRequest

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

    // A caught item failure preserves result cardinality for callers.
    final List<ServerResult> results = await _runBounded<ServerResult>(
      sendObjects.length,
      (int index) async {
        try {
          return await _send(sendObjects[index]);
        } catch (error, stackTrace) {
          logger(
            FcmLogLevel.error,
            'Batch message send failed',
            error: error,
            stackTrace: stackTrace,
          );
          return ServerFailure(
            statusCode: 0,
            errorPhrase: 'Transport or local validation failure',
            errorBody: error.toString(),
          );
        }
      },
    );

    final int successCount = results
        .where((ServerResult r) => r.successful)
        .length;
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
  /// Auth guide: https://firebase.google.com/docs/cloud-messaging/auth-server
  /// Scope: `https://www.googleapis.com/auth/firebase.messaging`
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
  ///
  /// Endpoint contract: https://firebase.google.com/docs/cloud-messaging/send/v1-api

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

    final List<String> validationErrors = message.validateForSend();
    if (validationErrors.isNotEmpty) {
      throw ArgumentError.value(
        message,
        'sendObject.message',
        validationErrors.join(' '),
      );
    }

    // Ensure we have a valid, non-expired access token.
    await _ensureValidToken();

    return _sendWithRetry(sendObject, attempt: 0);
  }

  /// Performs the FCM `projects.messages.send` POST, retrying retryable failures.
  ///
  /// Retry guidance: https://firebase.google.com/docs/cloud-messaging/error-codes

  ///
  /// [authRefreshed] tracks whether a forced token refresh has already been
  /// attempted for this request, so a stale-credential 401 is retried exactly
  /// once without consuming the [retryConfig] budget.
  Future<ServerResult> _sendWithRetry(
    FirebaseSend sendObject, {
    required int attempt,
    bool authRefreshed = false,
  }) async {
    final Uri url = Uri.parse('$_fcmApiEndpoint/$_projectId/messages:send');

    // OAuth refresh retries the same attempt; backoff retries increment it.
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_accessCredentials!.accessToken.data}',
    };

    logger(FcmLogLevel.debug, 'Sending FCM request (attempt ${attempt + 1})');

    final http.Response response;
    try {
      response = await _httpClient
          .post(url, headers: headers, body: json.encode(sendObject.toJson()))
          .timeout(requestTimeout);
    } on Exception catch (e, st) {
      // Connection resets, DNS failures and timeouts are transient: spend a
      // retry on them rather than surfacing them to the caller immediately.
      if (attempt < retryConfig.maxRetries) {
        final Duration delay = retryConfig.delayForAttempt(
          attempt,
          applyJitter: true,
        );
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

      logger(
        FcmLogLevel.error,
        'HTTP request failed',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }

    final bool successful = response.statusCode == 200;
    final Map<String, dynamic>? bodyMap = _tryParseJson(response.body);
    final FcmError? fcmError = !successful && bodyMap != null
        ? FcmError.fromResponseBody(bodyMap)
        : null;

    // Refresh only for OAuth authentication failures. A third-party APNs or
    // Web Push credential error is also HTTP 401 but cannot be fixed by replay.
    if (response.statusCode == 401 &&
        !authRefreshed &&
        (fcmError == null || fcmError.isOAuthAuthenticationError)) {
      logger(
        FcmLogLevel.warning,
        'FCM returned an OAuth 401 — refreshing access token and retrying once',
      );
      await _ensureValidToken(forceRefresh: true);
      return _sendWithRetry(sendObject, attempt: attempt, authRefreshed: true);
    }

    final String? targetToken = sendObject.message?.token;
    final String? targetFid = sendObject.message?.fid;

    if (successful) {
      // FCM may return an empty success body, so provide a valid empty model.
      final FirebaseMessage messageSent = bodyMap != null
          ? FirebaseMessage.fromJson(bodyMap)
          : const FirebaseMessage();

      final ServerSuccess result = ServerSuccess(
        statusCode: response.statusCode,
        messageSent: messageSent,
        responseHeaders: response.headers,
        attempts: attempt + 1,
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
      responseHeaders: response.headers,
      attempts: attempt + 1,
    );

    logger(
      FcmLogLevel.warning,
      'FCM request failed [${response.statusCode}]: '
      '${fcmError?.status ?? response.reasonPhrase}',
    );

    // Only mark a token as invalid when FCM explicitly rejects it as such.
    // Transient errors (quota, unavailable) do not invalidate the token.
    if (targetToken != null &&
        fcmError?.errorCode == FcmErrorCode.unregistered) {
      onRegistrationChange?.call(
        targetToken,
        FcmRegistrationStatus.unregistered,
      );
    }
    if (targetFid != null &&
        fcmError?.errorCode == FcmErrorCode.installationIdNotRegistered) {
      logger(
        FcmLogLevel.warning,
        'Firebase Installation ID is no longer registered',
      );
    }

    // Retry transient FCM status codes even when the body is empty or not JSON.
    final bool retryableStatus =
        response.statusCode == 429 ||
        response.statusCode == 500 ||
        response.statusCode == 503;
    final bool retryableError = fcmError?.isRetryable ?? false;
    if ((retryableStatus || retryableError) &&
        attempt < retryConfig.maxRetries) {
      final Duration delay = _retryDelay(
        response,
        attempt,
        isQuota:
            response.statusCode == 429 ||
            fcmError?.errorCode == FcmErrorCode.quotaExceeded,
      );
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

  /// Subscribes registration [tokens] to an FCM [topic].
  ///
  /// Deprecated Instance ID transport. References:
  /// https://firebase.google.com/docs/cloud-messaging/manage-topic-subscriptions
  /// https://developers.google.com/instance-id/reference
  /// The legacy endpoint accepts 1,000 tokens per call; longer lists are split.
  /// The [topic] should not include the `"/topics/"` prefix.
  @Deprecated('Uses the legacy Instance ID topic API.')
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

  /// Unsubscribes registration [tokens] from an FCM [topic].
  ///
  /// Deprecated Instance ID transport. References:
  /// https://firebase.google.com/docs/cloud-messaging/manage-topic-subscriptions
  /// https://developers.google.com/instance-id/reference
  /// The legacy endpoint accepts 1,000 tokens per call; longer lists are split.
  /// The [topic] should not include the `"/topics/"` prefix.
  @Deprecated('Uses the legacy Instance ID topic API.')
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

  /// Internal driver for the legacy Instance ID API.
  ///
  /// `messages:send` sends to topics but does not manage subscriptions.
  /// Reference: https://developers.google.com/instance-id/reference
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
    if (tokens.any((String token) => token.trim().isEmpty)) {
      throw ArgumentError.value(
        tokens,
        'tokens',
        'must not contain blank tokens',
      );
    }
    if (topic.trim().isEmpty || !_validTopicName(topic)) {
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
    // Results are accumulated in input order across the 1,000-token chunks.
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
            retryConfig: retryConfig,
            refreshAccessToken: () async {
              await _ensureValidToken(forceRefresh: true);
              return _accessCredentials!.accessToken.data;
            },
          );

      for (final TopicManagementTokenResult failed
          in chunkResult.failedResults) {
        if (failed.error == 'NOT_FOUND' || failed.error == 'UNREGISTERED') {
          onRegistrationChange?.call(
            failed.token,
            FcmRegistrationStatus.unregistered,
          );
        }
      }
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
    final bool isExpired =
        hasCredentials &&
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

  /// Returns a Retry-After delay or the configured exponential backoff.
  // Server-provided Retry-After takes precedence over local backoff policy.
  Duration _retryDelay(
    http.Response response,
    int attempt, {
    required bool isQuota,
  }) {
    final String? retryAfter = response.headers['retry-after']?.trim();
    if (retryAfter != null && retryAfter.isNotEmpty) {
      final int? seconds = int.tryParse(retryAfter);
      if (seconds != null && seconds >= 0) {
        return Duration(seconds: seconds);
      }
      final DateTime? retryAt = DateTime.tryParse(retryAfter);
      if (retryAt != null) {
        final Duration delay = retryAt.toUtc().difference(
          DateTime.now().toUtc(),
        );
        return delay.isNegative ? Duration.zero : delay;
      }
    }
    return isQuota
        ? retryConfig.quotaDelayForAttempt(attempt, applyJitter: true)
        : retryConfig.delayForAttempt(attempt, applyJitter: true);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  bool _validTopicName(String value) {
    return RegExp(r'^[a-zA-Z0-9-_.~%]{1,900}$').hasMatch(value);
  }

  /// Closes the underlying HTTP client and releases resources.
  ///
  /// FCM error/retry guidance: https://firebase.google.com/docs/cloud-messaging/error-codes

  ///
  /// Call this when the server is no longer needed (e.g., in `dispose()` of
  /// a widget or service locator cleanup). After calling [dispose], the server
  /// instance should not be used again.
  void dispose() {
    // Mark disposed before closing so later or re-entrant sends fail clearly.
    _disposed = true;
    if (closeHttpClient) {
      _httpClient.close();
    }
    logger(FcmLogLevel.debug, 'FirebaseCloudMessagingServer disposed');
  }
}

// ---------------------------------------------------------------------------
// ServerResult
// ---------------------------------------------------------------------------

/// Holds the outcome of a single FCM HTTP v1 send request.
///
/// Response contract: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages

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
    this.responseHeaders = const <String, String>{},
    this.attempts = 1,
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

  /// Response headers, including `Retry-After` when supplied by FCM.
  /// Syntax: https://www.rfc-editor.org/rfc/rfc9110.html#field.retry-after

  final Map<String, String> responseHeaders;

  /// Number of HTTP attempts used for this result.
  final int attempts;

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
        other.fcmError == fcmError &&
        other.responseHeaders.toString() == responseHeaders.toString() &&
        other.attempts == attempts;
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
      responseHeaders.toString(),
      attempts,
    );
  }
}

/// Represents a successful FCM send outcome.
final class ServerSuccess extends ServerResult {
  const ServerSuccess({
    required super.statusCode,
    required FirebaseMessage messageSent,
    super.responseHeaders,
    super.attempts,
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
    super.responseHeaders,
    super.attempts,
  }) : super(successful: false);
}
