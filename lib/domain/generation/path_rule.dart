/// Правило выбора пути по числам, замороженным срезом 17 (ADR-054).
///
/// Здесь — **чистые** функции, которыми `tool/recompute_matrix_s17.dart`
/// пересчитывает оплаченные ячейки без единого нового запроса:
///
/// 1. офлайн-исход ячейки в тех же определениях, что [OutcomeCounts]
///    (`cleanRate = clean / unique`, `dupRate = duplicates / unique`,
///    `blockRate = blocked / attempted`, `acceptanceRate = accepted / attempted`);
/// 2. сопоставимость объёма (TASK «Срез 17», п. 3): `absoluteClean` сравнивается
///    только при отношении принятых ≥ [kComparableVolumeThreshold], иначе
///    `volume_mismatch` — ячейка в критерий не идёт;
/// 3. N* — **минимальный** объём материала (в единицах), начиная с которого v3
///    не проигрывает legacy по качеству (`cleanRate`), дублям (`dupRate`) и
///    полноте (`absoluteClean`), причём на всех больших измеренных объёмах тоже.
library;

/// Порог сопоставимости объёма производства (TASK «Срез 17», п. 3): отношение
/// принятых ≥ 0,8 — объёмы сравнимы.
const double kComparableVolumeThreshold = 0.8;

/// Исход ячейки в замороженных определениях (счётчики, не доли).
final class PathOutcome {
  /// Создаёт исход из счётчиков ячейки.
  const PathOutcome({
    required this.attempted,
    required this.accepted,
    required this.unique,
    required this.clean,
    required this.duplicates,
    required this.blocked,
  }) : assert(attempted >= 0, 'Попытки не отрицательны'),
       assert(accepted >= 0, 'Принятое не отрицательно'),
       assert(unique >= 0, 'Уникальные не отрицательны'),
       assert(clean >= 0, 'Чистые не отрицательны'),
       assert(duplicates >= 0, 'Дубли не отрицательны'),
       assert(blocked >= 0, 'Заблокированные не отрицательны');

  /// Все попытки ячейки (`attempted`).
  final int attempted;

  /// Принято в колоду.
  final int accepted;

  /// Принято без пометки дубля.
  final int unique;

  /// Принято без пометок гейта.
  final int clean;

  /// Отложено/отброшено как дубли.
  final int duplicates;

  /// Заблокировано жёстким дефектом.
  final int blocked;

  /// Качество сохранённого: чистые / уникальные; `null` — сохранённых нет.
  double? get cleanRate => unique <= 0 ? null : clean / unique;

  /// Доля дублей от уникальных; `null` — сохранённых нет.
  double? get dupRate => unique <= 0 ? null : duplicates / unique;

  /// Доля блокированных от попыток; `null` — попыток нет.
  double? get blockRate => attempted <= 0 ? null : blocked / attempted;

  /// Доля принятых от попыток; `null` — попыток нет.
  double? get acceptanceRate => attempted <= 0 ? null : accepted / attempted;

  /// Полнота: абсолютное число чистых карточек (TASK «Срез 14», п. 2).
  int get absoluteClean => clean;

  @override
  String toString() =>
      'PathOutcome(попыток $attempted, принято $accepted, уникальных $unique, '
      'чистых $clean, дублей $duplicates)';
}

/// Отношение объёмов производства: меньшее принятое к большему; `null` — оба
/// нулевые (сравнивать нечего).
double? comparableVolumeRatio({
  required int acceptedA,
  required int acceptedB,
}) {
  final int max = acceptedA > acceptedB ? acceptedA : acceptedB;
  if (max <= 0) return null;
  final int min = acceptedA < acceptedB ? acceptedA : acceptedB;
  return min / max;
}

/// Сопоставим ли объём производства двух ячеек (отношение принятых ≥ порога).
bool comparableVolume({
  required int acceptedA,
  required int acceptedB,
  double threshold = kComparableVolumeThreshold,
}) {
  final double? ratio = comparableVolumeRatio(
    acceptedA: acceptedA,
    acceptedB: acceptedB,
  );
  return ratio != null && ratio >= threshold;
}

