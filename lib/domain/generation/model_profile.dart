/// Профиль модели — статические данные для планирования и упаковки батчей
/// (TASK «Срез 4», ADR-050: этап Allocation).
///
/// В логике распределения и упаковки нет магических чисел: окно контекста,
/// предел вывода, поддержка JSON-схемы и изображений, параллельность берутся
/// из профиля. Домен не зависит от Flutter, сети и БД.
library;

/// Одна карточка профиля: модель, её окно, предел вывода и возможности.
///
/// Значения окна и Vision согласованы с каталогом пресетов
/// (`kProviderPresets`, ADR-020) — пресет отвечает за выбор модели в UI,
/// профиль — за контракт планирования; согласованность держит тест
/// `model_profile_test.dart`.
final class ModelProfile {
  /// Создаёт профиль; противоречивые значения — ошибка программиста.
  const ModelProfile({
    required this.id,
    required this.provider,
    required this.contextWindow,
    required this.maxOutputTokens,
    required this.supportsJsonSchema,
    required this.supportsVision,
    required this.concurrency,
  }) : assert(id != '', 'У профиля обязан быть id'),
       assert(provider != '', 'У профиля обязан быть провайдер'),
       assert(contextWindow > 0, 'Окно контекста положительно'),
       assert(maxOutputTokens > 0, 'Предел вывода положителен'),
       assert(
         maxOutputTokens <= contextWindow,
         'Предел вывода не больше окна контекста',
       ),
       assert(concurrency > 0, 'Параллельность положительна'),
       assert(
         batchWindowShare > 0 && batchWindowShare <= 1,
         'Доля окна батча — в пределах (0, 1]',
       );

  /// id модели (совпадает с id в каталоге пресетов провайдера).
  final String id;

  /// Провайдер (`deepseek`, `openai`, `anthropic`, `gemini`, …).
  final String provider;

  /// Окно контекста в токенах.
  final int contextWindow;

  /// Предел вывода одного ответа в токенах.
  final int maxOutputTokens;

  /// Поддерживает ли модель strict JSON-схему ответа.
  final bool supportsJsonSchema;

  /// Принимает ли модель изображения.
  final bool supportsVision;

  /// Сколько запросов одного прогона можно держать в полёте.
  final int concurrency;

  /// Доля окна контекста, доступная одному батчу (TASK: 40 %).
  ///
  /// Оставшиеся 60 % — запас на недооценку токенов, обвязку провайдера и
  /// повторный запрос, а не место для второй партии: батч — единица запроса.
  static const double batchWindowShare = 0.4;

  /// Бюджет токенов одного батча: `contextWindow × batchWindowShare`.
  int get batchTokenBudget => (contextWindow * batchWindowShare).floor();

  /// Максимум карточек в одном батче по пределу вывода профиля.
  ///
  /// [outputTokensPerCard] — оценка вывода одной карточки; неположительная
  /// оценка — ошибка программиста.
  int maxCardsPerBatch(int outputTokensPerCard) {
    if (outputTokensPerCard <= 0) {
      throw ArgumentError.value(
        outputTokensPerCard,
        'outputTokensPerCard',
        'Оценка вывода карточки должна быть положительной',
      );
    }
    return maxOutputTokens ~/ outputTokensPerCard;
  }

