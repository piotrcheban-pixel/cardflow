/// Правила честного сравнения путей генерации (TASK «Срез 13», часть 3).
///
/// Метрики сравниваются только на сопоставимой базе:
/// 1) `cleanRate` — доля от **произведённых** (`generated`), а не от принятых:
///    путь, отбрасывающий сомнительное, иначе выглядел бы чище;
/// 2) ячейки заказа 20 и 40 — **нерешающие**: при малом `n` одно-два
///    предупреждения дают десятки процентов разницы, и вывод «лучше/хуже» из
///    них не следует;
/// 3) решение о флаге принимается по ячейкам 80/150/300, где знаменатель
///    `generated` сравним по смыслу у обоих путей.
///
/// Здесь только чистые правила; сама таблица собирается из существующих
/// `matrix.jsonl` (новых платных прогонов для пересчёта не делается).
library;

/// С какого заказа ячейка матрицы считается решающей.
const int kDecisiveRequestedFrom = 80;

/// Порог критерия флага среза 14: `cleanRate_matched` v3 не ниже 95 %.
const double kFlagCleanRateThreshold = 0.95;

/// true — по ячейке заказа [requested] можно делать вывод о флаге.
///
/// 20 и 40 — нерешающие (малый знаменатель); 80/150/300 — решающие.
bool isDecisiveCell(int requested) => requested >= kDecisiveRequestedFrom;

/// cleanRate по правилам среза 13: принято без пометок / произведено.
///
/// `null` — произведённых нет: «0 из 0» не является качеством.
double? cleanRateOfGenerated({
  required int cleanAccepted,
  required int generated,
}) => generated <= 0 ? null : cleanAccepted / generated;

/// cleanRate по прежнему правилу среза 12 (принято без пометок / принято) —
/// нужен только для колонки «было», чтобы видеть разницу баз.
double? cleanRateOfAccepted({
  required int cleanAccepted,
  required int accepted,
}) => accepted <= 0 ? null : cleanAccepted / accepted;

/// Сравнение пары ячеек (legacy против v3) на одном материале и заказе.
enum MatrixComparisonVerdict {
  /// v3 не хуже: cleanRate больше или равен.
  notWorse,

  /// v3 хуже legacy по cleanRate.
  worse,

  /// Сравнивать нельзя: ячейка нерешающая или нет данных.
  notDecisive,
}

/// Вердикт по паре ячеек на сопоставимой базе.
///
/// [v3CleanRate]/[legacyCleanRate] уже посчитаны от `generated`. Ячейка
/// нерешающая — [MatrixComparisonVerdict.notDecisive], даже если числа есть.
MatrixComparisonVerdict compareCells({
  required int requested,
  required double? v3CleanRate,
  required double? legacyCleanRate,
}) {
  if (!isDecisiveCell(requested)) {
    return MatrixComparisonVerdict.notDecisive;
  }
  if (v3CleanRate == null || legacyCleanRate == null) {
    return MatrixComparisonVerdict.notDecisive;
  }
  return v3CleanRate >= legacyCleanRate
      ? MatrixComparisonVerdict.notWorse
      : MatrixComparisonVerdict.worse;
}

/// Число различимых слотов заказа: 4 угла на единицу (primary + три).
///
/// Нужно для разбора `partial`: если принято ровно `4 × единиц`, остановка —
/// не предохранитель добора, а исчерпание различимых слотов плана.
const int kSlotsPerUnit = 4;

/// true — `accepted` делится на число углов: похоже на остановку `complete`
/// по слотам, а не на обрыв добора.
bool looksLikeSlotCapacity(int accepted) =>
    accepted > 0 && accepted % kSlotsPerUnit == 0;

/// Сколько единиц карты могло дать [accepted] различимых слотов.
int unitsOfSlots(int accepted) => accepted ~/ kSlotsPerUnit;

/// Одна произведённая карточка на сопоставимой базе: единица, чистота и
/// значимость единицы (для отбора «топ-80 по salience»).
class ProducedCardRef {
  /// Создаёт ссылку на произведённую карточку.
  const ProducedCardRef({
    required this.unitId,
    required this.clean,
    this.salience,
  });

  /// id единицы знания, к которой относится карточка.
  final String unitId;

  /// true — карточка без пометок гейта (чистая).
  final bool clean;

