/// Модели запуска пайплайна генерации (SPEC A8.5, ADR-015, ADR-020).
///
/// Домен не зависит от Flutter, Dio и БД: отмена и HTTP-транспорт живут в
/// `lib/api/generation/`.
library;

import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Запрос на генерацию карточек из разобранных документов.
class GenerationRunRequest {
  /// Создаёт запрос.
  const GenerationRunRequest({
    required this.documents,
    required this.account,
    required this.deckName,
    this.wishes,
    this.requestedCards,
    this.targetDeckId,
    this.images = const <GenerationAttachment>[],
    this.documentImages = const <DocumentImage>[],
  }) : assert(
         requestedCards == null || requestedCards > 0,
         'Заказ карточек должен быть положительным или null',
       );

  /// Разобранные документы (порядок прикрепления).
  final List<ParsedDocument> documents;

  /// Изображения и PDF-сканы (порядок прикрепления).
  final List<GenerationAttachment> images;

  /// Изображения, извлечённые из файлов, но не привязанные к тексту документа
  /// (итерация L76, ADR-037): значимые области страниц скана. Попадают в
  /// каталог `<images>` того фрагмента, где находятся страницы их файла.
  final List<DocumentImage> documentImages;

  /// Провайдер: протокол, адрес, модель и id ключа (ADR-020).
  final ProviderAccount account;

  /// Имя колоды (при `targetDeckId == null` — имя новой колоды).
  final String deckName;

  /// Необязательные пожелания по содержанию.
  final String? wishes;

  /// Явно заданное число карточек (например, из числового поля); `null` —
  /// разбирается из [wishes] (`requestedCardCount`), без искусственного среза.
  final int? requestedCards;

  /// Существующая колода; `null` — создать новую.
  final String? targetDeckId;
}

/// Фаза прогресса генерации.
enum GenerationProgressPhase {
  /// Нарезка материалов.
  chunking,

  /// Отправка фрагмента.
  sending,

  /// Получение и разбор ответа.
  receiving,
}

/// Прогресс генерации для UI.
class GenerationProgress {
  /// Создаёт прогресс.
  const GenerationProgress({
    required this.phase,
    this.chunkIndex,
    this.chunkCount,
    this.requestedCards,
    this.cards = const <GeneratedCard>[],
    this.imagesPending = false,
  });

  /// Фаза.
  final GenerationProgressPhase phase;

  /// Номер текущего фрагмента (с 1).
  final int? chunkIndex;

  /// Всего фрагментов.
  final int? chunkCount;

  /// Глобальная цель операции в карточках; `null`/`0` — цель не задана.
  final int? requestedCards;

  /// Принятые карточки прямо сейчас (7.14): UI показывает их, не дожидаясь
  /// окончания поиска картинок. Снимок неизменяемый.
  final List<GeneratedCard> cards;

  /// Картинки текущих карточек ещё догружаются.
  final bool imagesPending;
}

/// Колбэк прогресса.
typedef GenerationProgressCallback = void Function(GenerationProgress progress);

/// Ошибка одного фрагмента (частичный успех, A6.8).
class GenerationChunkFailure {
  /// Создаёт ошибку фрагмента.
  const GenerationChunkFailure({
    required this.chunkIndex,
    required this.code,
    required this.materialsText,
    required this.limit,
    this.sourceFiles = const <String>[],
    this.retryable = true,
    this.splitAttempted = false,
    this.providerReason,
    this.images = const <GenerationAttachment>[],
    this.documentImages = const <DocumentImage>[],
    this.reason,
    this.plannedChunk,
    this.retryAfter,
    this.attempts = 1,
  });

  /// Номер фрагмента (с 1).
  final int chunkIndex;

  /// Код ошибки.
  final GenerationErrorCode code;

  /// Внутренняя причина сбоя (fix-gen): `json_parse`, `schema_invalid`,
  /// `truncated`, `safety`, `http_4xx/5xx` и т.п.
  final GenerationFailureReason? reason;

  /// Текст фрагмента для повтора (в UI не показывается).
  final String materialsText;

  /// Лимит карточек фрагмента для повтора.
  final int limit;

  /// Имена файлов фрагмента.
  final List<String> sourceFiles;

  /// Можно ли повторить фрагмент кнопкой «Повторить неудавшиеся».
  final bool retryable;

