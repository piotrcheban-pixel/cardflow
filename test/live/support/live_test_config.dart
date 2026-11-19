/// Конфигурация live-тестов генерации (TASK 04, раздел 5).
///
/// Правила, которые заложены в типы и значения по умолчанию:
/// - обычный `flutter test` **не** отправляет платных запросов: live-набор
///   тегирован `live`, а конфигурация по умолчанию выключена (`enabled=false`,
///   `maxRequests=0`);
/// - запуск требует **явного действия**: `CARDFLOW_LIVE_TESTS=1` и бюджет
///   запросов больше нуля;
/// - отсутствие ключа — безопасный skip, а не падение набора;
/// - число запросов ограничено (`CARDFLOW_LIVE_MAX_REQUESTS`), стоимость —
///   тоже (`CARDFLOW_LIVE_MAX_COST_USD`); при неизвестном тарифе запуск
///   блокируется, если явно не разрешён `CARDFLOW_LIVE_ALLOW_UNKNOWN_COST=1`;
/// - каждый HTTP-вызов имеет таймаут (`CARDFLOW_LIVE_TIMEOUT_SEC`).
///
/// Значения ключей здесь только читаются и никогда не печатаются: наружу
/// отдаётся `present/absent`, в отчёты — только имена переменных.
library;

import 'dart:io';

import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Переменная явного разрешения live-тестов (значение `1`/`true`).
const String kLiveTestsVariable = 'CARDFLOW_LIVE_TESTS';

/// Провайдер live-тестов: id пресета каталога (`deepseek`, `openai`, …).
const String kLiveProviderVariable = 'CARDFLOW_LIVE_PROVIDER';

/// Модель live-тестов; пусто — модель провайдера по умолчанию из каталога.
const String kLiveModelVariable = 'CARDFLOW_LIVE_MODEL';

/// Базовый адрес (переопределение; по умолчанию — адрес пресета).
const String kLiveBaseUrlVariable = 'CARDFLOW_LIVE_BASE_URL';

/// Жёсткий лимит **логических** запросов к провайдеру за прогон.
const String kLiveMaxRequestsVariable = 'CARDFLOW_LIVE_MAX_REQUESTS';

/// Лимит предварительной стоимости в USD (0 — платный прогон запрещён).
const String kLiveMaxCostVariable = 'CARDFLOW_LIVE_MAX_COST_USD';

/// Разрешение прогона при неизвестном тарифе (по умолчанию нельзя).
const String kLiveAllowUnknownCostVariable = 'CARDFLOW_LIVE_ALLOW_UNKNOWN_COST';

/// Таймаут одного HTTP-запроса, секунды.
const String kLiveTimeoutVariable = 'CARDFLOW_LIVE_TIMEOUT_SEC';

/// Сценарий «несколько карточек prompt-only» (Test B).
const String kLiveEnablePromptOnlyVariable = 'CARDFLOW_LIVE_ENABLE_PROMPT_ONLY';

/// Сценарий «текстовый документ» (Tests C/D).
const String kLiveEnableMaterialsVariable = 'CARDFLOW_LIVE_ENABLE_MATERIALS';

/// Сценарий «изображения/Vision» (Test E).
const String kLiveEnableImagesVariable = 'CARDFLOW_LIVE_ENABLE_IMAGES';

/// Сценарий «восстановление после ошибки» (Test F).
const String kLiveEnableRecoveryVariable = 'CARDFLOW_LIVE_ENABLE_RECOVERY';

/// Явное включение Vision для пользовательской модели (каталог может врать).
const String kLiveVisionVariable = 'CARDFLOW_LIVE_VISION';

/// Файл отчёта прогона (JSON Lines); по умолчанию — под `build/`.
const String kLiveReportVariable = 'CARDFLOW_LIVE_REPORT';

