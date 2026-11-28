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
