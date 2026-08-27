import 'dart:convert';

import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final class AuditServer extends FirebaseCloudMessagingServer {
  AuditServer({
    required http.Client httpClient,
    super.retryConfig = const FcmRetryConfig(maxRetries: 0),
  }) : super(null, projectId: 'test-project', httpClient: httpClient);

  int authCount = 0;

  @override
  Future<AccessCredentials> obtainCredentials() async {
    authCount++;
    return AccessCredentials(
      AccessToken(
        'Bearer',
        'audit-token-$authCount',
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      <String>['https://www.googleapis.com/auth/firebase.messaging'],
    );
  }
}

const String auditSuccessBody =
    '{"name":"projects/test-project/messages/audit"}';

void main() {
  group('current FCM wire contracts', () {
    test('APNs typed alert is nested and raw APS fields are preserved', () {
      const FirebaseApnsConfig config = FirebaseApnsConfig(
        payload: <String, dynamic>{
          'aps': <String, dynamic>{'category': 'news', 'badge': 1},
          'custom': <String, dynamic>{'value': true},
        },
        notification: FirebaseApnsNotification(
          title: 'Title',
          body: 'Body',
          badge: 9,
        ),
      );

      final Map<String, dynamic> json = config.toJson();
      final Map<String, dynamic> payload =
          json['payload'] as Map<String, dynamic>;
      final Map<String, dynamic> aps = payload['aps'] as Map<String, dynamic>;
      final Map<String, dynamic> alert = aps['alert'] as Map<String, dynamic>;

      expect(alert, <String, dynamic>{'title': 'Title', 'body': 'Body'});
      expect(aps['badge'], 9);
      expect(aps['category'], 'news');
      expect(aps.containsKey('title'), isFalse);
      expect(payload['custom'], <String, dynamic>{'value': true});
    });

    test('Web Push uses browser property casing and preserves extensions', () {
      const FirebaseWebpushNotification notification =
          FirebaseWebpushNotification(
            title: 'Title',
            requireInteraction: true,
            timestamp: 123,
            vibrate: <int>[100, 50, 100],
            extra: <String, dynamic>{'futureProperty': 'kept'},
          );

      final Map<String, dynamic> json = notification.toJson();
      expect(json['requireInteraction'], isTrue);
      expect(json.containsKey('require_interaction'), isFalse);
      expect(json['timestamp'], 123);
      expect(json['vibrate'], <int>[100, 50, 100]);
      expect(json['futureProperty'], 'kept');
    });

    test(
      'structured FCM details are retained and generic NOT_FOUND is safe',
      () {
        final FcmError error = FcmError.fromResponseBody(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 400,
            'status': 'INVALID_ARGUMENT',
            'message': 'bad field',
            'details': <Map<String, dynamic>>[
              <String, dynamic>{
                '@type': 'type.googleapis.com/google.rpc.BadRequest',
                'fieldViolations': <Map<String, String>>[
                  <String, String>{
                    'field': 'message.data',
                    'description': 'bad',
                  },
                ],
              },
            ],
          },
        })!;
        expect(error.details, hasLength(1));
        expect(error.errorCode, FcmErrorCode.invalidArgument);

        final FcmError notFound = FcmError.fromResponseBody(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 404,
            'status': 'NOT_FOUND',
            'message': 'project not found',
          },
        })!;
        expect(notFound.errorCode, FcmErrorCode.unknown);
      },
    );

    test('quota backoff starts at the documented one-minute floor', () {
      const FcmRetryConfig config = FcmRetryConfig();
      expect(
        config.quotaDelayForAttempt(0),
        greaterThanOrEqualTo(const Duration(minutes: 1)),
      );
    });
  });

  group('server resilience', () {
    test('sendToFid sends the fid target', () async {
      late Map<String, dynamic> captured;
      final AuditServer server = AuditServer(
        httpClient: MockClient((http.Request request) async {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(auditSuccessBody, 200);
        }),
      );

      final ServerResult result = await server.sendToFid(
        'fid-123',
        const FirebaseMessage(notification: FirebaseNotification(title: 'Hi')),
      );

      expect(result.successful, isTrue);
      final Map<String, dynamic> message =
          captured['message'] as Map<String, dynamic>;
      expect(message['fid'], 'fid-123');
      expect(message.containsKey('token'), isFalse);
      server.dispose();
    });

    test('empty-body 503 is retried', () async {
      int calls = 0;
      final AuditServer server = AuditServer(
        retryConfig: const FcmRetryConfig(
          maxRetries: 1,
          initialDelay: Duration.zero,
        ),
        httpClient: MockClient((http.Request _) async {
          calls++;
          return calls == 1
              ? http.Response('', 503)
              : http.Response(auditSuccessBody, 200);
        }),
      );

      final ServerResult result = await server.send(
        const FirebaseSend(message: FirebaseMessage(token: 'token-a')),
      );
      expect(result.successful, isTrue);
      expect(calls, 2);
      server.dispose();
    });

    test('expected transport failures remain item-local in a batch', () async {
      final AuditServer server = AuditServer(
        httpClient: MockClient((http.Request request) async {
          final Map<String, dynamic> requestJson =
              jsonDecode(request.body) as Map<String, dynamic>;
          final Map<String, dynamic> message =
              requestJson['message'] as Map<String, dynamic>;
          if (message['token'] == 'bad') throw StateError('network failure');
          return http.Response(auditSuccessBody, 200);
        }),
      );

      final BatchResult result = await server.sendToMultiple(
        tokens: <String>['bad', 'good'],
        messageTemplate: const FirebaseMessage(),
      );

      expect(result.results, hasLength(2));
      expect(result.results[0].successful, isFalse);
      expect(result.results[1].successful, isTrue);
      server.dispose();
    });
  });

  group('topic response integrity', () {
    test('short result arrays preserve one failure per missing token', () {
      final TopicManagementResult result = TopicManagementResult.fromJson(
        <String, dynamic>{
          'results': <Map<String, dynamic>>[<String, dynamic>{}],
        },
        <String>['a', 'b'],
        statusCode: 200,
      );

      expect(result.results, hasLength(2));
      expect(result.successCount, 1);
      expect(result.failureCount, 1);
      expect(result.results[1].error, 'MALFORMED_RESPONSE');
      expect(result.malformedResponse, isTrue);
      expect(result.allSuccessful, isFalse);
    });
  });
}