/// Переменные окружения с ключами по id пресета.
///
/// Ollama/LM Studio локальные и ключа не требуют: их нет в таблице.
const Map<String, String> kLiveApiKeyVariables = <String, String>{
  'deepseek': 'DEEPSEEK_API_KEY',
  'openai': 'OPENAI_API_KEY',
  'anthropic': 'ANTHROPIC_API_KEY',
  'gemini': 'GEMINI_API_KEY',
  'openrouter': 'OPENROUTER_API_KEY',
  'moonshot': 'MOONSHOT_API_KEY',
  'minimax': 'MINIMAX_API_KEY',
  'groq': 'GROQ_API_KEY',
};

/// Провайдерские переопределения адреса (историческое имя `DEEPSEEK_BASE_URL`).
const Map<String, String> kLiveBaseUrlVariables = <String, String>{
  'deepseek': 'DEEPSEEK_BASE_URL',
  'openai': 'OPENAI_BASE_URL',
  'anthropic': 'ANTHROPIC_BASE_URL',
  'gemini': 'GEMINI_BASE_URL',
};

/// Провайдерские переопределения модели (историческое имя `DEEPSEEK_MODEL`).
const Map<String, String> kLiveModelVariables = <String, String>{
  'deepseek': 'DEEPSEEK_MODEL',
  'openai': 'OPENAI_MODEL',
  'anthropic': 'ANTHROPIC_MODEL',
  'gemini': 'GEMINI_MODEL',
};

/// Сценарии, каждый включается отдельным флагом (по умолчанию все выключены).
enum LiveScenario {
  /// Test A: короткий prompt-only.
  promptOnly(kLiveEnablePromptOnlyVariable),

  /// Test B: prompt-only с несколькими запросами (20 карточек).
  promptOnlyMany(kLiveEnablePromptOnlyVariable),

  /// Test C: небольшой текстовый документ.
  smallDocument(kLiveEnableMaterialsVariable),

  /// Test D: большой документ (адаптивное дробление).
  bigDocument(kLiveEnableMaterialsVariable),

  /// Test E: PDF с изображением / Vision.
  images(kLiveEnableImagesVariable),

  /// Test F: восстановление после ошибки (симуляция, не платный запрос).
  recovery(kLiveEnableRecoveryVariable);

  const LiveScenario(this.variable);

  /// Переменная окружения, включающая сценарий.
  final String variable;
}

/// Конфигурация live-прогона.
///
/// Неизменяемая; собирается из окружения один раз на файл теста. Значения по
/// умолчанию исключают любой запрос: `enabled=false`, `maxRequests=0`,
/// `maxEstimatedCostUsd=0`.
class LiveTestConfig {
  /// Создаёт конфигурацию (используется тестами напрямую).
  const LiveTestConfig({
    this.enabled = false,
    this.provider = 'deepseek',
    this.model = '',
    this.baseUrl = '',
    this.maxRequests = 0,
    this.maxEstimatedCostUsd = 0,
    this.allowUnknownCost = false,
    this.timeout = const Duration(seconds: 120),
    this.enablePromptOnly = false,
    this.enableMaterials = false,
    this.enableImages = false,
    this.enableRecovery = false,
    this.vision = false,
    this.reportPath = 'build/live/live-runs.jsonl',
    this.environment = const <String, String>{},
  });

  /// Полностью выключенная конфигурация (значение по умолчанию).
  const LiveTestConfig.disabled()
    : enabled = false,
      provider = 'deepseek',
      model = '',
      baseUrl = '',
      maxRequests = 0,
      maxEstimatedCostUsd = 0,
      allowUnknownCost = false,
      timeout = const Duration(seconds: 120),
      enablePromptOnly = false,
      enableMaterials = false,
      enableImages = false,
      enableRecovery = false,
      vision = false,
      reportPath = 'build/live/live-runs.jsonl',
      environment = const <String, String>{};

