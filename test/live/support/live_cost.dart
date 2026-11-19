/// Предварительная стоимость live-прогона (TASK 04, раздел 6).
///
/// Стоимость — **оценка сверху** по тарифу и ожидаемым токенам; фактический
/// расход придёт в `usage` и будет записан в отчёт калибровки
/// (`LiveRunRecord`). Неизвестный тариф даёт `amount == null` и явную причину:
/// ноль вместо неизвестности не подставляется.
library;

import 'live_pricing.dart';
import 'live_test_config.dart';

/// Оценка стоимости сценария.
class LiveCostEstimate {
  /// Создаёт оценку.
  const LiveCostEstimate({
    required this.provider,
    required this.model,
    required this.requests,
    required this.inputTokens,
    required this.outputTokens,
    required this.amount,
    required this.currency,
    required this.price,
    required this.unknownReason,
  });

  /// Провайдер (id пресета).
  final String provider;

  /// Модель.
  final String model;

  /// Ожидаемое число логических запросов.
  final int requests;

  /// Ожидаемый вход суммарно по всем запросам; `null` — не известен.
  final int? inputTokens;

  /// Ожидаемый выход суммарно (не резерв `max_tokens`); `null` — не известен.
  final int? outputTokens;

  /// Предварительная стоимость; `null` — тариф неизвестен.
  final double? amount;

  /// Валюта (пусто при неизвестной стоимости).
  final String currency;

  /// Тариф, по которому считали (если известен).
  final LivePrice? price;

  /// Причина неизвестной стоимости.
  final String? unknownReason;

  /// true, если стоимость посчитана.
  bool get isKnown => amount != null;

  /// Разрешает ли прогон бюджет из [config] и этот расчёт.
  ///
  /// Правила:
  /// - неизвестная стоимость блокирует запуск, если явно не разрешено
  ///   `allowUnknownCost`;
  /// - известная стоимость должна быть не больше лимита (по умолчанию лимит 0 —
  ///   платный прогон запрещён);
  /// - нулевая/отрицательная цена в бюджете — запрет.
  String? blockReason(LiveTestConfig config) {
    if (config.maxRequests <= 0) {
      return 'бюджет запросов ${config.maxRequests} — запросы запрещены';
    }
    if (requests > config.maxRequests) {
      return 'сценарий требует $requests запросов при лимите '
          '${config.maxRequests}';
    }
    if (!isKnown) {
      if (!config.allowUnknownCost) {
        return 'стоимость неизвестна (${unknownReason ?? 'нет тарифа'}); '
            'запуск требует $kLiveAllowUnknownCostVariable=1 после ручной '
            'оценки тарифа';
      }
      if (config.maxEstimatedCostUsd <= 0) {
        return 'при неизвестной стоимости нужен ненулевой лимит '
            '$kLiveMaxCostVariable';
      }
      return null;
    }
    if (config.maxEstimatedCostUsd <= 0) {
      return 'лимит стоимости не задан ($kLiveMaxCostVariable=0) — '
          'платный прогон запрещён';
    }
    if (amount! > config.maxEstimatedCostUsd) {
      return 'оценка ${formatAmount()} превышает лимит '
          '${config.maxEstimatedCostUsd.toStringAsFixed(4)} USD';
    }
    return null;
  }

  /// Стоимость строкой: `0.0031 USD` либо `неизвестна`.
  String formatAmount() {
    if (amount == null) return 'неизвестна';
    return '${amount!.toStringAsFixed(4)} $currency';
  }

  /// JSON для отчёта (null остаётся null, а не 0).
  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    'model': model,
    'requests': requests,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'amount': amount,
    'currency': currency.isEmpty ? null : currency,
    'priceVerifiedOn': price?.verifiedOn,
    'priceSource': price?.sourceUrl,
    'unknownReason': unknownReason,
  };

  @override
  String toString() =>
      'LiveCostEstimate($provider/$model, requests: $requests, '
      'cost: ${formatAmount()})';
}

/// Считает предварительную стоимость сценария.
///
/// [inputTokensPerRequest]/[outputTokensPerRequest] — ожидаемые значения на
/// один запрос (оценка сверху по плану и эвристике оценки токенов). Функция
/// чистая: сеть не используется и тарифы не «проверяются» запросами.
LiveCostEstimate estimateLiveCost({
  required String provider,
  required String model,
  required int requests,
  required int inputTokensPerRequest,
  required int outputTokensPerRequest,
}) {
  final int safeRequests = requests < 0 ? 0 : requests;
  final int inputTokens =
      safeRequests * (inputTokensPerRequest < 0 ? 0 : inputTokensPerRequest);
  final int outputTokens =
      safeRequests * (outputTokensPerRequest < 0 ? 0 : outputTokensPerRequest);
  final LivePrice? price = livePriceFor(provider, model);
  if (price == null) {
    return LiveCostEstimate(
      provider: provider,
      model: model,
      requests: safeRequests,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      amount: null,
      currency: '',
      price: null,
      unknownReason: kLivePriceUnknownReason,
    );
  }
  final double amount = price.costFor(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
  );
  return LiveCostEstimate(
    provider: provider,
    model: model,
    requests: safeRequests,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    amount: amount,
    currency: price.currency,
    price: price,
    unknownReason: null,
  );
}