  /// Значимость единицы; `null` — у пути нет карты знаний.
  final double? salience;
}

/// Сопоставимая база: единицы, по которым **оба** пути произвели хотя бы одну
/// карточку (TASK «Срез 14», часть 2).
///
/// Смысл: путь, произведший карточки только на «лёгкой» части материала, не
/// должен выглядеть чище из-за меньшего знаменателя. Поэтому `cleanRate_matched`
/// считается только по карточкам пересечения единиц, а `absoluteClean` —
/// рядом числом чистых карточек (доля без объёма вводит в заблуждение).
///
/// [topUnits] ограничивает базу верхом материала по значимости (для ячеек
/// заказа 150/300 — «топ-80 по salience»): при равной значимости порядок —
/// по id единицы, поэтому результат детерминирован.
class MatchedSubset {
  MatchedSubset._({
    required this.unitIds,
    required this.legacyProduced,
    required this.v3Produced,
  });

  /// Строит сопоставимую базу из произведённых карточек двух путей.
  factory MatchedSubset.of({
    required Iterable<ProducedCardRef> legacy,
    required Iterable<ProducedCardRef> v3,
    int? topUnits,
  }) {
    final List<ProducedCardRef> legacyAll = List<ProducedCardRef>.of(legacy);
    final List<ProducedCardRef> v3All = List<ProducedCardRef>.of(v3);
    final Set<String> matched =
        <String>{for (final ProducedCardRef ref in legacyAll) ref.unitId}
            .intersection(<String>{
              for (final ProducedCardRef ref in v3All) ref.unitId,
            });
    Set<String> selected = matched;
    if (topUnits != null && matched.length > topUnits) {
      final Map<String, double> salience = <String, double>{};
      for (final ProducedCardRef ref in <ProducedCardRef>[
        ...legacyAll,
        ...v3All,
      ]) {
        if (!matched.contains(ref.unitId)) continue;
        final double value = ref.salience ?? 0;
        if (value > (salience[ref.unitId] ?? double.negativeInfinity)) {
          salience[ref.unitId] = value;
        }
      }
      final List<String> ordered = matched.toList()
        ..sort((String a, String b) {
          final int bySalience = (salience[b] ?? 0).compareTo(salience[a] ?? 0);
          return bySalience != 0 ? bySalience : a.compareTo(b);
        });
      selected = ordered.take(topUnits).toSet();
    }
    return MatchedSubset._(
      unitIds: selected,
      legacyProduced: List<ProducedCardRef>.unmodifiable(
        legacyAll.where((ProducedCardRef ref) => selected.contains(ref.unitId)),
      ),
      v3Produced: List<ProducedCardRef>.unmodifiable(
        v3All.where((ProducedCardRef ref) => selected.contains(ref.unitId)),
      ),
    );
  }

  /// Единицы пересечения, вошедшие в базу.
  final Set<String> unitIds;

  /// Произведённые карточки legacy на этой базе.
  final List<ProducedCardRef> legacyProduced;

  /// Произведённые карточки v3 на этой базе.
  final List<ProducedCardRef> v3Produced;

  /// Произведено карточек legacy на базе.
  int get legacyGenerated => legacyProduced.length;

  /// Произведено карточек v3 на базе.
  int get v3Generated => v3Produced.length;

  /// Чистых карточек legacy на базе.
  int get legacyClean =>
      legacyProduced.where((ProducedCardRef ref) => ref.clean).length;

  /// Чистых карточек v3 на базе.
  int get v3Clean =>
      v3Produced.where((ProducedCardRef ref) => ref.clean).length;

  /// cleanRate legacy на сопоставимой базе; `null` — произведённых нет.
  double? get legacyCleanRate =>
      legacyGenerated <= 0 ? null : legacyClean / legacyGenerated;

  /// cleanRate v3 на сопоставимой базе; `null` — произведённых нет.
  double? get v3CleanRate => v3Generated <= 0 ? null : v3Clean / v3Generated;
}

/// Порог решающей базы: меньше 10 единиц — ячейка нерешающая (TASK срез 15,
/// п. 9). При малой базе одно-два предупреждения дают десятки процентов
/// разницы, и вывод «выполнен/не выполнен» из них не следует.
const int kMinMatchedUnits = 10;

