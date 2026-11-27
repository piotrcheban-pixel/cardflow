import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Отчёт дедупа и его учёт в журнале прогона (TASK «Срез 6»: «отчёт по
/// уровням дедупа в ledger»).
///
/// Журнал отвечает за арифметику заказа, отчёт — за то, **на каком уровне**
/// карточка признана дублем: точный ключ, нормализованный ключ, шинглы или
/// эмбеддинги. Дубль — пометка пары, а не удаление.
void main() {
  const DedupPair exact = DedupPair(
    leftId: 'a',
    rightId: 'b',
    level: DedupLevel.exact,
  );
  const DedupPair normalized = DedupPair(
    leftId: 'a',
    rightId: 'c',
    level: DedupLevel.normalized,
  );
  const DedupPair semantic = DedupPair(
    leftId: 'd',
    rightId: 'e',
    level: DedupLevel.semantic,
    similarity: 0.82,
  );

  group('DedupReport', () {
    test('пустой отчёт: ни пар, ни дублей, нули по всем уровням', () {
      final DedupReport report = DedupReport.empty();

      expect(report.pairs, isEmpty);
      expect(report.pairCount, 0);
      expect(report.duplicateIds, isEmpty);
      expect(report.byLevel, <DedupLevel, int>{
        DedupLevel.exact: 0,
        DedupLevel.normalized: 0,
        DedupLevel.semantic: 0,
        DedupLevel.embeddings: 0,
      });
    });

    test('счётчики по уровням и уровень карточки — сильнейший', () {
      final DedupReport report = DedupReport(
        pairs: const <DedupPair>[exact, normalized, semantic],
      );

      expect(report.pairCount, 3);
      expect(report.countOf(DedupLevel.exact), 1);
      expect(report.countOf(DedupLevel.normalized), 1);
      expect(report.countOf(DedupLevel.semantic), 1);
      expect(report.countOf(DedupLevel.embeddings), 0);
      expect(report.levelOf('a'), DedupLevel.exact);
      expect(report.levelOf('c'), DedupLevel.normalized);
      expect(report.levelOf('d'), DedupLevel.semantic);
      expect(report.levelOf('нет-такой'), isNull);
      expect(report.isDuplicate('b'), isTrue);
      expect(report.isDuplicate('zzz'), isFalse);
      expect(report.duplicateIds, <String>{'a', 'b', 'c', 'd', 'e'});
      expect(report.pairsOf('a'), hasLength(2));
    });

    test('список пар неизменяем', () {
      final DedupReport report = DedupReport(pairs: const <DedupPair>[exact]);

      expect(
        () => report.pairs.add(semantic),
        throwsUnsupportedError,
      );
    });

    test('пара с одинаковыми id или пустым id неконструируема', () {
      expect(
        () => DedupPair(leftId: 'a', rightId: 'a', level: DedupLevel.exact),
        throwsAssertionError,
      );
      expect(
        () => DedupPair(leftId: '', rightId: 'b', level: DedupLevel.exact),
        throwsAssertionError,
      );
    });
  });

  group('журнал прогона', () {
    test('отчёт дедупа живёт в ledger, арифметика заказа не меняется', () {
      final GenerationLedger ledger = GenerationLedger.fromBudgets(<int>[2, 1]);
      final DedupReport report = DedupReport(
        pairs: const <DedupPair>[exact, semantic],
      );

      final GenerationLedger withDedup = ledger.withDedup(report);

      expect(withDedup.dedup, same(report));
      expect(withDedup.requested, ledger.requested);
      expect(withDedup.accepted, ledger.accepted);
      expect(withDedup.remaining, ledger.remaining);
      expect(withDedup.batches, hasLength(2));
      expect(withDedup.dedup.countOf(DedupLevel.semantic), 1);
      expect(ledger.dedup.pairCount, 0, reason: 'журнал неизменяем');
    });

    test('события партии и причины не теряют отчёт дедупа', () {
      final DedupReport report = DedupReport(pairs: const <DedupPair>[exact]);
      final GenerationLedger ledger = GenerationLedger.fromBudgets(
        <int>[2],
      ).withDedup(report);

      final GenerationLedger recorded = ledger.record(
        0,
        generated: 2,
        duplicates: 1,
      );
      expect(recorded.dedup, same(report));
      expect(recorded.duplicates, 1);
      expect(recorded.accepted, 1);

      final GenerationLedger attempted = recorded.attempt(0);
      expect(attempted.dedup, same(report));

      final GenerationLedger caused = attempted.markCause(
        0,
        ShortfallKind.validationRejects,
      );
      expect(caused.dedup, same(report));

      final GenerationLedger replaced = caused.replace(
        GenerationBatchLedger.budget(batchIndex: 0, requested: 5),
      );
      expect(replaced.dedup, same(report));
    });
  });
}
