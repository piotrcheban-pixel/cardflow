import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/generation/generation_v3_progress.dart';

import '../../helpers/pump_app.dart';

/// Срез 9: степпер этапов пути v3 и счётчик «принято N из M».
void main() {
  Future<void> pumpStepper(
    WidgetTester tester, {
    GenerationProgressPhase? phase,
    int accepted = 0,
    int requested = 0,
    bool finishing = false,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: const <Override>[],
        home: Scaffold(
          body: GenerationV3ProgressView(
            phase: phase,
            accepted: accepted,
            requested: requested,
            finishing: finishing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('stageFor: фазы старого конвейера → этапы v3', () {
    expect(
      GenerationV3ProgressView.stageFor(GenerationProgressPhase.chunking),
      GenerationV3Stage.analysis,
    );
    expect(
      GenerationV3ProgressView.stageFor(GenerationProgressPhase.sending),
      GenerationV3Stage.generating,
    );
    expect(
      GenerationV3ProgressView.stageFor(GenerationProgressPhase.receiving),
      GenerationV3Stage.generating,
    );
    expect(
      GenerationV3ProgressView.stageFor(
        GenerationProgressPhase.receiving,
        finishing: true,
      ),
      GenerationV3Stage.validation,
    );
    expect(GenerationV3ProgressView.stageFor(null), GenerationV3Stage.planning);
  });

  testWidgets('все этапы названы из ARB, текущий помечен', (
    WidgetTester tester,
  ) async {
    await pumpStepper(
      tester,
      phase: GenerationProgressPhase.sending,
      accepted: 3,
      requested: 10,
    );
    final AppLocalizations l10n = l10nOf(tester);
    expect(find.text(l10n.generationStageTitle), findsOneWidget);
    expect(find.text(l10n.generationStageAnalysis), findsOneWidget);
    expect(find.text(l10n.generationStagePlanning), findsOneWidget);
    expect(find.text(l10n.generationStageGenerating), findsOneWidget);
    expect(find.text(l10n.generationStageValidation), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-v3-stage-analysis-done')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('generation-v3-stage-generating-current'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('generation-v3-stage-validation-pending'),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.generationProgressCardsCount(3, 10)), findsOneWidget);
  });

  testWidgets('авто-режим (заказ не задан) не показывает счётчик', (
    WidgetTester tester,
  ) async {
    await pumpStepper(
      tester,
      phase: GenerationProgressPhase.receiving,
      accepted: 4,
    );
    expect(
      find.byKey(const ValueKey<String>('generation-v3-accepted')),
      findsNothing,
    );
  });

  testWidgets('этап проверки становится текущим после завершения', (
    WidgetTester tester,
  ) async {
    await pumpStepper(
      tester,
      phase: GenerationProgressPhase.receiving,
      finishing: true,
      accepted: 6,
      requested: 6,
    );
    expect(
      find.byKey(
        const ValueKey<String>('generation-v3-stage-validation-current'),
      ),
      findsOneWidget,
    );
  });
}
