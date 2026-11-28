/// Выбор пути генерации — **функция от материала**, а не флаг в настройках
/// (TASK «Срез 17», часть 2, п. 11; ADR-054).
///
/// Мотивация: флаг в настройках перекладывал инженерное решение на
/// пользователя и сравнивал пути на несопоставимых объёмах. Здесь решение
/// выводится правилом «объём материала ≥ N* → v3, иначе legacy», где N*
/// получается из уже оплаченных ячеек (`lib/domain/generation/path_rule.dart`).
///
/// Режим настройки — трёхзначный: [GenerationPathMode.auto] (по правилу),
/// [GenerationPathMode.v3] и [GenerationPathMode.legacy] — ручное
/// переопределение. Пользователь видит выбор, а не скрытый bool.
library;

/// Режим выбора пути из настроек.
enum GenerationPathMode {
  /// По правилу от объёма материала (порог N*).
  auto('auto'),

  /// Ручное переопределение: путь v3.
  v3('v3'),

  /// Ручное переопределение: legacy-путь.
  legacy('legacy');

  const GenerationPathMode(this.wireName);

  /// Wire-код в JSON `app_settings` (обратная совместимость).
  final String wireName;

  /// Разбирает wire-код; неизвестное/отсутствующее — [auto] (ADR-019 §1).
  static GenerationPathMode fromWire(Object? value) {
    for (final GenerationPathMode mode in GenerationPathMode.values) {
      if (mode.wireName == value) return mode;
    }
    return GenerationPathMode.auto;
  }
}

/// Путь исполнения генерации.
enum GenerationPath {
  /// Этапы Understanding → Allocation → Batches → Replenish (ADR-050).
  v3,

  /// Прежний путь пайплайна (совместимый, не удалён).
  legacy;

  /// Wire-код пути (для ключа слепой выборки и отчётов).
  String get wireName => name;
}

/// Порог N*, с которого авто выбирает v3.
///
/// Данные среза 17 (пересчёт `live-s16/cells/*.json`, два материала — 10 и 33
/// единицы) **разрыва не дают**: v3 проигрывает legacy по объёму чистых
/// карточек на обоих объёмах, а по доле дублей — сильнее на большем
/// (`matrix-s17.md`). Поэтому порог не определён (`null`), и авто честно
/// остаётся на legacy — с явной пометкой [GenerationPathDecision.boundaryNotDetermined],
/// а не с выдуманным числом.
///
/// Когда появятся данные с разрывом, значение задаётся здесь (и ADR), а не
/// флагом в настройках: правило уже реализовано и покрыто тестами с порогом.
const int? kGenerationPathV3MinUnits = null;

/// Решение о пути: что выбрано, по какому режиму и при каком объёме.
final class GenerationPathDecision {
  /// Создаёт решение; все поля — из [selectGenerationPath].
  const GenerationPathDecision({
    required this.path,
    required this.mode,
    required this.materialUnits,
    required this.thresholdUnits,
  });

  /// Выбранный путь.
  final GenerationPath path;

  /// Режим из настроек, по которому принято решение.
  final GenerationPathMode mode;

  /// Объём материала в единицах, известный на входе (0 — неизвестен).
  final int materialUnits;

  /// Порог N*, действовавший при решении; `null` — не определён данными.
  final int? thresholdUnits;

  /// true — режим авто, но граница не определена данными: выбор legacy по
  /// консервативному умолчанию, а не потому, что правило доказало паритет.
  bool get boundaryNotDetermined =>
      mode == GenerationPathMode.auto && thresholdUnits == null;

  @override
  String toString() =>
      'GenerationPathDecision(${path.name}, режим ${mode.wireName}, '
      'единиц $materialUnits, порог ${thresholdUnits ?? '—'})';
}

/// Выбирает путь по режиму и порогу.
///
/// [materialUnits] — число единиц материала, известное до первого запроса
/// (на входе v3 карты ещё нет, поэтому 0 = «неизвестен»; при неопределённом
/// пороге значение на решение не влияет — так и должно быть).
/// [thresholdUnits] — параметр для тестов и будущих ADR; по умолчанию —
/// [kGenerationPathV3MinUnits].
GenerationPathDecision selectGenerationPath({
  required GenerationPathMode mode,
  int materialUnits = 0,
  int? thresholdUnits = kGenerationPathV3MinUnits,
}) {
  final GenerationPath path = switch (mode) {
    GenerationPathMode.v3 => GenerationPath.v3,
    GenerationPathMode.legacy => GenerationPath.legacy,
    GenerationPathMode.auto =>
      thresholdUnits != null && materialUnits >= thresholdUnits
          ? GenerationPath.v3
          : GenerationPath.legacy,
  };
  return GenerationPathDecision(
    path: path,
    mode: mode,
    materialUnits: materialUnits,
    thresholdUnits: thresholdUnits,
  );
}
