/// Тарифы провайдеров для **предварительной** оценки стоимости live-тестов
/// (TASK 04, раздел 6).
///
/// Правила:
/// - в таблицу попадают только значения с **официальной** страницы тарифов
///   провайдера, с URL и датой проверки;
/// - если тариф модели не подтверждён, записи нет: [livePriceFor] возвращает
///   `null`, стоимость считается **неизвестной** (не ноль);
/// - цена не является частью приложения и не подставляется в генерацию: это
///   инфраструктура подготовки испытаний;
/// - каталог приложения (`provider_preset.dart`) тарифов не содержит, поэтому
///   отсутствие записи здесь — ожидаемое состояние, а не дефект.
///
/// Проверено 2026-11-19:
/// - DeepSeek: <https://api-docs.deepseek.com/quick_start/pricing>
///   (`deepseek-flash` = DeepSeek-V4.1-Flash-1017, `deepseek-v4-pro`; off-peak
///   вдвое дешевле, поэтому для верхней оценки взяты **пиковые** тарифы);
/// - OpenAI: <https://developers.openai.com/api/docs/pricing> (standard, не
///   Batch/Flex/Fast; данные модели `gpt-4o`, `gpt-4o-mini`);
/// - Anthropic: <https://platform.claude.com/docs/en/about-claude/pricing> —
///   модели каталога приложения (`claude-3-5-*`) в актуальной таблице
///   отсутствуют, тариф неизвестен;
/// - Gemini: страница тарифов официального сайта недоступна из окружения
///   (редирект на `aistudio.google.com`) — тариф неизвестен, не подставляется.
library;

/// Тариф модели: цена за миллион токенов и источник.
class LivePrice {
  /// Создаёт тариф.
  const LivePrice({
    required this.inputPerMillion,
    required this.outputPerMillion,
    required this.currency,
    required this.sourceUrl,
    required this.verifiedOn,
    required this.basis,
  });

  /// Цена входных токенов за миллион.
  final double inputPerMillion;

  /// Цена выходных токенов за миллион.
  final double outputPerMillion;

  /// Валюта (`USD`).
  final String currency;

  /// Официальная страница тарифов.
  final String sourceUrl;

  /// Дата проверки (`YYYY-MM-DD`).
  final String verifiedOn;

  /// Основание выбора (например, «пиковый тариф — верхняя оценка»).
  final String basis;

  /// Стоимость [inputTokens] + [outputTokens] по этому тарифу.
  double costFor({required int inputTokens, required int outputTokens}) {
    return inputTokens / 1000000 * inputPerMillion +
        outputTokens / 1000000 * outputPerMillion;
  }

  @override
  String toString() =>
      'LivePrice($inputPerMillion/$outputPerMillion $currency, '
      'verified $verifiedOn)';
}

/// Тарифы каталога приложения, подтверждённые официальными страницами.
const Map<String, LivePrice> kLivePrices = <String, LivePrice>{
  // DeepSeek: пиковые тарифы (off-peak: $0.15 вход / $0.60 выход).
  'deepseek/deepseek-flash': LivePrice(
    inputPerMillion: 0.30,
    outputPerMillion: 1.20,
    currency: 'USD',
    sourceUrl: 'https://api-docs.deepseek.com/quick_start/pricing',
    verifiedOn: '2026-11-19',
    basis: 'пиковый тариф deepseek-flash (верхняя оценка; off-peak вдвое ниже)',
  ),
  'deepseek/deepseek-v4-pro': LivePrice(
    inputPerMillion: 1.32,
    outputPerMillion: 3.96,
    currency: 'USD',
    sourceUrl: 'https://api-docs.deepseek.com/quick_start/pricing',
    verifiedOn: '2026-11-19',
    basis: 'пиковый тариф deepseek-v4-pro (верхняя оценка)',
  ),
  // OpenAI: standard-тарифы (не Batch/Flex/Fast), страница проверена.
  'openai/gpt-4o': LivePrice(
    inputPerMillion: 2.50,
    outputPerMillion: 10.00,
    currency: 'USD',
    sourceUrl: 'https://developers.openai.com/api/docs/pricing',
    verifiedOn: '2026-11-19',
    basis: 'standard, short context',
  ),
  'openai/gpt-4o-mini': LivePrice(
    inputPerMillion: 0.15,
    outputPerMillion: 0.60,
    currency: 'USD',
    sourceUrl: 'https://developers.openai.com/api/docs/pricing',
    verifiedOn: '2026-11-19',
    basis: 'standard, short context',
  ),
};

/// Причина, по которой тариф считается неизвестным.
const String kLivePriceUnknownReason =
    'тариф модели не подтверждён официальной страницей провайдера '
    '(проверено 2026-11-19); стоимость неизвестна — не ноль';

/// Тариф модели или `null`, если он не подтверждён.
LivePrice? livePriceFor(String provider, String model) {
  return kLivePrices['$provider/${model.trim()}'];
}
