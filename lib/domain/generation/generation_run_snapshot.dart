/// Снимок прогона генерации, восстановленный из БД (TASK «Срез 8», ARCH §3.5,
/// ADR-051).
///
/// Здесь нет библиотеки хранения: снимок — доменное значение, которое
/// отдаёт слой данных и на которое опирается правило восстановления
/// (`run_resume.dart`). Поэтому «продолжить с пятой партии» проверяется без
/// drift, а слой данных отвечает только за точность чтения/записи строк.
library;

import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/generation/dedup_mark.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_run.dart';

/// Состояние партии в сохранённом прогоне.
///
/// Отдельный статус нужен, чтобы восстановление не считало выполненной партию,
/// упавшую посередине: `running` — процесс начал запрос и не отметил результат,
/// `failed` — партия завершилась ошибкой, `done` — отработала (недобор внутри
/// партии — дело журнала, а не статуса).
enum GenerationBatchStatus {
  /// Партия ещё не запускалась.
  pending('pending'),

  /// Партия запущена, результат неизвестен (падение процесса/приложения).
  running('running'),

  /// Партия отработала.
  done('done'),

  /// Партия завершилась ошибкой.
  failed('failed');

  const GenerationBatchStatus(this.wireName);

  /// Wire-имя в БД (`generation_batches.status`).
  final String wireName;

  /// Партия требует повторного выполнения при восстановлении.
  bool get needsExecution => this != GenerationBatchStatus.done;

  /// Разбирает статус из строки БД; неизвестная строка — [FormatException].
  static GenerationBatchStatus fromWire(String value) {
    for (final GenerationBatchStatus status in values) {
      if (status.wireName == value) return status;
    }
    throw FormatException('Неизвестный статус партии: $value');
  }
}

/// Партия прогона: статус и счётчики журнала.
class GenerationBatchRecord {
  /// Создаёт запись партии.
  const GenerationBatchRecord({
    required this.ledger,
    this.status = GenerationBatchStatus.pending,
  });

  /// Счётчики партии (заказано/произведено/принято/долг).
  final GenerationBatchLedger ledger;

  /// Статус выполнения партии.
  final GenerationBatchStatus status;

  /// Номер партии (совпадает с индексом в журнале).
  int get batchIndex => ledger.batchIndex;

  /// Копия с другим статусом и/или счётчиками.
  GenerationBatchRecord copyWith({
    GenerationBatchStatus? status,
    GenerationBatchLedger? ledger,
  }) {
    return GenerationBatchRecord(
      ledger: ledger ?? this.ledger,
      status: status ?? this.status,
    );
  }

  /// Запись требует повторного выполнения (не `done`).
  bool get needsExecution => status.needsExecution;

  @override
  String toString() =>
      'GenerationBatchRecord(партия $batchIndex, ${status.wireName}, '
      'принято ${ledger.accepted}/${ledger.requested})';
}

/// Принятая карточка прогона, сохранённая до импорта в колоду.
///
/// [contentHash] — ключ идемпотентности импорта вместе с `run_id`
/// (уникальный индекс `idx_card_drafts_run_hash`). Хеш считается один раз при
/// записи черновика (`contentHashOf`), а не при каждом импорте.
class RunCardDraft {
  /// Создаёт черновик.
  const RunCardDraft({
    required this.contentHash,
    required this.batchIndex,
    required this.card,
    this.importedCardId,
    this.duplicateOf,
    this.dedupLevel,
  });

  /// Хеш содержимого `front + "\u0000" + back`.
  final String contentHash;

  /// Партия, в которой карточка принята.
  final int batchIndex;

  /// Структура карточки (без байтов изображений).
  final GeneratedCard card;

  /// `cards.id`, если черновик уже импортирован; `null` — ещё нет.
  final String? importedCardId;

  /// Вторая сторона пары дублей (срез 13): `content_hash` другого черновика
  /// этого прогона или `deck:<cards.id>`; `null` — дублем не признана.
  final String? duplicateOf;

  /// Уровень каскада дедупа; `null` — дублем не признана.
  final DedupLevel? dedupLevel;

  /// true — карточка уже в колоде (повторный импорт её не дублирует).
  bool get isImported => importedCardId != null;

  /// true — этап Dedup пометил карточку парой.
  bool get isDuplicate => dedupLevel != null;

  @override
  String toString() =>
      'RunCardDraft(партия $batchIndex, $contentHash'
      '${isImported ? ', импортирована' : ''}'
      '${dedupLevel == null ? '' : ', дубль ${dedupLevel!.wireName}'})';
}

/// Снимок сохранённого прогона: этап, партии, принятые карточки, карта.
///
/// [unitCount] — сколько единиц карты знаний сохранено: по нему правило
/// восстановления понимает, прошёл ли прогон этап Understanding (иначе его
/// придётся повторить, и кэш карты знаний может сэкономить запрос).
class GenerationRunSnapshot {
  /// Создаёт снимок; партии обязаны идти подряд с 0.
  GenerationRunSnapshot({
    required this.runId,
    required this.stage,
    required List<GenerationBatchRecord> batches,
    List<RunCardDraft> drafts = const <RunCardDraft>[],
    this.unitCount = 0,
    this.deckId,
    this.createdAt,
    this.updatedAt,
  }) : batches = List<GenerationBatchRecord>.unmodifiable(batches),
       drafts = List<RunCardDraft>.unmodifiable(drafts) {
    assert(
      _numberedFromZero(this.batches),
      'Партии прогона обязаны нумероваться подряд с 0',
    );
  }