/// Одна строка пер-юнитных данных отчёта: произведено и чисто по единице.
///
/// [unitId] — id единицы своего пути (v3 — единица карты `ku:…`, legacy —
/// раздел), [sectionId] — раздел материала: общий ключ сопоставления, потому
/// что пространства id единиц у путей разные (`journal/QUESTIONS.md` Q27).
class ProductionUnit {
  /// Создаёт строку; [warningCodes] копируется вызывающим слоем как есть.
  const ProductionUnit({
    required this.unitId,
    required this.produced,
    required this.clean,
    this.sectionId,
    this.salience,
    this.warningCodes = const <String, int>{},
  }) : assert(produced >= 0, 'Произведённое не может быть отрицательным'),
       assert(
         clean >= 0 && clean <= produced,
         'Чистых не больше произведённых',
       ),
       assert(
         salience == null || (salience >= 0 && salience <= 1),
         'Значимость единицы — в диапазоне 0..1',
       );

  /// id единицы своего пути.
  final String unitId;

  /// Раздел материала (общий ключ сопоставления); `null` — ключ по [unitId].
  final String? sectionId;

  /// Произведено карточек по единице (включая заблокированные гейтом).
  final int produced;

  /// Чистых карточек по единице (принятые без пометок).
  final int clean;

  /// Значимость единицы; `null` — у пути нет карты знаний.
  final double? salience;

  /// Коды пометок единицы (для отчёта/диагностики).
  final Map<String, int> warningCodes;
}

/// Сопоставимая база, построенная **из пер-юнитных данных** (TASK срез 15).
///
/// Правило: единица входит в базу, если оба пути произвели по ней хотя бы одну
/// карточку. Сопоставление идёт по общему ключу — разделу материала, если он
/// известен, иначе по id единицы. Живые пути различаются пространством id
/// единиц (v3 — единицы карты, legacy — разделы), поэтому база строится по
/// разделу: единицей статистики остаётся единица карты v3 внутри сопоставимых
/// разделов ([v3UnitCount]).
///
/// «Топ-N по salience» ([MatchedUnitBase.of] `topUnits`): значимость раздела —
/// максимум значимости его единиц; при равенстве порядок — по ключу, поэтому
/// результат детерминирован.
class MatchedUnitBase {
  MatchedUnitBase._({
    required this.keys,
    required this.legacyProduced,
    required this.legacyClean,
    required this.v3Produced,
    required this.v3Clean,
    required this.legacyUnitCount,
    required this.v3UnitCount,
  });

  /// Строит базу из пер-юнитных данных обоих путей.
  factory MatchedUnitBase.of({
    required Iterable<ProductionUnit> legacy,
    required Iterable<ProductionUnit> v3,
    int? topUnits,
  }) {
    final List<ProductionUnit> legacyRows = List<ProductionUnit>.of(legacy);
    final List<ProductionUnit> v3Rows = List<ProductionUnit>.of(v3);
    final Set<String> legacyKeys = <String>{
      for (final ProductionUnit row in legacyRows)
        if (row.produced > 0) _keyOf(row),
    };
    final Set<String> v3Keys = <String>{
      for (final ProductionUnit row in v3Rows)
        if (row.produced > 0) _keyOf(row),
    };
    Set<String> selected = legacyKeys.intersection(v3Keys);
    if (topUnits != null && selected.length > topUnits) {
      final Map<String, double> salience = <String, double>{};
      for (final ProductionUnit row in v3Rows) {
        final String key = _keyOf(row);
        if (!selected.contains(key)) continue;
        final double value = row.salience ?? 0;
        if (value > (salience[key] ?? double.negativeInfinity)) {
          salience[key] = value;
        }
      }
      final List<String> ordered = selected.toList()
        ..sort((String a, String b) {
          final int bySalience = (salience[b] ?? 0).compareTo(salience[a] ?? 0);
          return bySalience != 0 ? bySalience : a.compareTo(b);
        });
      selected = ordered.take(topUnits).toSet();
    }
    var legacyProduced = 0;
    var legacyClean = 0;
    var v3Produced = 0;
    var v3Clean = 0;
    var legacyUnits = 0;
    var v3Units = 0;
    for (final ProductionUnit row in legacyRows) {
      if (!selected.contains(_keyOf(row))) continue;
      legacyProduced += row.produced;
      legacyClean += row.clean;
      legacyUnits++;
    }
    for (final ProductionUnit row in v3Rows) {
      if (!selected.contains(_keyOf(row))) continue;
      v3Produced += row.produced;
      v3Clean += row.clean;
      v3Units++;
    }
    return MatchedUnitBase._(
      keys: Set<String>.unmodifiable(selected),
      legacyProduced: legacyProduced,
      legacyClean: legacyClean,
      v3Produced: v3Produced,
      v3Clean: v3Clean,
      legacyUnitCount: legacyUnits,
      v3UnitCount: v3Units,
    );
  }