  /// Собирает конфигурацию из окружения процесса.
  factory LiveTestConfig.fromEnvironment([Map<String, String>? environment]) {
    final Map<String, String> env =
        environment ?? _platformEnvironmentOrEmpty();
    final String provider = _value(env, kLiveProviderVariable).isNotEmpty
        ? _value(env, kLiveProviderVariable)
        : 'deepseek';
    final ProviderPreset? preset = providerPresetById(provider);
    final String modelOverride = _value(env, kLiveModelVariable);
    final String providerModel = _value(
      env,
      kLiveModelVariables[provider] ?? '',
    );
    final String model = modelOverride.isNotEmpty
        ? modelOverride
        : providerModel.isNotEmpty
        ? providerModel
        : preset?.defaultModel.id ?? '';
    final String baseUrlOverride = _value(env, kLiveBaseUrlVariable);
    final String providerBaseUrl = _value(
      env,
      kLiveBaseUrlVariables[provider] ?? '',
    );
    final String baseUrl = baseUrlOverride.isNotEmpty
        ? baseUrlOverride
        : providerBaseUrl.isNotEmpty
        ? providerBaseUrl
        : preset?.baseUrl ?? '';
    final ProviderPresetModel? presetModel = preset?.modelById(model);
    final String report = _value(env, kLiveReportVariable);
    return LiveTestConfig(
      enabled: _flag(env, kLiveTestsVariable),
      provider: provider,
      model: model,
      baseUrl: baseUrl,
      maxRequests: _positiveInt(env, kLiveMaxRequestsVariable),
      maxEstimatedCostUsd: _nonNegativeDouble(env, kLiveMaxCostVariable),
      allowUnknownCost: _flag(env, kLiveAllowUnknownCostVariable),
      timeout: Duration(
        seconds: _positiveInt(env, kLiveTimeoutVariable, fallback: 120),
      ),
      enablePromptOnly: _flag(env, kLiveEnablePromptOnlyVariable),
      enableMaterials: _flag(env, kLiveEnableMaterialsVariable),
      enableImages: _flag(env, kLiveEnableImagesVariable),
      enableRecovery: _flag(env, kLiveEnableRecoveryVariable),
      vision:
          _flag(env, kLiveVisionVariable) ||
          (presetModel?.supportsVision ?? false),
      reportPath: report.isNotEmpty ? report : 'build/live/live-runs.jsonl',
      environment: env,
    );
  }

  /// Окружение, из которого собрана конфигурация (без значений ключей в логах).
  final Map<String, String> environment;

  /// Явное разрешение live-тестов (`CARDFLOW_LIVE_TESTS`).
  final bool enabled;

  /// id пресета каталога.
  final String provider;

  /// Идентификатор модели.
  final String model;

  /// Базовый адрес (пресет или переопределение).
  final String baseUrl;

  /// Лимит логических запросов; `0` — запросы запрещены.
  final int maxRequests;

  /// Лимит предварительной стоимости в USD; `0` — платный прогон запрещён.
  final double maxEstimatedCostUsd;

  /// Явное разрешение прогона при неизвестном тарифе.
  final bool allowUnknownCost;

  /// Таймаут одного HTTP-запроса.
  final Duration timeout;

  /// Включён ли сценарий prompt-only.
  final bool enablePromptOnly;

  /// Включены ли сценарии с документами.
  final bool enableMaterials;

  /// Включён ли сценарий с изображениями (Test E).
  final bool enableImages;

  /// Включён ли сценарий восстановления (Test F).
  final bool enableRecovery;

  /// Считается ли модель видящей изображения (явный флаг или каталог).
  final bool vision;

  /// Путь файла отчёта (JSON Lines).
  final String reportPath;

  /// Пресет каталога (может быть `null` для неизвестного id).
  ProviderPreset? get preset => providerPresetById(provider);

  /// Имя переменной окружения с ключом провайдера; `null` — ключ не нужен.
  String? get apiKeyVariable => kLiveApiKeyVariables[provider];

