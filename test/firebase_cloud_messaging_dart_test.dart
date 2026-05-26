import 'dart:convert';

import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
import 'package:test/test.dart';

/// Unit tests for firebase_cloud_messaging_dart v2.1.0

///
/// Run with:
///   dart run build_runner build --delete-conflicting-outputs
///   dart test
void main() {
  // -------------------------------------------------------------------------
  // AndroidMessagePriority serialization (critical regression test)
  // The FCM API requires uppercase "NORMAL" / "HIGH" not lowercase.
  // -------------------------------------------------------------------------
  group('AndroidMessagePriority JSON values', () {
    test('normal serializes to "NORMAL"', () {
      final FirebaseAndroidConfig config = const FirebaseAndroidConfig(
        priority: AndroidMessagePriority.normal,
      );
      final Map<String, dynamic> map = config.toJson();
      expect(map['priority'], equals('NORMAL'));
    });

    test('high serializes to "HIGH"', () {
      final FirebaseAndroidConfig config = const FirebaseAndroidConfig(
        priority: AndroidMessagePriority.high,
      );
      final Map<String, dynamic> map = config.toJson();
      expect(map['priority'], equals('HIGH'));
    });

    test('round-trips from JSON', () {
      const Map<String, String> input = <String, String>{'priority': 'HIGH'};
      final FirebaseAndroidConfig config =
          FirebaseAndroidConfig.fromJson(input);
      expect(config.priority, AndroidMessagePriority.high);
      expect(config.toJson()['priority'], equals('HIGH'));
    });
  });

  // -------------------------------------------------------------------------
  // AndroidNotificationProxy serialization (new in v2.1.0)

  // -------------------------------------------------------------------------
  group('AndroidNotificationProxy JSON values', () {
    test('allow serializes to "ALLOW"', () {
      final FirebaseAndroidNotification notification =
          const FirebaseAndroidNotification(
        proxy: AndroidNotificationProxy.allow,
      );
      final Map<String, dynamic> map = notification.toJson();
      expect(map['proxy'], equals('ALLOW'));
    });

    test('deny serializes to "DENY"', () {
      final FirebaseAndroidNotification n = const FirebaseAndroidNotification(
        proxy: AndroidNotificationProxy.deny,
      );
      expect(n.toJson()['proxy'], equals('DENY'));
    });
  });

  // -------------------------------------------------------------------------
  // FirebaseAndroidConfig — new field
  // -------------------------------------------------------------------------
  group('FirebaseAndroidConfig', () {
    test('directBootOk serializes to "direct_boot_ok"', () {
      const FirebaseAndroidConfig config =
          FirebaseAndroidConfig(directBootOk: true);
      expect(config.toJson()['direct_boot_ok'], isTrue);
    });

    test('directBootOk round-trips from JSON', () {
      final FirebaseAndroidConfig config = FirebaseAndroidConfig.fromJson(
          <String, dynamic>{'direct_boot_ok': false});
      expect(config.directBootOk, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // FirebaseFcmOptions
  // -------------------------------------------------------------------------
  group('FirebaseFcmOptions', () {
    test('analyticsLabel serializes correctly', () {
      const FirebaseFcmOptions opts = FirebaseFcmOptions(
        analyticsLabel: 'promo',
      );
      final Map<String, dynamic> map = opts.toJson();
      expect(map['analytics_label'], equals('promo'));
    });

    test('round-trips from JSON', () {
      final FirebaseFcmOptions opts =
          FirebaseFcmOptions.fromJson(<String, dynamic>{
        'analytics_label': 'test',
      });
      expect(opts.analyticsLabel, equals('test'));
    });
  });

  // -------------------------------------------------------------------------
  // FirebaseMessage serialization round-trip
  // -------------------------------------------------------------------------
  group('FirebaseMessage JSON round-trip', () {
    test('basic message serializes and deserializes', () {
      const FirebaseMessage message = FirebaseMessage(
        token: 'device-token-abc',
        data: <String, String>{'key': 'value'},
        notification: FirebaseNotification(
          title: 'Hello',
          body: 'World',
          image: 'https://example.com/img.jpg',
        ),
      );

      final String encoded = jsonEncode(message.toJson());
      final Map<String, dynamic> map =
          jsonDecode(encoded) as Map<String, dynamic>;
      expect(map['token'], equals('device-token-abc'));
      expect(map['data'], equals(<String, String>{'key': 'value'}));
      expect((map['notification'] as Map<String, dynamic>)['title'],
          equals('Hello'));

      final FirebaseMessage decoded = FirebaseMessage.fromJson(map);
      expect(decoded.token, equals('device-token-abc'));
      expect(decoded.notification?.title, equals('Hello'));
    });

    test('copyWith replaces only specified fields', () {
      const FirebaseMessage original = FirebaseMessage(token: 'abc');
      final FirebaseMessage copy = original.copyWith(token: 'xyz');
      expect(copy.token, equals('xyz'));
      expect(copy.topic, isNull);
    });

    test('copyWith(topic:) leaves token unchanged', () {
      const FirebaseMessage original = FirebaseMessage(token: 'tok');
      final FirebaseMessage copy = original.copyWith(topic: 'weather');
      // Note: in practice you would set only one target field.
      expect(copy.token, equals('tok'));
      expect(copy.topic, equals('weather'));
    });
  });

  // -------------------------------------------------------------------------
  // FirebaseSend — null message assertion
  // -------------------------------------------------------------------------
  group('FirebaseSend', () {
    test('assert fires when message is null', () {
      expect(
        () => FirebaseSend(),
        throwsA(isA<AssertionError>()),
      );
    });

    test('copyWith replaces validateOnly', () {
      final FirebaseSend original = const FirebaseSend(
        message: FirebaseMessage(token: 'x'),
      );
      final FirebaseSend copy = original.copyWith(validateOnly: true);
      expect(copy.validateOnly, isTrue);
      expect(copy.message?.token, equals('x'));
    });

    test('serializes validate_only key', () {
      final FirebaseSend send = const FirebaseSend(
        validateOnly: true,
        message: FirebaseMessage(token: 'tok'),
      );
      final Map<String, dynamic> map = send.toJson();
      expect(map['validate_only'], isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // FcmError parsing
  // -------------------------------------------------------------------------
  group('FcmError', () {
    test('parses UNREGISTERED from response body', () {
      final Map<String, dynamic> body = json.decode('''{
        "error": {
          "code": 404,
          "message": "Requested entity was not found.",
          "status": "UNREGISTERED"
        }
      }''') as Map<String, dynamic>;

      final FcmError? error = FcmError.fromResponseBody(body);
      expect(error, isNotNull);
      expect(error!.code, equals(404));
      expect(error.errorCode, equals(FcmErrorCode.unregistered));
      expect(error.isRetryable, isFalse);
    });

    test('parses QUOTA_EXCEEDED and marks it retryable', () {
      final Map<String, dynamic> body = json.decode('''{
        "error": {
          "code": 429,
          "message": "Quota exceeded.",
          "status": "QUOTA_EXCEEDED"
        }
      }''') as Map<String, dynamic>;

      final FcmError? error = FcmError.fromResponseBody(body);
      expect(error!.errorCode, equals(FcmErrorCode.quotaExceeded));
      expect(error.isRetryable, isTrue);
    });

    test('parses UNAVAILABLE and marks it retryable', () {
      final Map<String, dynamic> body = json.decode('''{
        "error": {
          "code": 503,
          "message": "The service is currently unavailable.",
          "status": "UNAVAILABLE"
        }
      }''') as Map<String, dynamic>;

      final FcmError? error = FcmError.fromResponseBody(body);
      expect(error!.errorCode, equals(FcmErrorCode.unavailable));
      expect(error.isRetryable, isTrue);
    });

    test('parses INTERNAL and marks it retryable', () {
      final Map<String, dynamic> body = json.decode('''{
        "error": {
          "code": 500,
          "message": "Internal server error.",
          "status": "INTERNAL"
        }
      }''') as Map<String, dynamic>;

      final FcmError? error = FcmError.fromResponseBody(body);
      expect(error!.errorCode, equals(FcmErrorCode.internal));
      expect(error.isRetryable, isTrue);
    });

    test('returns null when body has no error key', () {
      final FcmError? error = FcmError.fromResponseBody(
          <String, dynamic>{'message': 'some-msg-id'});
      expect(error, isNull);
    });

    test('maps unknown status to FcmErrorCode.unknown', () {
      final Map<String, dynamic> body = json.decode('''{
        "error": {
          "code": 999,
          "message": "Future error.",
          "status": "FUTURE_ERROR_CODE"
        }
      }''') as Map<String, dynamic>;

      final FcmError? error = FcmError.fromResponseBody(body);
      expect(error!.errorCode, equals(FcmErrorCode.unknown));
    });
  });

  // -------------------------------------------------------------------------
  // FcmRetryConfig — delay calculation
  // -------------------------------------------------------------------------
  group('FcmRetryConfig', () {
    test('delayForAttempt doubles on each attempt', () {
      const FcmRetryConfig config = FcmRetryConfig(
        maxRetries: 5,
        maxDelay: Duration(seconds: 60),
      );
      expect(config.delayForAttempt(0), equals(const Duration(seconds: 1)));
      expect(config.delayForAttempt(1), equals(const Duration(seconds: 2)));
      expect(config.delayForAttempt(2), equals(const Duration(seconds: 4)));
    });

    test('delay is capped at maxDelay', () {
      const FcmRetryConfig config = FcmRetryConfig(
        maxRetries: 10,
        maxDelay: Duration(seconds: 5),
      );
      // Attempt 3 → 8s, but capped at 5s
      expect(config.delayForAttempt(3), equals(const Duration(seconds: 5)));
    });

    test('FcmRetryConfig.none has maxRetries 0', () {
      expect(FcmRetryConfig.none.maxRetries, equals(0));
    });
  });

  // -------------------------------------------------------------------------
  // BatchResult aggregation
  // -------------------------------------------------------------------------
  group('BatchResult', () {
    ServerResult makeResult({required bool successful, int code = 200}) {
      if (successful) {
        return const ServerSuccess(
          statusCode: 200,
          messageSent: FirebaseMessage(),
        );
      } else {
        return ServerFailure(
          statusCode: code,
        );
      }
    }

    test('successCount and failureCount are correct', () {
      final BatchResult batch = BatchResult(
        results: <TokenResult>[
          TokenResult(token: 't1', serverResult: makeResult(successful: true)),
          TokenResult(
              token: 't2',
              serverResult: makeResult(successful: false, code: 404)),
          TokenResult(token: 't3', serverResult: makeResult(successful: true)),
        ],
      );
      expect(batch.successCount, equals(2));
      expect(batch.failureCount, equals(1));
      expect(batch.allSuccessful, isFalse);
      expect(batch.anySuccessful, isTrue);
    });

    test('failedResults contains only failed tokens', () {
      final BatchResult batch = BatchResult(
        results: <TokenResult>[
          TokenResult(token: 't1', serverResult: makeResult(successful: true)),
          TokenResult(token: 't2', serverResult: makeResult(successful: false)),
        ],
      );
      expect(batch.failedResults.length, equals(1));
      expect(batch.failedResults.first.token, equals('t2'));
    });

    test('allSuccessful is true when all succeed', () {
      final BatchResult batch = BatchResult(
        results: <TokenResult>[
          TokenResult(token: 't1', serverResult: makeResult(successful: true)),
          TokenResult(token: 't2', serverResult: makeResult(successful: true)),
        ],
      );
      expect(batch.allSuccessful, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // ServerResult
  // -------------------------------------------------------------------------
  group('ServerResult', () {
    const ServerSuccess result = ServerSuccess(
      statusCode: 200,
      messageSent: FirebaseMessage(name: 'projects/p/messages/1'),
    );

    test('ServerSuccess holds correct data', () {
      expect(result.successful, isTrue);
      expect(result.statusCode, equals(200));
      expect(result.messageSent.name, equals('projects/p/messages/1'));
    });

    test('ServerFailure holds error details', () {
      const ServerFailure failure = ServerFailure(
        statusCode: 500,
        errorPhrase: 'Internal Error',
      );
      expect(failure.successful, isFalse);
      expect(failure.statusCode, equals(500));
      expect(failure.errorPhrase, equals('Internal Error'));
    });

    test('toString includes key fields', () {
      expect(result.toString(), contains('successful: true'));
      expect(result.toString(), contains('statusCode: 200'));
    });

    test('equality works', () {
      const ServerSuccess same = ServerSuccess(
        statusCode: 200,
        messageSent: FirebaseMessage(name: 'projects/p/messages/1'),
      );
      expect(result, equals(same));
    });
  });

  // -------------------------------------------------------------------------
  // FirebaseApnsConfig — Nesting verification
  // -------------------------------------------------------------------------
  group('FirebaseApnsConfig nesting', () {
    test('notification is nested inside payload.aps in toJson()', () {
      final FirebaseApnsConfig config = const FirebaseApnsConfig(
        notification: FirebaseApnsNotification(
          title: 'APNs Title',
          badge: 5,
        ),
      );

      final Map<String, dynamic> json = config.toJson();

      // Should not be at the top level
      expect(json.containsKey('notification'), isFalse);

      // Should be inside payload -> aps
      final dynamic payload = json['payload'];
      expect(payload, isNotNull);
      final dynamic aps = (payload as Map<String, dynamic>)['aps'];
      expect(aps, isNotNull);
      expect((aps as Map<String, dynamic>)['title'], equals('APNs Title'));
      expect(aps['badge'], equals(5));
    });

    test('round-trips notification from payload.aps in fromJson()', () {
      final Map<String, dynamic> json = <String, Map<String, dynamic>>{
        'payload': <String, Map<String, String>>{
          'aps': <String, String>{
            'title': 'iOS Alert',
            'sound': 'default',
          }
        }
      };

      final FirebaseApnsConfig config = FirebaseApnsConfig.fromJson(json);

      expect(config.notification, isNotNull);
      expect(config.notification?.title, equals('iOS Alert'));
      expect(config.notification?.sound, equals('default'));
    });

    test('merges notification into existing payload fields', () {
      final FirebaseApnsConfig config = const FirebaseApnsConfig(
        payload: <String, dynamic>{'custom-key': 'custom-value'},
        notification: FirebaseApnsNotification(badge: 1),
      );

      final Map<String, dynamic> json = config.toJson();

      final dynamic payload = json['payload'];
      expect((payload as Map<String, dynamic>)['custom-key'],
          equals('custom-value'));
      expect((payload['aps'] as Map<String, dynamic>)['badge'], equals(1));
    });
  });

  // -------------------------------------------------------------------------
  // New Platform Expansions (v2.1.0)
  // -------------------------------------------------------------------------
  group('v2.1.0 Platform Expansions', () {
    test('APNs: interruption-level, relevance-score, target-content-id', () {
      const FirebaseApnsNotification notification = FirebaseApnsNotification(
        interruptionLevel: InterruptionLevel.timeSensitive,
        relevanceScore: 0.75,
        targetContentId: 'group-123',
      );

      final Map<String, dynamic> json = notification.toJson();
      expect(json['interruption-level'], equals('time-sensitive'));
      expect(json['relevance-score'], equals(0.75));
      expect(json['target-content-id'], equals('group-123'));

      final FirebaseApnsNotification decoded =
          FirebaseApnsNotification.fromJson(json);
      expect(
          decoded.interruptionLevel, equals(InterruptionLevel.timeSensitive));
      expect(decoded.relevanceScore, equals(0.75));
      expect(decoded.targetContentId, equals('group-123'));
    });

    test('Webpush: dir, lang, renotify, timestamp, data', () {
      const FirebaseWebpushNotification notification =
          FirebaseWebpushNotification(
        dir: WebpushDirection.rtl,
        lang: 'ar',
        renotify: true,
        timestamp: '1625097600000',
        data: <String, dynamic>{'click_url': 'https://example.com'},
      );

      final Map<String, dynamic> json = notification.toJson();
      expect(json['dir'], equals('rtl'));
      expect(json['lang'], equals('ar'));
      expect(json['renotify'], isTrue);
      expect(json['timestamp'], equals('1625097600000'));
      expect(json['data'],
          equals(<String, String>{'click_url': 'https://example.com'}));

      final FirebaseWebpushNotification decoded =
          FirebaseWebpushNotification.fromJson(json);
      expect(decoded.dir, equals(WebpushDirection.rtl));
      expect(decoded.lang, equals('ar'));
      expect(decoded.renotify, isTrue);
      expect(decoded.timestamp, equals('1625097600000'));
      expect(decoded.data,
          equals(<String, String>{'click_url': 'https://example.com'}));
    });
  });
}
