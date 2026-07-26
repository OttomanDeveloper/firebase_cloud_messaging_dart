/// The result for a single token when subscribing or unsubscribing to a topic.
final class TopicManagementTokenResult {

  const TopicManagementTokenResult({
    required this.token,
    required this.successful,
    this.error,
  });
  /// The device token that was requested.
  final String token;

  /// Whether the operation succeeded for this explicit token.
  final bool successful;

  /// The error code returned by the Instance ID API, if any.
  /// Common errors include `NOT_FOUND` or `INVALID_ARGUMENT`.
  final String? error;

  @override
  String toString() =>
      'TopicManagementTokenResult(token: $token, successful: $successful, error: $error)';
}

/// The aggregate result from a batch subscribe/unsubscribe operation.
final class TopicManagementResult {

  const TopicManagementResult({
    required this.successCount,
    required this.failureCount,
    required this.results,
  });

  /// Parses the raw JSON response from the IID batch API.
  ///
  /// [statusCode] is the HTTP status of the response, used to describe the
  /// failure when the body carries no usable error information (for example an
  /// HTML error page from a proxy).
  factory TopicManagementResult.fromJson(
    Map<String, dynamic> json,
    List<String> tokens, {
    int? statusCode,
  }) {
    // The response structure is:
    // { "results": [ {}, {"error": "NOT_FOUND"} ] }
    final dynamic rawResults = json['results'];

    if (rawResults is! List) {
      // The whole request failed (e.g. 401 with a google.rpc error envelope,
      // or a non-JSON body). Mark every token as failed with the best error
      // description available.
      final String error = _describeError(json['error'], statusCode);
      return TopicManagementResult(
        successCount: 0,
        failureCount: tokens.length,
        results: tokens
            .map((String t) => TopicManagementTokenResult(
                  token: t,
                  successful: false,
                  error: error,
                ))
            .toList(),
      );
    }

    final List<TopicManagementTokenResult> mappedResults =
        <TopicManagementTokenResult>[
      for (final (int index, dynamic item) in rawResults.indexed)
        if (item is Map<String, dynamic>)
          TopicManagementTokenResult(
            token:
                index < tokens.length ? tokens[index] : 'unknown-token-$index',
            successful: item['error'] == null,
            error: item['error'] == null
                ? null
                : _describeError(item['error'], null),
          ),
    ];

    final int successCount = mappedResults
        .where((TopicManagementTokenResult r) => r.successful)
        .length;
    final int failureCount = mappedResults.length - successCount;

    return TopicManagementResult(
      successCount: successCount,
      failureCount: failureCount,
      results: mappedResults,
    );
  }
  /// Renders an `error` field into a stable string.
  ///
  /// The Instance ID API returns a bare string per token (`"NOT_FOUND"`), but a
  /// request-level failure comes back as a `google.rpc` envelope
  /// (`{"code": 401, "status": "UNAUTHENTICATED", ...}`), and a proxy can
  /// return no JSON at all. All three shapes are handled here.
  static String _describeError(Object? error, int? statusCode) {
    if (error is String && error.isNotEmpty) return error;

    if (error is Map<String, dynamic>) {
      final Object? status = error['status'];
      if (status is String && status.isNotEmpty) return status;

      final Object? message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }

    if (statusCode != null) return 'HTTP_$statusCode';
    return 'UNKNOWN_ERROR';
  }

  /// The total number of tokens successfully processed.
  final int successCount;

  /// The total number of tokens that failed.
  final int failureCount;

  /// Detailed results corresponding 1:1 in order to the tokens passed in the request.
  final List<TopicManagementTokenResult> results;

  /// True if all tokens were successfully processed.
  bool get allSuccessful => failureCount == 0;

  /// Retrieves only the results that failed, useful for purging stale tokens.
  List<TopicManagementTokenResult> get failedResults =>
      results.where((TopicManagementTokenResult r) => !r.successful).toList();

  @override
  String toString() {
    return 'TopicManagementResult(success: $successCount, fail: $failureCount)';
  }
}
