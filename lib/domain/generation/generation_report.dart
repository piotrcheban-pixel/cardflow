/// Отчёт прогона генерации (TASK «Срез 7», п. 4).
///
/// Отчёт — не «сколько вернулось сейчас», а снимок заказа: `requested` и
/// `accepted`, причины недобора машинными кодами, покрытие единиц знания,
/// расход токенов по этапам, версии промптов и длительность. Собирается из
/// журнала (`GenerationLedger`) и итога добора ([ReplenishOutcome]), поэтому
/// ложный успех невозможен: [isComplete] требует и закрытого заказа, и
/// заполненных слотов. Пользовательский текст — в ARB на слое UI, здесь только
/// коды (`journal/QUESTIONS.md` Q17).
library;

import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/card_reason_code.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/outcome_counts.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Машинный код причины «в материале нет текстового слоя» (срез 11, п. 10).
///
/// Не ошибка Understanding, а свойство материала: скан без текста не даёт
/// карту знаний. Код живёт в отчёте (`understandingFailures`) и переводится в
/// ARB на слое UI.
const String kNoTextLayerCode = 'no_text_layer';

/// Покрытие единицы знания: сколько карточек заказано, сколько произведено и
/// принято, сколько из принятых — чистые.
///
/// Срез 15 (L230): кроме заказа и принятого, отчёт несёт **пер-юнитные**
/// `produced`, `clean` и `warningCodes`, а также `sectionId` — раздел
/// материала, по которому единицы двух путей сопоставимы (у v3 это
/// `KnowledgeUnit.sectionId`, у legacy — сам раздел). Без этих полей
/// `matchedSubset` строится по агрегату `coverage`, то есть по допущению.
class UnitCoverage {
  /// Создаёт запись покрытия.
  ///
  /// [produced] по умолчанию равен [accepted] (legacy не различает
  /// произведённое и принятое), [clean] — `0`: «чистых не передали» не значит
  /// «все чистые».
  const UnitCoverage({
    required this.unitId,
    required this.planned,
    required this.accepted,
    this.salience,
    this.sectionId,
    int? produced,
    int? clean,
    this.warningCodes = const <String, int>{},
  }) : produced = produced ?? accepted,
       clean = clean ?? 0,
       assert(planned >= 0, 'Заказ по единице не может быть отрицательным'),
       assert(accepted >= 0, 'Принятое по единице не может быть отрицательным'),
       assert(
         produced == null || produced >= 0,
         'Произведённое по единице не может быть отрицательным',
       ),
       assert(
         clean == null || (clean >= 0 && clean <= accepted),
         'Чистых по единице не больше принятых',
       ),
       assert(
         salience == null || (salience >= 0 && salience <= 1),
         'Значимость единицы — в диапазоне 0..1',
       );

  /// id единицы карты знаний (v3) или раздела (legacy).
  final String unitId;

  /// Сколько карточек по единице заказано в плане.
  final int planned;

  /// Сколько карточек по единице принято.
  final int accepted;

  /// Сколько карточек модели отнесено к единице: принято + заблокировано
  /// гейтом (у legacy отброшенные раздел не называют и сюда не входят).
  final int produced;

  /// Сколько принятых карточек единицы без пометок гейта.
  final int clean;

  /// Коды пометок гейта по единице (`not_atomic`: 1, …).
  final Map<String, int> warningCodes;

  /// Раздел материала — общий ключ сопоставления путей (срез 15).
  ///
  /// У v3 — `KnowledgeUnit.sectionId`; у legacy — id раздела. `null` — у
  /// единицы нет разреза (id единиц разных путей несопоставимы напрямую).
  final String? sectionId;

  /// Значимость единицы карты (`KnowledgeUnit.salience`); `null` — у пути нет
  /// карты знаний (legacy-разделы): средняя значимость не выдумывается.
  final double? salience;

  /// true — по единице есть хотя бы одна принятая карточка.
  bool get isCovered => accepted > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnitCoverage &&
          other.unitId == unitId &&
          other.planned == planned &&
          other.accepted == accepted &&
          other.produced == produced &&
          other.clean == clean &&
          other.salience == salience &&
          other.sectionId == sectionId &&
          _sameCodes(other.warningCodes, warningCodes);

  @override
  int get hashCode => Object.hash(
    unitId,
    planned,
    accepted,
    produced,
    clean,
    salience,
    sectionId,
    Object.hashAllUnordered(<int>[
      for (final MapEntry<String, int> entry in warningCodes.entries)
        Object.hash(entry.key, entry.value),
    ]),
  );

