/// Production-проводка пути v3: `GenerationRunRequest` → тонкий фасад
/// (TASK «Срез 11», часть 3, п. 8–10).
///
/// Класс собирает **существующие** реализации портов, ничего не переписывая:
/// - Understanding — [UnderstandingService] с HTTP-вызовом
///   [HttpKnowledgeMapCaller] (адаптеры + транспорт + `RetryPolicy`) и кэшем
///   карт на БД (`DriftKnowledgeMapCache`, срез 8);
/// - Generation — [AdapterCardsBatchPort] поверх тех же адаптеров;
/// - Replenish — [ReplenishStage] с часами и политикой этапа;
/// - Persistence — `GenerationRunCardSink` (журнал запуска, срез 8) и импорт
///   черновиков в колоду `importRunCards`.
///
/// На вход раннера приходит тот же `GenerationRunRequest`, что у legacy-пути:
/// материалы превращаются в `Document` (`ContentModelBuilder`) — несколько
/// файлов становятся одним документом с разделами всех файлов (границы
/// сдвинуты), тема без файлов идёт prompt-only. На выходе —
/// `GenerationRunResult` с [GenerationReport]: предпросмотр берёт «принято N из
/// M», причины недобора, покрытие единиц и расход токенов из отчёта, а не из
/// счётчиков экрана (п. 9).
///
/// Ограничения пути (осознанные, не маскируются): отмена проверяется **между**
/// запросами (`CancellationSignal` не пробрасывается в `LlmPort` среза 5);
/// байты изображений карточек в черновик не пишутся (L220); несколько файлов
/// теряют `source_file` карточки (имя колоды и разделы сохраняются).
library;

import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/api/generation/cards_batch_port.dart';
import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_v3_facade.dart';
import 'package:cardflow/api/generation/http_knowledge_map_caller.dart';
import 'package:cardflow/api/generation/understanding_service.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/prompts/cards_prompt.dart';
import 'package:cardflow/api/prompts/understanding_prompt.dart';
import 'package:cardflow/data/generation/drift_generation_run_store.dart';
import 'package:cardflow/data/generation/drift_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/completion_verdict.dart';
import 'package:cardflow/domain/generation/generation_card_limit.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Импорт черновиков прогона в колоду: `(runId, deckId, deckName) → сколько`.
typedef RunCardsImport = Future<int> Function(
  String runId,
  String? deckId,
  String deckName,
);

/// Путь v3 для production-раннера (`GenerationV3Path`).
class GenerationV3PathRunner {
  /// Создаёт проводку; все зависимости — существующие реализации слоёв.
  GenerationV3PathRunner({
    required this.apiKeyStore,
    required this.transport,
    required this.runStore,
    required this.knowledgeMapCache,
    required this.importer,
    this.clock = const SystemClock(),
    this.contentBuilder = const ContentModelBuilder(),
    this.replenishPolicy = const ReplenishPolicy(),
    this.mapOutputTokens = kDefaultMapOutputTokens,
    this.outputTokensPerCard = kDefaultOutputTokensPerCard,
    this.promptVersions = const <String, String>{
      'understanding': understandingPromptVersion,
      'generating': cardsPromptVersion,
      'replenishing': cardsPromptVersion,
    },
  });

  /// Ключи провайдеров (значение в логи не попадает).
  final ApiKeyStore apiKeyStore;

  /// HTTP-транспорт генерации (таймауты, отмена, redaction).
  final GenerationTransport transport;

  /// Журнал прогона на БД (`generation_jobs` + черновики, срез 8).
  final DriftGenerationRunStore runStore;

  /// Кэш карты знаний на БД: повторный материал не платит за Understanding.
  final DriftKnowledgeMapCache knowledgeMapCache;

  /// Импорт черновиков прогона в колоду.
  final RunCardsImport importer;

  /// Часы прогона.
  final Clock clock;

  /// Сборщик `ContentModel` из `ParsedDocument`.
  final ContentModelBuilder contentBuilder;

  /// Политика добора (проходы, попытки на слот, предохранители).
  final ReplenishPolicy replenishPolicy;

  /// Лимит вывода Understanding (`max_tokens`); по нему же делятся обрывы.
  final int mapOutputTokens;

  /// Оценка вывода карточки при упаковке батчей.
  final int outputTokensPerCard;

  /// Версии промптов по этапам (в журнал и отчёт).
  final Map<String, String> promptVersions;

