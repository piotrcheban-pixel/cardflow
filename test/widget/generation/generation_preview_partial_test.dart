import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/ui/generation/generation_preview_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Предпросмотр при частичном успехе (fix-gen, Д6) и управление картинкой (Д3).
void main() {
  late FakeGenerationRunner runner;
  late FakeGenerationCardStore store;

  setUp(() {
    runner = FakeGenerationRunner();
    store = FakeGenerationCardStore();
  });

  GenerationRunRequest request() {
    return GenerationRunRequest(
      documents: const <ParsedDocument>[],
      account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
      deckName: 'Новая колода',
    );
  }

  GenerationRunResult resultWith({
    required List<GeneratedCard> cards,
    List<GenerationChunkFailure> failures = const <GenerationChunkFailure>[],
    int rejectedCards = 0,
  }) {
    return GenerationRunResult(
      jobId: 'job-fix-gen',
      status: failures.isEmpty
          ? GenerationJobStatus.done
          : GenerationJobStatus.partial,
      cards: cards,
      failures: failures,
      tokensUsed: 42,
      estimatedTokens: 100,
      duplicatesRemoved: 0,
      chunkCount: failures.length + 2,
      cancelled: false,
      rejectedCards: rejectedCards,
    );
  }

  Future<void> pumpPreview(
    WidgetTester tester,
    GenerationRunResult result,
  ) async {
    final List<Override> overrides = <Override>[
      generationRunnerProvider.overrideWithValue(runner),
      generationCardStoreProvider.overrideWithValue(store),
      deckRepositoryProvider.overrideWithValue(FakeDeckRepository()),
    ];
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides,
        home: GenerationPreviewScreen(request: request(), result: result),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton importAllButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('generation-preview-import-all')),
    );
  }

  testWidgets(
    '2 успешных фрагмента + 1 упавший: импорт активен, колода создаётся, '
    'ошибка видна списком',
    (tester) async {
      final failure = GenerationChunkFailure(
        chunkIndex: 3,
        code: GenerationErrorCode.invalidResponse,
        reason: GenerationFailureReason.jsonParse,
        materialsText: 'третий',
        limit: 10,
      );
      await pumpPreview(
        tester,
        resultWith(
          cards: <GeneratedCard>[
            const GeneratedCard(
              front: 'Первый вопрос?',
              back: 'Первый ответ.',
              cardType: CardType.basic,
            ),
            const GeneratedCard(
              front: 'Второй вопрос?',
              back: 'Второй ответ.',
              cardType: CardType.basic,
            ),
          ],
          failures: <GenerationChunkFailure>[failure],
        ),
      );
      final l10n = l10nOf(tester);

      expect(importAllButton(tester).onPressed, isNotNull);
      expect(
        find.byKey(const ValueKey<String>('generation-preview-failure-0')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Фрагмент 3 из 3'),
        findsOneWidget,
        reason: 'номер фрагмента и понятная причина',
      );
      expect(
        find.textContaining(l10n.generationReasonJsonParse),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('generation-preview-import-all')),
      );
      await tester.pumpAndSettle();

      expect(store.importedCards, hasLength(1));
      expect(store.importedCards.single, hasLength(2));
      expect(store.lastDeckName, 'Новая колода');
    },
  );

  testWidgets('невалидная карточка пропускается, валидные импортируются', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      resultWith(
        cards: <GeneratedCard>[
          const GeneratedCard(
            front: '',
            back: 'Ответ.',
            cardType: CardType.basic,
          ),
          const GeneratedCard(
            front: 'Хороший вопрос?',
            back: 'Хороший ответ.',
            cardType: CardType.basic,
          ),
        ],
      ),
    );
    final l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-import-all')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.generationImportedWithSkipped(1, 1)), findsOneWidget);
    expect(store.importedCards, hasLength(1));
    expect(store.importedCards.single.single.front, 'Хороший вопрос?');
  });

  testWidgets('карточки с ошибкой схемы показаны счётчиком', (tester) async {
    await pumpPreview(
      tester,
      resultWith(
        cards: <GeneratedCard>[
          const GeneratedCard(
            front: 'Вопрос?',
            back: 'Ответ.',
            cardType: CardType.basic,
          ),
        ],
        rejectedCards: 2,
      ),
    );
    final l10n = l10nOf(tester);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-rejected')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationRejectedCards(2)), findsOneWidget);
  });

  testWidgets('картинку можно убрать до импорта', (tester) async {
    final Uint8List png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final GeneratedCard card = makeGeneratedCard(
      front: 'Что на схеме?',
      back: 'Ферма.',
      image: makeCardImage(mediaType: AttachmentMediaType.png, bytes: png),
    );
    await pumpPreview(tester, resultWith(cards: <GeneratedCard>[card]));

    expect(
      find.byKey(const ValueKey<String>('generation-preview-image-0')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-remove-image-0')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('generation-preview-image-0')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('generation-preview-import-all')),
    );
    await tester.pumpAndSettle();
    expect(store.importedCards.single.single.image, isNull);
  });
}
