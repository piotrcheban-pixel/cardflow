import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/ui/generation/generation_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

Future<T> inlineIsolate<T>(Future<T> Function() task) => task();

void main() {
  late FakeDocumentGateway gateway;
  late FakeGenerationRunner runner;
  late FakeApiKeyStore keyStore;
  late FakeGenerationSettingsStore settingsStore;
  late FakeDeckRepository deckRepository;

  setUp(() {
    gateway = FakeDocumentGateway();
    runner = FakeGenerationRunner();
    keyStore = FakeApiKeyStore(<GenerationProvider, String>{
      GenerationProvider.openai: 'test-key',
    });
    settingsStore = FakeGenerationSettingsStore();
    deckRepository = FakeDeckRepository();
  });

  List<Override> overrides() {
    return <Override>[
      documentGatewayProvider.overrideWithValue(gateway),
      fileParsingServiceProvider.overrideWithValue(
        FileParsingService(isolateRunner: inlineIsolate),
      ),
      generationRunnerProvider.overrideWithValue(runner),
      generationCardStoreProvider.overrideWithValue(FakeGenerationCardStore()),
      apiKeyStoreProvider.overrideWithValue(keyStore),
      generationSettingsStoreProvider.overrideWithValue(settingsStore),
      deckRepositoryProvider.overrideWithValue(deckRepository),
    ];
  }

  GenerationRunResult resultWith(List<GeneratedCard> cards) {
    return GenerationRunResult(
      jobId: 'job-1',
      status: GenerationJobStatus.done,
      cards: cards,
      failures: const <GenerationChunkFailure>[],
      tokensUsed: 42,
      estimatedTokens: 100,
      duplicatesRemoved: 0,
      chunkCount: 1,
      cancelled: false,
    );
  }

  Future<void> pumpScreen(WidgetTester tester, {String? deckId}) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides(),
        home: GenerationScreen(deckId: deckId),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> attachTextFile(WidgetTester tester) async {
    gateway.picked = <PickedDocument>[
      const PickedDocument(
        path: '/tmp/лекция.txt',
        name: 'лекция.txt',
        sizeBytes: 30,
      ),
    ];
    gateway.bytesByPath['/tmp/лекция.txt'] = Uint8List.fromList(
      utf8.encode('Материал лекции'),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('рендер: заголовок, зона прикрепления, пожелания, кнопка', (
    tester,
  ) async {
    await pumpScreen(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationAttachHint), findsOneWidget);
    expect(find.text(l10n.generationWishesLabel), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-start')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationFilesEmpty), findsOneWidget);
  });

  testWidgets('пикер: файл разобран, статус и оценка токенов', (tester) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    final l10n = l10nOf(tester);
    expect(gateway.pickCalls, 1);
    expect(gateway.readCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('generation-file-tile-0')),
      findsOneWidget,
    );
    expect(find.text('лекция.txt'), findsOneWidget);
    expect(find.text(l10n.generationFileParsed), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-estimate')),
      findsOneWidget,
    );
    expect(find.textContaining('Примерно'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('generation-start')),
    );
    expect(start.onPressed, isNotNull);
  });

  testWidgets('файл можно убрать', (tester) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-file-remove-0')),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationFilesEmpty), findsOneWidget);
  });

  testWidgets('ошибка файла показывается строкой ARB и не блокирует экран', (
    tester,
  ) async {
    gateway.picked = <PickedDocument>[
      const PickedDocument(
        path: '/tmp/старый.doc',
        name: 'старый.doc',
        sizeBytes: 10,
      ),
    ];
    await pumpScreen(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.parserErrorUnsupportedFormat), findsOneWidget);
  });

  testWidgets('старт без файлов — сообщение ARB', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationNoFilesError), findsOneWidget);
    expect(runner.runCalls, 0);
  });

  testWidgets('старт: запрос с документами и именем колоды из файла', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.result = resultWith(<GeneratedCard>[
      const GeneratedCard(
        front: 'Вопрос',
        back: 'Ответ',
        cardType: CardType.basic,
      ),
    ]);
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();

    expect(runner.runCalls, 1);
    expect(runner.lastRequest, isNotNull);
    expect(runner.lastRequest!.documents, hasLength(1));
    expect(runner.lastRequest!.documents.single.fileName, 'лекция.txt');
    expect(runner.lastRequest!.deckName, 'лекция');
    expect(runner.lastRequest!.targetDeckId, isNull);
    expect(runner.lastRequest!.provider, GenerationProvider.openai);
    expect(runner.lastRequest!.modelId, 'gpt-4o-mini');
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationPreviewTitle), findsOneWidget);
  });

  testWidgets('нет ключа: баннер и переход в настройки', (tester) async {
    keyStore = FakeApiKeyStore();
    await pumpScreen(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationKeyMissing), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-open-settings')),
      findsOneWidget,
    );
  });

  testWidgets('прогресс и отмена: текст фрагмента и отмена токена', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.pending = Completer<GenerationRunResult>();
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pump();

    runner.lastProgress!(
      const GenerationProgress(
        phase: GenerationProgressPhase.sending,
        chunkIndex: 1,
        chunkCount: 3,
      ),
    );
    await tester.pump();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationProgressSending(1, 3)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-cancel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('generation-cancel')));
    await tester.pump();
    expect(runner.lastCancellation, isNotNull);
    expect(runner.lastCancellation!.isCancelled, isTrue);

    runner.pending!.complete(
      const GenerationRunResult(
        jobId: 'job-1',
        status: GenerationJobStatus.cancelled,
        cards: <GeneratedCard>[],
        failures: <GenerationChunkFailure>[],
        tokensUsed: 0,
        estimatedTokens: 10,
        duplicatesRemoved: 0,
        chunkCount: 0,
        cancelled: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.generationCancelled), findsOneWidget);
  });

  testWidgets('ошибка генерации — строка ARB без сырых деталей', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.error = const GenerationException(
      GenerationErrorCode.invalidApiKey,
      details: 'raw-provider-detail',
    );
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationErrorInvalidApiKey), findsOneWidget);
    expect(find.textContaining('raw-provider-detail'), findsNothing);
  });

  testWidgets('целевая колода: имя показывается, поле имени скрыто', (
    tester,
  ) async {
    deckRepository = FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Моя колода', totalCards: 5),
      ],
    );
    await pumpScreen(tester, deckId: 'deck-1');
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationTargetDeck('Моя колода')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-deck-name')),
      findsNothing,
    );
  });
}
