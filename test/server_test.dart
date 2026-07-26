import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A server whose OAuth exchange is stubbed out, so the send path can be
/// driven entirely through an injected [http.Client].
final class TestServer extends FirebaseCloudMessagingServer {
  TestServer({
    required http.Client httpClient,
    super.retryConfig = const FcmRetryConfig(maxRetries: 0),
    super.requestTimeout = const Duration(seconds: 5),
    super.maxConcurrency = 50,
    super.onRegistrationChange,
    Duration tokenLifetime = const Duration(hours: 1),
  })  : _tokenLifetime = tokenLifetime,
        super(
          null,
          projectId: 'test-project',
          httpClient: httpClient,
        );

  final Duration _tokenLifetime;

  /// Number of times credentials were requested — lets tests assert that a
  /// 401 forced exactly one refresh.
  int authCount = 0;

  @override
  Future<AccessCredentials> obtainCredentials() async {
    authCount++;
    return AccessCredentials(
      AccessToken(
        'Bearer',
        'fake-token-$authCount',
        DateTime.now().toUtc().add(_tokenLifetime),
      ),
      null,
      <String>['https://www.googleapis.com/auth/firebase.messaging'],
    );
  }
}

/// Builds an FCM error body in the shape the v1 API actually returns.
String errorBody({
  required int code,
  required String status,
  String? detailErrorCode,
  String message = 'boom',
}) {
  return jsonEncode(<String, dynamic>{
    'error': <String, dynamic>{
      'code': code,
      'message': message,
      'status': status,
      if (detailErrorCode != null)
        'details': <Map<String, String>>[
          <String, String>{
            '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
            'errorCode': detailErrorCode,
          },
        ],
    },
  });
}

const String successBody =
    '{"name":"projects/test-project/messages/1234567890"}';

FirebaseSend tokenSend([String token = 'token-a']) => FirebaseSend(
      message: FirebaseMessage(
        token: token,
        notification: const FirebaseNotification(title: 'Hi'),
      ),
    );

