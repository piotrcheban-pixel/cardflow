/// Бюджет входа и трассировка расчёта (раздел D аудита TASK 01).
///
/// Формула D.1: бюджет материалов считается от окна модели, резерва вывода,
/// фиксированной обвязки (системный промпт, схема, обёртка, каталог
/// изображений, image-части) и запаса безопасности. Клампинга в 2 000 нет:
/// если бюджет меньше минимально рабочего, это явный признак невыполнимого
/// плана ([GenerationBudget.isWorkable] == false), а не «всё равно 2000».
///
/// Значения-допущения ниже — конфигурация приложения, а не характеристики
/// моделей: ни одно из них не является подтверждённым лимитом провайдера.
/// Домен не зависит от Flutter.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/model_capabilities.dart';

/// Оценка вывода на одну карточку, токенов (допущение, калибруется на `usage`).
///
/// Выводится из правил промпта: `front` ≤ 500 символов, `back` ≤ 2000
/// (`card_content_validator.dart`) при консервативных 2,5 симв./токен ≈ 1000
/// токенов плюс JSON-конверт карточки. Не характеристика модели.
const int kBudgetPerCardOutputTokens = 1024;

/// Конверт ответа `{"cards":[…]}` и служебные поля, токенов (допущение).
const int kBudgetJsonEnvelopeTokens = 16;

/// Лимит вывода по умолчанию, если возможности модели его не дают (D.2).
const int kBudgetDefaultOutputCapTokens = 4096;

/// Консервативный бюджет материалов при неизвестном окне (C.5: вход ≤ 6000).
const int kBudgetUnknownContextInputTokens = 6000;

/// Консервативный лимит вывода при неизвестном окне (C.5: вывод ≤ 2048).
const int kBudgetUnknownContextOutputCapTokens = 2048;

/// Минимальный рабочий бюджет входа (D.1).
const int kBudgetMinWorkableInputTokens = 512;

/// Минимальный запас безопасности для известного окна (D.1).
const int kBudgetMinSafetyMarginTokens = 256;

/// Доля окна под запас безопасности (D.1).
const double kBudgetSafetyMarginFraction = 0.05;

/// Консервативный перевод байтов тела в токены (E.5).
///
/// Кириллица в UTF-8 — 2 байта на символ, консервативная оценка ≤ 2,2
/// символа на токен, итого не более 4 байт тела на токен. Значение —
/// конфигурация, а не факт провайдера; используется только для ограничения
/// тела запроса.
const int kBudgetBytesPerTokenBound = 4;

/// Настраиваемые значения-допущения бюджета (калибруются живыми прогонами).
class GenerationBudgetConfig {
  /// Создаёт конфигурацию; значения по умолчанию — из разделов C/D аудита.
  const GenerationBudgetConfig({
    this.perCardOutputTokens = kBudgetPerCardOutputTokens,
    this.jsonEnvelopeTokens = kBudgetJsonEnvelopeTokens,
    this.defaultOutputCapTokens = kBudgetDefaultOutputCapTokens,
    this.unknownContextInputTokens = kBudgetUnknownContextInputTokens,
    this.unknownContextOutputCapTokens = kBudgetUnknownContextOutputCapTokens,
    this.minWorkableInputTokens = kBudgetMinWorkableInputTokens,
    this.minSafetyMarginTokens = kBudgetMinSafetyMarginTokens,
    this.safetyMarginFraction = kBudgetSafetyMarginFraction,
    this.bytesPerTokenBound = kBudgetBytesPerTokenBound,
  });

  /// Оценка вывода на одну карточку.
  final int perCardOutputTokens;

  /// Конверт ответа.
  final int jsonEnvelopeTokens;

  /// Лимит вывода, если возможности модели его не дают.
  final int defaultOutputCapTokens;

  /// Бюджет материалов при неизвестном окне.
  final int unknownContextInputTokens;

  /// Лимит вывода при неизвестном окне.
  final int unknownContextOutputCapTokens;

  /// Минимально рабочий бюджет материалов.
  final int minWorkableInputTokens;

  /// Минимальный запас безопасности.
  final int minSafetyMarginTokens;

  /// Доля окна под запас безопасности.
  final double safetyMarginFraction;

  /// Байт тела на токен для ограничения размера запроса.
  final int bytesPerTokenBound;
}

/// Источник бюджета: данные модели или консервативное допущение.
enum BudgetSource {
  /// Окно контекста известно — бюджет посчитан по нему.
  capabilities,

  /// Окно неизвестно — действует консервативное допущение.
  assumption,
}

/// Размер тела после base64-кодирования (округление вверх до 4 байт).
int base64EncodedByteLength(int bytes) {
  if (bytes <= 0) return 0;
  return ((bytes + 2) ~/ 3) * 4;
}