  /// Влезает ли батч в профиль: выход ≤ `maxOutputTokens` и
  /// `вход + выход ≤ batchTokenBudget`.
  ///
  /// Оба предела обязательны: окно может быть огромным, а предел вывода —
  /// маленьким (и наоборот), поэтому «40 % окна» само по себе не гарантирует,
  /// что ответ не будет обрезан.
  bool fitsBatch({required int inputTokens, required int outputTokens}) {
    if (inputTokens < 0 || outputTokens < 0) return false;
    if (outputTokens > maxOutputTokens) return false;
    return inputTokens + outputTokens <= batchTokenBudget;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ModelProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ModelProfile($id, $provider, окно $contextWindow, '
      'вывод $maxOutputTokens, concurrency $concurrency)';
}

/// Каталог профилей: данные для 3+ провайдеров (TASK «Срез 4»).
///
/// Пресеты (`kProviderPresets`) описывают модель для UI; профиль добавляет то,
/// что нужно планировщику: предел вывода, поддержку JSON-схемы и
/// параллельность. Независимая копия окна и Vision намеренная — тест
/// сверяет её с пресетами, чтобы расхождение было видно.
const List<ModelProfile> kModelProfiles = <ModelProfile>[
  // DeepSeek. Strict `response_format` с JSON-схемой отвечает 400 (лестница
  // совместимости ADR-021), поэтому схема не поддерживается, а `json_object`
  // и текст разбирает приложение.
  ModelProfile(
    id: 'deepseek-flash',
    provider: 'deepseek',
    contextWindow: 1000000,
    maxOutputTokens: 384000,
    supportsJsonSchema: false,
    supportsVision: true,
    concurrency: 2,
  ),
  ModelProfile(
    id: 'deepseek-v4-pro',
    provider: 'deepseek',
    contextWindow: 1000000,
    maxOutputTokens: 384000,
    supportsJsonSchema: false,
    supportsVision: false,
    concurrency: 2,
  ),
  // OpenAI: strict JSON-схема и Vision есть у обеих моделей каталога.
  ModelProfile(
    id: 'gpt-4o',
    provider: 'openai',
    contextWindow: 128000,
    maxOutputTokens: 16384,
    supportsJsonSchema: true,
    supportsVision: true,
    concurrency: 4,
  ),
  ModelProfile(
    id: 'gpt-4o-mini',
    provider: 'openai',
    contextWindow: 128000,
    maxOutputTokens: 16384,
    supportsJsonSchema: true,
    supportsVision: true,
    concurrency: 4,
  ),
  // Anthropic: структурированный ответ — через tools, `response_format`
  // нет; Vision поддерживается.
  ModelProfile(
    id: 'claude-3-5-sonnet-latest',
    provider: 'anthropic',
    contextWindow: 200000,
    maxOutputTokens: 8192,
    supportsJsonSchema: false,
    supportsVision: true,
    concurrency: 3,
  ),
  ModelProfile(
    id: 'claude-3-5-haiku-latest',
    provider: 'anthropic',
    contextWindow: 200000,
    maxOutputTokens: 8192,
    supportsJsonSchema: false,
    supportsVision: true,
    concurrency: 3,
  ),
  // Gemini: `responseSchema` и Vision поддерживаются.
  ModelProfile(
    id: 'gemini-2.5-flash',
    provider: 'gemini',
    contextWindow: 1048576,
    maxOutputTokens: 65536,
    supportsJsonSchema: true,
    supportsVision: true,
    concurrency: 4,
  ),
  ModelProfile(
    id: 'gemini-2.0-flash',
    provider: 'gemini',
    contextWindow: 1048576,
    maxOutputTokens: 8192,
    supportsJsonSchema: true,
    supportsVision: true,
    concurrency: 4,
  ),
];

/// Профиль по id модели или `null`, если модели нет в каталоге.
ModelProfile? modelProfileById(String id) {
  for (final ModelProfile profile in kModelProfiles) {
    if (profile.id == id) return profile;
  }
  return null;
}

/// Профиль по id модели; для неизвестной — консервативный профиль.
ModelProfile modelProfileOrDefault(String id) =>
    modelProfileById(id) ?? kConservativeModelProfile;

/// Консервативный профиль для модели, которой нет в каталоге: маленькое окно,
/// без схемы и изображений, один запрос за раз.
///
/// Значения — допущение приложения (ADR-039 §5), а не характеристика
/// провайдера: планировщик обязан работать и для пользовательской модели.
const ModelProfile kConservativeModelProfile = ModelProfile(
  id: 'unknown',
  provider: 'unknown',
  contextWindow: 32000,
  maxOutputTokens: 4096,
  supportsJsonSchema: false,
  supportsVision: false,
  concurrency: 1,
);
