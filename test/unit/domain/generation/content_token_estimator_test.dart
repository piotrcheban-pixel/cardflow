import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';

/// TASK 02B: минимальный контракт оценки единиц содержимого.
///
/// Полноценный `GenerationEstimator` (раздел G аудита) заменит эту
/// реализацию; поведение «неизвестно ≠ ноль» и «нет универсальных 1000
/// токенов на изображение» проверяется здесь.
void main() {
  const HeuristicContentTokenEstimator estimator =
      HeuristicContentTokenEstimator();

  group('Текст', () {
    test('оценка консервативная: 2,5 символа на токен, пустой текст — 0', () {
      expect(estimator.estimateText(''), 0);
      expect(estimator.estimateText('абвгд'), 2);
      expect(estimator.estimateText('а' * 25), 10);
      expect(estimator.charsPerToken, 2.5);
      expect(estimator.version, isNotEmpty);
    });

    test('детерминированность: одинаковый текст — одинаковая оценка', () {
      const String text = 'Повторяемый текст для проверки детерминизма.';
      expect(estimator.estimateText(text), estimator.estimateText(text));
    });
  });

  group('Изображения', () {
    test('размеры известны — размерная эвристика с пометкой допущения', () {
      final ImageTokenEstimate estimate = estimator.estimateImage(
        width: 1500,
        height: 1500,
        bytes: 1000,
      );
      expect(estimate.tokens, 3000, reason: '2 250 000 / 750');
      expect(estimate.source, ImageTokenSource.dimensionHeuristic);
      expect(estimate.isAssumption, isTrue);
    });

    test('размеры неизвестны — байтовая эвристика, не 1000 на изображение', () {
      final ImageTokenEstimate estimate = estimator.estimateImage(bytes: 1024);
      expect(estimate.tokens, 4, reason: 'ceil(1024 / 256)');
      expect(estimate.tokens, isNot(1000));
      expect(estimate.source, ImageTokenSource.byteHeuristic);
      expect(estimate.isAssumption, isTrue);

      final ImageTokenEstimate big = estimator.estimateImage(
        bytes: 1024 * 1024,
      );
      expect(big.tokens, 4096);
    });

    test('модель предоставила формулу — используется она, без допущения', () {
      final _FixedImageModel model = _FixedImageModel(123);
      final ImageTokenEstimate estimate = estimator.estimateImage(
        width: 10,
        height: 10,
        bytes: 20,
        model: model,
      );
      expect(estimate.tokens, 123);
      expect(estimate.source, ImageTokenSource.model);
      expect(estimate.isAssumption, isFalse);
      expect(model.lastWidth, 10);
      expect(model.lastHeight, 10);
      expect(model.lastBytes, 20);
    });

    test('нулевой/отрицательный размер не даёт отрицательных токенов', () {
      expect(estimator.estimateImage(bytes: 0).tokens, greaterThanOrEqualTo(0));
      expect(
        estimator.estimateImage(bytes: -10).tokens,
        greaterThanOrEqualTo(0),
      );
    });

    test('конфигурация коэффициентов используется', () {
      const HeuristicContentTokenEstimator custom =
          HeuristicContentTokenEstimator(
            pixelsPerToken: 100,
            bytesPerToken: 10,
          );
      expect(
        custom.estimateImage(width: 100, height: 100, bytes: 1).tokens,
        100,
      );
      expect(custom.estimateImage(bytes: 100).tokens, 10);
    });

    test('toString фиксирует источник и пометку допущения', () {
      expect(
        estimator.estimateImage(width: 10, height: 10, bytes: 1).toString(),
        contains('dimensionHeuristic'),
      );
      expect(
        estimator.estimateImage(width: 10, height: 10, bytes: 1).toString(),
        contains('assumption'),
      );
      expect(
        estimator
            .estimateImage(bytes: 1, model: _FixedImageModel(5))
            .toString(),
        isNot(contains('assumption')),
      );
    });
  });
}

class _FixedImageModel implements ImageTokenModel {
  _FixedImageModel(this.tokens);

  final int tokens;
  int? lastWidth;
  int? lastHeight;
  int? lastBytes;

  @override
  int estimate({int? width, int? height, required int bytes}) {
    lastWidth = width;
    lastHeight = height;
    lastBytes = bytes;
    return tokens;
  }

  @override
  String get source => 'test_formula';
}
