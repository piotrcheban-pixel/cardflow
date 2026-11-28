import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/completion_verdict.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/ui/generation/generation_preview_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Срез 11, п. 9: предпросмотр берёт «принято N из M», причины недобора с
/// числами, покрытие единиц и расход токенов из [GenerationReport], а не из
/// [CompletionVerdict]; п. 10 — причина отсутствия карты знаний видна строкой.
void main() {
  GenerationRunRequest request() => GenerationRunRequest(
    documents: const <ParsedDocument>[],
    account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
    deckName: 'Новая колода',
  );

  GenerationReport reportOf({
    List<String> understandingFailures = const <String>[],
    int? materialCapacity,
  }) => GenerationReport(
    requested: 8,
    accepted: 6,
    stage: GenerationStage.partial,
    reason: ReplenishStopReason.exhaustedMaterial,
    reasons: <String>[ShortfallKind.exhaustedMaterial.wireName],
    unitCoverage: <UnitCoverage>[
      const UnitCoverage(unitId: 'ku:0', planned: 4, accepted: 6),
      const UnitCoverage(unitId: 'ku:1', planned: 4, accepted: 0),
    ],
    tokensByStage: const <GenerationStage, TokenUsage>{
      GenerationStage.understanding: TokenUsage(totalTokens: 30),
      GenerationStage.generating: TokenUsage(totalTokens: 100),
      GenerationStage.replenishing: TokenUsage(totalTokens: 20),
    },
    promptVersions: const <String, String>{},
    duration: const Duration(seconds: 3),
    passes: 1,
    requests: 2,
    invalid: 2,
    materialCapacity: materialCapacity,
    unfilledSlots: 2,
    shortfallReasons: const <ShortfallKind, int>{
      ShortfallKind.exhaustedMaterial: 2,
    },
    understandingFailures: understandingFailures,
  );

  GenerationRunResult resultWith({GenerationReport? report}) =>
      GenerationRunResult(
        jobId: 'job-1',
        status: GenerationJobStatus.partial,
        cards: const <GeneratedCard>[],
        failures: const <GenerationChunkFailure>[],
        tokensUsed: 150,
        estimatedTokens: 100,
        duplicatesRemoved: 0,
        chunkCount: 1,
        cancelled: false,
        // Вердикт намеренно расходится с отчётом: UI обязан читать отчёт.
        verdict: const CompletionVerdict(
          outcome: CompletionOutcome.partial,
          requested: 10,
          accepted: 9,
        ),
        report: report,
      );

  List<Override> overrides() => <Override>[
    generationRunnerProvider.overrideWithValue(FakeGenerationRunner()),
    generationCardStoreProvider.overrideWithValue(FakeGenerationCardStore()),
    deckRepositoryProvider.overrideWithValue(FakeDeckRepository()),
  ];

  Future<void> pumpPreview(
    WidgetTester tester,
    GenerationRunResult result,
  ) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides(),
        home: GenerationPreviewScreen(request: request(), result: result),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('отчёт: принято N из M, причины числами, покрытие и токены', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      resultWith(report: reportOf(understandingFailures: <String>[])),
    );
    final l10n = l10nOf(tester);

    expect(
      find.byKey(const ValueKey<String>('generation-preview-report')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.generationVerdictPartial(6, 8)),
      findsOneWidget,
      reason: 'числа — из отчёта, а не из вердикта (9 из 10)',
    );
    expect(find.text(l10n.generationVerdictPartial(9, 10)), findsNothing);
    expect(
      find.text(
        l10n.generationReportShortfall(
          l10n.generationShortfallExhaustedMaterial,
          2,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('generation-preview-report-coverage')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationReportCoverage(1, 2)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-report-tokens')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationReportTokens(150)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-verdict')),
      findsNothing,
      reason: 'с отчётом вердикт не источник чисел',
    );
  });

  testWidgets('скан без текстового слоя: причина видна, а не пустой итог', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      resultWith(
        report: reportOf(understandingFailures: <String>['no_text_layer']),
      ),
    );
    final l10n = l10nOf(tester);

    expect(
      find.byKey(const ValueKey<String>('generation-preview-understanding')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationUnderstandingNoText), findsOneWidget);
  });

  testWidgets('ёмкость материала видна числом рядом с причиной недобора', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      resultWith(report: reportOf(materialCapacity: 188)),
    );
    final l10n = l10nOf(tester);

    expect(
      find.byKey(
        const ValueKey<String>('generation-preview-material-capacity'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(l10n.generationReportMaterialCapacity(188)),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.generationReportShortfall(
          l10n.generationShortfallExhaustedMaterial,
          2,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('без отчёта: прежний вердикт (legacy-путь не меняется)', (
    tester,
  ) async {
    await pumpPreview(tester, resultWith());
    final l10n = l10nOf(tester);

    expect(
      find.byKey(const ValueKey<String>('generation-preview-verdict')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationVerdictPartial(9, 10)), findsOneWidget);
  });
}
