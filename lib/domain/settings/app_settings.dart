/// Пользовательские настройки приложения CardFlow (SPEC A6.6, ADR-019).
///
/// Домен без Flutter и БД: [toJson]/[fromJson] — контракт значения
/// `app_settings.value_json` с ключом `app.settings`; числовые поля
/// нормализуются в допустимые диапазоны, неверные типы отвергаются.
library;

/// Тема приложения (A6.6, «Внешний вид»).
enum AppThemePreference {
  /// Следовать системной теме.
  system('system'),

  /// Светлая тема.
  light('light'),

  /// Тёмная тема.
  dark('dark');

  const AppThemePreference(this.wireName);

  /// Значение для JSON.
  final String wireName;

  /// Разбирает тему; неизвестная — [FormatException].
  static AppThemePreference fromWire(String value) {
    for (final AppThemePreference preference in values) {
      if (preference.wireName == value) return preference;
    }
    throw FormatException('Неизвестная тема: $value');
  }
}

/// Профиль анимации (A6.6, «Выразительная / Стандартная»).
enum MotionPreference {
  /// Выразительная пружина M3E и пульс Stories.
  expressive('expressive'),

  /// Стандартная пружина без пульса.
  standard('standard');

  const MotionPreference(this.wireName);

  /// Значение для JSON.
  final String wireName;

  /// Разбирает профиль; неизвестный — [FormatException].
  static MotionPreference fromWire(String value) {
    for (final MotionPreference preference in values) {
      if (preference.wireName == value) return preference;
    }
    throw FormatException('Неизвестный профиль анимации: $value');
  }
}

/// Снимок настроек приложения (A6.6, ADR-019).
class AppSettings {
  /// Создаёт настройки (значения по умолчанию — аргументы конструктора).
  const AppSettings({
    this.theme = AppThemePreference.system,
    this.dynamicColor = false,
    this.motion = MotionPreference.expressive,
    this.dyslexiaFont = false,
    this.textScale = 1,
    this.highContrast = false,
    this.haptics = true,
    this.desiredRetention = 0.9,
    this.learningSteps = defaultLearningSteps,
    this.dailyNewLimit = 20,
    this.dailyReviewLimit = 200,
    this.generationPipelineV3 = false,
  });

  /// Версия контракта JSON.
  static const int version = 1;

  /// Значения по умолчанию (SPEC молчит — ADR-019 §1).
  static const AppSettings defaults = AppSettings();

