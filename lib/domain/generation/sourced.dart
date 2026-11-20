/// Значение характеристики модели вместе с происхождением (ADR-039).
///
/// Правило: у каждого числа есть источник и, где применимо, дата и ссылка.
/// «Неизвестно» — `null`, а не 0 и не «типовое» число семейства моделей.
/// Домен не зависит от Flutter.
library;

/// Источник значения характеристики модели.
///
/// Приоритет при слиянии (ADR-039 §2): `userConfigured` → `providerApi` →
/// `officialCatalog` → `assumption` → `unknown`.
enum CapabilitySource {
  /// Значение введено пользователем в настройках модели.
  userConfigured(4, 'user_configured'),

  /// Значение получено от API провайдера (discovery).
  providerApi(3, 'provider_api'),

  /// Значение из официального каталога/документации приложения.
  officialCatalog(2, 'official_catalog'),

  /// Консервативное допущение приложения (не характеристика провайдера).
  assumption(1, 'assumption'),

  /// Подтверждённого значения нет.
  unknown(0, 'unknown');

  const CapabilitySource(this.priority, this.wireName);

  /// Приоритет при слиянии: больше — важнее.
  final int priority;

  /// Имя в JSON (`capabilities_source`, кэш характеристик).
  final String wireName;

  /// true, если источник известен (не [CapabilitySource.unknown]).
  bool get isKnown => this != CapabilitySource.unknown;

  /// Разбирает источник из JSON; неизвестная/битая строка — `unknown`.
  ///
  /// Читает и прежние wire-значения (ADR-039 §5): `user` → `userConfigured`,
  /// `preset`/`verified` → `officialCatalog`, `inferred` → `assumption`.
  static CapabilitySource fromWire(Object? value) {
    if (value is String) {
      for (final CapabilitySource source in values) {
        if (source.wireName == value) return source;
      }
      switch (value) {
        case 'user':
          return CapabilitySource.userConfigured;
        case 'preset':
        case 'verified':
          return CapabilitySource.officialCatalog;
        case 'inferred':
          return CapabilitySource.assumption;
      }
    }
    return CapabilitySource.unknown;
  }
}

/// Семантика окна контекста модели.
enum ContextSemantics {
  /// Окно — сумма входа и выхода (DeepSeek, OpenAI-compatible, OpenRouter).
  totalInputPlusOutput,

  /// Окно — только вход; выход ограничен отдельно (Anthropic, Gemini).
  inputOnly,

  /// Семантика неизвестна — планировать консервативно (как total).
  unknown,
}

/// Значение [value] с источником [source], датой наблюдения и ссылкой.
///
/// [observedAt] обязателен для `providerApi`/`userConfigured` по смыслу, но
/// конструктор его не требует: старые записи могут не иметь даты.
/// [sourceRef] — URL/имя эндпоинта **без query-параметров** (в query бывают
/// ключи).
final class Sourced<T> {
  /// Создаёт значение с источником.
  const Sourced(
    this.value, {
    required this.source,
    this.observedAt,
    this.sourceRef,
  }) : assert(
         source != CapabilitySource.providerApi ||
             sourceRef != null ||
             value == null,
         'Значение из API обязано иметь ссылку на источник',
       );

  /// Значение неизвестно.
  const Sourced.absent({this.sourceRef})
    : value = null,
      source = CapabilitySource.unknown,
      observedAt = null;

  /// Значение или `null`.
  final T? value;

  /// Источник значения.
  final CapabilitySource source;

  /// Когда значение получено/задано.
  final DateTime? observedAt;

  /// Ссылка на источник без query-параметров.
  final String? sourceRef;

  /// true, если значение известно (в том числе `false` и `0`).
  bool get isKnown => value != null && source != CapabilitySource.unknown;

  /// true, если значение — допущение приложения.
  bool get isAssumption => isKnown && source == CapabilitySource.assumption;

  /// Копия с другим значением/источником.
  Sourced<T> copyWith({
    T? value,
    CapabilitySource? source,
    DateTime? observedAt,
    String? sourceRef,
  }) => Sourced<T>(
    value ?? this.value,
    source: source ?? this.source,
    observedAt: observedAt ?? this.observedAt,
    sourceRef: sourceRef ?? this.sourceRef,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Sourced<T> &&
          other.value == value &&
          other.source == source &&
          other.observedAt == observedAt &&
          other.sourceRef == sourceRef;

  @override
  int get hashCode => Object.hash(value, source, observedAt, sourceRef);

  @override
  String toString() =>
      'Sourced(${value ?? 'unknown'}, ${source.wireName}'
      '${observedAt == null ? '' : ', $observedAt'})';
}
