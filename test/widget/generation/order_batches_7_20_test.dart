import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/generation/generation_preview_screen.dart';
import 'package:cardflow/ui/generation/generation_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/settings_fakes.dart';

/// Разбор файлов в тесте — без изолята (детерминированно).
Future<T> inlineIsolate<T>(Future<T> Function() task) => task();

/// Итерация 7.20: интерфейс показывает заказ пользователя, число партий и
/// распределение, а нехватку материала — отдельно от бюджета модели.
void main() {
  late FakeDocumentGateway gateway;
  late FakeGenerationRunner runner;
  late FakeApiKeyStore keyStore;
  late FakeProviderAccountsStore accountsStore;
  late FakeDeckRepository deckRepository;

  setUp(() {
    gateway = FakeDocumentGateway();
    runner = FakeGenerationRunner();
    keyStore = FakeApiKeyStore(<String, String>{'deepseek': 'sk-deepseek'});
    accountsStore = FakeProviderAccountsStore(
      ProviderAccounts.empty.withAccount(
        testProviderAccount(modelId: 'deepseek-chat'),
      ),
    );
    deckRepository = FakeDeckRepository();
  });

  List<Override> overrides() => <Override>[
    documentGatewayProvider.overrideWithValue(gateway),
    fileParsingServiceProvider.overrideWithValue(
      FileParsingService(isolateRunner: inlineIsolate),
    ),
    generationRunnerProvider.overrideWithValue(runner),
    generationCardStoreProvider.overrideWithValue(FakeGenerationCardStore()),
    apiKeyStoreProvider.overrideWithValue(keyStore),
    providerAccountsStoreProvider.overrideWithValue(accountsStore),
    deckRepositoryProvider.overrideWithValue(deckRepository),
    appSettingsStoreProvider.overrideWithValue(FakeAppSettingsStore()),
  ];

  /// Лекция из [repetitions] повторений: её мягкая ёмкость измеряется той же
  /// эвристикой ADR-040, что и в плане.
  String lectureText(int repetitions) => List<String>.filled(
    repetitions,
    'Фотосинтез — это процесс преобразования световой энергии.',
  ).join(' ');

  int capacityOf(String text) =>
      SectionFeatures.of(title: '', text: text).capacity;

  Future<void> attachLecture(
    WidgetTester tester, {
    required int repetitions,
  }) async {
    gateway.picked = <PickedDocument>[
      const PickedDocument(
        path: '/tmp/лекция.txt',
        name: 'лекция.txt',
        sizeBytes: 30,
      ),
    ];
    gateway.bytesByPath['/tmp/лекция.txt'] = Uint8List.fromList(
      utf8.encode(lectureText(repetitions)),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      appWithHome(overrides: overrides(), home: const GenerationScreen()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterCards(WidgetTester tester, String value) async {
    final Finder field = find.byKey(
      const ValueKey<String>('generation-cards-count'),
    );
    await tester.scrollUntilVisible(
      field,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Future<void> expandDetails(WidgetTester tester) async {
    final Finder details = find.byKey(
      const ValueKey<String>('generation-plan-details'),
    );
    await tester.scrollUntilVisible(
      details,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  String textOf(WidgetTester tester, String id) =>
      tester.widget<Text>(find.byKey(ValueKey<String>(id))).data!;

  testWidgets('заказ 40: «Запрошено: 40 карточек», партии и распределение', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester);
    await attachLecture(tester, repetitions: 1200);
    await enterCards(tester, '40');

    final Finder requested = find.byKey(
      const ValueKey<String>('generation-plan-requested'),
    );
    // Строка у поля (ревью 7.20, R3): значение пользователя видно сразу.
    await tester.scrollUntilVisible(
      requested,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      textOf(tester, 'generation-plan-requested'),
      'Запрошено: 40 карточек',
    );
    final Finder previewFinder = find.byKey(
      const ValueKey<String>('generation-plan-preview'),
    );
    await tester.scrollUntilVisible(
      previewFinder,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    final String preview = textOf(tester, 'generation-plan-preview');
    expect(preview, contains('запрошено — 40'));
    expect(preview, contains('в плане — 40'));
    // Бюджет одного ответа компенсируется партиями — ложного сообщения нет.
    expect(find.textContaining('бюджета модели не хватает'), findsNothing);
    expect(
      find.textContaining('Запрошено 40 карточек, план может выдать'),
      findsNothing,
    );

    await expandDetails(tester);
    expect(textOf(tester, 'plan-detail-cards-requested'), '40');
    expect(textOf(tester, 'plan-detail-cards-planned'), '40');
    expect(textOf(tester, 'plan-detail-cards-per-batch'), '22');
    expect(textOf(tester, 'plan-detail-batch-sizes'), '22, 18');
    expect(textOf(tester, 'plan-detail-batches'), '2');
  });

  testWidgets('нехватка материала показана отдельно от бюджета модели', (
    WidgetTester tester,
  ) async {
    final int capacity = capacityOf(lectureText(400));
    expect(capacity, lessThan(40), reason: 'фикстура должна быть малой');
    await pumpScreen(tester);
    await attachLecture(tester, repetitions: 400);
    await enterCards(tester, '40');

    final Finder warning = find.byKey(
      const ValueKey<String>('generation-plan-warning-0'),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('generation-plan-preview')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(warning, findsOneWidget);
    final String message = tester.widget<Text>(warning).data!;
    expect(message, contains('Материала хватает примерно на $capacity'));
    expect(message, contains('из 40'));
    expect(message, isNot(contains('бюджета модели')));
    // Заказ не подменяется: в плане ровно 40 карточек.
    expect(textOf(tester, 'generation-plan-preview'), contains('в плане — 40'));
  });

  testWidgets(
    'предпросмотр результата: созданное количество и причина недобора',
    (WidgetTester tester) async {
      final ParsedDocument document = ParsedDocument(
        format: DocumentFormat.txt,
        fileName: 'лекция.txt',
        text: lectureText(1200),
        sections: <ParsedSection>[
          ParsedSection(start: 0, end: lectureText(1200).length),
        ],
      );
      final ProviderAccount account = testProviderAccount(
        modelId: 'deepseek-chat',
      );
      final GenerationPlan plan = const GenerationPlanBuilder().build(
        documents: <ParsedDocument>[document],
        capabilities: const ModelCapabilities(
          contextWindowTokens: 128000,
          contextSource: CapabilitySource.officialCatalog,
          maxOutputTokens: 8192,
        ),
        requestedCards: 40,
      );
      final GenerationRunResult result = GenerationRunResult(
        jobId: 'job-1',
        status: GenerationJobStatus.done,
        cards: const <GeneratedCard>[
          GeneratedCard(
            front: 'Единственная карточка',
            back: 'Ответ',
            cardType: CardType.basic,
          ),
        ],
        failures: const <GenerationChunkFailure>[],
        tokensUsed: 100,
        estimatedTokens: 200,
        duplicatesRemoved: 0,
        chunkCount: plan.chunks.length,
        cancelled: false,
        plan: plan,
        shortfallCards: 39,
        skippedBatches: 2,
        exhaustedSectionIds: const <String>['doc:лекция.txt#0'],
      );
      await tester.pumpWidget(
        appWithHome(
          overrides: overrides(),
          home: GenerationPreviewScreen(
            request: GenerationRunRequest(
              documents: <ParsedDocument>[document],
              account: account,
              deckName: 'Новая колода',
              requestedCards: 40,
            ),
            result: result,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder exhausted = find.byKey(
        const ValueKey<String>('generation-preview-material-exhausted'),
      );
      expect(exhausted, findsOneWidget);
      expect(
        tester.widget<Text>(exhausted).data,
        'Материал исчерпан: создано 1 карточек из 40. '
        'Оставшиеся партии остановлены — карточки не выдумывались.',
      );
      // Требование §4: запрошенное число видно и в предпросмотре.
      expect(
        find.byKey(const ValueKey<String>('generation-preview-plan-warning')),
        findsNothing,
        reason: 'план запросил весь заказ — предупреждать не о чем',
      );
    },
  );

  testWidgets('сбой партии не выдаётся за исчерпание материала', (
    WidgetTester tester,
  ) async {
    // Ревью 7.20 (R2): недобор из-за упавших партий (failures) не должен
    // показываться как «материал исчерпан» — причиной считается только
    // shortfallCards/skippedBatches.
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[
        ParsedDocument(
          format: DocumentFormat.txt,
          fileName: 'лекция.txt',
          text: lectureText(1200),
          sections: <ParsedSection>[
            ParsedSection(start: 0, end: lectureText(1200).length),
          ],
        ),
      ],
      capabilities: const ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.officialCatalog,
        maxOutputTokens: 8192,
      ),
      requestedCards: 40,
    );
    final GenerationRunResult result = GenerationRunResult(
      jobId: 'job-2',
      status: GenerationJobStatus.partial,
      cards: const <GeneratedCard>[
        GeneratedCard(
          front: 'Одна карточка',
          back: 'Ответ',
          cardType: CardType.basic,
        ),
      ],
      failures: <GenerationChunkFailure>[
        GenerationChunkFailure(
          chunkIndex: 2,
          code: GenerationErrorCode.network,
          materialsText: 'материал',
          limit: 18,
        ),
      ],
      tokensUsed: 100,
      estimatedTokens: 200,
      duplicatesRemoved: 0,
      chunkCount: plan.chunks.length,
      cancelled: false,
      plan: plan,
    );
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides(),
        home: GenerationPreviewScreen(
          request: GenerationRunRequest(
            documents: const <ParsedDocument>[],
            account: testProviderAccount(modelId: 'deepseek-chat'),
            deckName: 'Новая колода',
            requestedCards: 40,
          ),
          result: result,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('generation-preview-material-exhausted'),
      ),
      findsNothing,
      reason: 'сбой сети — не исчерпание материала',
    );
    expect(
      find.byKey(const ValueKey<String>('generation-preview-partial')),
      findsOneWidget,
    );
  });

  test('тексты предупреждений не приписывают недобор бюджету модели', () {
    // Проверка ARB-контракта: сообщение об исчерпании материала говорит о
    // материале, а `requestedAbovePlan` — о содержательных разделах.
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('ru'));
    expect(
      l10n.generationPlanMaterialCapacityBelowRequested(32, 40),
      contains('Материала хватает примерно на 32 карточек из 40'),
    );
    expect(
      l10n.generationPlanMaterialCapacityBelowRequested(32, 40),
      isNot(contains('бюджета модели')),
    );
    expect(
      l10n.generationPlanRequestedAboveAchievable(40, 0),
      isNot(contains('бюджета модели')),
    );
    expect(l10n.generationPlanRequestedCount(40), 'Запрошено: 40 карточек');
  });
}