  /// Фрагмент уже дробился до этой ошибки (повтор не должен дробить снова
  /// без нового разрешения A8.5 шаг 8).
  final bool splitAttempted;

  /// Безопасная причина отказа провайдера (HTTP 400) для сообщения UI.
  final String? providerReason;

  /// Вложения фрагмента (для повтора image-запроса).
  final List<GenerationAttachment> images;

  /// Изображения из документов фрагмента (для повтора, fix-gen Д3).
  final List<DocumentImage> documentImages;

  /// Фрагмент плана, который упал (для точного повтора и дробления).
  ///
  /// `null` — результат старого пути/теста: повтор восстанавливает фрагмент из
  /// [materialsText]/[documentImages].
  final PlannedChunk? plannedChunk;

  /// Пауза из `Retry-After`, если провайдер её сообщил (TASK 03, требование 5.7).
  ///
  /// Транспорт уже учитывает заголовок для автоматических повторов; здесь
  /// значение нужно UI, чтобы сказать «повторите через N секунд», а не просто
  /// «слишком много запросов».
  final Duration? retryAfter;

  /// Сколько запросов уже сделано по фрагменту (1 — первичный).
  final int attempts;
}

/// Результат генерации (он же данные предпросмотра).
/// Покрытие раздела материала созданными карточками (TASK 5).
///
/// [sectionId] — короткий id раздела (`promptId`), [allocated] — сколько
/// карточек плану выделено, [produced] — сколько принято из ответов,
/// [exhausted] — раздел помечен исчерпанным.
class GenerationSectionCoverage {
  const GenerationSectionCoverage({
    required this.sectionId,
    required this.allocated,
    required this.produced,
    required this.exhausted,
  });

  final String sectionId;
  final int allocated;
  final int produced;
  final bool exhausted;
}

/// Результат запуска генерации.
class GenerationRunResult {
  /// Создаёт результат.
  const GenerationRunResult({
    required this.jobId,
    required this.status,
    required this.cards,
    required this.failures,
    required this.tokensUsed,
    required this.estimatedTokens,
    required this.duplicatesRemoved,
    required this.chunkCount,
    required this.cancelled,
    this.rejectedCards = 0,
    this.fatalErrorCode,
    this.fatalProviderReason,
    this.plan,
    this.calibration = const TokenCalibrationReport.empty(),
    this.recoveryRequestsUsed = 0,
    this.recoveryBudget = 0,
    this.sentDocumentImageIds = const <String>[],
    this.shortfallCards = 0,
    this.skippedBatches = 0,
    this.trimmedCards = 0,
    this.exhaustedSectionIds = const <String>[],
    this.sectionCoverage = const <GenerationSectionCoverage>[],
    this.truncatedChunks = 0,
    this.salvagedCards = 0,
    this.imageResolveFailures = 0,
  });

  /// Идентификатор задания `generation_jobs`.
  final String jobId;

  /// Итоговый статус задания.
  final GenerationJobStatus status;

  /// Полученные карточки (дедуплицированные, в порядке ответов).
  final List<GeneratedCard> cards;

  /// Ошибки фрагментов.
  final List<GenerationChunkFailure> failures;

  /// Фактический расход токенов.
  final int tokensUsed;

  /// Оценка до отправки (для UI).
  final int estimatedTokens;

  /// Сколько дублей отсеяно.
  final int duplicatesRemoved;

  /// Недобор принятых карточек относительно заказанных в партиях (v8).
  final int shortfallCards;

  /// Сколько партий не отправлено из-за исчерпания разделов.
  final int skippedBatches;

  /// Сколько карточек сверх заказанных отброшено (не добавлено в результат).
  final int trimmedCards;

  /// Разделы, помеченные исчерпанными (`source_exhausted`/недобор < 50 %).
  final List<String> exhaustedSectionIds;

  /// Покрытие разделов материала принятыми карточками (TASK 5).
  final List<GenerationSectionCoverage> sectionCoverage;

  /// Сколько партий модель оборвала по лимиту вывода (TASK 04).
  ///
  /// Часть этих партий не потеряна: полные карточки спасены из прерванного
  /// JSON ([salvagedCards]), остаток добирается следующими партиями.
  final int truncatedChunks;

  /// Сколько карточек спасено из оборванных ответов (TASK 04).
  final int salvagedCards;

