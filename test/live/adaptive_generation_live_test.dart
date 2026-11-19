// Live-испытания адаптивной генерации (TASK 04–05; запуск — только по
// отдельному разрешению владельца).
//
// ВАЖНО: по умолчанию файл не делает ни одного запроса. Каждый сценарий
// пропускается, пока не заданы ЯВНЫЕ переменные окружения:
//
//   CARDFLOW_LIVE_TESTS=1              — разрешение live-прогона
//   CARDFLOW_LIVE_PROVIDER=deepseek    — провайдер (id пресета каталога)
//   CARDFLOW_LIVE_MODEL=deepseek-flash — модель (актуальный id DeepSeek)
//   CARDFLOW_LIVE_MAX_REQUESTS=20      — лимит ЛОГИЧЕСКИХ запросов на A–C
//   CARDFLOW_LIVE_MAX_COST_USD=0.12    — лимит стоимости на A–C
//   CARDFLOW_LIVE_ENABLE_PROMPT_ONLY=1 / _MATERIALS=1 / _IMAGES=1
//   DEEPSEEK_API_KEY=…                 — ключ (значение не печатать)
//
// Прогон: fvm flutter test test/live/adaptive_generation_live_test.dart --tags live
//
// Без CARDFLOW_LIVE_TESTS=1 тесты пропускаются даже при наличии ключа —
// случайный `flutter test` не тратит деньги. Бюджеты (логические запросы,
// HTTP-обмены, физические попытки, стоимость) — ОБЩИЕ на весь файл: A+B+C
// вместе не могут превысить один лимит. Отчёт пишется в
// `build/live/live-runs.jsonl` (числа и машинные коды, без материалов и ключей).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import 'support/live_budget.dart';
import 'support/live_fixtures.dart';
import 'support/live_harness.dart';
import 'support/live_pricing.dart';
import 'support/live_quality.dart';
import 'support/live_run_report.dart';
import 'support/live_scenarios.dart';
import 'support/live_test_config.dart';