/// Бюджет материалов одного фрагмента с полной трассировкой расчёта.
class GenerationBudget {
  const GenerationBudget({
    required this.inputBudget,
    required this.contextWindowTokens,
    required this.fixedOverheadTokens,
    required this.expectedOutputTokens,
    required this.reservedOutputTokens,
    required this.safetyMarginTokens,
    required this.minWorkableInputTokens,
    required this.maxInputTokensLimit,
    required this.maxRequestBytesLimit,
    required this.source,
    required this.trace,
  });

  /// Считает бюджет по формуле D.1.
  ///
  /// [limit] — заказ карточек на фрагмент (0 — заказ ещё не распределён).
  /// [imagePartBytes] — суммарные байты image-частей запроса (до base64).
  factory GenerationBudget.compute({
    required ModelCapabilities capabilities,
    required int limit,
    required int systemPromptTokens,
    required int schemaTokens,
    required int wrapperTokens,
    required int catalogTokens,
    required int imageTokens,
    GenerationBudgetConfig config = const GenerationBudgetConfig(),
    int imagePartBytes = 0,
  }) {
    assert(limit >= 0, 'Заказ карточек не может быть отрицательным');
    assert(
      config.bytesPerTokenBound > 0,
      'Граница байт на токен должна быть > 0',
    );
    final int cards = limit;
    final int systemPrompt = _nonNegative(systemPromptTokens);
    final int schema = _nonNegative(schemaTokens);
    final int wrapper = _nonNegative(wrapperTokens);
    final int catalog = _nonNegative(catalogTokens);
    final int images = _nonNegative(imageTokens);
    final int fixedOverhead =
        systemPrompt + schema + wrapper + catalog + images;

    final int? contextWindow = capabilities.contextWindowTokens;
    final bool contextKnown = contextWindow != null;
    final bool outputCapAssumed = capabilities.maxOutputTokens == null;
    final int outputCap =
        capabilities.maxOutputTokens ??
        (contextKnown
            ? config.defaultOutputCapTokens
            : config.unknownContextOutputCapTokens);
    final int expectedOutput = math.min(
      outputCap,
      cards * config.perCardOutputTokens + config.jsonEnvelopeTokens,
    );
    final int reservedOutput = _nonNegative(expectedOutput);

    final int? safetyMargin = contextKnown
        ? math.max(
            config.minSafetyMarginTokens,
            (contextWindow * config.safetyMarginFraction).round(),
          )
        : null;

    int inputBudget = contextKnown
        ? contextWindow - reservedOutput - fixedOverhead - safetyMargin!
        : config.unknownContextInputTokens;

    final int? maxInputTokens = capabilities.maxInputTokens;
    int? maxInputTokensLimit;
    if (maxInputTokens != null) {
      maxInputTokensLimit = maxInputTokens - fixedOverhead;
      inputBudget = math.min(inputBudget, maxInputTokensLimit);
    }

    final int? maxRequestBytes = capabilities.maxRequestBytes;
    int? maxRequestBytesLimit;
    if (maxRequestBytes != null) {
      maxRequestBytesLimit = maxRequestBytes;
      final int availableBytes =
          maxRequestBytes - base64EncodedByteLength(imagePartBytes);
      final int textTokens = availableBytes <= 0
          ? 0
          : availableBytes ~/ config.bytesPerTokenBound;
      inputBudget = math.min(inputBudget, textTokens);
    }

    final BudgetSource source = contextKnown
        ? BudgetSource.capabilities
        : BudgetSource.assumption;
    final BudgetTrace trace = BudgetTrace(
      formula: contextKnown ? formulaKnownContext : formulaUnknownContext,
      source: source,
      contextWindowTokens: contextWindow,
      contextSource: capabilities.contextSource,
      outputCapTokens: outputCap,
      outputCapAssumed: outputCapAssumed,
      expectedOutputTokens: expectedOutput,
      reservedOutputTokens: reservedOutput,
      fixedOverheadTokens: fixedOverhead,
      systemPromptTokens: systemPrompt,
      schemaTokens: schema,
      wrapperTokens: wrapper,
      catalogTokens: catalog,
      imageTokens: images,
      safetyMarginTokens: safetyMargin,
      minWorkableInputTokens: config.minWorkableInputTokens,
      maxInputTokensLimit: maxInputTokensLimit,
      maxRequestBytesLimit: maxRequestBytesLimit,
      inputBudget: inputBudget,
      unknownFields: capabilities.unknownFields,
    );
    return GenerationBudget(
      inputBudget: inputBudget,
      contextWindowTokens: contextWindow,
      fixedOverheadTokens: fixedOverhead,
      expectedOutputTokens: expectedOutput,
      reservedOutputTokens: reservedOutput,
      safetyMarginTokens: safetyMargin,
      minWorkableInputTokens: config.minWorkableInputTokens,
      maxInputTokensLimit: maxInputTokensLimit,
      maxRequestBytesLimit: maxRequestBytesLimit,
      source: source,
      trace: trace,
    );
  }