  /// Сколько раз не удалось разрешить изображения карточки (TASK 04).
  ///
  /// Карточка при этом сохранена без картинки: поиск иллюстраций — best effort.
  final int imageResolveFailures;

  /// Сколько фрагментов обработано.
  final int chunkCount;

  /// Пользователь отменил генерацию.
  final bool cancelled;

  /// Сколько карточек отброшено поштучно (схема/структура) — fix-gen Д6.
  final int rejectedCards;

  /// Fatal-код, после которого пайплайн остановился, но карточки уже получены
  /// (например, ключ отозван после первого фрагмента). Сообщение показывается
  /// пользователю, предпросмотр остаётся доступным.
  final GenerationErrorCode? fatalErrorCode;

  /// Безопасная причина отказа провайдера для [fatalErrorCode].
  final String? fatalProviderReason;

  /// План, по которому выполнялась генерация (D.8, in-memory).
  ///
  /// `null` — старый результат/тест без плана. План нужен предпросмотру:
  /// показать заказ/достижимое число карточек, потери и предупреждения.
  final GenerationPlan? plan;

  /// Калибровка «оценка vs фактический `usage`» за запуск (TASK 03).
  ///
  /// Содержит только машинные значения и отношения; пустой отчёт — не ошибка,
  /// а отсутствие данных (провайдер не сообщил `usage`).
  final TokenCalibrationReport calibration;

  /// Сколько дополнительных запросов потрачено на восстановление.
  final int recoveryRequestsUsed;

  /// Действующий бюджет восстановления для этого запуска (зависит от плана).
  final int recoveryBudget;

  /// id изображений (`img1…`), реально отправленных модели image-частями.
  ///
  /// Для старых результатов/тестов без плана — пусто.
  final List<String> sentDocumentImageIds;

  /// true, если бюджет восстановления был исчерпан (часть фрагментов не
  /// удалось вылечить дроблением).
  bool get recoveryBudgetExhausted =>
      recoveryBudget > 0 && recoveryRequestsUsed >= recoveryBudget;

  /// Предупреждения плана (пусто, если плана нет).
  List<PlanWarningCode> get planWarnings =>
      plan?.validity.warnings ?? const <PlanWarningCode>[];

  /// Запрошенное пользователем число карточек (0 — не задано/нет плана).
  int get requestedCards => plan?.requestedCards ?? 0;

  /// Достижимое по плану число карточек (0 — нет плана).
  int get achievableCards => plan?.achievableCards ?? 0;

  /// true, если генерация шла без материалов (prompt-only, ADR-024).
  bool get promptOnly => plan?.isPromptOnly ?? false;
}

/// Этап прогона генерации v3 (ARCH §2, ADR-050).
///
/// Порядок: `planned → understanding → generating → validating → dedup →
/// replenishing → ready | partial | failed | cancelled`. `replenishing` —
/// этап решения о доборе: оттуда можно вернуться в [generating] (новая
/// партия), завершить прогон ([ready]/[partial]) или упасть/отмениться.
/// [failed] и [cancelled] допустимы с любого незавершённого этапа.
enum GenerationStage {
  /// План построен, работа ещё не началась.
  planned,

  /// Понимание материала (карта знаний/кандидаты утверждений).
  understanding,

  /// Запросы партий к модели.
  generating,

  /// Проверка структуры, цитат и качества карточек.
  validating,

  /// Вердикт на дубли: точный отбрасывается, смысловой помечается.
  dedup,

  /// Решение о доборе: долг, причина и новый бюджет на добор.
  replenishing,

  /// Заказ выполнен: принято не меньше, чем запрошено.
  ready,

  /// Недобор: принято меньше, чем запрошено (число и причина — в журнале).
  partial,

  /// Прогон упал: карточек нет или ошибка фатальна.
  failed,

  /// Прогон отменён пользователем.
  cancelled;

  /// true — этап завершает прогон: дальше переходов нет.
  bool get isTerminal => switch (this) {
    GenerationStage.ready ||
    GenerationStage.partial ||
    GenerationStage.failed ||
    GenerationStage.cancelled => true,
    _ => false,
  };