void main() {
  final LiveTestConfig config = LiveTestConfig.fromEnvironment(
    Platform.environment,
  );
  final LiveRunRecorder recorder = LiveRunRecorder(
    reportPath: config.reportPath,
  );
  final String? baseSkip = config.skipReason;

  // Общие на весь файл лимиты: A+B+C делят один бюджет, а не получают по
  // отдельному на каждый тест.
  final LiveRequestBudget logicalBudget = LiveRequestBudget(
    maxRequests: config.maxRequests,
    label: '${config.provider}/${config.model} logical',
  );
  final LiveRequestBudget httpBudget = LiveRequestBudget(
    maxRequests: config.maxRequests * 2,
    label: '${config.provider}/${config.model} http',
  );
  final LivePrice? price = livePriceFor(config.provider, config.model);
  final LiveCostGuard? costGuard =
      price != null && config.maxEstimatedCostUsd > 0
      ? LiveCostGuard(
          price: price,
          maxCostUsd: config.maxEstimatedCostUsd,
          label: '${config.provider}/${config.model}',
        )
      : null;
  final LiveAttemptLimiter attemptLimiter = LiveAttemptLimiter(
    maxAttempts: httpBudget.maxRequests * RetryPolicy().maxAttempts,
    costGuard: costGuard,
  );

  /// Пропуск сценария: глобальный gate → флаг сценария → Vision → стоимость.
  String? skipFor(LiveScenarioPlan plan) {
    if (baseSkip != null) return baseSkip;
    final String? scenarioSkip = config.scenarioSkipReason(plan.kind);
    if (scenarioSkip != null) return scenarioSkip;
    if (!config.isScenarioSelected(plan.id)) {
      return 'Сценарий ${plan.id} не выбран: $kLiveScenariosVariable';
    }
    if (plan.requiresVision && !config.vision) {
      return 'нужна Vision-модель: $kLiveVisionVariable=1 или пресет с '
          'supportsVision';
    }
    return plan.costFor(config).blockReason(config);
  }

  LiveHarness createHarness() {
    return LiveHarness.create(
      config: config,
      recorder: recorder,
      budget: logicalBudget,
      httpBudget: httpBudget,
      attemptLimiter: attemptLimiter,
      costGuard: costGuard,
    );
  }

  /// Карточка проходит ту же проверку, что предпросмотр перед импортом
  /// (`CardDraft.validate`); фактическая запись в drift-БД проверяется
  /// офлайновым интеграционным тестом.
  bool isImportable(GeneratedCard card) {
    final CardDraft draft = CardDraft(
      front: card.front,
      back: card.back,
      cardType: card.cardType,
      tags: card.tags,
    );
    return draft.validate().isEmpty;
  }

  /// Общие ожидания для любого сценария: HTTP 200 — не доказательство
  /// качества, поэтому проверяются структура, расход, бюджеты и измеримые
  /// дефекты.
  void expectHealthyRun(
    LiveScenarioOutcome outcome, {
    required int maxCards,
    required bool expectMultipleRequests,
  }) {
    final GenerationRunResult result = outcome.result;
    final LiveRunRecord record = outcome.record;
    // ignore: avoid_print — evidence в логе прогона: числа без материалов/ключей.
    print(
      'LIVE ${record.scenario}: status=${result.status.name}, '
      'cards=${result.cards.length}, tokens=${result.tokensUsed}, '
      'logical=${record.logicalRequests}, http=${record.httpRequests}, '
      'attempts=${record.httpAttempts ?? 'unknown'}, '
      'retries=${record.retries ?? 'unknown'}, '
      'input=${record.actualInputTokens ?? 'unknown'}, '
      'output=${record.actualOutputTokens ?? 'unknown'}, '
      'cost=${record.actualCostUsd?.toStringAsFixed(5) ?? 'unknown'} USD '
      '(оценка ${record.estimatedCostUsd?.toStringAsFixed(5) ?? 'unknown'}), '
      'elapsed=${outcome.elapsed.inMilliseconds} ms',
    );

    expect(result.cards, isNotEmpty, reason: 'ни одной карточки');
    expect(result.cards.length, lessThanOrEqualTo(maxCards));
    for (final card in result.cards) {
      expect(card.front.trim(), isNotEmpty);
      expect(card.back.trim(), isNotEmpty);
      expect(
        isImportable(card),
        isTrue,
        reason: 'карточка не пройдёт проверку предпросмотра перед импортом',
      );
    }
    expect(result.status, GenerationJobStatus.done);
    expect(result.failures, isEmpty);
    if (expectMultipleRequests) {
      expect(
        result.chunkCount,
        greaterThan(1),
        reason: 'ожидалось несколько запросов плана',
      );
    }
    final LiveCardQualityReport quality = LiveCardQualityReport.evaluate(
      result.cards,
    );
    expect(quality.emptyFront, 0);
    expect(quality.emptyBack, 0);
    expect(
      quality.duplicateCards,
      0,
      reason: 'дедуп пайплайна пропустил дубль',
    );
    expect(quality.tooLongFront, 0);
    expect(quality.tooLongBack, 0);
    expect(quality.tooManyTags, 0);

    // Калибровка: сэмплы есть всегда, факт `usage` — если провайдер сообщил;
    // отсутствие usage фиксируется, а не превращается в 0.
    expect(result.calibration.samples, isNotEmpty);
    // Бюджеты соблюдены: ни одного запроса сверх лимита.
    expect(record.logicalRequests, greaterThan(0));
    expect(record.logicalRequests, lessThanOrEqualTo(config.maxRequests));
    expect(record.httpRequests, lessThanOrEqualTo(record.httpBudgetMax));
    final int? attempts = record.httpAttempts;
    if (attempts != null) {
      expect(
        attempts,
        lessThanOrEqualTo(record.httpBudgetMax * RetryPolicy().maxAttempts),
      );
    }
    final double? spent = record.guardTotalSpentUsd;
    if (spent != null) {
      expect(
        spent,
        lessThanOrEqualTo(config.maxEstimatedCostUsd + 1e-9),
        reason: 'cost guard превысил лимит',
      );
    }
  }

  test(
    'Test A: prompt-only, 5 карточек — запрос, JSON, парсинг, usage, preview',
    () async {
      final LiveHarness harness = createHarness();
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById('prompt_only_short')!;

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
        expectedOutputTokens: plan.outputTokensPerRequest,
        request: GenerationRunRequest(
          documents: const [],
          account: config.account,
          deckName: 'TASK 05 — Test A',
          wishes: liveWishesShort(cards: plan.requestedCards),
          requestedCards: plan.requestedCards,
        ),
      );
      await harness.writeReport();

      expectHealthyRun(
        outcome,
        maxCards: plan.requestedCards,
        expectMultipleRequests: false,
      );
      final GenerationRunResult result = outcome.result;
      expect(outcome.result.plan, isNotNull);
      expect(result.plan!.isPromptOnly, isTrue);
      expect(result.plan!.chunks, hasLength(1));
      expect(result.plan!.chunks.single.limit, plan.requestedCards);
      expect(outcome.record.estimatorVersion, isNotNull);
      expect(outcome.record.requestSizeBytes, isNotNull);
      if (result.cards.length < plan.requestedCards) {
        // Не ошибка провайдера/парсинга: фиксируем достижимое число, а не
        // подменяем его «пятью карточками».
        // ignore: avoid_print
        print(
          'LIVE Test A shortfall: requested=${plan.requestedCards}, '
          'cards=${result.cards.length}, status=${result.status.name}',
        );
      }
    },
    skip: skipFor(liveScenarioPlanById('prompt_only_short')!),
    timeout: const Timeout(Duration(minutes: 5)),
    tags: <String>['live'],
  );

  test(
    'Test B: prompt-only, 40 карточек — несколько запросов, continuity, '
    'без дублей',
    () async {
      final LiveHarness harness = createHarness();
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById(
        'prompt_only_many_40',
      )!;

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
        expectedOutputTokens: plan.outputTokensPerRequest,
        request: GenerationRunRequest(
          documents: const [],
          account: config.account,
          deckName: 'TASK 05 — Test B',
          wishes: liveWishesMany(cards: plan.requestedCards),
          requestedCards: plan.requestedCards,
        ),
      );
      await harness.writeReport();

      expectHealthyRun(
        outcome,
        maxCards: plan.requestedCards,
        expectMultipleRequests: plan.expectsMultipleRequests,
      );
      final GenerationRunResult result = outcome.result;
      expect(result.plan!.isPromptOnly, isTrue);
      // План распределяет заказ целиком: сумма лимитов = заказ.
      final int limits = result.plan!.chunks.fold<int>(
        0,
        (int sum, PlannedChunk chunk) => sum + chunk.limit,
      );
      expect(limits, plan.requestedCards);
      expect(
        result.plan!.chunks.length,
        plan.expectedRequests,
        reason: '7 карточек/запрос при лимите вывода 8192',
      );
      // Continuity: первый запрос без сводки, все последующие — со сводкой
      // уже созданных карточек (TASK 03, D12). Тексты не сохраняются —
      // только факт наличия блока.
      expect(harness.calls.length, greaterThanOrEqualTo(2));
      expect(
        harness.calls.first.hasContinuation,
        isFalse,
        reason: 'первый запрос не должен содержать сводку продолжения',
      );
      for (final LiveCallRecord call in harness.calls.skip(1)) {
        expect(
          call.hasContinuation,
          isTrue,
          reason: 'запрос ${call.index} без continuity-блока',
        );
      }
      // Заметная доля заказа (модель может вернуть меньше в одном фрагменте).
      expect(
        result.cards.length,
        greaterThanOrEqualTo(plan.requestedCards ~/ 2),
      );
      if (result.cards.length < plan.requestedCards) {
        // ignore: avoid_print
        print(
          'LIVE Test B shortfall: requested=${plan.requestedCards}, '
          'cards=${result.cards.length}, status=${result.status.name}, '
          'logical=${outcome.record.logicalRequests}',
        );
      }
    },
    skip: skipFor(liveScenarioPlanById('prompt_only_many_40')!),
    timeout: const Timeout(Duration(minutes: 15)),
    tags: <String>['live'],
  );

  test(
    'Test C: небольшой документ — извлечение, план, материал, importable',
    () async {
      final LiveHarness harness = createHarness();
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById('small_document')!;
      // Production-парсер TXT: извлечение текста и границы разделов реальные,
      // а не заранее собранный ParsedDocument.
      final ParsedDocument document = await liveSmallDocumentParsed();

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
        expectedOutputTokens: plan.outputTokensPerRequest,
        request: GenerationRunRequest(
          documents: <ParsedDocument>[document],
          account: config.account,
          deckName: 'TASK 05 — Test C',
          wishes:
              'Сделай ${plan.requestedCards} карточки по этому материалу. '
              'Опирайся только на текст документа.',
          requestedCards: plan.requestedCards,
        ),
      );
      await harness.writeReport();

      expectHealthyRun(
        outcome,
        maxCards: plan.requestedCards,
        expectMultipleRequests: plan.expectsMultipleRequests,
      );
      final GenerationRunResult result = outcome.result;
      // Prompt-only путь не должен включаться при наличии документа.
      expect(result.plan!.isPromptOnly, isFalse);
      expect(
        result.plan!.omitted,
        isEmpty,
        reason: 'материал не должен теряться',
      );
      // Связи document/section/unit сохранены в плане (id вида `doc:<файл>#…`).
      final List<UnitSpan> units = result.plan!.chunks
          .expand((PlannedChunk chunk) => chunk.units)
          .toList(growable: false);
      expect(units, isNotEmpty, reason: 'план не содержит единиц документа');
      expect(
        units.every((UnitSpan unit) => unit.unitId.startsWith('doc:')),
        isTrue,
        reason: 'единицы документа обязаны иметь id `doc:`',
      );
      // Цитата-источник допустима и ожидаема, но модель не обязана её
      // возвращать: фиксируем факт в отчёте качества.
      final LiveCardQualityReport quality = LiveCardQualityReport.evaluate(
        result.cards,
      );
      // ignore: avoid_print
      print('LIVE quality ${plan.id}: ${quality.toMarkdown()}');
    },
    skip: skipFor(liveScenarioPlanById('small_document')!),
    timeout: const Timeout(Duration(minutes: 5)),
    tags: <String>['live'],
  );

  test(
    'Test D: большой документ — адаптивное дробление, порядок, частичный успех',
    () async {
      final LiveHarness harness = createHarness();
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById('big_document_30')!;
      final ParsedDocument document = liveBigDocument();

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
        expectedOutputTokens: plan.outputTokensPerRequest,
        request: GenerationRunRequest(
          documents: <ParsedDocument>[document],
          account: config.account,
          deckName: 'TASK 04 — Test D',
          wishes:
              'Сделай ${plan.requestedCards} карточек по конспекту, '
              'не пропускай разделы, порядок сохрани.',
          requestedCards: plan.requestedCards,
        ),
      );
      await harness.writeReport();

      expectHealthyRun(
        outcome,
        maxCards: plan.requestedCards,
        expectMultipleRequests: plan.expectsMultipleRequests,
      );
      final GenerationRunResult result = outcome.result;
      expect(result.plan!.isPromptOnly, isFalse);
      expect(result.plan!.chunks.length, greaterThan(1));
      expect(result.plan!.omitted, isEmpty);
      // Порядок фрагментов сохраняется: индексы идут 1..N без пропусков.
      for (var index = 0; index < result.plan!.chunks.length; index++) {
        expect(result.plan!.chunks[index].index, index + 1);
      }
    },
    skip: skipFor(liveScenarioPlanById('big_document_30')!),
    timeout: const Timeout(Duration(minutes: 15)),
    tags: <String>['live'],
  );

  test(
    'Test E: PDF с изображением — image-части, каталог, статусы изображений',
    () async {
      final LiveHarness harness = createHarness();
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById('pdf_with_image')!;
      final ParsedDocument document = await livePdfWithImage();
      expect(
        document.images,
        isNotEmpty,
        reason: 'фикстура PDF обязана содержать извлечённое изображение',
      );

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
        expectedOutputTokens: plan.outputTokensPerRequest,
        request: GenerationRunRequest(
          documents: <ParsedDocument>[document],
          account: config.account,
          deckName: 'TASK 04 — Test E',
          wishes: 'Сделай ${plan.requestedCards} карточки по схеме и тексту.',
          requestedCards: plan.requestedCards,
        ),
        imageCount: plan.images,
      );
      await harness.writeReport();

      expectHealthyRun(
        outcome,
        maxCards: plan.requestedCards,
        expectMultipleRequests: false,
      );
      final GenerationRunResult result = outcome.result;
      expect(
        result.sentDocumentImageIds,
        isNotEmpty,
        reason: 'изображение документа должно уйти image-частью (Vision)',
      );
      final List<PlannedImage> images = result.plan!.images;
      expect(images, isNotEmpty);
      expect(
        images.any((PlannedImage image) => image.sentToModel),
        isTrue,
        reason: 'ни одно изображение не передано модели',
      );
    },
    skip: skipFor(liveScenarioPlanById('pdf_with_image')!),
    timeout: const Timeout(Duration(minutes: 5)),
    tags: <String>['live'],
  );
}
