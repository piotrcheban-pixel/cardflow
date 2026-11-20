/// Параметры планирования генерации (ADR-040 §2).
///
/// Единственное место коэффициентов вывода и запаса точности. Значения —
/// конфигурация приложения (допущения), а не характеристики модели; лимиты
/// модели приходят отдельно ([ModelLimits]) со своим источником.
/// Домен не зависит от Flutter.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/model_limits.dart';

/// Конфигурация бюджета вывода и запаса точности.
final class GenerationPlanningConfig {
  /// Создаёт конфигурацию; значения по умолчанию — из ADR-040 §2.
  const GenerationPlanningConfig({
    this.tokensPerCard = 300,
    this.outputFill = 0.85,
    this.schemaOverheadTokens = 200,
    this.minBatchCards = 5,
    this.batchCardsCeiling = 40,
    this.estimateMargin = 0.10,
    this.exactMargin = 0.03,
    this.unknownContextMaterialTokens = 6000,
    this.unknownContextOutputTokens = 2048,
    this.defaultOutputTokens = 8192,
    this.jsonBodyOverheadBytes = 1024,
  }) : assert(tokensPerCard > 0),
       assert(outputFill > 0 && outputFill <= 1),
       assert(schemaOverheadTokens >= 0),
       assert(minBatchCards >= 1),
       assert(batchCardsCeiling >= minBatchCards),
       assert(estimateMargin >= 0 && exactMargin >= 0),
       assert(unknownContextMaterialTokens > 0),
       assert(unknownContextOutputTokens > 0),
       assert(defaultOutputTokens > 0),
       assert(jsonBodyOverheadBytes >= 0);

  /// Токены вывода на одну карточку (средняя карточка; калибруется по usage).
  final int tokensPerCard;

  /// Доля `max_tokens`, которую можно занять карточками.
  final double outputFill;

  /// Служебные токены JSON-ответа.
  final int schemaOverheadTokens;

  /// Минимальное осмысленное число карточек в партии.
  final int minBatchCards;

  /// Потолок карточек в одном ответе (на запрос, а не на весь заказ).
  final int batchCardsCeiling;

  /// Запас, когда вход — оценка.
  final double estimateMargin;

  /// Запас, когда вход посчитан нативно (`count_tokens`).
  final double exactMargin;

  /// Бюджет материалов при неизвестном окне (legacy-допущение приложения).
  final int unknownContextMaterialTokens;

  /// Лимит вывода при неизвестном окне (допущение).
  final int unknownContextOutputTokens;

  /// Лимит вывода, если модель его не сообщает, а окно известно.
  final int defaultOutputTokens;

  /// Запас тела запроса (обёртка/JSON), байт.
  final int jsonBodyOverheadBytes;

  /// Запас точности для вида оценки.
  double margin({required bool exact}) => exact ? exactMargin : estimateMargin;

  /// Токены, которые нужны под [cards] карточек.
  ///
  /// `ceil((cards × tokensPerCard + schemaOverhead) / outputFill)`.
  int tokensFor(int cards) {
    final int safe = cards < 0 ? 0 : cards;
    final double value =
        (safe * tokensPerCard + schemaOverheadTokens) / outputFill;
    return value <= 0 ? 0 : value.ceil();
  }

  /// Сколько карточек помещается в [tokens] токенов ответа.
  ///
  /// `floor((tokens × outputFill − schemaOverhead) / tokensPerCard)`.
  int cardsFor(int tokens) {
    final double value =
        (tokens * outputFill - schemaOverheadTokens) / tokensPerCard;
    if (!value.isFinite || value <= 0) return 0;
    return value.floor();
  }

  /// Потолок вывода модели: подтверждённый лимит, иначе совместимое с окном
  /// допущение (ADR-040 §3, `RequestBudget`).
  int outputCapFor(ModelLimits limits) {
    final int? maxOutput = limits.maxOutputTokens.value;
    if (maxOutput != null) return maxOutput;
    final int? context = limits.contextTokens.value;
    if (context == null) return unknownContextOutputTokens;
    return math.min(defaultOutputTokens, math.max(1, context ~/ 2));
  }

  /// Желаемый объём ответа для заказа [requestedCards].
  ///
  /// `min(maxOutput, tokensFor(min(max(requested, minBatchCards), ceiling)))`.
  /// `null` — заказ «авто»: желаемый объём — полный потолок.
  int desiredOutputTokens({
    required int? requestedCards,
    required int maxOutputTokens,
  }) {
    final int cards;
    if (requestedCards == null) {
      cards = batchCardsCeiling;
    } else {
      cards = math.min(
        math.max(requestedCards, minBatchCards),
        batchCardsCeiling,
      );
    }
    return math.min(maxOutputTokens, tokensFor(cards));
  }
}
