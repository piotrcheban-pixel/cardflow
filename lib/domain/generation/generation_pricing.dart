/// Цены генерации и состояние их неизвестности (раздел G.5 аудита TASK 01).
///
/// В репозитории нет ни одной подтверждённой цены провайдера (приложение 2
/// аудита), поэтому цена — nullable-значение: `null` означает «неизвестно», а
/// не «ноль». Стоимость считается только при известных обеих ценах и валюте;
/// иначе результата стоимости нет ([GenerationCost] `null`), а [PricingState]
/// остаётся `incomplete`/`unknown`. Домен не зависит от Flutter.
library;

/// Полнота цен аккаунта.
enum PricingState {
  /// Обе цены и валюта известны — стоимость можно посчитать.
  complete,

  /// Известна только часть данных — стоимость посчитать нельзя.
  incomplete,

  /// Не известно ничего — стоимость посчитать нельзя.
  unknown,
}

/// Цена за миллион токенов и валюта; любое поле может быть неизвестно.
///
/// Значения попадают сюда только из пользовательских настроек (раздел K.1
/// аудита): каталог провайдеров не содержит цен, и подставлять их нельзя.
class GenerationPricing {
  /// Создаёт структуру цен; неизвестное значение — `null`.
  const GenerationPricing({
    this.inputPerMillion,
    this.outputPerMillion,
    this.currency,
  });

  /// Полностью неизвестная цена (`state == unknown`).
  static const GenerationPricing unknown = GenerationPricing();

  /// Цена входных токенов за миллион; `null` — неизвестно.
  final double? inputPerMillion;

  /// Цена выходных токенов за миллион; `null` — неизвестно.
  final double? outputPerMillion;

  /// Валюта цены (`USD`, `RUB`, …); `null` — неизвестно.
  final String? currency;

  /// true, если стоимость можно посчитать: обе цены и валюта известны.
  bool get isComplete =>
      _isKnownPrice(inputPerMillion) &&
      _isKnownPrice(outputPerMillion) &&
      (currency?.isNotEmpty ?? false);

  /// Состояние полноты цен.
  PricingState get state {
    if (inputPerMillion == null &&
        outputPerMillion == null &&
        currency == null) {
      return PricingState.unknown;
    }
    return isComplete ? PricingState.complete : PricingState.incomplete;
  }

  /// Стоимость запроса; `null` при неполных ценах — никогда не ноль.
  ///
  /// Формула G.5: `tokens / 1e6 × price`. Нулевая цена — известное значение
  /// (бесплатная модель), поэтому 0 возвращается честно, если цена задана;
  /// при неизвестной цене — только `null`.
  GenerationCost? costFor({
    required int inputTokens,
    required int outputTokens,
  }) {
    assert(inputTokens >= 0, 'Токены не могут быть отрицательными');
    assert(outputTokens >= 0, 'Токены не могут быть отрицательными');
    if (!isComplete) return null;
    final double input = inputTokens / 1000000 * inputPerMillion!;
    final double output = outputTokens / 1000000 * outputPerMillion!;
    return GenerationCost(
      input: input,
      output: output,
      total: input + output,
      currency: currency!,
    );
  }

  /// JSON-представление для аккаунта провайдера (раздел K.1 аудита).
  Map<String, Object?> toJson() => <String, Object?>{
    'input_per_mtok': inputPerMillion,
    'output_per_mtok': outputPerMillion,
    'currency': currency,
  };

  /// Разбирает цены; `null` — если значение не является объектом.
  ///
  /// Отсутствующие и некорректные поля остаются неизвестными (`null`), а не
  /// нулём; отрицательные и нечисловые значения цен отбрасываются.
  static GenerationPricing? fromJson(Object? json) {
    if (json is! Map) return null;
    return GenerationPricing(
      inputPerMillion: _priceFromJson(json['input_per_mtok']),
      outputPerMillion: _priceFromJson(json['output_per_mtok']),
      currency: _currencyFromJson(json['currency']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenerationPricing &&
          other.inputPerMillion == inputPerMillion &&
          other.outputPerMillion == outputPerMillion &&
          other.currency == currency;

  @override
  int get hashCode => Object.hash(inputPerMillion, outputPerMillion, currency);

  @override
  String toString() => isComplete
      ? 'GenerationPricing($inputPerMillion/$outputPerMillion $currency)'
      : 'GenerationPricing(${state.name})';
}

/// Посчитанная стоимость запроса в валюте цен аккаунта.
class GenerationCost {
  /// Создаёт стоимость.
  const GenerationCost({
    required this.input,
    required this.output,
    required this.total,
    required this.currency,
  });

  /// Стоимость входных токенов.
  final double input;

  /// Стоимость выходных токенов.
  final double output;

  /// Суммарная стоимость.
  final double total;

  /// Валюта (из цен аккаунта).
  final String currency;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenerationCost &&
          other.input == input &&
          other.output == output &&
          other.total == total &&
          other.currency == currency;

  @override
  int get hashCode => Object.hash(input, output, total, currency);

  @override
  String toString() => 'GenerationCost(${total.toStringAsFixed(6)} $currency)';
}

bool _isKnownPrice(double? value) =>
    value != null && value.isFinite && value >= 0;

double? _priceFromJson(Object? value) {
  if (value is num && value.isFinite && value >= 0) return value.toDouble();
  return null;
}

String? _currencyFromJson(Object? value) {
  if (value is! String) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