void main() {
  // ---------------------------------------------------------------------------
  // FcmError — details[] is authoritative, status is a fallback
  // ---------------------------------------------------------------------------
  group('FcmError code resolution', () {
    test('reads errorCode from the FcmError detail, not the rpc status', () {
      // A 404 arrives with the generic NOT_FOUND status; the FCM code lives
      // in details[].
      final FcmError error = FcmError.fromResponseBody(
        jsonDecode(errorBody(
          code: 404,
          status: 'NOT_FOUND',
          detailErrorCode: 'UNREGISTERED',
        )) as Map<String, dynamic>,
      )!;

      expect(error.errorCode, FcmErrorCode.unregistered);
      expect(error.status, 'NOT_FOUND');
      expect(error.isRetryable, isFalse);
    });

    test('maps RESOURCE_EXHAUSTED status to quotaExceeded and retryable', () {
      // Quota failures surface as RESOURCE_EXHAUSTED at the rpc layer. Before
      // this mapping existed they fell through to `unknown` and were never
      // retried.
      final FcmError error = FcmError.fromResponseBody(
        jsonDecode(errorBody(code: 429, status: 'RESOURCE_EXHAUSTED'))
            as Map<String, dynamic>,
      )!;

      expect(error.errorCode, FcmErrorCode.quotaExceeded);
      expect(error.isRetryable, isTrue);
    });

    test('QUOTA_EXCEEDED detail is retryable', () {
      final FcmError error = FcmError.fromResponseBody(
        jsonDecode(errorBody(
          code: 429,
          status: 'RESOURCE_EXHAUSTED',
          detailErrorCode: 'QUOTA_EXCEEDED',
        )) as Map<String, dynamic>,
      )!;

      expect(error.errorCode, FcmErrorCode.quotaExceeded);
      expect(error.isRetryable, isTrue);
    });

    test('APNS_AUTH_ERROR detail maps to thirdPartyAuthError', () {
      final FcmError error = FcmError.fromResponseBody(
        jsonDecode(errorBody(
          code: 401,
          status: 'UNAUTHENTICATED',
          detailErrorCode: 'APNS_AUTH_ERROR',
        )) as Map<String, dynamic>,
      )!;

      expect(error.errorCode, FcmErrorCode.thirdPartyAuthError);
    });

    test('bare PERMISSION_DENIED does NOT become a token-invalidating code',
        () {
      // Ambiguous with an IAM/service-account problem — mapping it to
      // senderIdMismatch would wipe the caller's whole token table.
      final FcmError error = FcmError.fromResponseBody(
        jsonDecode(errorBody(code: 403, status: 'PERMISSION_DENIED'))
            as Map<String, dynamic>,
      )!;

      expect(error.errorCode, FcmErrorCode.unknown);
    });

    test('bare UNAUTHENTICATED does NOT become a token-invalidating code', () {
      final FcmError error = FcmError.fromResponseBody(
        jsonDecode(errorBody(code: 401, status: 'UNAUTHENTICATED'))
            as Map<String, dynamic>,
      )!;

      expect(error.errorCode, FcmErrorCode.unknown);
    });

    test('ignores unrelated detail types', () {
      final Map<String, dynamic> body = <String, dynamic>{
        'error': <String, dynamic>{
          'code': 400,
          'message': 'bad',
          'status': 'INVALID_ARGUMENT',
          'details': <Map<String, dynamic>>[
            <String, dynamic>{
              '@type': 'type.googleapis.com/google.rpc.BadRequest',
              'fieldViolations': <dynamic>[],
            },
          ],
        },
      };

      final FcmError error = FcmError.fromResponseBody(body)!;
      expect(error.errorCode, FcmErrorCode.invalidArgument);
    });

    test('survives a malformed details array', () {
      final Map<String, dynamic> body = <String, dynamic>{
        'error': <String, dynamic>{
          'code': 500,
          'message': 'bad',
          'status': 'INTERNAL',
          'details': 'not-a-list',
        },
      };

      expect(
        FcmError.fromResponseBody(body)!.errorCode,
        FcmErrorCode.internal,
      );
    });

    test('has value equality', () {
      const FcmError a = FcmError(
        code: 404,
        message: 'gone',
        status: 'NOT_FOUND',
        errorCode: FcmErrorCode.unregistered,
      );
      const FcmError b = FcmError(
        code: 404,
        message: 'gone',
        status: 'NOT_FOUND',
        errorCode: FcmErrorCode.unregistered,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // ---------------------------------------------------------------------------
  // Argument validation — must survive AOT compilation, where asserts vanish
  // ---------------------------------------------------------------------------
  group('argument validation', () {
    late TestServer server;

    setUp(() {
      server = TestServer(
        httpClient: MockClient(
          (http.Request _) async => http.Response(successBody, 200),
        ),
      );
    });

    tearDown(() => server.dispose());

    test('rejects a message with no target', () {
      expect(
        () => server.send(
          const FirebaseSend(message: FirebaseMessage()),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a message with two targets', () {
      expect(
        () => server.send(
          const FirebaseSend(
            message: FirebaseMessage(token: 'a', topic: 'news'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an empty token list', () {
      expect(
        () => server.sendToMultiple(
          tokens: <String>[],
          messageTemplate: const FirebaseMessage(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an empty sendObjects list', () {
      expect(
        () => server.sendMessages(<FirebaseSend>[]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a topic carrying the /topics/ prefix', () {
      expect(
        () => server.subscribeTokensToTopic(
          topic: '/topics/news',
          tokens: <String>['a'],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an empty token list for topic management', () {
      expect(
        () => server.subscribeTokensToTopic(
          topic: 'news',
          tokens: <String>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects service account JSON without project_id', () {
      expect(
        () => FirebaseCloudMessagingServer(<String, dynamic>{
          'type': 'service_account',
          'client_email': 'a@b.com',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects ADC mode without a project id', () {
      expect(
        () => FirebaseCloudMessagingServer.applicationDefault(projectId: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a non-positive maxConcurrency', () {
      expect(
        () => FirebaseCloudMessagingServer.applicationDefault(
          projectId: 'p',
          maxConcurrency: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws StateError after dispose', () async {
      final TestServer disposed = TestServer(
        httpClient: MockClient(
          (http.Request _) async => http.Response(successBody, 200),
        ),
      )..dispose();

      expect(() => disposed.send(tokenSend()), throwsA(isA<StateError>()));
      expect(
        () => disposed.subscribeTokensToTopic(
          topic: 'news',
          tokens: <String>['a'],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Auth lifecycle
  // ---------------------------------------------------------------------------
  group('auth', () {
    test('refreshes once and replays the request on a 401', () async {
      int calls = 0;
      final List<String> sentTokens = <String>[];

      final TestServer server = TestServer(
        httpClient: MockClient((http.Request request) async {
          calls++;
          sentTokens.add(request.headers['Authorization']!);
          if (calls == 1) {
            return http.Response(
              errorBody(code: 401, status: 'UNAUTHENTICATED'),
              401,
            );
          }
          return http.Response(successBody, 200);
        }),
      );

      final ServerResult result = await server.send(tokenSend());

      expect(result.successful, isTrue);
      expect(calls, 2);
      expect(server.authCount, 2, reason: 'the 401 must force one refresh');
      expect(sentTokens.first, isNot(equals(sentTokens.last)),
          reason: 'the replay must carry the new token');

      server.dispose();
    });

    test('does not loop forever when the 401 persists', () async {
      int calls = 0;
      final TestServer server = TestServer(
        httpClient: MockClient((http.Request _) async {
          calls++;
          return http.Response(
            errorBody(code: 401, status: 'UNAUTHENTICATED'),
            401,
          );
        }),
      );

      final ServerResult result = await server.send(tokenSend());

      expect(result.successful, isFalse);
      expect(calls, 2, reason: 'one original attempt plus one auth replay');

      server.dispose();
    });

    test('refreshes a token that expires inside the safety margin', () async {
      final TestServer server = TestServer(
        httpClient: MockClient(
          (http.Request _) async => http.Response(successBody, 200),
        ),
        // Shorter than the 60s expiry margin, so every send re-authenticates.
        tokenLifetime: const Duration(seconds: 30),
      );

      await server.send(tokenSend());
      await server.send(tokenSend());

      expect(server.authCount, 2);
      server.dispose();
    });

    test('reuses a token that is comfortably valid', () async {
      final TestServer server = TestServer(
        httpClient: MockClient(
          (http.Request _) async => http.Response(successBody, 200),
        ),
      );

      await server.send(tokenSend());
      await server.send(tokenSend());

      expect(server.authCount, 1);
      server.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Retry behaviour
  // ---------------------------------------------------------------------------
  group('retry', () {
    test('retries a RESOURCE_EXHAUSTED quota failure', () async {
      int calls = 0;
      final TestServer server = TestServer(
        retryConfig: const FcmRetryConfig(
          maxRetries: 2,
          initialDelay: Duration(milliseconds: 1),
        ),
        httpClient: MockClient((http.Request _) async {
          calls++;
          if (calls < 3) {
            return http.Response(
              errorBody(code: 429, status: 'RESOURCE_EXHAUSTED'),
              429,
            );
          }
          return http.Response(successBody, 200);
        }),
      );

      final ServerResult result = await server.send(tokenSend());

      expect(result.successful, isTrue);
      expect(calls, 3);
      server.dispose();
    });

    test('does not retry a permanent error', () async {
      int calls = 0;
      final TestServer server = TestServer(
        retryConfig: const FcmRetryConfig(
          maxRetries: 2,
          initialDelay: Duration(milliseconds: 1),
        ),
        httpClient: MockClient((http.Request _) async {
          calls++;
          return http.Response(
            errorBody(
              code: 400,
              status: 'INVALID_ARGUMENT',
              detailErrorCode: 'INVALID_ARGUMENT',
            ),
            400,
          );
        }),
      );

      final ServerResult result = await server.send(tokenSend());

      expect(result.successful, isFalse);
      expect(calls, 1);
      server.dispose();
    });

    test('retries a transport failure and then succeeds', () async {
      int calls = 0;
      final TestServer server = TestServer(
        retryConfig: const FcmRetryConfig(
          maxRetries: 2,
          initialDelay: Duration(milliseconds: 1),
        ),
        httpClient: MockClient((http.Request _) async {
          calls++;
          if (calls < 3) {
            throw const SocketException('connection reset');
          }
          return http.Response(successBody, 200);
        }),
      );

      final ServerResult result = await server.send(tokenSend());

      expect(result.successful, isTrue);
      expect(calls, 3);
      server.dispose();
    });

    test('rethrows a transport failure once retries are exhausted', () async {
      final TestServer server = TestServer(
        retryConfig: const FcmRetryConfig(
          maxRetries: 1,
          initialDelay: Duration(milliseconds: 1),
        ),
        httpClient: MockClient((http.Request _) async {
          throw const SocketException('down');
        }),
      );

      await expectLater(
        server.send(tokenSend()),
        throwsA(isA<SocketException>()),
      );
      server.dispose();
    });

    test('times out a hung request instead of hanging forever', () async {
      final TestServer server = TestServer(
        requestTimeout: const Duration(milliseconds: 30),
        httpClient: MockClient((http.Request _) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response(successBody, 200);
        }),
      );

      await expectLater(
        server.send(tokenSend()),
        throwsA(isA<TimeoutException>()),
      );
      server.dispose();
    });

    test('honours the Retry-After header', () async {
      int calls = 0;
      final Stopwatch stopwatch = Stopwatch()..start();

      final TestServer server = TestServer(
        retryConfig: const FcmRetryConfig(
          maxRetries: 2,
          // Far longer than the header, so a wrong pick is obvious.
          initialDelay: Duration(seconds: 30),
        ),
        httpClient: MockClient((http.Request _) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              errorBody(code: 503, status: 'UNAVAILABLE'),
              503,
              headers: <String, String>{'retry-after': '1'},
            );
          }
          return http.Response(successBody, 200);
        }),
      );

      final ServerResult result = await server.send(tokenSend());
      stopwatch.stop();

      expect(result.successful, isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
      server.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Registration callback
  // ---------------------------------------------------------------------------
  group('onRegistrationChange', () {
    test('reports unregistered when the detail says so', () async {
      final List<(String, FcmRegistrationStatus)> events =
          <(String, FcmRegistrationStatus)>[];

      final TestServer server = TestServer(
        onRegistrationChange: (String t, FcmRegistrationStatus s) =>
            events.add((t, s)),
        httpClient: MockClient(
          (http.Request _) async => http.Response(
            errorBody(
              code: 404,
              status: 'NOT_FOUND',
              detailErrorCode: 'UNREGISTERED',
            ),
            404,
          ),
        ),
      );

      await server.send(tokenSend('stale-token'));

      expect(events, <(String, FcmRegistrationStatus)>[
        ('stale-token', FcmRegistrationStatus.unregistered),
      ]);
      server.dispose();
    });

    test('stays silent on a credential failure', () async {
      final List<(String, FcmRegistrationStatus)> events =
          <(String, FcmRegistrationStatus)>[];

      final TestServer server = TestServer(
        onRegistrationChange: (String t, FcmRegistrationStatus s) =>
            events.add((t, s)),
        httpClient: MockClient(
          (http.Request _) async => http.Response(
            errorBody(code: 403, status: 'PERMISSION_DENIED'),
            403,
          ),
        ),
      );

      await server.send(tokenSend('good-token'));

      expect(events, isEmpty,
          reason: 'an IAM problem must not invalidate tokens');
      server.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Bounded fan-out
  // ---------------------------------------------------------------------------
  group('fan-out', () {
    test('never exceeds maxConcurrency in flight', () async {
      int inFlight = 0;
      int peak = 0;

      final TestServer server = TestServer(
        maxConcurrency: 3,
        httpClient: MockClient((http.Request _) async {
          inFlight++;
          peak = inFlight > peak ? inFlight : peak;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return http.Response(successBody, 200);
        }),
      );

      final BatchResult batch = await server.sendToMultiple(
        tokens: List<String>.generate(20, (int i) => 'token-$i'),
        messageTemplate: const FirebaseMessage(
          notification: FirebaseNotification(title: 'Hi'),
        ),
      );

      expect(batch.results.length, 20);
      expect(batch.successCount, 20);
      expect(peak, lessThanOrEqualTo(3));
      server.dispose();
    });

    test('preserves token order in the results', () async {
      final TestServer server = TestServer(
        maxConcurrency: 4,
        httpClient: MockClient((http.Request request) async {
          // Reverse the latency so completion order differs from input order.
          final Map<String, dynamic> body =
              jsonDecode(request.body) as Map<String, dynamic>;
          final Map<String, dynamic> message =
              body['message'] as Map<String, dynamic>;
          final int index =
              int.parse((message['token'] as String).split('-').last);
          await Future<void>.delayed(Duration(milliseconds: 20 - index));
          return http.Response(successBody, 200);
        }),
      );

      final List<String> tokens =
          List<String>.generate(10, (int i) => 'token-$i');
      final BatchResult batch = await server.sendToMultiple(
        tokens: tokens,
        messageTemplate: const FirebaseMessage(
          notification: FirebaseNotification(title: 'Hi'),
        ),
      );

      expect(
        batch.results.map((TokenResult r) => r.token).toList(),
        equals(tokens),
      );
      server.dispose();
    });

    test('sendMessages keeps request order', () async {
      final TestServer server = TestServer(
        maxConcurrency: 2,
        httpClient: MockClient((http.Request request) async {
          final Map<String, dynamic> body =
              jsonDecode(request.body) as Map<String, dynamic>;
          final Map<String, dynamic> message =
              body['message'] as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, String>{'name': message['token'] as String}),
            200,
          );
        }),
      );

      final List<ServerResult> results = await server.sendMessages(
        <FirebaseSend>[
          tokenSend('token-0'),
          tokenSend('token-1'),
          tokenSend('token-2'),
        ],
      );

      expect(
        results.map((ServerResult r) => r.messageSent?.name).toList(),
        <String>['token-0', 'token-1', 'token-2'],
      );
      server.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Topic management
  // ---------------------------------------------------------------------------
  group('topic management', () {
    test('splits token lists longer than 1000 into batches', () async {
      final List<int> batchSizes = <int>[];

      final TestServer server = TestServer(
        httpClient: MockClient((http.Request request) async {
          final Map<String, dynamic> body =
              jsonDecode(request.body) as Map<String, dynamic>;
          final List<dynamic> tokens =
              body['registration_tokens'] as List<dynamic>;
          batchSizes.add(tokens.length);

          return http.Response(
            jsonEncode(<String, dynamic>{
              'results': List<Map<String, dynamic>>.generate(
                tokens.length,
                (int _) => <String, dynamic>{},
              ),
            }),
            200,
          );
        }),
      );

      final List<String> tokens =
          List<String>.generate(2500, (int i) => 'token-$i');
      final TopicManagementResult result = await server.subscribeTokensToTopic(
        topic: 'news',
        tokens: tokens,
      );

      expect(batchSizes, <int>[1000, 1000, 500]);
      expect(result.results.length, 2500);
      expect(result.successCount, 2500);
      expect(result.results.first.token, 'token-0');
      expect(result.results.last.token, 'token-2499');
      server.dispose();
    });

    test('handles a google.rpc error envelope without throwing', () async {
      final TestServer server = TestServer(
        httpClient: MockClient(
          (http.Request _) async => http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{
                'code': 401,
                'message': 'Request had invalid authentication credentials.',
                'status': 'UNAUTHENTICATED',
              },
            }),
            401,
          ),
        ),
      );

      final TopicManagementResult result = await server.subscribeTokensToTopic(
        topic: 'news',
        tokens: <String>['a', 'b'],
      );

      expect(result.failureCount, 2);
      expect(result.allSuccessful, isFalse);
      expect(result.results.first.error, 'UNAUTHENTICATED');
      server.dispose();
    });

    test('falls back to the HTTP status for a non-JSON body', () async {
      final TestServer server = TestServer(
        httpClient: MockClient(
          (http.Request _) async => http.Response('<html>502</html>', 502),
        ),
      );

      final TopicManagementResult result =
          await server.unsubscribeTokensFromTopic(
        topic: 'news',
        tokens: <String>['a'],
      );

      expect(result.results.single.error, 'HTTP_502');
      server.dispose();
    });

    test('still reports per-token string errors', () async {
      final TestServer server = TestServer(
        httpClient: MockClient(
          (http.Request _) async => http.Response(
            jsonEncode(<String, dynamic>{
              'results': <Map<String, dynamic>>[
                <String, dynamic>{},
                <String, dynamic>{'error': 'NOT_FOUND'},
              ],
            }),
            200,
          ),
        ),
      );

      final TopicManagementResult result = await server.subscribeTokensToTopic(
        topic: 'news',
        tokens: <String>['a', 'b'],
      );

      expect(result.successCount, 1);
      expect(result.failedResults.single.error, 'NOT_FOUND');
      server.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Wire format
  // ---------------------------------------------------------------------------
  group('serialised payload', () {
    test('omits unset fields instead of sending nulls', () async {
      late Map<String, dynamic> captured;

      final TestServer server = TestServer(
        httpClient: MockClient((http.Request request) async {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(successBody, 200);
        }),
      );

      await server.send(tokenSend());

      final Map<String, dynamic> message =
          captured['message'] as Map<String, dynamic>;

      expect(message.keys, containsAll(<String>['token', 'notification']));
      expect(message.containsKey('topic'), isFalse);
      expect(message.containsKey('condition'), isFalse);
      expect(message.containsKey('android'), isFalse);
      expect(
        (message['notification'] as Map<String, dynamic>).containsKey('body'),
        isFalse,
      );
      server.dispose();
    });

    test('never emits the phantom apns.notification key', () {
      // ApnsConfig has no `notification` member on the wire — FCM rejects the
      // request outright if the key is present, even with a null value.
      final Map<String, dynamic> json = const FirebaseApnsConfig(
        headers: <String, String>{'apns-priority': '10'},
      ).toJson();

      expect(json.containsKey('notification'), isFalse);
      expect(json['headers'], <String, String>{'apns-priority': '10'});
    });

    test('still nests a typed apns notification under payload.aps', () {
      final Map<String, dynamic> json = const FirebaseApnsConfig(
        notification: FirebaseApnsNotification(title: 'Hi', badge: 1),
      ).toJson();

      expect(json.containsKey('notification'), isFalse);
      final Map<String, dynamic> payload =
          json['payload'] as Map<String, dynamic>;
      final Map<String, dynamic> aps = payload['aps'] as Map<String, dynamic>;
      expect(aps['title'], 'Hi');
      expect(aps['badge'], 1);
      expect(aps.containsKey('sound'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------
  group('value equality', () {
    test('FirebaseMessage compares by content', () {
      const FirebaseMessage a = FirebaseMessage(
        token: 'x',
        notification: FirebaseNotification(title: 'Hi', body: 'There'),
      );
      const FirebaseMessage b = FirebaseMessage(
        token: 'x',
        notification: FirebaseNotification(title: 'Hi', body: 'There'),
      );
      const FirebaseMessage c = FirebaseMessage(token: 'y');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('ServerResult equality holds for distinct but equal instances', () {
      final ServerResult a = ServerFailure(
        statusCode: 404,
        fcmError: FcmError.fromResponseBody(
          jsonDecode(errorBody(
            code: 404,
            status: 'NOT_FOUND',
            detailErrorCode: 'UNREGISTERED',
          )) as Map<String, dynamic>,
        ),
        errorBody: 'body',
      );
      final ServerResult b = ServerFailure(
        statusCode: 404,
        fcmError: FcmError.fromResponseBody(
          jsonDecode(errorBody(
            code: 404,
            status: 'NOT_FOUND',
            detailErrorCode: 'UNREGISTERED',
          )) as Map<String, dynamic>,
        ),
        errorBody: 'body',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