  /// Шаги обучения по умолчанию (ADR-004).
  static const List<Duration> defaultLearningSteps = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 10),
  ];

  /// Допустимый масштаб текста.
  static const double minTextScale = 0.8;

  /// Верхняя граница масштаба текста.
  static const double maxTextScale = 1.4;

  /// Нижняя граница желаемого удержания.
  static const double minRetention = 0.7;

  /// Верхняя граница желаемого удержания.
  static const double maxRetention = 0.95;

  /// Минимальная длительность шага обучения.
  static const int minLearningStepMinutes = 1;

  /// Максимальная длительность шага обучения.
  static const int maxLearningStepMinutes = 60;

  /// Максимум шагов обучения.
  static const int maxLearningSteps = 5;

  /// Максимум дневного лимита (0 — без лимита).
  static const int maxDailyLimit = 999;

  /// Тема.
  final AppThemePreference theme;

  /// Динамические цвета (A4.1, L6c).
  final bool dynamicColor;

  /// Профиль анимации.
  final MotionPreference motion;

  /// Шрифт для дислексии.
  final bool dyslexiaFont;

  /// Масштаб текста.
  final double textScale;

  /// Повышенный контраст.
  final bool highContrast;

  /// Тактильная отдача.
  final bool haptics;

  /// Желаемое удержание FSRS.
  final double desiredRetention;

  /// Шаги обучения FSRS (1–5, 1–60 мин).
  final List<Duration> learningSteps;

  /// Дневной лимит новых карточек (0 — без лимита).
  final int dailyNewLimit;

  /// Дневной лимит повторных карточек (0 — без лимита).
  final int dailyReviewLimit;

  /// Путь генерации v3 (TASK «Срез 9», ADR-050): этапы, вердикт по журналу,
  /// пометки дублей вместо удаления и метрики прогона.
  ///
  /// Срез 15 (часть 0): флаг снова **выключен по умолчанию**. Критерий среза 14
  /// был выведен из агрегата `coverage`, а не измерен пер-юнитными данными
  /// (L230), поэтому решение не считается доказанным; включение — только после
  /// честного замера `journal/generation-v3/verify-s15.md`. Старый путь
  /// остаётся доступным и не удалён.
  final bool generationPipelineV3;

  /// Сериализация в `app_settings.value_json`.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'theme': theme.wireName,
    'dynamic_color': dynamicColor,
    'motion': motion.wireName,
    'dyslexia_font': dyslexiaFont,
    'text_scale': textScale,
    'high_contrast': highContrast,
    'haptics': haptics,
    'desired_retention': desiredRetention,
    'learning_steps_minutes': <int>[
      for (final Duration step in learningSteps) step.inMinutes,
    ],
    'daily_new_limit': dailyNewLimit,
    'daily_review_limit': dailyReviewLimit,
    'generation_pipeline_v3': generationPipelineV3,
  };

  /// Разбирает JSON; неизвестные ключи игнорируются (ADR-019 §1).
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final Object? version = json['version'];
    if (version != AppSettings.version) {
      throw FormatException('Неизвестная версия настроек: $version');
    }
    return AppSettings(
      theme: _theme(json['theme']),
      dynamicColor: _bool(
        json['dynamic_color'],
        AppSettings.defaults.dynamicColor,
      ),
      motion: _motion(json['motion']),
      dyslexiaFont: _bool(
        json['dyslexia_font'],
        AppSettings.defaults.dyslexiaFont,
      ),
      textScale: _double(
        json['text_scale'],
        AppSettings.defaults.textScale,
        minTextScale,
        maxTextScale,
      ),
      highContrast: _bool(
        json['high_contrast'],
        AppSettings.defaults.highContrast,
      ),
      haptics: _bool(json['haptics'], AppSettings.defaults.haptics),
      desiredRetention: _double(
        json['desired_retention'],
        AppSettings.defaults.desiredRetention,
        minRetention,
        maxRetention,
      ),
      learningSteps: _learningSteps(json['learning_steps_minutes']),
      dailyNewLimit: _int(
        json['daily_new_limit'],
        AppSettings.defaults.dailyNewLimit,
        0,
        maxDailyLimit,
      ),
      dailyReviewLimit: _int(
        json['daily_review_limit'],
        AppSettings.defaults.dailyReviewLimit,
        0,
        maxDailyLimit,
      ),
      generationPipelineV3: _bool(
        json['generation_pipeline_v3'],
        AppSettings.defaults.generationPipelineV3,
      ),
    );
  }

  /// Копия с заменой полей.
  AppSettings copyWith({
    AppThemePreference? theme,
    bool? dynamicColor,
    MotionPreference? motion,
    bool? dyslexiaFont,
    double? textScale,
    bool? highContrast,
    bool? haptics,
    double? desiredRetention,
    List<Duration>? learningSteps,
    int? dailyNewLimit,
    int? dailyReviewLimit,
    bool? generationPipelineV3,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      motion: motion ?? this.motion,
      dyslexiaFont: dyslexiaFont ?? this.dyslexiaFont,
      textScale: _clampDouble(
        textScale ?? this.textScale,
        minTextScale,
        maxTextScale,
      ),
      highContrast: highContrast ?? this.highContrast,
      haptics: haptics ?? this.haptics,
      desiredRetention: _clampDouble(
        desiredRetention ?? this.desiredRetention,
        minRetention,
        maxRetention,
      ),
      learningSteps: learningSteps == null
          ? this.learningSteps
          : _normalizeSteps(learningSteps),
      dailyNewLimit: _clampInt(
        dailyNewLimit ?? this.dailyNewLimit,
        0,
        maxDailyLimit,
      ),
      dailyReviewLimit: _clampInt(
        dailyReviewLimit ?? this.dailyReviewLimit,
        0,
        maxDailyLimit,
      ),
      generationPipelineV3: generationPipelineV3 ?? this.generationPipelineV3,
    );
  }

  static AppThemePreference _theme(Object? value) {
    if (value == null) return AppThemePreference.system;
    if (value is! String) {
      throw FormatException('Тема должна быть строкой: $value');
    }
    return AppThemePreference.fromWire(value);
  }

  static MotionPreference _motion(Object? value) {
    if (value == null) return MotionPreference.expressive;
    if (value is! String) {
      throw FormatException('Профиль анимации должен быть строкой: $value');
    }
    return MotionPreference.fromWire(value);
  }

  static bool _bool(Object? value, bool fallback) {
    if (value == null) return fallback;
    if (value is! bool) throw FormatException('Ожидался bool: $value');
    return value;
  }

  static double _double(
    Object? value,
    double fallback,
    double min,
    double max,
  ) {
    if (value == null) return fallback;
    if (value is! num) throw FormatException('Ожидалось число: $value');
    return _clampDouble(value.toDouble(), min, max);
  }

  static int _int(Object? value, int fallback, int min, int max) {
    if (value == null) return fallback;
    if (value is! num) throw FormatException('Ожидалось число: $value');
    return _clampInt(value.toInt(), min, max);
  }

  static double _clampDouble(double value, double min, double max) =>
      value < min ? min : (value > max ? max : value);

  static int _clampInt(int value, int min, int max) =>
      value < min ? min : (value > max ? max : value);

  static List<Duration> _learningSteps(Object? value) {
    if (value == null) return defaultLearningSteps;
    if (value is! List) {
      throw FormatException('Шаги обучения должны быть списком: $value');
    }
    final List<Duration> steps = <Duration>[];
    for (final Object? item in value) {
      if (item is! num) {
        throw FormatException('Шаг обучения должен быть числом: $item');
      }
      steps.add(
        Duration(
          minutes: _clampInt(
            item.toInt(),
            minLearningStepMinutes,
            maxLearningStepMinutes,
          ),
        ),
      );
    }
    return _normalizeSteps(steps);
  }

  /// Сортирует шаги, убирает дубликаты, ограничивает количество; пусто —
  /// значения по умолчанию.
  static List<Duration> _normalizeSteps(List<Duration> source) {
    if (source.isEmpty) return defaultLearningSteps;
    final List<Duration> steps = <Duration>[];
    for (final Duration step in source) {
      final Duration normalized = Duration(
        minutes: _clampInt(
          step.inMinutes,
          minLearningStepMinutes,
          maxLearningStepMinutes,
        ),
      );
      if (!steps.contains(normalized)) steps.add(normalized);
    }
    steps.sort((Duration a, Duration b) => a.compareTo(b));
    if (steps.length > maxLearningSteps) {
      return List<Duration>.unmodifiable(steps.take(maxLearningSteps));
    }
    return List<Duration>.unmodifiable(steps);
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.dynamicColor == dynamicColor &&
      other.motion == motion &&
      other.dyslexiaFont == dyslexiaFont &&
      other.textScale == textScale &&
      other.highContrast == highContrast &&
      other.haptics == haptics &&
      other.desiredRetention == desiredRetention &&
      _stepsEqual(other.learningSteps) &&
      other.dailyNewLimit == dailyNewLimit &&
      other.dailyReviewLimit == dailyReviewLimit &&
      other.generationPipelineV3 == generationPipelineV3;

  bool _stepsEqual(List<Duration> other) {
    if (other.length != learningSteps.length) return false;
    for (int index = 0; index < other.length; index++) {
      if (other[index] != learningSteps[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    theme,
    dynamicColor,
    motion,
    dyslexiaFont,
    textScale,
    highContrast,
    haptics,
    desiredRetention,
    Object.hashAll(learningSteps),
    dailyNewLimit,
    dailyReviewLimit,
    generationPipelineV3,
  );

  @override
  String toString() =>
      'AppSettings(theme: ${theme.wireName}, motion: ${motion.wireName}, '
      'textScale: $textScale, retention: $desiredRetention, '
      'steps: ${learningSteps.length}, newLimit: $dailyNewLimit, '
      'reviewLimit: $dailyReviewLimit)';
}
