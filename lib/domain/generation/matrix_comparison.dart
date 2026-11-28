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
FlagCriterionVerdict flagCriterion({
  required int requested,
  required double? v3CleanRateMatched,
  required int v3AbsoluteClean,
  required int legacyAbsoluteClean,
}) {
  if (!isDecisiveCell(requested)) return FlagCriterionVerdict.notDecisive;
  if (v3CleanRateMatched == null) return FlagCriterionVerdict.notMet;
  final bool clean = v3CleanRateMatched >= kFlagCleanRateThreshold;
  final bool volume = v3AbsoluteClean >= legacyAbsoluteClean;
  return clean && volume
      ? FlagCriterionVerdict.met
      : FlagCriterionVerdict.notMet;
}
