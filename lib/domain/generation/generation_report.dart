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
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Машинный код причины «в материале нет текстового слоя» (срез 11, п. 10).
///
/// Не ошибка Understanding, а свойство материала: скан без текста не даёт
/// карту знаний. Код живёт в отчёте (`understandingFailures`) и переводится в
/// ARB на слое UI.
const String kNoTextLayerCode = 'no_text_layer';

/// Покрытие единицы знания: сколько карточек заказано и сколько принято.
class UnitCoverage {
  /// Создаёт запись покрытия.
  const UnitCoverage({
    required this.unitId,
    required this.planned,
    required this.accepted,
    this.salience,
  }) : assert(planned >= 0, 'Заказ по единице не может быть отрицательным'),
       assert(accepted >= 0, 'Принятое по единице не может быть отрицательным'),
       assert(
         salience == null || (salience >= 0 && salience <= 1),
         'Значимость единицы — в диапазоне 0..1',
       );

  /// id единицы карты знаний.
  final String unitId;

  /// Сколько карточек по единице заказано в плане.
  final int planned;

  /// Сколько карточек по единице принято.
  final int accepted;

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
          other.salience == salience;

  @override
  int get hashCode => Object.hash(unitId, planned, accepted, salience);

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
    Map<String, int> warningCodes = const <String, int>{},
    Map<DedupLevel, int> duplicatesByLevel = const <DedupLevel, int>{},
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
    final Map<String, int> warningCodes = <String, int>{};
    var acceptedWithWarnings = 0;
    for (final GeneratedCard card in outcome.acceptedCards) {
      final String? unitId = card.unitId;
      if (unitId != null) {
        acceptedByUnit[unitId] = (acceptedByUnit[unitId] ?? 0) + 1;
      }
      if (card.gateReasons.isEmpty) continue;
      acceptedWithWarnings++;
      for (final CardReasonCode code in card.gateReasons) {
        warningCodes[code.wireName] = (warningCodes[code.wireName] ?? 0) + 1;
      }
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
            planned: plannedByUnit[budget.unit.id] ?? budget.cards,
            accepted: acceptedByUnit[budget.unit.id] ?? 0,
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
      warningCodes: warningCodes,
      duplicatesByLevel: duplicatesByLevel,
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

  /// Коды пометок принятых карточек с числами (`not_atomic`: 2, …).
  ///
  /// v3 — wire-коды `CardReasonCode`, legacy — `CardIssueCode.name`. Текстов
  /// материалов здесь нет, только машинные коды (протокол §10).
  final Map<String, int> warningCodes;

  /// Дубли по уровням каскада (точный/нормализованный/семантический).
  ///
  /// Пустая карта — дублей не было; счётчик [duplicates] остаётся.
  final Map<DedupLevel, int> duplicatesByLevel;

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

  /// cleanRate = принято без warning / принято (TASK «Срез 12», п. 3).
  ///
  /// `null` — принятых нет: «0 из 0» не является качеством.
  double? get cleanRate => accepted <= 0 ? null : cleanAccepted / accepted;

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