  /// Ключ сопоставления: раздел материала, иначе id единицы.
  static String _keyOf(ProductionUnit row) => row.sectionId ?? row.unitId;

  /// Ключи (разделы/единицы), вошедшие в базу.
  final Set<String> keys;

  /// Произведено карточек legacy на базе.
  final int legacyProduced;

  /// Чистых карточек legacy на базе.
  final int legacyClean;

  /// Произведено карточек v3 на базе.
  final int v3Produced;

  /// Чистых карточек v3 на базе.
  final int v3Clean;

  /// Строк legacy в базе (разделы).
  final int legacyUnitCount;

  /// Единиц карты v3 в базе — «число единиц в matchedSubset» для порога.
  final int v3UnitCount;

  /// Число сопоставимых разрезов (разделов).
  int get sectionCount => keys.length;

  /// cleanRate legacy на сопоставимой базе; `null` — произведённых нет.
  double? get legacyCleanRate =>
      legacyProduced <= 0 ? null : legacyClean / legacyProduced;

  /// cleanRate v3 на сопоставимой базе; `null` — произведённых нет.
  double? get v3CleanRate => v3Produced <= 0 ? null : v3Clean / v3Produced;

  /// true — база решающая: единиц не меньше [kMinMatchedUnits] и числа есть.
  bool get isDecisive =>
      v3UnitCount >= kMinMatchedUnits &&
      legacyCleanRate != null &&
      v3CleanRate != null;
}

/// cleanRate на сопоставимой базе из **агрегатов** `matrix.jsonl`.
///
/// В существующей матрице нет пер-юнитных карточек, но есть `coverage`
/// (доля единиц с произведённой карточкой). При `coverage == 1` у пути нет
/// единиц без карточки, поэтому из сопоставимой базы не выпадает ни одна
/// произведённая карточка: `matched = произведено`. При `coverage < 1` база
/// невосстановима из агрегатов — возвращается `null`, а не догадка.
double? cleanRateMatchedFromCoverage({
  required int clean,
  required int generated,
  required double? coverage,
}) {
  if (coverage == null || coverage < 1) return null;
  return cleanRateOfGenerated(cleanAccepted: clean, generated: generated);
}

/// Итог критерия флага среза 14 по одной решающей ячейке (TASK, п. 8).
enum FlagCriterionVerdict {
  /// Критерий по ячейке выполнен.
  met,

  /// Критерий по ячейке не выполнен.
  notMet,

  /// Ячейка нерешающая (20/40) или данных нет.
  notDecisive,
}

/// Критерий флага: `cleanRate_matched` v3 ≥ 95 % И `absoluteClean` v3 не
/// меньше legacy — на решающей ячейке.
///
/// [matchedUnits] — число единиц сопоставимой базы: меньше [kMinMatchedUnits]
/// делает ячейку нерешающей даже при наличии чисел (TASK срез 15, п. 9).
FlagCriterionVerdict flagCriterion({
  required int requested,
  required double? v3CleanRateMatched,
  required int v3AbsoluteClean,
  required int legacyAbsoluteClean,
  int? matchedUnits,
}) {
  if (!isDecisiveCell(requested)) return FlagCriterionVerdict.notDecisive;
  if (matchedUnits != null && matchedUnits < kMinMatchedUnits) {
    return FlagCriterionVerdict.notDecisive;
  }
  if (v3CleanRateMatched == null) return FlagCriterionVerdict.notMet;
  final bool clean = v3CleanRateMatched >= kFlagCleanRateThreshold;
  final bool volume = v3AbsoluteClean >= legacyAbsoluteClean;
  return clean && volume
      ? FlagCriterionVerdict.met
      : FlagCriterionVerdict.notMet;
}