  /// Формула расчёта при известном окне (для трассировки/диагностики).
  static const String formulaKnownContext =
      'inputBudget = contextWindow - reservedOutput - fixedOverhead '
      '- safetyMargin';

  /// Формула расчёта при неизвестном окне.
  static const String formulaUnknownContext =
      'inputBudget = unknownContextInputBudget (assumption)';

  /// Бюджет материалов фрагмента; может быть отрицательным (невыполнимый
  /// план), клампинга нет.
  final int inputBudget;

  /// Окно контекста модели; `null` — неизвестно.
  final int? contextWindowTokens;

  /// Фиксированная обвязка запроса (промпт + схема + обёртка + каталог +
  /// изображения), токенов.
  final int fixedOverheadTokens;

  /// Ожидаемый/резервный вывод по заказу карточек, токенов.
  final int expectedOutputTokens;

  /// Резерв вывода (сейчас равен [expectedOutputTokens], см. D.1/G.4).
  final int reservedOutputTokens;

  /// Запас безопасности; `null` — окно неизвестно (запас не применяется).
  final int? safetyMarginTokens;

  /// Минимально рабочий бюджет материалов.
  final int minWorkableInputTokens;

  /// Применённый входной лимит провайдера; `null` — не задан.
  final int? maxInputTokensLimit;

  /// Применённый лимит тела запроса; `null` — не задан.
  final int? maxRequestBytesLimit;

  /// Источник бюджета.
  final BudgetSource source;

  /// Трассировка: слагаемые, источники и неизвестные поля.
  final BudgetTrace trace;

  /// true, если окно контекста известно.
  bool get hasKnownContextWindow => contextWindowTokens != null;

  /// true, если бюджета хватает для минимально осмысленной работы.
  bool get isWorkable => inputBudget >= minWorkableInputTokens;

  /// Сколько токенов не хватает до минимально рабочего бюджета (0 — хватает).
  int get shortfallTokens =>
      isWorkable ? 0 : minWorkableInputTokens - inputBudget;

  /// Неизвестные поля возможностей, повлиявшие на расчёт.
  List<String> get unknownFields => trace.unknownFields;

  @override
  String toString() =>
      'GenerationBudget(input: $inputBudget, context: $contextWindowTokens, '
      'source: ${source.name})';
}

/// Трассировка расчёта бюджета (D.1/D.8): формула, слагаемые, источники.
class BudgetTrace {
  /// Создаёт трассировку.
  const BudgetTrace({
    required this.formula,
    required this.source,
    required this.contextWindowTokens,
    required this.contextSource,
    required this.outputCapTokens,
    required this.outputCapAssumed,
    required this.expectedOutputTokens,
    required this.reservedOutputTokens,
    required this.fixedOverheadTokens,
    required this.systemPromptTokens,
    required this.schemaTokens,
    required this.wrapperTokens,
    required this.catalogTokens,
    required this.imageTokens,
    required this.safetyMarginTokens,
    required this.minWorkableInputTokens,
    required this.maxInputTokensLimit,
    required this.maxRequestBytesLimit,
    required this.inputBudget,
    required this.unknownFields,
  });

  /// Применённая формула.
  final String formula;

  /// Источник бюджета.
  final BudgetSource source;

  /// Окно контекста; `null` — неизвестно.
  final int? contextWindowTokens;

  /// Источник окна контекста.
  final CapabilitySource contextSource;

  /// Лимит вывода, использованный в расчёте.
  final int outputCapTokens;

  /// true, если лимит вывода — допущение, а не данные модели.
  final bool outputCapAssumed;

  /// Ожидаемый вывод.
  final int expectedOutputTokens;

  /// Резерв вывода.
  final int reservedOutputTokens;

  /// Фиксированная обвязка.
  final int fixedOverheadTokens;

  /// Системный промпт.
  final int systemPromptTokens;

  /// Схема ответа.
  final int schemaTokens;

  /// Обёртка пользовательского сообщения.
  final int wrapperTokens;

  /// Каталог `<images>` и подписи image-частей.
  final int catalogTokens;

  /// Оценка токенов изображений.
  final int imageTokens;

  /// Запас безопасности; `null` — неприменим (окно неизвестно).
  final int? safetyMarginTokens;

  /// Минимально рабочий бюджет.
  final int minWorkableInputTokens;

  /// Входной лимит провайдера; `null` — не задан.
  final int? maxInputTokensLimit;

  /// Лимит тела запроса; `null` — не задан.
  final int? maxRequestBytesLimit;

  /// Итоговый бюджет материалов.
  final int inputBudget;

  /// Неизвестные поля возможностей.
  final List<String> unknownFields;

  @override
  String toString() =>
      'BudgetTrace($formula, input: $inputBudget, '
      'outputCap: $outputCapTokens${outputCapAssumed ? ' (assumption)' : ''}, '
      'fixed: $fixedOverheadTokens, safety: $safetyMarginTokens)';
}

int _nonNegative(int value) => value < 0 ? 0 : value;