  /// Статус задания для `generation_jobs.status` (SPEC A5, A8.5 шаг 12).
  ///
  /// Терминальные этапы ложатся в статусы по смыслу: [ready] — `done`,
  /// [partial] — `partial`, [failed] — `error`, [cancelled] — `cancelled`;
  /// промежуточные этапы пишутся как `running`.
  GenerationJobStatus get jobStatus => switch (this) {
    GenerationStage.ready => GenerationJobStatus.done,
    GenerationStage.partial => GenerationJobStatus.partial,
    GenerationStage.failed => GenerationJobStatus.error,
    GenerationStage.cancelled => GenerationJobStatus.cancelled,
    _ => GenerationJobStatus.running,
  };
}

/// Допустимые переходы стейт-машины прогона ([GenerationRunState.advanceTo]).
///
/// Этапы не перескакивают: `understanding` нельзя пропустить, а [ready] и
/// [partial] достижимы только из [replenishing] — после решения о доборе.
/// Терминальные этапы не имеют исходящих переходов. Самопереход запрещён.
const Map<GenerationStage, Set<GenerationStage>> _stageTransitions =
    <GenerationStage, Set<GenerationStage>>{
      GenerationStage.planned: <GenerationStage>{
        GenerationStage.understanding,
        GenerationStage.failed,
        GenerationStage.cancelled,
      },
      GenerationStage.understanding: <GenerationStage>{
        GenerationStage.generating,
        GenerationStage.failed,
        GenerationStage.cancelled,
      },
      GenerationStage.generating: <GenerationStage>{
        GenerationStage.validating,
        GenerationStage.failed,
        GenerationStage.cancelled,
      },
      GenerationStage.validating: <GenerationStage>{
        GenerationStage.dedup,
        GenerationStage.failed,
        GenerationStage.cancelled,
      },
      GenerationStage.dedup: <GenerationStage>{
        GenerationStage.replenishing,
        GenerationStage.failed,
        GenerationStage.cancelled,
      },
      GenerationStage.replenishing: <GenerationStage>{
        GenerationStage.generating,
        GenerationStage.ready,
        GenerationStage.partial,
        GenerationStage.failed,
        GenerationStage.cancelled,
      },
      GenerationStage.ready: <GenerationStage>{},
      GenerationStage.partial: <GenerationStage>{},
      GenerationStage.failed: <GenerationStage>{},
      GenerationStage.cancelled: <GenerationStage>{},
    };

/// Недопустимый переход стейт-машины прогона.
///
/// Бросается вместо «молчаливого» перехода: пропущенный этап или `done` без
/// добора — ошибка программиста, а не сценарий (ARCH §3.2: ложный успех
/// запрещён).
class InvalidGenerationStageTransition implements Exception {
  /// Создаёт исключение пары [from] → [to].
  const InvalidGenerationStageTransition({
    required this.from,
    required this.to,
  });

  /// Этап, с которого пытались уйти.
  final GenerationStage from;

  /// Этап, на который пытались перейти.
  final GenerationStage to;

  @override
  String toString() => 'Недопустимый переход этапа: ${from.name} → ${to.name}';
}

/// Стейт-машина прогона генерации v3 (ARCH §2).
///
/// Неизменяемое состояние: [advanceTo] возвращает новое состояние или бросает
/// [InvalidGenerationStageTransition]. Машина проверяет **форму** пути, а не
/// числа: `ready` при долге не отличить от `ready` без долга — это делает
/// вердикт Completion (S9) по журналу, здесь же невозможно перескочить этап
/// (например, `generating → ready`).
class GenerationRunState {
  /// Состояние на этапе [stage] (возобновление из журнала/теста).
  const GenerationRunState(this.stage);

  /// Начальное состояние: план построен.
  const GenerationRunState.planned() : stage = GenerationStage.planned;

  /// Текущий этап.
  final GenerationStage stage;

  /// true — прогон завершён (дальше переходов нет).
  bool get isTerminal => stage.isTerminal;

  /// Допустимые следующие этапы (пусто у терминальных).
  Set<GenerationStage> get allowedNext =>
      _stageTransitions[stage] ?? const <GenerationStage>{};

  /// true, если переход [next] разрешён из текущего этапа.
  bool canAdvanceTo(GenerationStage next) => allowedNext.contains(next);

  /// Переходит на этап [next]; недопустимый переход — исключение.
  GenerationRunState advanceTo(GenerationStage next) {
    if (!canAdvanceTo(next)) {
      throw InvalidGenerationStageTransition(from: stage, to: next);
    }
    return GenerationRunState(next);
  }

  @override
  String toString() => 'GenerationRunState(${stage.name})';
}
