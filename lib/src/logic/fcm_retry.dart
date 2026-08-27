import 'dart:math';

/// Controls retry behavior for FCM transient failures.
///
/// FCM guidance: https://firebase.google.com/docs/cloud-messaging/error-codes
/// Retry-After grammar: https://www.rfc-editor.org/rfc/rfc9110.html#field.retry-after
final class FcmRetryConfig {
  const FcmRetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.quotaInitialDelay = const Duration(minutes: 1),
    this.quotaMaxDelay = const Duration(minutes: 10),
    this.jitter = true,
  }) : assert(maxRetries >= 0);

  /// Number of retries after the initial attempt.
  final int maxRetries;

  /// Generic transient-error delay before the first retry.
  final Duration initialDelay;

  /// Maximum generic transient retry delay.
  final Duration maxDelay;

  /// Minimum initial delay for quota errors; FCM recommends at least one minute.
  /// Reference: https://firebase.google.com/docs/cloud-messaging/error-codes#quota_exceeded
  final Duration quotaInitialDelay;

  /// Maximum quota retry delay.
  final Duration quotaMaxDelay;

  /// Whether concurrent retries receive equal jitter by default.
  /// FCM recommends jitter when retrying multiple messages.
  final bool jitter;

  /// A preset that disables retries.
  static const FcmRetryConfig none = FcmRetryConfig(
    maxRetries: 0,
    jitter: false,
  );

  /// Validates values with runtime exceptions, including in release builds.
  void validate() {
    if (maxRetries < 0) {
      throw ArgumentError.value(
        maxRetries,
        'maxRetries',
        'must be non-negative',
      );
    }
    if (initialDelay < Duration.zero) {
      throw ArgumentError.value(
        initialDelay,
        'initialDelay',
        'must be non-negative',
      );
    }
    if (maxDelay < Duration.zero) {
      throw ArgumentError.value(maxDelay, 'maxDelay', 'must be non-negative');
    }
    if (quotaInitialDelay < Duration.zero) {
      throw ArgumentError.value(
        quotaInitialDelay,
        'quotaInitialDelay',
        'must be non-negative',
      );
    }
    if (quotaMaxDelay < Duration.zero) {
      throw ArgumentError.value(
        quotaMaxDelay,
        'quotaMaxDelay',
        'must be non-negative',
      );
    }
  }

  /// Calculates generic exponential backoff for a zero-indexed attempt.
  Duration delayForAttempt(
    int attempt, {
    Random? random,
    bool applyJitter = false,
  }) {
    validate();
    return _calculate(
      attempt,
      initialDelay,
      maxDelay,
      random: random,
      applyJitter: applyJitter && jitter,
    );
  }

  /// Calculates quota-safe exponential backoff for a zero-indexed attempt.
  Duration quotaDelayForAttempt(
    int attempt, {
    Random? random,
    bool applyJitter = false,
  }) {
    validate();
    // Quota backoff uses its own limits because FCM recommends slower recovery.
    final Duration base = _calculate(
      attempt,
      quotaInitialDelay,
      quotaMaxDelay,
      random: random,
      applyJitter: false,
    );
    if (!applyJitter || !jitter || base == Duration.zero) return base;

    final int baseMs = base.inMilliseconds;
    final int remainingMs = quotaMaxDelay.inMilliseconds - baseMs;
    if (remainingMs <= 0) return base;
    final int extraMs = min(remainingMs, max(1, baseMs));
    return Duration(
      milliseconds: baseMs + (random ?? Random()).nextInt(extraMs + 1),
    );
  }

  static Duration _calculate(
    int attempt,
    Duration initial,
    Duration maximum, {
    Random? random,
    required bool applyJitter,
  }) {
    if (attempt < 0) {
      throw ArgumentError.value(attempt, 'attempt', 'must be non-negative');
    }
    // Cap the shift to avoid integer growth for unusually large attempt values.
    final int shift = attempt > 30 ? 30 : attempt;
    final int rawMs = initial.inMilliseconds * (1 << shift);
    final int cappedMs = min(maximum.inMilliseconds, rawMs);
    if (!applyJitter || cappedMs <= 1) {
      return Duration(milliseconds: max(0, cappedMs));
    }
    // Equal jitter samples only from the upper half of the capped window.
    final Random source = random ?? Random();
    final int half = cappedMs ~/ 2;
    return Duration(milliseconds: half + source.nextInt(cappedMs - half + 1));
  }

  @override
  String toString() =>
      'FcmRetryConfig{maxRetries: $maxRetries, '
      'initialDelay: $initialDelay, maxDelay: $maxDelay, '
      'quotaInitialDelay: $quotaInitialDelay, quotaMaxDelay: $quotaMaxDelay, '
      'jitter: $jitter}';
}