  static bool _sameCodes(Map<String, int> left, Map<String, int> right) {
    if (left.length != right.length) return false;
    for (final MapEntry<String, int> entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  String toString() => 'UnitCoverage($unitId, $accepted/$planned)';
}

/// Отчёт прогона: заказ, принятое, причины, покрытие, расход, версии, время.
class GenerationReport {
  /// Создаёт отчёт; списки и карты копируются и становятся неизменяемыми.
  GenerationReport({
    required this.requested,
    required this.accepted,
    required this.stage,
    required this.reason,
    required List<String> reasons,
    required List<UnitCoverage> unitCoverage,
    required Map<GenerationStage, TokenUsage> tokensByStage,
    required Map<String, String> promptVersions,
    required this.duration,
    required this.passes,
    required this.requests,
    this.invalid = 0,
    this.duplicates = 0,
    this.generated = 0,
    this.acceptedWithWarnings = 0,
    this.acceptedDuplicates = 0,
    this.blocked = 0,
    Map<String, int> warningCodes = const <String, int>{},
    Map<DedupLevel, int> duplicatesByLevel = const <DedupLevel, int>{},
    int? duplicateMarked,
    this.understandingRequests = 0,
    List<Duration> batchDurations = const <Duration>[],
    this.materialCapacity,
    this.unfilledSlots = 0,
    Map<ShortfallKind, int> shortfallReasons = const <ShortfallKind, int>{},
    List<String> understandingFailures = const <String>[],
    this.guards,
  }) : reasons = List<String>.unmodifiable(reasons),
       unitCoverage = List<UnitCoverage>.unmodifiable(unitCoverage),
       tokensByStage = Map<GenerationStage, TokenUsage>.unmodifiable(
         tokensByStage,
       ),
       shortfallReasons = Map<ShortfallKind, int>.unmodifiable(
         shortfallReasons,
       ),
       warningCodes = Map<String, int>.unmodifiable(warningCodes),
       duplicatesByLevel = Map<DedupLevel, int>.unmodifiable(duplicatesByLevel),
       // Пометок не передали — дубли считаются парами каскада: прежнее
       // поведение отчёта среза 12 не меняется молча.
       duplicateMarked =
           duplicateMarked ??
           duplicatesByLevel.values.fold<int>(
             0,
             (int sum, int value) => sum + value,
           ),
       batchDurations = List<Duration>.unmodifiable(batchDurations),
       understandingFailures = List<String>.unmodifiable(understandingFailures),
       promptVersions = Map<String, String>.unmodifiable(promptVersions);

  /// Собирает отчёт по итогу добора и плану заказа.
  ///
  /// [initialUsage] — расход первого прохода (этап `generating`);
  /// [initialDuration] — его длительность (суммируется с [outcome]);
  /// [promptVersions] — версии промптов по этапам («generating»,
  /// «replenishing», …): подставляет вызывающий слой, у домена нет промптов.
  factory GenerationReport.fromReplenish({
    required AllocationPlan plan,
    required ReplenishOutcome outcome,
    TokenUsage initialUsage = const TokenUsage(),
    TokenUsage? understandingUsage,
    Duration initialDuration = Duration.zero,
    Map<String, String> promptVersions = const <String, String>{},
    List<String> understandingFailures = const <String>[],
    List<Duration> batchDurations = const <Duration>[],
    Map<DedupLevel, int> duplicatesByLevel = const <DedupLevel, int>{},
    List<GeneratedCard>? acceptedCards,
    List<GeneratedCard> blockedCards = const <GeneratedCard>[],
    int duplicateMarked = 0,
    int blocked = 0,
    int acceptedDuplicates = 0,
    int understandingRequests = 0,
  }) {
    final List<String> reasons = <String>[];
    if (!outcome.isComplete) {
      _addReason(reasons, outcome.reason.wireName);
      final ShortfallKind? shortfall = outcome.shortfall;
      if (shortfall != null) _addReason(reasons, shortfall.wireName);
      if (outcome.invalid > 0 || outcome.duplicates > 0) {
        _addReason(reasons, ShortfallKind.validationRejects.wireName);
      }
    }

    final Map<String, int> plannedByUnit = <String, int>{};
    for (final AllocatedCard card in plan.cards) {
      plannedByUnit[card.unitId] = (plannedByUnit[card.unitId] ?? 0) + 1;
    }
    final Map<String, int> acceptedByUnit = <String, int>{};
    final Map<String, int> producedByUnit = <String, int>{};
    final Map<String, int> cleanByUnit = <String, int>{};
    final Map<String, Map<String, int>> codesByUnit =
        <String, Map<String, int>>{};
    final Map<String, int> warningCodes = <String, int>{};
    var acceptedWithWarnings = 0;
    // Пометки считаются по карточкам **после** этапа Dedup (срез 13, часть 1):
    // фасад передаёт список с пометками `possibleDuplicate`, а числа заказа и
    // принятого остаются из итога добора — дубль не удалён.
    final List<GeneratedCard> markedCards =
        acceptedCards ?? outcome.acceptedCards;
    for (final GeneratedCard card in markedCards) {
      final String? unitId = card.unitId;
      if (unitId != null) {
        acceptedByUnit[unitId] = (acceptedByUnit[unitId] ?? 0) + 1;
        producedByUnit[unitId] = (producedByUnit[unitId] ?? 0) + 1;
        if (card.gateReasons.isEmpty) {
          cleanByUnit[unitId] = (cleanByUnit[unitId] ?? 0) + 1;
        } else {
          final Map<String, int> codes = codesByUnit.putIfAbsent(
            unitId,
            () => <String, int>{},
          );
          for (final CardReasonCode code in card.gateReasons) {
            codes[code.wireName] = (codes[code.wireName] ?? 0) + 1;
          }
        }
      }
      if (card.gateReasons.isEmpty) continue;
      acceptedWithWarnings++;
      for (final CardReasonCode code in card.gateReasons) {
        warningCodes[code.wireName] = (warningCodes[code.wireName] ?? 0) + 1;
      }
    }
    // Заблокированные гейтом карточки произведены моделью и несут `unit_id`:
    // в честной базе это знаменатель единицы, а не «не было» (срез 15).
    for (final GeneratedCard card in blockedCards) {
      final String? unitId = card.unitId;
      if (unitId == null) continue;
      producedByUnit[unitId] = (producedByUnit[unitId] ?? 0) + 1;
    }

    return GenerationReport(
      requested: plan.requested,
      accepted: outcome.accepted,
      stage: outcome.stage,
      reason: outcome.reason,
      reasons: reasons,
      unitCoverage: <UnitCoverage>[
        for (final UnitBudget budget in plan.units)
          UnitCoverage(
            unitId: budget.unit.id,
            sectionId: budget.unit.sectionId,
            planned: plannedByUnit[budget.unit.id] ?? budget.cards,
            accepted: acceptedByUnit[budget.unit.id] ?? 0,
            produced: producedByUnit[budget.unit.id] ?? 0,
            clean: cleanByUnit[budget.unit.id] ?? 0,
            warningCodes: codesByUnit[budget.unit.id] ?? const <String, int>{},
            salience: budget.unit.salience,
          ),
      ],
      tokensByStage: <GenerationStage, TokenUsage>{
        GenerationStage.understanding: ?understandingUsage,
        GenerationStage.generating: initialUsage,
        GenerationStage.replenishing: outcome.usage,
      },
      promptVersions: promptVersions,
      duration: initialDuration + outcome.duration,
      passes: outcome.passes.length,
      requests: outcome.requests,
      invalid: outcome.invalid,
      duplicates: outcome.duplicates,
      generated: outcome.accepted + outcome.invalid + outcome.duplicates,
      acceptedWithWarnings: acceptedWithWarnings,
      acceptedDuplicates: acceptedDuplicates,
      blocked: blocked,
      warningCodes: warningCodes,
      duplicatesByLevel: duplicatesByLevel,
      duplicateMarked: duplicateMarked,
      understandingRequests: understandingRequests,
      batchDurations: <Duration>[...batchDurations, ...outcome.batchDurations],
      materialCapacity: outcome.materialCapacity,
      unfilledSlots: outcome.unfilledSlots,
      shortfallReasons: _shortfallReasonsOf(outcome),
      understandingFailures: understandingFailures,
      guards: outcome.guards,
    );
  }

  /// Причины недобора **множеством с числами** (TASK срез 10, п. 5).
  ///
  /// Прежний `reasons` — список кодов без чисел и без «сколько»; отчёт теперь
  /// отвечает на вопрос «сколько карточек потеряно и почему»: отброшенные
  /// валидацией и дубли — своими счётчиками, причина остановки — остатком.
  /// Остаток, полностью объяснённый счётчиками, не дублируется причиной
  /// остановки (иначе дубли выглядели бы ещё и как исчерпание материала).
  static Map<ShortfallKind, int> _shortfallReasonsOf(ReplenishOutcome outcome) {
    if (outcome.remaining <= 0) return const <ShortfallKind, int>{};
    final Map<ShortfallKind, int> found = <ShortfallKind, int>{};
    final ShortfallKind? stopKind = outcome.shortfall;
    // Слот закрыт как «обе попытки заблокированы»: потерянные карточки — это
    // незакрытые слоты (remaining), а не число отброшенных записей модели:
    // на один слот их пришлось две, и считать их «карточками недобора» значит
    // дважды объяснять одну потерю (TASK «Срез 11», п. 3).
    if (stopKind == ShortfallKind.validationRejects) {
      found[ShortfallKind.validationRejects] = outcome.remaining;
      return found;
    }
    // Слот закрыт двумя смысловыми коллизиями (срез 16): потеря — незакрытые
    // слоты, а не число отложенных карточек (на слот их пришлось две).
    if (stopKind == ShortfallKind.duplicates) {
      found[ShortfallKind.duplicates] = outcome.remaining;
      return found;
    }
    if (outcome.duplicates > 0) {
      found[ShortfallKind.duplicates] = outcome.duplicates;
    }
    if (outcome.invalid > 0) {
      found[ShortfallKind.validationRejects] = outcome.invalid;
    }
    final int explained = outcome.invalid + outcome.duplicates;
    if (stopKind != null && outcome.remaining > explained) {
      found[stopKind] = outcome.remaining;
    } else if (found.isEmpty && outcome.remaining > explained) {
      found[ShortfallKind.exhaustedMaterial] = outcome.remaining;
    }
    return found;
  }

  /// Запрошено карточек (заказ плана).
  final int requested;

  /// Принято карточек (первый проход и добор).
  final int accepted;

  /// Терминальный этап прогона.
  final GenerationStage stage;

  /// Точная причина остановки добора.
  final ReplenishStopReason reason;

  /// Причины недобора машинными кодами: причина остановки, класс недобора и
  /// `validation_rejects`, если карточки отбрасывались. У успеха причин нет.
  final List<String> reasons;

  /// Покрытие единиц знания: заказ и принятое по каждой.
  final List<UnitCoverage> unitCoverage;

  /// Расход токенов по этапам (первый проход и добор).
  ///
  /// Ключа этапа нет в карте — этап не сообщил расход (например, Understanding
  /// в этом срезе не подключался).
  final Map<GenerationStage, TokenUsage> tokensByStage;

  /// Версии промптов по этапам (например, `generating: gen-cards-v3`).
  final Map<String, String> promptVersions;

  /// Длительность прогона.
  final Duration duration;

  /// Сколько проходов добора выполнено.
  final int passes;

  /// Запросов модели за прогон, включая первый проход и повторы.
  final int requests;

  /// Отброшено валидацией/схемой.
  final int invalid;

  /// Отброшено как дубли.
  final int duplicates;

  /// Произведено моделью: принято + отброшено валидацией/схемой + дубли
  /// (TASK «Срез 12», п. 4: числитель/знаменатель acceptanceRate).
  final int generated;

  /// Принято карточек с пометками гейта (warning) — «грязное» принятое.
  final int acceptedWithWarnings;

  /// Принято с пометкой смыслового дубля (`possibleDuplicate`).
  ///
  /// Нужен только `unique` в [OutcomeCounts]: у v3 пометок больше нет (дубль
  /// откладывается до принятия, срез 16), у legacy — принятые почти-дубли.
  final int acceptedDuplicates;

  /// Отброшено жёстким дефектом (гейт v3) или проверкой поля (legacy).
  ///
  /// Отдельно от [invalid]: `blockRate` считается по этому числу.
  final int blocked;

  /// Коды пометок принятых карточек с числами (`not_atomic`: 2, …).
  ///
  /// v3 — wire-коды `CardReasonCode`, legacy — `CardIssueCode.name`. Текстов
  /// материалов здесь нет, только машинные коды (протокол §10).
  final Map<String, int> warningCodes;

  /// Дубли по уровням каскада (точный/нормализованный/семантический).
  ///
  /// Пустая карта — дублей не было; счётчик [duplicates] остаётся.
  final Map<DedupLevel, int> duplicatesByLevel;

  /// Карточек помечено этапом Dedup (срез 13): пары [duplicatesByLevel] в
  /// карточках, **не удалённых** из принятого.
  ///
  /// У v3 — пометки `possibleDuplicate` (смысловой дубль остаётся в колоде);
  /// у legacy — отброшенные точные дубли плюс помеченные почти-дубли, т. е.
  /// сумма уровней каскада. Знаменатель [duplicateRate] — [generated].
  final int duplicateMarked;

  /// Запросов Understanding за прогон (TASK «Срез 13», п. 7).
  ///
  /// Включает повторы лестницы ADR-021 и деление обрезанных фрагментов; из
  /// кэша карты — 0. «Запросов на 10 разделов» считает стенд.
  final int understandingRequests;

  /// Отметки времени запросов модели (успешных и ошибочных), TASK п. 6.
  final List<Duration> batchDurations;

  /// «Материала достаточно примерно на N качественных карточек»; `null` —
  /// материал не признан исчерпанным.
  final int? materialCapacity;

  /// Слотов заказа без принятой карточки.
  final int unfilledSlots;

  /// Причины недобора с числами: сколько карточек потеряно по каждой (п. 5
  /// среза 10). Пустая карта — недобора нет.
  final Map<ShortfallKind, int> shortfallReasons;

  /// Фактические предохранители операции добора (п. 4 среза 10); `null` —
  /// операция шла мимо [ReplenishStage] и пределов не объявляла.
  final ReplenishGuards? guards;

  /// Машинные коды причин, по которым Understanding не дал карту (срез 11,
  /// п. 10): `no_text_layer` — в материале нет текстового слоя, `json_parse`/
  /// `schema_invalid`/`truncated`/`provider_error` — помеченные фрагменты.
  ///
  /// Список непустой не делает прогон исключением: карточки просто не
  /// появляются, а причина видна числом/кодом в отчёте и предпросмотре.
  final List<String> understandingFailures;

  /// true — заказ выполнен: этап [GenerationStage.ready], все слоты заполнены и
  /// принято не меньше запрошенного (недобор успехом не считается).
  bool get isComplete =>
      stage == GenerationStage.ready &&
      unfilledSlots == 0 &&
      accepted >= requested;

  /// Принято без пометок гейта (`accepted − acceptedWithWarnings`).
  int get cleanAccepted => accepted - acceptedWithWarnings;

  /// Исход попыток: attempted / accepted / unique / clean и производные
  /// (TASK «Срез 16», часть 1). Один код для legacy и v3 — из этого отчёта.
  OutcomeCounts get outcome => OutcomeCounts.fromReport(this);

  /// Число чистых карточек рядом с [cleanRate] (TASK «Срез 14», часть 2).
  ///
  /// Доля без объёма вводит в заблуждение: «100 % из 15» и «97 % из 189» —
  /// разные величины качества прогона, и видеть это нужно числом.
  int get absoluteClean => cleanAccepted;

  /// Качество **сохранённой** карточки: чистые / уникальные принятые.
  ///
  /// Определение **заморожено** срезом 17 (ADR-054, часть 0): знаменатель —
  /// [OutcomeCounts.unique], а не [generated]. Дубль не двигает эту величину —
  /// он считается отдельно в [duplicateRate]. `null` — сохранённых нет:
  /// «0 из 0» не качество.
  double? get cleanRate => outcome.cleanRate;

  /// Доля дублей от уникальных (замороженное определение среза 17).
  ///
  /// `null` — сохранённых нет. Раньше (срез 13) здесь был
  /// `duplicateMarked / generated`; сменить это снова можно только ADR (TASK
  /// «Срез 17», п. 4).
  double? get duplicateRate => outcome.dupRate;

  /// Долг: `max(0, requested − accepted)`.
  int get remaining => requested > accepted ? requested - accepted : 0;

  /// Единиц с принятой хотя бы одной карточкой.
  int get coveredUnits =>
      unitCoverage.where((UnitCoverage coverage) => coverage.isCovered).length;

  /// Единиц без единой принятой карточки.
  int get uncoveredUnits => unitCoverage.length - coveredUnits;

  static void _addReason(List<String> reasons, String code) {
    if (!reasons.contains(code)) reasons.add(code);
  }

  @override
  String toString() =>
      'GenerationReport(${stage.name}, принято $accepted/$requested, '
      'причины ${reasons.isEmpty ? 'нет' : reasons.join(', ')}, '
      'проходов $passes, запросов $requests, $duration)';
}