  /// Нужен ли ключ провайдеру.
  bool get requiresApiKey => preset?.requiresApiKey ?? true;

  /// Ключ провайдера (только из окружения; значение не логируется).
  String? get apiKey {
    final String? variable = apiKeyVariable;
    if (variable == null) return null;
    final String value = _value(environment, variable);
    return value.isEmpty ? null : value;
  }

  /// Ключ присутствует (без раскрытия значения).
  bool get hasApiKey => apiKey != null;

  /// Аккаунт провайдера для пайплайна.
  ///
  /// Модель берётся из конфигурации **как есть** (каталог может не знать новую
  /// модель): подстановки «модели по умолчанию» нет — иначе live-тест молча
  /// проверял бы другую модель.
  ProviderAccount get account {
    final ProviderPreset? current = preset;
    final ProviderPresetModel? presetModel = current?.modelById(model);
    final int contextTokens =
        presetModel?.contextTokens ?? kCustomProviderContextTokens;
    return ProviderAccount(
      id: current?.id ?? provider,
      label: current?.label ?? provider,
      presetId: current?.id,
      protocol: current?.protocol ?? ProviderProtocol.openaiCompletions,
      baseUrl: baseUrl,
      modelId: model,
      contextTokens: contextTokens,
      requiresApiKey: requiresApiKey,
      supportsVision: vision,
    );
  }

  /// Причина пропуска всего live-набора; `null` — можно запускать.
  String? get skipReason {
    if (!enabled) {
      return 'Live-тесты выключены: задайте $kLiveTestsVariable=1 '
          '(обычный flutter test не тратит деньги)';
    }
    if (maxRequests <= 0) {
      return 'Бюджет запросов не задан: $kLiveMaxRequestsVariable '
          '(по умолчанию 0 — запросы запрещены)';
    }
    if (preset == null) {
      return 'Неизвестный провайдер «$provider»: нет пресета каталога';
    }
    if (model.trim().isEmpty) {
      return 'Модель не задана: $kLiveModelVariable';
    }
    if (requiresApiKey && !hasApiKey) {
      final String variable = apiKeyVariable ?? 'API_KEY';
      return 'Нет ключа $variable — live-тест пропущен (безопасно)';
    }
    return null;
  }

  /// Причина пропуска сценария (флаг сценария) или `null`.
  String? scenarioSkipReason(LiveScenario scenario) {
    final bool flag = switch (scenario) {
      LiveScenario.promptOnly ||
      LiveScenario.promptOnlyMany => enablePromptOnly,
      LiveScenario.smallDocument || LiveScenario.bigDocument => enableMaterials,
      LiveScenario.images => enableImages,
      LiveScenario.recovery => enableRecovery,
    };
    if (flag) return null;
    return 'Сценарий ${scenario.name} выключен: ${scenario.variable}=1';
  }

  /// Копия с заменёнными полями (для тестов инфраструктуры).
  LiveTestConfig copyWith({
    bool? enabled,
    String? provider,
    String? model,
    String? baseUrl,
    int? maxRequests,
    double? maxEstimatedCostUsd,
    bool? allowUnknownCost,
    Duration? timeout,
    bool? enablePromptOnly,
    bool? enableMaterials,
    bool? enableImages,
    bool? enableRecovery,
    bool? vision,
    String? reportPath,
    Map<String, String>? environment,
  }) {
    return LiveTestConfig(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      maxRequests: maxRequests ?? this.maxRequests,
      maxEstimatedCostUsd: maxEstimatedCostUsd ?? this.maxEstimatedCostUsd,
      allowUnknownCost: allowUnknownCost ?? this.allowUnknownCost,
      timeout: timeout ?? this.timeout,
      enablePromptOnly: enablePromptOnly ?? this.enablePromptOnly,
      enableMaterials: enableMaterials ?? this.enableMaterials,
      enableImages: enableImages ?? this.enableImages,
      enableRecovery: enableRecovery ?? this.enableRecovery,
      vision: vision ?? this.vision,
      reportPath: reportPath ?? this.reportPath,
      environment: environment ?? this.environment,
    );
  }

