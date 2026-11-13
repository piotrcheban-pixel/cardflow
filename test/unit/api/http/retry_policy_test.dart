import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/http/retry_policy.dart';

/// Красная фаза итерации 3b: retry/backoff/429 (SPEC A8.6, ADR-012 §1).
void main() {
  group('parseRetryAfter', () {
    final now = DateTime.utc(2026, 11, 13, 12, 0, 0);

    test('секунды', () {
      expect(parseRetryAfter('3'), const Duration(seconds: 3));
      expect(parseRetryAfter('0'), Duration.zero);
      expect(parseRetryAfter(' 7 '), const Duration(seconds: 7));
    });

    test('отрицательное и мусор → null/ноль', () {
      expect(parseRetryAfter('-5'), Duration.zero);
      expect(parseRetryAfter('abc'), isNull);
      expect(parseRetryAfter(''), isNull);
      expect(parseRetryAfter(null), isNull);
    });

    test('HTTP-date (RFC 9110)', () {
      final future = now.add(const Duration(seconds: 5));
      expect(
        parseRetryAfter(HttpDate.format(future), now: () => now),
        const Duration(seconds: 5),
      );
      final past = now.subtract(const Duration(seconds: 5));
      expect(
        parseRetryAfter(HttpDate.format(past), now: () => now),
        Duration.zero,
      );
    });
  });

  group('RetryPolicy.decide', () {
    RetryPolicy policy({int maxAttempts = 4, double Function()? jitter}) {
      return RetryPolicy(maxAttempts: maxAttempts, jitter: jitter ?? () => 1.0);
    }

    test('5xx: экспоненциальный backoff с джиттером, максимум попыток', () {
      final retry = policy();
      expect(
        retry.decide(attempt: 1, statusCode: 500).delay,
        const Duration(seconds: 1),
      );
      expect(
        retry.decide(attempt: 2, statusCode: 502).delay,
        const Duration(seconds: 2),
      );
      expect(
        retry.decide(attempt: 3, statusCode: 503).delay,
        const Duration(seconds: 4),
      );
      expect(retry.decide(attempt: 4, statusCode: 500).shouldRetry, isFalse);
      expect(retry.decide(attempt: 4, statusCode: 500).delay, Duration.zero);
    });

    test('джиттер масштабирует задержку (full jitter)', () {
      final retry = policy(jitter: () => 0.5);
      expect(
        retry.decide(attempt: 1, statusCode: 500).delay,
        const Duration(milliseconds: 500),
      );
      final zero = policy(jitter: () => 0.0);
      expect(zero.decide(attempt: 1, statusCode: 500).delay, Duration.zero);
    });

    test('maxDelay ограничивает рост', () {
      final retry = RetryPolicy(
        maxAttempts: 10,
        baseDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 3),
        jitter: () => 1.0,
      );
      expect(
        retry.decide(attempt: 5, statusCode: 500).delay,
        const Duration(seconds: 3),
      );
    });

    test('429: пауза ровно по Retry-After', () {
      final retry = policy(jitter: () => 0.1);
      final decision = retry.decide(
        attempt: 1,
        statusCode: 429,
        retryAfter: const Duration(seconds: 2),
      );
      expect(decision.shouldRetry, isTrue);
      expect(decision.delay, const Duration(seconds: 2));
    });

    test('429 без Retry-After — backoff как у 5xx', () {
      final retry = policy();
      expect(
        retry.decide(attempt: 2, statusCode: 429).delay,
        const Duration(seconds: 2),
      );
    });

    test('429: maxRetryAfter настраивается (cap — осознанное решение)', () {
      final retry = RetryPolicy(
        maxRetryAfter: const Duration(seconds: 5),
        jitter: () => 1.0,
      );
      expect(
        retry
            .decide(
              attempt: 1,
              statusCode: 429,
              retryAfter: const Duration(seconds: 4),
            )
            .delay,
        const Duration(seconds: 4),
      );
      expect(
        retry
            .decide(
              attempt: 1,
              statusCode: 429,
              retryAfter: const Duration(seconds: 6),
            )
            .shouldRetry,
        isFalse,
      );
    });

    test('429 с огромным Retry-After: автоматического повтора нет', () {
      final retry = policy();
      final decision = retry.decide(
        attempt: 1,
        statusCode: 429,
        retryAfter: const Duration(seconds: 120),
      );
      expect(decision.shouldRetry, isFalse);
      expect(decision.delay, Duration.zero);
    });

    test('401/403/400/404/422 не повторяются', () {
      final retry = policy();
      for (final status in <int>[400, 401, 403, 404, 422]) {
        expect(
          retry.decide(attempt: 1, statusCode: status).shouldRetry,
          isFalse,
          reason: 'status=$status',
        );
      }
    });

    test('таймаут и сетевая ошибка повторяются', () {
      final retry = policy();
      expect(retry.decide(attempt: 1, isTimeout: true).shouldRetry, isTrue);
      expect(
        retry.decide(attempt: 1, isConnectionError: true).shouldRetry,
        isTrue,
      );
      expect(retry.decide(attempt: 4, isTimeout: true).shouldRetry, isFalse);
    });

    test('неизвестная ошибка без статуса не повторяется', () {
      expect(policy().decide(attempt: 1).shouldRetry, isFalse);
    });

    test('attempt < 1 → ArgumentError', () {
      expect(
        () => policy().decide(attempt: 0, statusCode: 500),
        throwsArgumentError,
      );
      expect(
        () => policy().decide(attempt: -1, statusCode: 500),
        throwsArgumentError,
      );
    });

    test('maxAttempts=1: единственная попытка не повторяется', () {
      final retry = RetryPolicy(maxAttempts: 1, jitter: () => 1.0);
      expect(retry.decide(attempt: 1, statusCode: 500).shouldRetry, isFalse);
    });
  });
}