  /// Идентификатор прогона (`generation_runs.id`).
  final String runId;

  /// Этап стейт-машины, сохранённый последним.
  final GenerationStage stage;

  /// Партии прогона в порядке плана.
  final List<GenerationBatchRecord> batches;

  /// Принятые карточки в порядке принятия (включая уже импортированные).
  final List<RunCardDraft> drafts;

  /// Сколько единиц карты знаний сохранено.
  final int unitCount;

  /// Колода результата, если импорт уже был.
  final String? deckId;

  /// Момент создания прогона.
  final DateTime? createdAt;

  /// Момент последнего изменения.
  final DateTime? updatedAt;

  /// Журнал прогона по сохранённым партиям.
  ///
  /// Пары дедупа восстанавливаются из строк черновиков ([dedup], срез 13):
  /// пометки `is_duplicate_of` + `dedup_level` персистятся, поэтому после
  /// перезапуска прогона они на месте (L219).
  GenerationLedger get ledger => GenerationLedger(
    batches: <GenerationBatchLedger>[
      for (final GenerationBatchRecord record in batches) record.ledger,
    ],
  );

  /// Отчёт дедупа из сохранённых строк: пара (вторая сторона → черновик) с
  /// уровнем каскада. Пустой — пометок нет.
  ///
  /// Точный дубль внутри прогона хранится одной строкой (уникальный индекс
  /// `run_id + content_hash`): вторая сторона совпадает с ключом, и первой
  /// стороной пары становится маркер [DedupMark.identicalSidePrefix] — иначе
  /// [DedupPair] ссылался бы на одну и ту же карточку дважды.
  DedupReport get dedup => DedupReport(
    pairs: <DedupPair>[
      for (final RunCardDraft draft in drafts)
        if (draft.duplicateOf != null && draft.dedupLevel != null)
          DedupPair(
            leftId: draft.duplicateOf == draft.contentHash
                ? '${DedupMark.identicalSidePrefix}${draft.contentHash}'
                : draft.duplicateOf!,
            rightId: draft.contentHash,
            level: draft.dedupLevel!,
          ),
    ],
  );

  /// Принятые карточки (без импортированных дублей структуры).
  List<GeneratedCard> get acceptedCards => <GeneratedCard>[
    for (final RunCardDraft draft in drafts) draft.card,
  ];

  /// Карточки, ещё не импортированные в колоду.
  List<RunCardDraft> get pendingDrafts => <RunCardDraft>[
    for (final RunCardDraft draft in drafts)
      if (!draft.isImported) draft,
  ];

  /// Номер первой партии, которую надо выполнить повторно; равен числу партий,
  /// если все выполнены.
  int get resumeBatchIndex {
    for (final GenerationBatchRecord record in batches) {
      if (record.needsExecution) return record.batchIndex;
    }
    return batches.length;
  }

  /// Партии, которые надо выполнить при восстановлении (в порядке плана).
  List<int> get pendingBatchIndexes => <int>[
    for (final GenerationBatchRecord record in batches)
      if (record.needsExecution) record.batchIndex,
  ];

  /// true — прогон дошёл до успешного/частичного завершения (продолжать нечего).
  bool get isFinished =>
      stage == GenerationStage.ready || stage == GenerationStage.partial;

  /// true — сохранённый прогон можно продолжить, а не начинать заново.
  ///
  /// Завершённый прогон не продолжается; упавший/отменённый/незавершённый —
  /// продолжается: принятое и выполненные партии не перезапрашиваются.
  bool get isResumable => !isFinished;

  /// Этап, с которого продолжается прогон.
  ///
  /// - единиц карты нет → `understanding` (этап не пройден или не сохранён);
  /// - есть невыполненные партии → `generating`;
  /// - все партии выполнены → `replenishing` (решение о доборе и вердикт).
  GenerationStage get resumeStage {
    if (unitCount == 0) return GenerationStage.understanding;
    if (pendingBatchIndexes.isNotEmpty) return GenerationStage.generating;
    return GenerationStage.replenishing;
  }

  static bool _numberedFromZero(List<GenerationBatchRecord> batches) {
    for (var index = 0; index < batches.length; index++) {
      if (batches[index].batchIndex != index) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'GenerationRunSnapshot($runId, ${stage.name}, '
      '${batches.length} парт., ${drafts.length} черн., '
      'единиц $unitCount${isResumable ? ', с ${resumeStage.name}/'
                '${resumeBatchIndex + 1}' : ''})';
}

/// Хеш содержимого принятой карточки для ключа идемпотентности.
String draftContentHashOf(GeneratedCard card) =>
    contentHashOf(front: card.front, back: card.back);