  /// Краткая безопасная сводка (без ключей и тел).
  @override
  String toString() =>
      'LiveTestConfig(provider: $provider, model: $model, '
      'enabled: $enabled, maxRequests: $maxRequests, '
      'maxCost: $maxEstimatedCostUsd USD, key: ${hasApiKey ? 'present' : 'absent'})';

  static String _value(Map<String, String> env, String name) {
    if (name.isEmpty) return '';
    return (env[name] ?? '').trim();
  }

  static bool _flag(Map<String, String> env, String name) {
    final String value = _value(env, name).toLowerCase();
    return value == '1' || value == 'true' || value == 'yes' || value == 'on';
  }

  static int _positiveInt(
    Map<String, String> env,
    String name, {
    int fallback = 0,
  }) {
    final int? parsed = int.tryParse(_value(env, name));
    if (parsed == null || parsed < 0) return fallback;
    return parsed;
  }

  static double _nonNegativeDouble(Map<String, String> env, String name) {
    final String raw = _value(env, name).replaceAll(',', '.');
    final double? parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0 || !parsed.isFinite) return 0;
    return parsed;
  }
}

/// Быстрый конструктор «запускаем, ключ есть» для unit-тестов инфраструктуры.
LiveTestConfig liveConfigForTests({
  String provider = 'deepseek',
  String model = 'deepseek-flash',
  int maxRequests = 3,
  double maxEstimatedCostUsd = 0.05,
  bool allowUnknownCost = false,
  Map<String, String>? environment,
}) {
  return LiveTestConfig(
    enabled: true,
    provider: provider,
    model: model,
    maxRequests: maxRequests,
    maxEstimatedCostUsd: maxEstimatedCostUsd,
    allowUnknownCost: allowUnknownCost,
    environment: environment ?? const <String, String>{},
  );
}

/// Причина пропуска, если live-прогон не разрешён явно (`null` — разрешён).
///
/// Общий gate для всех файлов `test/live`: без `CARDFLOW_LIVE_TESTS=1` ни
/// платные, ни сетевые live-проверки не запускаются даже при включённом теге.
String? liveOptInSkipReason([Map<String, String>? environment]) {
  final Map<String, String> env = environment ?? _platformEnvironmentOrEmpty();
  if (!_envFlag(env, kLiveTestsVariable)) {
    return 'Live-тесты выключены: задайте $kLiveTestsVariable=1 '
        '(обычный flutter test не тратит деньги)';
  }
  return null;
}

/// Флаг окружения (`1`/`true`/`yes`/`on`); отсутствие — `false`.
bool _envFlag(Map<String, String> env, String name) {
  final String value = (env[name] ?? '').trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'yes' || value == 'on';
}

/// Причина пропуска для «подробных» live-тестов (проверки конкретных
/// контрактов: fallback-лестница, картинки, PDF-сканы).
///
/// Они не считают бюджет запросов внутри себя (это делает управляемый набор
/// `adaptive_generation_live_test.dart`), поэтому требуют явного разрешения и
/// ключа, но не бюджета: запускать их следует по одному файлу.
String? liveDetailedTestsSkipReason({
  required String? apiKey,
  required String keyVariable,
  Map<String, String>? environment,
}) {
  final String? optIn = liveOptInSkipReason(environment);
  if (optIn != null) return optIn;
  if (apiKey == null || apiKey.isEmpty) {
    return 'Нет $keyVariable — live-тест пропущен (безопасно)';
  }
  return null;
}

Map<String, String> _platformEnvironmentOrEmpty() {
  try {
    return Platform.environment;
  } on Object {
    // Веб/ограниченное окружение: переменные недоступны — live-тесты
    // остаются выключенными.
    return const <String, String>{};
  }
}
