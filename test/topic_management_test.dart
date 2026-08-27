import 'dart:convert';
import 'package:firebase_cloud_messaging_dart/firebase_cloud_messaging_dart.dart';
import 'package:test/test.dart';

void main() {
  group('TopicManagementResult', () {
    test('parses successful response correctly', () {
      final Map<String, dynamic> json =
          jsonDecode('''{
        "results": [
          {},
          {}
        ]
      }''')
              as Map<String, dynamic>;

      final TopicManagementResult result = TopicManagementResult.fromJson(
        json,
        <String>['token1', 'token2'],
      );

      expect(result.results.length, 2);
      expect(result.successCount, 2);
      expect(result.failureCount, 0);
      expect(result.allSuccessful, isTrue);
      expect(result.failedResults, isEmpty);
    });

    test('parses partially failed response correctly', () {
      final Map<String, dynamic> json =
          jsonDecode('''{
        "results": [
          {},
          {"error": "NOT_FOUND"},
          {"error": "INVALID_ARGUMENT"}
        ]
      }''')
              as Map<String, dynamic>;

      final TopicManagementResult result = TopicManagementResult.fromJson(
        json,
        <String>['token1', 'token2', 'token3'],
      );

      expect(result.results.length, 3);
      expect(result.successCount, 1);
      expect(result.failureCount, 2);
      expect(result.allSuccessful, isFalse);

      final List<TopicManagementTokenResult> failures = result.failedResults;
      expect(failures.length, 2);
      expect(failures[0].token, 'token2');
      expect(failures[0].error, 'NOT_FOUND');
      expect(failures[1].token, 'token3');
      expect(failures[1].error, 'INVALID_ARGUMENT');
    });

    test('handles empty results', () {
      final Map<String, dynamic> json = <String, dynamic>{};
      final TopicManagementResult result = TopicManagementResult.fromJson(
        json,
        <String>[],
      );

      expect(result.results, isEmpty);
      expect(result.successCount, 0);
      expect(result.failureCount, 0);
      expect(result.allSuccessful, isTrue);
    });
  });
}
