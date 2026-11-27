import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';

/// Срез 2 (TASK.txt): стейт-машина прогона генерации v3.
///
/// Путь: planned → understanding → generating → validating → dedup →
/// replenishing → ready | partial | failed | cancelled. Переход проверяется,
/// недопустимый — исключение (DoD: generating → ready невозможно).
void main() {
  /// Ведёт состояние по каноническому пути до [target].
  GenerationRunState stateAt(GenerationStage target) {
    var state = const GenerationRunState.planned();
    const List<GenerationStage> path = <GenerationStage>[
      GenerationStage.understanding,
      GenerationStage.generating,
      GenerationStage.validating,
      GenerationStage.dedup,
      GenerationStage.replenishing,
      GenerationStage.ready,
    ];
    for (final GenerationStage next in path) {
      if (state.stage == target) return state;
      state = state.advanceTo(next);
    }
    expect(state.stage, target, reason: 'этап $target недостижим по канону');
    return state;
  }

  test('канонический путь planned → understanding → generating → validating → '
      'dedup → replenishing → ready', () {
    var state = GenerationRunState.planned();
    expect(state.stage, GenerationStage.planned);
    expect(state.isTerminal, isFalse);

    const List<GenerationStage> path = <GenerationStage>[
      GenerationStage.understanding,
      GenerationStage.generating,
      GenerationStage.validating,
      GenerationStage.dedup,
      GenerationStage.replenishing,
      GenerationStage.ready,
    ];
    for (final GenerationStage next in path) {
      state = state.advanceTo(next);
      expect(state.stage, next);
    }
    expect(state.isTerminal, isTrue);
    expect(state.allowedNext, isEmpty);
  });

  test('DoD: переход generating → ready невозможен', () {
    final GenerationRunState state = stateAt(GenerationStage.generating);
    expect(state.stage, GenerationStage.generating);
    expect(
      () => state.advanceTo(GenerationStage.ready),
      throwsA(
        isA<InvalidGenerationStageTransition>()
            .having(
              (InvalidGenerationStageTransition error) => error.from,
              'from',
              GenerationStage.generating,
            )
            .having(
              (InvalidGenerationStageTransition error) => error.to,
              'to',
              GenerationStage.ready,
            ),
      ),
    );
  });

  test('этапы нельзя перескакивать: planned → generating запрещён', () {
    const GenerationRunState state = GenerationRunState.planned();
    expect(
      () => state.advanceTo(GenerationStage.generating),
      throwsA(isA<InvalidGenerationStageTransition>()),
    );
    expect(
      () => state.advanceTo(GenerationStage.dedup),
      throwsA(isA<InvalidGenerationStageTransition>()),
    );
    expect(
      () => state.advanceTo(GenerationStage.planned),
      throwsA(isA<InvalidGenerationStageTransition>()),
      reason: 'стоять на месте нельзя',
    );
  });

  test('добор возвращает прогон в generating', () {
    final GenerationRunState replenishing = stateAt(
      GenerationStage.replenishing,
    );
    final GenerationRunState again = replenishing.advanceTo(
      GenerationStage.generating,
    );
    expect(again.stage, GenerationStage.generating);
    expect(
      again.advanceTo(GenerationStage.validating).stage,
      GenerationStage.validating,
    );
  });

  test('ready и partial достижимы только после решения о доборе', () {
    final GenerationRunState dedup = stateAt(GenerationStage.dedup);
    expect(
      () => dedup.advanceTo(GenerationStage.ready),
      throwsA(isA<InvalidGenerationStageTransition>()),
    );
    expect(
      () => dedup.advanceTo(GenerationStage.partial),
      throwsA(isA<InvalidGenerationStageTransition>()),
    );
    final GenerationRunState replenishing = dedup.advanceTo(
      GenerationStage.replenishing,
    );
    expect(
      replenishing.advanceTo(GenerationStage.ready).stage,
      GenerationStage.ready,
    );
    expect(
      replenishing.advanceTo(GenerationStage.partial).stage,
      GenerationStage.partial,
    );
  });

  test('cancelled и failed допустимы с любого незавершённого этапа', () {
    for (final GenerationStage stage in GenerationStage.values) {
      final GenerationRunState state = GenerationRunState(stage);
      for (final GenerationStage terminal in <GenerationStage>[
        GenerationStage.failed,
        GenerationStage.cancelled,
      ]) {
        if (stage.isTerminal) {
          expect(
            () => state.advanceTo(terminal),
            throwsA(isA<InvalidGenerationStageTransition>()),
            reason: 'из терминального этапа $stage переходов нет',
          );
        } else {
          expect(state.canAdvanceTo(terminal), isTrue);
          expect(state.advanceTo(terminal).stage, terminal);
        }
      }
    }
  });

  test('из терминального этапа нельзя вернуться в работу', () {
    for (final GenerationStage stage in GenerationStage.values) {
      if (!stage.isTerminal) continue;
      final GenerationRunState state = GenerationRunState(stage);
      expect(state.allowedNext, isEmpty);
      for (final GenerationStage back in <GenerationStage>[
        GenerationStage.planned,
        GenerationStage.understanding,
        GenerationStage.generating,
        GenerationStage.validating,
        GenerationStage.dedup,
        GenerationStage.replenishing,
      ]) {
        expect(
          () => state.advanceTo(back),
          throwsA(isA<InvalidGenerationStageTransition>()),
          reason: 'из $stage нельзя вернуться в $back',
        );
      }
    }
  });

  test('полная матрица переходов согласована', () {
    for (final GenerationStage from in GenerationStage.values) {
      final GenerationRunState state = GenerationRunState(from);
      for (final GenerationStage to in GenerationStage.values) {
        final bool allowed = state.canAdvanceTo(to);
        expect(
          state.allowedNext.contains(to),
          allowed,
          reason: '$from → $to: allowedNext и canAdvanceTo расходятся',
        );
        if (allowed) {
          expect(
            state.advanceTo(to).stage,
            to,
            reason: '$from → $to должен вести в $to',
          );
        } else {
          expect(
            () => state.advanceTo(to),
            throwsA(isA<InvalidGenerationStageTransition>()),
            reason: '$from → $to должен бросать исключение',
          );
        }
      }
    }
  });

  test('allowedNext — путь вперёд и терминалы, без возвратов', () {
    expect(const GenerationRunState.planned().allowedNext, <GenerationStage>{
      GenerationStage.understanding,
      GenerationStage.failed,
      GenerationStage.cancelled,
    });
    expect(stateAt(GenerationStage.generating).allowedNext, <GenerationStage>{
      GenerationStage.validating,
      GenerationStage.failed,
      GenerationStage.cancelled,
    });
    expect(stateAt(GenerationStage.dedup).allowedNext, <GenerationStage>{
      GenerationStage.replenishing,
      GenerationStage.failed,
      GenerationStage.cancelled,
    });
    expect(stateAt(GenerationStage.replenishing).allowedNext, <GenerationStage>{
      GenerationStage.generating,
      GenerationStage.ready,
      GenerationStage.partial,
      GenerationStage.failed,
      GenerationStage.cancelled,
    });
  });

  test(
    'терминальные этапы сопоставлены статусам generation_jobs (SPEC A5)',
    () {
      expect(GenerationStage.ready.jobStatus, GenerationJobStatus.done);
      expect(GenerationStage.partial.jobStatus, GenerationJobStatus.partial);
      expect(GenerationStage.failed.jobStatus, GenerationJobStatus.error);
      expect(
        GenerationStage.cancelled.jobStatus,
        GenerationJobStatus.cancelled,
      );
      for (final GenerationStage stage in <GenerationStage>[
        GenerationStage.planned,
        GenerationStage.understanding,
        GenerationStage.generating,
        GenerationStage.validating,
        GenerationStage.dedup,
        GenerationStage.replenishing,
      ]) {
        expect(stage.jobStatus, GenerationJobStatus.running);
        expect(stage.isTerminal, isFalse);
      }
    },
  );

  test('исключение недопустимого перехода называет этапы', () {
    final GenerationRunState state = stateAt(GenerationStage.generating);
    Object? caught;
    try {
      state.advanceTo(GenerationStage.ready);
    } on InvalidGenerationStageTransition catch (error) {
      caught = error;
    }
    expect(caught, isA<InvalidGenerationStageTransition>());
    final String text = caught.toString();
    expect(text, contains('generating'));
    expect(text, contains('ready'));
    expect(state.toString(), contains('generating'));
  });
}
