import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/ui/generation/generation_preview_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  late FakeGenerationRunner runner;
  late FakeGenerationCardStore store;

  setUp(() {
    runner = FakeGenerationRunner();
    store = FakeGenerationCardStore();
  });

  GenerationRunRequest request() {
    return const GenerationRunRequest(
      documents: <ParsedDocument>[],
      provider: GenerationProvider.openai,
      modelId: 'gpt-4o',
      deckName: 'Новая колода',
    );
  }

  GenerationRunResult resultWith({
    List<GeneratedCard>? cards,
    List<GenerationChunkFailure>? failures,
    int duplicatesRemoved = 0,
    int tokensUsed = 42,
  }) {
    return GenerationRunResult(
      jobId: 'job-1',
      status: failures == null || failures.isEmpty
          ? GenerationJobStatus.done
          : GenerationJobStatus.partial,
      cards:
          cards ??
          <GeneratedCard>[
            const GeneratedCard(
              front: 'Первый вопрос',
              back: 'Первый ответ',
              cardType: CardType.basic,
              tags: <String>['тег'],
            ),
            const GeneratedCard(
              front: 'Второй вопрос',
              back: 'Второй ответ',
              cardType: CardType.basic,
            ),
          ],
      failures: failures ?? const <GenerationChunkFailure>[],
      tokensUsed: tokensUsed,
      estimatedTokens: 100,
      duplicatesRemoved: duplicatesRemoved,
      chunkCount: 2,
      cancelled: false,
    );
  }

  List<Override> overrides() {
    return <Override>[
      generationRunnerProvider.overrideWithValue(runner),
      generationCardStoreProvider.overrideWithValue(store),
      deckRepositoryProvider.overrideWithValue(FakeDeckRepository()),
    ];
  }

  Future<void> pumpPreview(
    WidgetTester tester,
    GenerationRunResult result, {
    GenerationRunRequest? runRequest,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides(),
        home: GenerationPreviewScreen(
          request: runRequest ?? request(),
          result: result,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('рендер: карточки, выбор, дубли и токены', (tester) async {
    await pumpPreview(
      tester,
      resultWith(duplicatesRemoved: 2, tokensUsed: 42),
    );
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationPreviewTitle), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text('Второй вопрос'), findsOneWidget);
    expect(find.text(l10n.generationPreviewSelected(2, 2)), findsOneWidget);
    expect(find.text(l10n.generationDuplicatesRemoved(2)), findsOneWidget);
    expect(find.text(l10n.generationTokensUsed(42)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-import-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('generation-preview-import-selected')),
      findsOneWidget,
    );
  });

  testWidgets('снятие чекбокса: счётчик и импорт только выбранных', (
    tester,
  ) async {
    await pumpPreview(tester, resultWith());
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-checkbox-1')),
    );
    await tester.pump();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationPreviewSelected(1, 2)), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-import-selected')),
    );
    await tester.pumpAndSettle();

    expect(store.importedCards, hasLength(1));
    expect(store.importedCards.single, hasLength(1));
    expect(store.importedCards.single.single.front, 'Первый вопрос');
    expect(store.lastJobId, 'job-1');
    expect(store.lastDeckName, 'Новая колода');
    expect(store.lastDeckId, isNull);
  });

  testWidgets('инлайн-редактирование: правки уходят в импорт', (tester) async {
    await pumpPreview(tester, resultWith());
    await tester.enterText(
      find.byKey(const ValueKey<String>('generation-preview-front-0')),
      'Исправленный вопрос',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('generation-preview-back-0')),
      'Исправленный ответ',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-import-all')),
    );
    await tester.pumpAndSettle();

    expect(store.importedCards, hasLength(1));
    final imported = store.importedCards.single;
    expect(imported, hasLength(2));
    expect(imported[0].front, 'Исправленный вопрос');
    expect(imported[0].back, 'Исправленный ответ');
  });

  testWidgets('импорт всех игнорирует снятые чекбоксы', (tester) async {
    await pumpPreview(tester, resultWith());
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-checkbox-0')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-import-all')),
    );
    await tester.pumpAndSettle();
    expect(store.importedCards.single, hasLength(2));
  });

  testWidgets('пустой фронт у выбранной карточки — импорт не выполняется', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      resultWith(
        cards: <GeneratedCard>[
          const GeneratedCard(
            front: '',
            back: 'Ответ',
            cardType: CardType.basic,
          ),
        ],
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-import-all')),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationPreviewValidationError), findsOneWidget);
    expect(store.importedCards, isEmpty);
  });

  testWidgets('частичный успех: ошибки фрагментов и повтор', (tester) async {
    final failure = GenerationChunkFailure(
      chunkIndex: 2,
      code: GenerationErrorCode.network,
      materialsText: 'второй',
      limit: 10,
    );
    final first = resultWith(
      failures: <GenerationChunkFailure>[failure],
      cards: <GeneratedCard>[
        const GeneratedCard(
          front: 'Первый вопрос',
          back: 'Первый ответ',
          cardType: CardType.basic,
        ),
      ],
    );
    await pumpPreview(tester, first);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.generationFailuresTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-failure-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('generation-preview-retry-failed')),
      findsOneWidget,
    );

    runner.retryResult = resultWith(
      cards: <GeneratedCard>[
        const GeneratedCard(
          front: 'Первый вопрос',
          back: 'Первый ответ',
          cardType: CardType.basic,
        ),
        const GeneratedCard(
          front: 'Третий вопрос',
          back: 'Третий ответ',
          cardType: CardType.basic,
        ),
      ],
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-retry-failed')),
    );
    await tester.pumpAndSettle();

    expect(runner.retryCalls, 1);
    expect(runner.lastPrevious, first);
    expect(find.text('Третий вопрос'), findsOneWidget);
    expect(find.text(l10n.generationFailuresTitle), findsNothing);
  });

  testWidgets('пустой результат — сообщение ARB', (tester) async {
    await pumpPreview(
      tester,
      resultWith(cards: const <GeneratedCard>[]),
    );
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationPreviewEmpty), findsOneWidget);
  });
}
