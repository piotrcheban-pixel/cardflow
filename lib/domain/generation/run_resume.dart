/// Правило восстановления прогона (TASK «Срез 8», ARCH §3.5, ADR-051).
///
/// Восстановление — это **не перезапуск с начала**: выполненные партии не
/// перезапрашиваются, принятые карточки не теряются, понимание материала не
/// оплачивается повторно (кэш карты знаний). Правило здесь чистое и не знает
/// про drift: слой данных отдаёт снимок (`GenerationRunSnapshot`), а план
/// восстановления говорит, с какого этапа и с каких партий продолжать.
library;

import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/generation_run_snapshot.dart';

/// План продолжения сохранённого прогона.
class GenerationResumePlan {
  /// Создаёт план; [batchIndexes] — партии к выполнению по порядку.
  const GenerationResumePlan({
    required this.runId,
    required this.stage,
    required this.batchIndexes,
    required this.accepted,
    required this.ledger,
    required this.isResumable,
    this.unitCount = 0,
  });

  /// Идентификатор прогона.
  final String runId;

  /// Этап, с которого продолжается прогон.
  final GenerationStage stage;

  /// Номера партий, которые надо выполнить (по возрастанию).
  final List<int> batchIndexes;

  /// Уже принятые карточки: они остаются в предпросмотре и участвуют в дедупе.
  final List<GeneratedCard> accepted;

  /// Журнал прогона на момент восстановления.
  final GenerationLedger ledger;

  /// true — прогон можно продолжить (false — он уже завершён).
  final bool isResumable;

  /// Сколько единиц карты знаний уже сохранено.
  final int unitCount;

  /// Номер первой партии к выполнению; `null` — выполнять нечего.
  int? get firstBatchIndex => batchIndexes.isEmpty ? null : batchIndexes.first;

  /// true — выполненные партии не будут перезапрошены.
  bool get skipsCompletedWork => accepted.isNotEmpty || batchIndexes.isNotEmpty;

  /// true — нужен новый вызов Understanding (карты знаний нет).
  bool get needsUnderstanding => stage == GenerationStage.understanding;

  /// true — план не делает ничего: прогон завершён или уже всё выполнено.
  bool get isEmpty => !isResumable || batchIndexes.isEmpty;

  @override
  String toString() =>
      'GenerationResumePlan($runId, ${stage.name}, '
      'партии $batchIndexes, принято ${accepted.length})';
}

/// Строит план продолжения по снимку прогона.
///
/// Завершённый прогон (`ready`/`partial`) не продолжается: план с
/// `isResumable == false` и пустым списком партий. Для восстановимого прогона
/// этап и партии берутся из правила снимка: выполненные (`done`) партии не
/// попадают в план, незавершённые (`pending`/`running`/`failed`) — попадают в
/// порядке плана.
GenerationResumePlan planGenerationResume(GenerationRunSnapshot snapshot) {
  if (!snapshot.isResumable) {
    return GenerationResumePlan(
      runId: snapshot.runId,
      stage: snapshot.stage,
      batchIndexes: const <int>[],
      accepted: snapshot.acceptedCards,
      ledger: snapshot.ledger,
      isResumable: false,
      unitCount: snapshot.unitCount,
    );
  }
  return GenerationResumePlan(
    runId: snapshot.runId,
    stage: snapshot.resumeStage,
    batchIndexes: List<int>.unmodifiable(snapshot.pendingBatchIndexes),
    accepted: List<GeneratedCard>.unmodifiable(snapshot.acceptedCards),
    ledger: snapshot.ledger,
    isResumable: true,
    unitCount: snapshot.unitCount,
  );
}
