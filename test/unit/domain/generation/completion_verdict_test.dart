import 'package:cardflow/domain/generation/completion_verdict.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Партия журнала: [accepted] + [duplicates] + [invalid] = произведено.
GenerationBatchLedger batch({
  required int index,
  required int requested,
  int accepted = 0,
  int duplicates = 0,
  int invalid = 0,
  int attempts = 1,
  ShortfallKind? cause,
}) {
  return GenerationBatchLedger(
    batchIndex: index,
    requested: requested,
    generated: accepted + duplicates + invalid,
    duplicates: duplicates,
    invalid: invalid,
    attempts: attempts,
    cause: cause,
  );
}

GenerationLedger ledgerOf(List<GenerationBatchLedger> batches) =>
    GenerationLedger(batches: batches);

void main() {
  group('CompletionVerdict.fromLedger — «ложный успех запрещён»', () {
    test('done только при «принято ≥ заказано»', () {
      final CompletionVerdict verdict = CompletionVerdict.fromLedger(
        ledgerOf(<GenerationBatchLedger>[
          batch(index: 0, requested: 10, accepted: 10),
        ]),
      );
      expect(verdict.outcome, CompletionOutcome.done);
      expect(verdict.isDone, isTrue);
      expect(verdict.shortfall, 0);
      expect(verdict.jobStatus, GenerationJobStatus.done);
    });

    test('недобор — partial с числом и классом причины', () {
      final CompletionVerdict verdict = CompletionVerdict.fromLedger(
        ledgerOf(<GenerationBatchLedger>[
          batch(
            index: 0,
            requested: 10,
            accepted: 6,
            cause: ShortfallKind.truncated,
          ),
        ]),
      );
      expect(verdict.outcome, CompletionOutcome.partial);
      expect(verdict.isDone, isFalse);
      expect(verdict.requested, 10);
      expect(verdict.accepted, 6);
      expect(verdict.shortfall, 4);
      expect(verdict.reasons, <ShortfallKind>[ShortfallKind.truncated]);
      expect(verdict.jobStatus, GenerationJobStatus.partial);
    });

    test('«принято 20 из 20» — done, даже если модель произвела больше', () {
      final CompletionVerdict verdict = CompletionVerdict.fromLedger(
        ledgerOf(<GenerationBatchLedger>[
          batch(index: 0, requested: 20, accepted: 20, duplicates: 5),
        ]),
      );
      expect(verdict.outcome, CompletionOutcome.done);
      expect(verdict.accepted, 20);
    });

    test('дубли и отбросы не делают недобор успехом', () {
      final CompletionVerdict verdict = CompletionVerdict.fromLedger(
        ledgerOf(<GenerationBatchLedger>[
          batch(
            index: 0,
            requested: 8,
            accepted: 5,
            duplicates: 2,
            invalid: 1,
            cause: ShortfallKind.validationRejects,
          ),
        ]),
      );
      expect(verdict.outcome, CompletionOutcome.partial);
      expect(verdict.shortfall, 3);
      expect(verdict.reasons, <ShortfallKind>[ShortfallKind.validationRejects]);
    });
  });

  group('CompletionVerdict — отмена и сбой', () {
    test('отмена без принятого — cancelled', () {
      final CompletionVerdict verdict = CompletionVerdict.fromLedger(
        ledgerOf(<GenerationBatchLedger>[
          batch(index: 0, requested: 4, attempts: 0),
        ]),
        cancelled: true,
      );
      expect(verdict.outcome, CompletionOutcome.cancelled);
      expect(verdict.reasons, <ShortfallKind>[ShortfallKind.cancelled]);
      expect(verdict.jobStatus, GenerationJobStatus.cancelled);
    });

    test('отмена с принятым — partial: принятое не теряется (срез 7)', () {
      final CompletionVerdict verdict = CompletionVerdict.fromLedger(
        ledgerOf(<GenerationBatchLedger>[
          batch(index: 0, requested: 4, accepted: 2),
        ]),
        cancelled: true,
      );
      expect(verdict.outcome, CompletionOutcome.partial);
      expect(verdict.accepted, 2);
      expect(verdict.reasons, contains(ShortfallKind.cancelled));
    });

    test('сбой без карточек — failed, с карточками — partial', () {
      final CompletionVerdict empty = _failed(accepted: 0);
      expect(empty.outcome, CompletionOutcome.failed);
      expect(empty.reasons, <ShortfallKind>[ShortfallKind.providerError]);
      expect(empty.jobStatus, GenerationJobStatus.error);

      final CompletionVerdict partial = _failed(accepted: 3);
      expect(partial.outcome, CompletionOutcome.partial);
      expect(partial.accepted, 3);
      expect(partial.jobStatus, GenerationJobStatus.partial);
    });

    test('ёмкость материала доходит до вердикта числом', () {
      final CompletionVerdict verdict = CompletionVerdict.fromLedger(
        ledgerOf(<GenerationBatchLedger>[
          batch(
            index: 0,
            requested: 40,
            accepted: 12,
            cause: ShortfallKind.exhaustedMaterial,
          ),
        ]),
        materialCapacity: 12,
      );
      expect(verdict.materialCapacity, 12);
      expect(verdict.reasons, <ShortfallKind>[ShortfallKind.exhaustedMaterial]);
    });
  });

  group('CompletionVerdict.auto — заказ не задан (BACKLOG S9)', () {
    test('done требует отсутствия долга и хотя бы одной карточки', () {
      final CompletionVerdict verdict = CompletionVerdict.auto(
        accepted: 7,
        requests: 2,
        failedRequests: 0,
      );
      expect(verdict.outcome, CompletionOutcome.done);
      expect(verdict.isDone, isTrue);
    });

    test('упавший запрос не даёт done даже с карточками', () {
      final CompletionVerdict verdict = CompletionVerdict.auto(
        accepted: 7,
        requests: 3,
        failedRequests: 1,
      );
      expect(verdict.outcome, CompletionOutcome.partial);
      expect(verdict.reasons, <ShortfallKind>[ShortfallKind.providerError]);
    });

    test('пустой ответ — не done, но и не failed', () {
      final CompletionVerdict verdict = CompletionVerdict.auto(
        accepted: 0,
        requests: 1,
        failedRequests: 0,
      );
      expect(verdict.outcome, CompletionOutcome.partial);
      expect(verdict.isDone, isFalse);
      expect(verdict.requestsWithoutCards, 1);
    });

    test('отмена без принятого — cancelled', () {
      final CompletionVerdict verdict = CompletionVerdict.auto(
        accepted: 0,
        requests: 2,
        failedRequests: 0,
        cancelled: true,
      );
      expect(verdict.outcome, CompletionOutcome.cancelled);
    });
  });
}

CompletionVerdict _failed({required int accepted}) {
  return CompletionVerdict.fromLedger(
    ledgerOf(<GenerationBatchLedger>[
      batch(index: 0, requested: 5, accepted: accepted),
    ]),
    failed: true,
  );
}
