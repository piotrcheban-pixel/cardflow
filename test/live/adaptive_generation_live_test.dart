// Live-испытания адаптивной генерации (TASK 04, раздел 7; запуск — TASK 05).
//
// ВАЖНО: по умолчанию файл не делает ни одного запроса. Каждый сценарий
// пропускается, пока не заданы ЯВНЫЕ переменные окружения:
//
//   CARDFLOW_LIVE_TESTS=1              — разрешение live-прогона
//   CARDFLOW_LIVE_PROVIDER=deepseek    — провайдер (id пресета каталога)
//   CARDFLOW_LIVE_MODEL=deepseek-flash — модель
//   CARDFLOW_LIVE_MAX_REQUESTS=6       — лимит логических запросов
//   CARDFLOW_LIVE_MAX_COST_USD=0.10    — лимит предварительной стоимости
//   CARDFLOW_LIVE_ENABLE_PROMPT_ONLY=1 / _MATERIALS=1 / _IMAGES=1
//   DEEPSEEK_API_KEY=…                 — ключ (значение не печатать)
//
// Прогон: fvm flutter test test/live/adaptive_generation_live_test.dart --tags live
//
// Без CARDFLOW_LIVE_TESTS=1 тесты пропускаются даже при наличии ключа —
// случайный `flutter test` не тратит деньги. Отчёт пишется в
// `build/live/live-runs.jsonl` (числа и машинные коды, без материалов и ключей).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import 'support/live_fixtures.dart';
import 'support/live_harness.dart';
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

  /// Пропуск сценария: глобальный gate → флаг сценария → Vision → стоимость.
  String? skipFor(LiveScenarioPlan plan) {
    if (baseSkip != null) return baseSkip;
    final String? scenarioSkip = config.scenarioSkipReason(plan.kind);
    if (scenarioSkip != null) return scenarioSkip;
    if (plan.requiresVision && !config.vision) {
      return 'нужна Vision-модель: $kLiveVisionVariable=1 или пресет с '
          'supportsVision';
    }
    return plan.costFor(config).blockReason(config);
  }

  /// Общие ожидания для любого сценария: HTTP 200 — не доказательство
  /// качества, поэтому проверяются структура, расход и измеримые дефекты.
  void expectHealthyRun(
    LiveScenarioOutcome outcome, {
    required int maxCards,
    required bool expectMultipleRequests,
  }) {
    final GenerationRunResult result = outcome.result;
    // ignore: avoid_print — evidence в логе прогона: числа без материалов/ключей.
    print(
      'LIVE ${outcome.record.scenario}: status=${result.status.name}, '
      'cards=${result.cards.length}, tokens=${result.tokensUsed}, '
      'requests=${outcome.record.requests}, '
      'input=${outcome.record.actualInputTokens ?? 'unknown'}, '
      'output=${outcome.record.actualOutputTokens ?? 'unknown'}, '
      'cost≈${outcome.record.requests} req, '
      'elapsed=${outcome.elapsed.inMilliseconds} ms',
    );

    expect(result.cards, isNotEmpty, reason: 'ни одной карточки');
    expect(result.cards.length, lessThanOrEqualTo(maxCards));
    for (final card in result.cards) {
      expect(card.front.trim(), isNotEmpty);
      expect(card.back.trim(), isNotEmpty);
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

    // Калибровка: сэмплы есть всегда, факт `usage` — если провайдер сообщил;
    // отсутствие usage фиксируется, а не превращается в 0.
    expect(result.calibration.samples, isNotEmpty);
    // Бюджет соблюдён: ни одного запроса сверх лимита.
    expect(outcome.record.requests, lessThanOrEqualTo(config.maxRequests));
  }

  test(
    'Test A: prompt-only, 3 карточки — запрос, JSON, парсинг, usage, preview',
    () async {
      final LiveHarness harness = LiveHarness.create(
        config: config,
        recorder: recorder,
      );
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById('prompt_only_short')!;

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
        request: GenerationRunRequest(
          documents: const [],
          account: config.account,
          deckName: 'TASK 04 — Test A',
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
      expect(outcome.result.plan, isNotNull);
      expect(outcome.result.plan!.isPromptOnly, isTrue);
      expect(outcome.record.estimatorVersion, isNotNull);
      expect(outcome.record.requestSizeBytes, isNotNull);
      expect(outcome.record.actualInputTokens, isNotNull);
    },
    skip: skipFor(liveScenarioPlanById('prompt_only_short')!),
    timeout: const Timeout(Duration(minutes: 5)),
    tags: <String>['live'],
  );

  test(
    'Test B: prompt-only, 20 карточек — несколько запросов, состояние '
    'продолжения, без дублей',
    () async {
      final LiveHarness harness = LiveHarness.create(
        config: config,
        recorder: recorder,
      );
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById(
        'prompt_only_many_20',
      )!;

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
        request: GenerationRunRequest(
          documents: const [],
          account: config.account,
          deckName: 'TASK 04 — Test B',
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
      // Заметная доля заказа (модель может вернуть меньше в одном фрагменте).
      expect(
        result.cards.length,
        greaterThanOrEqualTo(plan.requestedCards ~/ 2),
      );
    },
    skip: skipFor(liveScenarioPlanById('prompt_only_many_20')!),
    timeout: const Timeout(Duration(minutes: 10)),
    tags: <String>['live'],
  );

  test(
    'Test C: небольшой документ — извлечение, план, соответствие материалу',
    () async {
      final LiveHarness harness = LiveHarness.create(
        config: config,
        recorder: recorder,
      );
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById('small_document')!;
      final document = liveSmallDocument();

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
        request: GenerationRunRequest(
          documents: <ParsedDocument>[document],
          account: config.account,
          deckName: 'TASK 04 — Test C',
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
      expect(result.plan!.isPromptOnly, isFalse);
      expect(
        result.plan!.omitted,
        isEmpty,
        reason: 'материал не должен теряться',
      );
      // Для материалового сценария цитата-источник допустима и ожидаема, но
      // модель не обязана её возвращать: фиксируем факт в отчёте качества.
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
      final LiveHarness harness = LiveHarness.create(
        config: config,
        recorder: recorder,
      );
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById('big_document_30')!;
      final document = liveBigDocument();

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
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
      final LiveHarness harness = LiveHarness.create(
        config: config,
        recorder: recorder,
      );
      addTearDown(harness.close);
      final LiveScenarioPlan plan = liveScenarioPlanById('pdf_with_image')!;
      final document = await livePdfWithImage();
      expect(
        document.images,
        isNotEmpty,
        reason: 'фикстура PDF обязана содержать извлечённое изображение',
      );

      final LiveScenarioOutcome outcome = await harness.run(
        scenario: plan.id,
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