  /// Выполняет прогон v3 для запроса раннера.
  ///
  /// [runId] — id задания (`generation_jobs`), созданного раннером заранее.
  Future<GenerationRunResult> run(
    GenerationRunRequest request, {
    required String runId,
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  }) async {
    final ProviderAccount account = request.account;
    final ModelProfile profile = modelProfileOrDefault(account.modelId);
    final DateTime startedAt = clock.now();
    await runStore.openRun(
      runId: runId,
      stage: GenerationStage.planned,
      now: startedAt,
      provider: account.id,
      model: account.modelId,
      promptVersions: promptVersions,
    );

    try {
      final AdapterCardsBatchPort port = AdapterCardsBatchPort(
        transport: transport,
        apiKeyStore: apiKeyStore,
      );
      final HttpKnowledgeMapCaller mapCaller = HttpKnowledgeMapCaller(
        transport: transport,
        apiKeyStore: apiKeyStore,
        account: account,
        maxOutputTokens: mapOutputTokens,
      );
      final UnderstandingService understanding = UnderstandingService(
        caller: mapCaller,
        cache: knowledgeMapCache,
        maxOutputTokens: mapOutputTokens,
      );
      final GenerationRunCardSink sink = GenerationRunCardSink(
        store: runStore,
        runId: runId,
        clock: clock.now,
      );
      final GenerationV3Facade facade = GenerationV3Facade(
        engine: CardsBatchEngine(
          port: port,
          account: account,
          sink: sink,
          promptVersion: cardsPromptVersion,
        ),
        replenish: ReplenishStage(
          port: port,
          account: account,
          clock: clock,
          policy: replenishPolicy,
          outputTokensPerCard: outputTokensPerCard,
        ),
        profile: profile,
        understanding: understanding.build,
        sink: sink,
        importer: (String id) =>
            importer(id, request.targetDeckId, request.deckName),
        promptVersions: promptVersions,
        outputTokensPerCard: outputTokensPerCard,
      );

      final Document? document = documentOf(request);
      final GenerationV3Run run = await facade.run(
        runId: runId,
        requestedCards:
            request.requestedCards ?? requestedCardCount(request.wishes),
        document: document,
        theme: document == null ? request.wishes : null,
        cancellation: cancellation == null
            ? null
            : _CancellationSignal(cancellation),
        startedAt: startedAt,
      );
      await runStore.saveStage(runId, run.report.stage, now: clock.now());
      // Единицы карты — в журнал прогона: восстановление после перезапуска
      // продолжит с генерации, а не с понимания (срез 8).
      await runStore.openRun(
        runId: runId,
        stage: run.report.stage,
        now: clock.now(),
        units: run.map.units,
        provider: account.id,
        model: account.modelId,
        promptVersions: promptVersions,
      );
      onProgress?.call(
        GenerationProgress(
          phase: GenerationProgressPhase.receiving,
          cards: run.acceptedCards,
        ),
      );
      return runResultOf(run: run, requestedCards: run.report.requested);
    } on Object {
      await _markFailedBestEffort(runId);
      rethrow;
    }
  }

  /// Материал запроса → `Document` (несколько файлов — одним документом).
  ///
  /// Документ нужен гейту (цитата по offsets) и Understanding; без материалов
  /// возвращается `null` — тогда путь prompt-only (тема в пожеланиях).
  Document? documentOf(GenerationRunRequest request) {
    final List<ParsedDocument> documents = request.documents;
    if (documents.isEmpty) return null;
    if (documents.length == 1) {
      return contentBuilder.build(documents.single);
    }
    final StringBuffer buffer = StringBuffer();
    final List<ParsedSection> sections = <ParsedSection>[];
    for (final ParsedDocument document in documents) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      final int base = buffer.length;
      buffer.write(document.text);
      for (final ParsedSection section in document.sections) {
        sections.add(
          ParsedSection(
            start: base + section.start,
            end: base + section.end,
            title: section.title,
          ),
        );
      }
    }
    final ParsedDocument combined = ParsedDocument(
      format: documents.first.format,
      fileName: <String>[
        for (final ParsedDocument doc in documents) doc.fileName,
      ].join(' + '),
      text: buffer.toString(),
      sections: sections,
    );
    return contentBuilder.build(combined);
  }

  /// Итог прогона v3 в форме результата раннера (п. 9).
  ///
  /// Числа — из отчёта: «принято N из M», причины недобора и расход токенов
  /// предпросмотр читает из [GenerationRunResult.report], а не из счётчиков.
  GenerationRunResult runResultOf({
    required GenerationV3Run run,
    required int requestedCards,
  }) {
    final GenerationReport report = run.report;
    final int tokensUsed = <int>[
      for (final TokenUsage usage in report.tokensByStage.values)
        ?usage.totalTokens,
    ].fold<int>(0, (int sum, int value) => sum + value);
    return GenerationRunResult(
      jobId: run.runId,
      status: report.stage.jobStatus,
      cards: run.acceptedCards,
      // Причины отсутствия карты знаний — в отчёте (`understandingFailures`):
      // предпросмотр показывает их отдельной строкой, а не как «упавший
      // фрагмент» генерации.
      failures: const <GenerationChunkFailure>[],
      tokensUsed: tokensUsed,
      estimatedTokens: 0,
      duplicatesRemoved: report.duplicates,
      chunkCount: run.plan.batches.length,
      cancelled: report.stage == GenerationStage.cancelled,
      rejectedCards: report.invalid,
      shortfallCards: report.remaining,
      verdict: CompletionVerdict.fromReport(report),
      report: report,
    );
  }

  /// Пометить прогон сбойным, не скрывая исходную ошибку.
  Future<void> _markFailedBestEffort(String runId) async {
    try {
      await runStore.saveStage(runId, GenerationStage.failed, now: clock.now());
    } on Object {
      // Сбой журнала не должен подменять причину сбоя генерации: исходная
      // ошибка уходит вызывающему слою как есть.
    }
  }
}

/// Сигнал отмены домена поверх отмены UI.
class _CancellationSignal implements CancellationSignal {
  const _CancellationSignal(this._cancellation);

  final GenerationCancellation _cancellation;

  @override
  bool get isCancelled => _cancellation.isCancelled;
}
