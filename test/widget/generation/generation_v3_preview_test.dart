import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/completion_verdict.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_metrics.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/generation/generation_preview_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Срез 9: предпросмотр с вердиктом, причинами недобора, группировкой по темам,
/// пометками карточек и «Почему?» по блоку источника.
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

  const List<GeneratedCard> cards = <GeneratedCard>[
    GeneratedCard(
      front: 'Что такое молекула?',
      back: 'Наименьшая частица вещества',
      cardType: CardType.basic,
      tags: <String>['статика'],
      issues: <CardIssueCode>[CardIssueCode.possibleDuplicate],
      sourceAnchorText: 'Молекула — наименьшая частица вещества.',
      sourceAnchorSection: 'Раздел 1',
    ),
    GeneratedCard(
      front: 'Что такое атом?',
      back: 'Часть молекулы',
      cardType: CardType.basicReversed,
      tags: <String>['статика'],
      issues: <CardIssueCode>[CardIssueCode.answerInFront],
    ),
    GeneratedCard(
      front: 'Что такое давление?',
      back: 'Сила на единицу площади',
      cardType: CardType.basic,
    ),
  ];

  GenerationRunResult result() {
    return GenerationRunResult(
      jobId: 'job-v3',
      status: GenerationJobStatus.partial,
      cards: cards,
      failures: const <GenerationChunkFailure>[],
      tokensUsed: 1500,
      estimatedTokens: 1200,
      duplicatesRemoved: 0,
      chunkCount: 1,
      cancelled: false,
      verdict: const CompletionVerdict(
        outcome: CompletionOutcome.partial,
        requested: 5,
        accepted: 3,
        reasons: <ShortfallKind>[ShortfallKind.truncated],
      ),
      metrics: const GenerationMetrics(
        requested: 5,
        accepted: 3,
        generated: 3,
        inputTokens: 1000,
        requests: 1,
        coveredUnits: 1,
        totalUnits: 1,
      ),
    );
  }

  List<Override> overrides() {
    return <Override>[
      generationRunnerProvider.overrideWithValue(runner),
      generationCardStoreProvider.overrideWithValue(store),
      deckRepositoryProvider.overrideWithValue(FakeDeckRepository()),
    ];
  }

  Future<void> pumpPreview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides(),
        home: GenerationPreviewScreen(request: request(), result: result()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('вердикт: «принято N из M» и причины недобора', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester);
    final AppLocalizations l10n = l10nOf(tester);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-verdict')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationVerdictPartial(3, 5)), findsOneWidget);
    expect(find.text(l10n.generationShortfallReasonsTitle), findsOneWidget);
    expect(find.text(l10n.generationShortfallTruncated), findsOneWidget);
  });

  testWidgets('группировка по темам: «статика» и «Без темы»', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester);
    final AppLocalizations l10n = l10nOf(tester);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-topic-статика')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('generation-preview-topic-untitled')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.generationPreviewTopicTitle('статика')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationPreviewTopicUntitled), findsOneWidget);
  });

  testWidgets('пометки: возможный дубль, обратная сторона, предупреждение', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester);
    expect(
      find.byKey(const ValueKey<String>('generation-mark-possible-duplicate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('generation-mark-reverse-side')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('generation-mark-warning')),
      findsOneWidget,
    );
  });

  testWidgets('«Почему?» показывает блок источника, а не выдержку', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester);
    final AppLocalizations l10n = l10nOf(tester);
    final Finder why = find.byKey(
      const ValueKey<String>('generation-preview-why-0'),
    );
    expect(why, findsOneWidget);
    await tester.tap(why);
    await tester.pumpAndSettle();

    expect(find.text(l10n.reviewWhySheetTitle), findsOneWidget);
    expect(
      find.text(l10n.generationWhySourceSection('Раздел 1')),
      findsOneWidget,
    );
    final Text block = tester.widget<Text>(
      find.byKey(const ValueKey<String>('generation-why-block')),
    );
    expect(block.data, 'Молекула — наименьшая частица вещества.');
  });

  testWidgets('у карточки без блока источника «Почему?» нет', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-why-1')),
      findsNothing,
    );
  });
}
