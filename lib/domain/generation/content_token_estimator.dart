/// Оценка токенов единиц содержимого для планировщика адаптивной генерации.
///
/// Это **минимальный контракт** этапа TASK 02B: полноценный `GenerationEstimator`
/// (раздел G аудита TASK 01 — script-aware коэффициенты, схема, цена, калибровка
/// по `usage`) появляется на следующем этапе и реализует этот же интерфейс.
/// Планировщик не создаёт собственную систему оценки: он получает готовые
/// токены единиц от этого контракта.
///
/// Что здесь сознательно **не** делается:
/// - нет «универсальных 1000 токенов на изображение» (L-20): оценка идёт по
///   интерфейсу [ImageTokenModel], если модель его предоставляет, иначе — по
///   размеру в пикселях/байтах с явной пометкой допущения;
/// - `text.length / 3.5` не используется как «точный» подсчёт: текстовый
///   коэффициент остаётся прежним консервативным `TokenEstimator` (2,5 симв./токен).
/// Домен не зависит от Flutter.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';

/// Сколько пикселей изображения приходится на один токен (допущение).
///
/// Стартовое консервативное значение из раздела E.4 аудита TASK 01; подлежит
/// калибровке на живых прогонах (раздел G.7). Это **не** подтверждённая
/// формула провайдера: источник таких формул в репозитории отсутствует.
const int kImagePixelsPerToken = 750;

/// Сколько байт изображения приходится на один токен, если размеры неизвестны.
///
/// Консервативная оценка сверху для полностью неизвестного случая (E.4,
/// приоритет 3): 100 КБ изображение ≈ 390 токенов, 1 МБ ≈ 4096 токенов.
const int kImageBytesPerToken = 256;

/// Источник оценки токенов изображения (E.4).
enum ImageTokenSource {
  /// Оценка по [ImageTokenModel] возможностей модели (провайдерная формула).
  model,

  /// Эвристика по пикселям (`width × height / kImagePixelsPerToken`).
  dimensionHeuristic,

  /// Эвристика по байтам содержимого (размеры неизвестны).
  byteHeuristic,
}

/// Оценка токенов одного изображения с источником и пометкой неизвестности.
class ImageTokenEstimate {
  /// Создаёт оценку.
  const ImageTokenEstimate({
    required this.tokens,
    required this.source,
    required this.isAssumption,
  }) : assert(tokens >= 0, 'Токены не могут быть отрицательными');

  /// Оценка в токенах.
  final int tokens;

  /// Откуда взялась оценка.
  final ImageTokenSource source;

  /// true, если это допущение приложения, а не данные модели.
  final bool isAssumption;

  @override
  String toString() =>
      'ImageTokenEstimate($tokens, ${source.name}'
      '${isAssumption ? ', assumption' : ''})';
}

/// Контракт оценки единиц содержимого (заменяется `GenerationEstimator`).
///
/// Реализация обязана быть детерминированной: одинаковый вход даёт одинаковый
/// результат (иначе планирование перестаёт быть воспроизводимым).
abstract interface class ContentTokenEstimator {
  /// Версия оценки (пишется в `GenerationEstimate.estimatorVersion`).
  String get version;

  /// Сколько символов в среднем приходится на токен (для жёсткого деления
  /// текста, когда смысловые границы исчерпаны). Консервативная величина.
  double get charsPerToken;

  /// Оценка токенов текста.
  int estimateText(String text);

  /// Оценка токенов изображения.
  ///
  /// [model] — оценщик из возможностей модели (`ModelCapabilities.imageTokens`);
  /// `null` — подтверждённой формулы нет, работает консервативная эвристика
  /// с [ImageTokenEstimate.isAssumption] == true.
  ImageTokenEstimate estimateImage({
    int? width,
    int? height,
    required int bytes,
    ImageTokenModel? model,
  });
}

/// Консервативная эвристика: [TokenEstimator] для текста + размеры/байты для
/// изображений. Полноценная script-aware оценка — следующий этап (G).
class HeuristicContentTokenEstimator implements ContentTokenEstimator {
  /// Создаёт оценщик.
  const HeuristicContentTokenEstimator({
    this.textEstimator = const TokenEstimator(),
    this.pixelsPerToken = kImagePixelsPerToken,
    this.bytesPerToken = kImageBytesPerToken,
  }) : assert(pixelsPerToken > 0, 'Пикселей на токен должно быть > 0'),
       assert(bytesPerToken > 0, 'Байт на токен должно быть > 0');

  /// Оценщик текста (существующий контракт приложения).
  final TokenEstimator textEstimator;

  /// Пикселей на токен для размерной эвристики.
  final int pixelsPerToken;

  /// Байт на токен для байтовой эвристики.
  final int bytesPerToken;

  @override
  String get version => 'heuristic/1';

  @override
  double get charsPerToken => textEstimator.charsPerToken;

  @override
  int estimateText(String text) => textEstimator.estimate(text);

  @override
  ImageTokenEstimate estimateImage({
    int? width,
    int? height,
    required int bytes,
    ImageTokenModel? model,
  }) {
    final int safeBytes = bytes < 0 ? 0 : bytes;
    if (model != null) {
      final int tokens = model.estimate(
        width: width,
        height: height,
        bytes: safeBytes,
      );
      return ImageTokenEstimate(
        tokens: tokens < 0 ? 0 : tokens,
        source: ImageTokenSource.model,
        isAssumption: false,
      );
    }
    if (width != null && height != null && width > 0 && height > 0) {
      final int tokens = math.max(1, (width * height / pixelsPerToken).ceil());
      return ImageTokenEstimate(
        tokens: tokens,
        source: ImageTokenSource.dimensionHeuristic,
        isAssumption: true,
      );
    }
    final int tokens = math.max(1, (safeBytes / bytesPerToken).ceil());
    return ImageTokenEstimate(
      tokens: tokens,
      source: ImageTokenSource.byteHeuristic,
      isAssumption: true,
    );
  }
}
