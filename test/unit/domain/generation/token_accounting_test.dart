import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/token_accounting.dart';

/// TASK 03: оценка ≠ факт, неизвестное ≠ 0, калибровка по `usage`.
void main() {
  group('TokenValue: виды значений', () {
    test('оценка, резерв и точное значение различаются видом', () {
      const TokenValue estimate = TokenValue.estimate(100, source: 'heuristic');
      const TokenValue reserve = TokenValue.reserve(8192, source: 'plan');
      const TokenValue exact = TokenValue.exact(97, source: 'usage');
      expect(estimate.kind, TokenValueKind.estimate);
      expect(reserve.kind, TokenValueKind.reserve);
      expect(exact.kind, TokenValueKind.exact);
      expect(estimate.isEstimate, isTrue);
      expect(exact.isEstimate, isFalse);
      expect(exact.tokens, 97);
    });

    test('неизвестное значение — null, а не 0', () {
      const TokenValue unknown = TokenValue.unknown(source: 'usage.prompt');
      expect(unknown.isKnown, isFalse);
      expect(unknown.tokens, isNull);
      expect(unknown.kind, TokenValueKind.unknown);
    });

    test('нулевое известное значение — не неизвестность', () {
      const TokenValue zero = TokenValue.exact(0, source: 'no-images');
      expect(zero.isKnown, isTrue);
      expect(zero.kind, TokenValueKind.exact);
    });

    test('отрицательное значение запрещено', () {
      expect(
        () => TokenValue.estimate(-1, source: 'test'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('TokenValue.sum', () {
    test('сумма оценок остаётся оценкой', () {
      final TokenValue sum = TokenValue.sum(const <TokenValue>[
        TokenValue.estimate(10, source: 'a'),
        TokenValue.estimate(20, source: 'b'),
      ], source: 'sum');
      expect(sum.tokens, 30);
      expect(sum.kind, TokenValueKind.estimate);
    });

    test('неизвестное слагаемое делает сумму неизвестной (не 0)', () {
      final TokenValue sum = TokenValue.sum(const <TokenValue>[
        TokenValue.estimate(10, source: 'a'),
        TokenValue.unknown(source: 'b'),
      ], source: 'sum');
      expect(sum.isKnown, isFalse);
    });

    test('резерв в сумме помечает итог резервом', () {
      final TokenValue sum = TokenValue.sum(const <TokenValue>[
        TokenValue.estimate(10, source: 'a'),
        TokenValue.reserve(100, source: 'out'),
      ], source: 'sum');
      expect(sum.tokens, 110);
      expect(sum.kind, TokenValueKind.reserve);
    });
  });

  group('TokenCalibrationSample', () {
    TokenCalibrationSample sample({
      int? estimated,
      int? actualIn,
      int? actualOut,
      int limit = 1,
    }) {
      return TokenCalibrationSample(
        chunkIndex: 1,
        attempt: 1,
        recovered: false,
        plannedInput: TokenValue.estimate(estimated ?? 100, source: 'plan'),
        requestInput: TokenValue.estimate(estimated ?? 100, source: 'request'),
        actualInput: actualIn == null
            ? const TokenValue.unknown(source: 'usage.prompt_tokens')
            : TokenValue.exact(actualIn, source: 'usage.prompt_tokens'),
        actualOutput: actualOut == null
            ? const TokenValue.unknown(source: 'usage.completion_tokens')
            : TokenValue.exact(actualOut, source: 'usage.completion_tokens'),
        reservedOutput: TokenValue.reserve(limit * 1024, source: 'max_tokens'),
        estimatorVersion: 'heuristic/1/request-1',
      );
    }

    test('отношение факт/оценка считается только при известных значениях', () {
      expect(sample(estimated: 100, actualIn: 90).inputRatio, 0.9);
      expect(sample(estimated: 100).inputRatio, isNull);
      expect(sample(estimated: 0, actualIn: 10).inputRatio, isNull);
    });

    test('отношение факт/резерв вывода', () {
      expect(sample(actualOut: 512, limit: 1).outputRatio, 0.5);
      expect(sample(limit: 1).outputRatio, isNull);
    });

    test('отсутствие usage фиксируется явно', () {
      final TokenCalibrationSample empty = sample();
      expect(empty.usageAbsent, isTrue);
      expect(empty.hasCompleteUsage, isFalse);
      final TokenCalibrationSample withInput = sample(actualIn: 90);
      expect(withInput.usageAbsent, isFalse);
      expect(withInput.hasCompleteUsage, isFalse);
    });
  });

  group('TokenCalibrationReport', () {
    TokenCalibrationSample sample({
      required int estimated,
      int? actualIn,
      int? actualOut,
    }) {
      return TokenCalibrationSample(
        chunkIndex: 1,
        attempt: 1,
        recovered: false,
        plannedInput: TokenValue.estimate(estimated, source: 'plan'),
        requestInput: TokenValue.estimate(estimated, source: 'request'),
        actualInput: actualIn == null
            ? const TokenValue.unknown(source: 'usage.prompt_tokens')
            : TokenValue.exact(actualIn, source: 'usage.prompt_tokens'),
        actualOutput: actualOut == null
            ? const TokenValue.unknown(source: 'usage.completion_tokens')
            : TokenValue.exact(actualOut, source: 'usage.completion_tokens'),
        reservedOutput: const TokenValue.reserve(1024, source: 'max_tokens'),
        estimatorVersion: 'heuristic/1/request-1',
      );
    }

    test('пустой отчёт — нет данных, а не «0 токенов»', () {
      const TokenCalibrationReport report = TokenCalibrationReport.empty();
      expect(report.hasFacts, isFalse);
      expect(report.meanInputRatio, isNull);
      expect(report.samplesWithoutUsage, 0);
      expect(report.toString(), contains('n/a'));
    });

    test('среднее и разброс отношения входа', () {
      final TokenCalibrationReport report = TokenCalibrationReport(
        samples: <TokenCalibrationSample>[
          sample(estimated: 100, actualIn: 80, actualOut: 100),
          sample(estimated: 100, actualIn: 120, actualOut: 200),
        ],
        failedRequests: 1,
      );
      expect(report.inputSamples, 2);
      expect(report.outputSamples, 2);
      expect(report.meanInputRatio, 1.0);
      expect(report.minInputRatio, 0.8);
      expect(report.maxInputRatio, 1.2);
      expect(report.samplesWithoutUsage, 0);
      expect(report.failedRequests, 1);
    });

    test('ответы без usage учитываются отдельно', () {
      final TokenCalibrationReport report = TokenCalibrationReport(
        samples: <TokenCalibrationSample>[
          sample(estimated: 100),
          sample(estimated: 100, actualIn: 90),
        ],
        failedRequests: 2,
      );
      expect(report.samplesWithoutUsage, 1);
      expect(report.inputSamples, 1);
      expect(report.meanInputRatio, 0.9);
    });
  });
}