/// Один измеренный объём материала: сколько единиц и как справились пути.
final class MaterialPathPoint {
  /// Создаёт точку зависимости.
  const MaterialPathPoint({
    required this.units,
    required this.legacy,
    required this.v3,
  });

  /// Число единиц материала (у v3 — единицы карты знаний, срез 15).
  final int units;

  /// Исход legacy-пути на том же материале.
  final PathOutcome legacy;

  /// Исход пути v3 на том же материале.
  final PathOutcome v3;
}

/// Почему порог получился (или не получился).
enum PathThresholdReason {
  /// Найден N*: v3 не проигрывает от него и на всех больших объёмах.
  crossover,

  /// Данные разрыва не дают: v3 не выигрывает ни на одном измеренном объёме.
  noCrossover,

  /// v3 выигрывает на меньшем объёме и проигрывает на большем — правило
  /// «объём ≥ N* → v3» неверно для этих данных.
  notMonotonic,
}

/// Результат вывода порога: N* и причина, по которой он такой.
final class PathThresholdResult {
  /// Создаёт результат.
  const PathThresholdResult({
    required this.thresholdUnits,
    required this.reason,
    required this.winningUnits,
  });

  /// Порог N*; `null` — данные его не дают.
  final int? thresholdUnits;

  /// Причина (машинный код, для отчёта).
  final PathThresholdReason reason;

  /// Объёмы, на которых v3 не проиграл (по возрастанию).
  final List<int> winningUnits;

  /// Короткая пометка для отчёта: «выбор на границе не определён данными».
  bool get boundaryNotDetermined =>
      reason == PathThresholdReason.noCrossover ||
      reason == PathThresholdReason.notMonotonic ||
      thresholdUnits == null;
}

/// Выводит N* из измеренных точек.
///
/// Точка считается выигрышем v3, если выполнены **все** условия:
/// `cleanRate(v3) ≥ cleanRate(legacy)`, `dupRate(v3) ≤ dupRate(legacy)`,
/// `absoluteClean(v3) ≥ absoluteClean(legacy)`. `null` в доле — не выигрыш
/// (сравнивать нечего; догадка запрещена).
///
/// N* — первый выигрышный объём, если все большие объёмы тоже выигрышные;
/// иначе см. [PathThresholdReason].
PathThresholdResult derivePathThreshold(List<MaterialPathPoint> points) {
  final List<MaterialPathPoint> sorted = List<MaterialPathPoint>.of(points)
    ..sort((MaterialPathPoint a, MaterialPathPoint b) => a.units - b.units);
  final List<int> winning = <int>[
    for (final MaterialPathPoint point in sorted)
      if (_v3DoesNotLose(point)) point.units,
  ];
  if (winning.isEmpty) {
    return PathThresholdResult(
      thresholdUnits: null,
      reason: PathThresholdReason.noCrossover,
      winningUnits: const <int>[],
    );
  }
  final int firstWinningIndex = sorted.indexWhere(_v3DoesNotLose);
  final bool allAboveWin = sorted.skip(firstWinningIndex).every(_v3DoesNotLose);
  if (!allAboveWin) {
    return PathThresholdResult(
      thresholdUnits: null,
      reason: PathThresholdReason.notMonotonic,
      winningUnits: List<int>.unmodifiable(winning),
    );
  }
  return PathThresholdResult(
    thresholdUnits: sorted[firstWinningIndex].units,
    reason: PathThresholdReason.crossover,
    winningUnits: List<int>.unmodifiable(winning),
  );
}

bool _v3DoesNotLose(MaterialPathPoint point) {
  final double? legacyClean = point.legacy.cleanRate;
  final double? v3Clean = point.v3.cleanRate;
  final double? legacyDup = point.legacy.dupRate;
  final double? v3Dup = point.v3.dupRate;
  if (legacyClean == null || v3Clean == null) return false;
  if (legacyDup == null || v3Dup == null) return false;
  return v3Clean >= legacyClean - 1e-9 &&
      v3Dup <= legacyDup + 1e-9 &&
      point.v3.absoluteClean >= point.legacy.absoluteClean;
}
