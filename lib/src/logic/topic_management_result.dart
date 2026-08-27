/// The result for a single token in a topic-management operation.
///
/// Legacy response reference: https://developers.google.com/instance-id/reference
final class TopicManagementTokenResult {
  const TopicManagementTokenResult({
    required this.token,
    required this.successful,
    this.error,
  });

  final String token;
  final bool successful;
  final String? error;

  @override
  String toString() =>
      'TopicManagementTokenResult(token: $token, successful: $successful, '
      'error: $error)';
}

/// Aggregate result from a topic subscribe/unsubscribe operation.
///
/// FCM guide: https://firebase.google.com/docs/cloud-messaging/manage-topic-subscriptions
/// Legacy response reference: https://developers.google.com/instance-id/reference
final class TopicManagementResult {
  const TopicManagementResult({
    required this.successCount,
    required this.failureCount,
    required this.results,
    this.statusCode,
    this.errorBody,
    this.malformedResponse = false,
  });

  /// Parses the legacy Instance ID batch response while preserving one result
  /// for every requested token.
  factory TopicManagementResult.fromJson(
    Map<String, dynamic> json,
    List<String> tokens, {
    int? statusCode,
  }) {
    final dynamic rawResults = json['results'];
    final String requestError = _describeError(json['error'], statusCode);

    if (statusCode != null && statusCode != 200) {
      return _failedRequest(tokens, statusCode, requestError, json);
    }

    if (rawResults is! List) {
      return _failedRequest(tokens, statusCode, requestError, json);
    }

    final bool malformed = rawResults.length != tokens.length;
    final List<TopicManagementTokenResult> mapped =
        <TopicManagementTokenResult>[
          for (int index = 0; index < tokens.length; index++)
            _mapItem(
              tokens[index],
              index < rawResults.length ? rawResults[index] : null,
              missing: index >= rawResults.length,
            ),
        ];
    final int successCount = mapped
        .where((TopicManagementTokenResult result) => result.successful)
        .length;

    return TopicManagementResult(
      successCount: successCount,
      failureCount: mapped.length - successCount,
      results: mapped,
      statusCode: statusCode,
      errorBody: json['error']?.toString(),
      malformedResponse:
          malformed ||
          rawResults.any((dynamic item) => item is! Map<String, dynamic>),
    );
  }

  final int successCount;
  final int failureCount;
  final List<TopicManagementTokenResult> results;
  final int? statusCode;
  final String? errorBody;
  final bool malformedResponse;

  bool get allSuccessful => failureCount == 0 && !malformedResponse;

  List<TopicManagementTokenResult> get failedResults => results
      .where((TopicManagementTokenResult result) => !result.successful)
      .toList();

  static TopicManagementTokenResult _mapItem(
    String token,
    dynamic item, {
    required bool missing,
  }) {
    if (missing || item is! Map<String, dynamic>) {
      return TopicManagementTokenResult(
        token: token,
        successful: false,
        error: 'MALFORMED_RESPONSE',
      );
    }
    final dynamic error = item['error'];
    return TopicManagementTokenResult(
      token: token,
      successful: error == null,
      error: error == null ? null : _describeError(error, null),
    );
  }

  static TopicManagementResult _failedRequest(
    List<String> tokens,
    int? statusCode,
    String error,
    Map<String, dynamic> json,
  ) {
    return TopicManagementResult(
      successCount: 0,
      failureCount: tokens.length,
      results: <TopicManagementTokenResult>[
        for (final String token in tokens)
          TopicManagementTokenResult(
            token: token,
            successful: false,
            error: error,
          ),
      ],
      statusCode: statusCode,
      errorBody: json['error']?.toString(),
    );
  }

  static String _describeError(Object? error, int? statusCode) {
    if (error is String && error.isNotEmpty) return error;
    if (error is Map<String, dynamic>) {
      final Object? status = error['status'];
      if (status is String && status.isNotEmpty) return status;
      final Object? message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return statusCode == null ? 'UNKNOWN_ERROR' : 'HTTP_$statusCode';
  }

  @override
  String toString() =>
      'TopicManagementResult(success: $successCount, '
      'fail: $failureCount, malformed: $malformedResponse)';
}
