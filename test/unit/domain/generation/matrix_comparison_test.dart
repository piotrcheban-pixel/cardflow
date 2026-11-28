// Правила честной базы сравнения (TASK «Срез 13», часть 3): cleanRate от
// произведённых, нерешающие ячейки 20/40, решение только по 80/150/300 и
// разбор `ready`-недобора через различимые слоты.
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/matrix_comparison.dart';

void main() {
  group('cleanRate — доля от произведённых', () {
    test('один и тот же числитель, разные знаменатели', () {
      // 8 «чистых» из 10 произведённых: путь, отбросивший 2 сомнительные,
      // не должен выглядеть чище из-за меньшего знаменателя.
      expect(
        cleanRateOfGenerated(cleanAccepted: 8, generated: 10),
        closeTo(0.8, 1e-9),
      );
      expect(
        cleanRateOfAccepted(cleanAccepted: 8, accepted: 8),
        closeTo(1.0, 1e-9),
        reason: 'прежняя база среза 12 для колонки «было»',
      );
    });

    test('нет произведённых — null, а не ноль', () {
      expect(cleanRateOfGenerated(cleanAccepted: 0, generated: 0), isNull);
      expect(cleanRateOfAccepted(cleanAccepted: 0, accepted: 0), isNull);
    });
  });

  group('нерешающие ячейки', () {
    test('20 и 40 — нерешающие, 80/150/300 — решающие', () {
      expect(isDecisiveCell(20), isFalse);
      expect(isDecisiveCell(40), isFalse);
      expect(isDecisiveCell(80), isTrue);
      expect(isDecisiveCell(150), isTrue);
      expect(isDecisiveCell(300), isTrue);
    });

    test('вердикт по нерешающей ячейке не выводится даже при числах', () {
      expect(
        compareCells(requested: 20, v3CleanRate: 0.95, legacyCleanRate: 1.0),
        MatrixComparisonVerdict.notDecisive,
      );
    });

    test('на решающей ячейке v3 не хуже или хуже — по числам', () {
      expect(
        compareCells(
          requested: 300,
          v3CleanRate: 0.973,
          legacyCleanRate: 0.986,
        ),
        MatrixComparisonVerdict.worse,
      );
      expect(
        compareCells(requested: 80, v3CleanRate: 1.0, legacyCleanRate: 1.0),
        MatrixComparisonVerdict.notWorse,
      );
    });

    test('нет числа хотя бы у одной стороны — нерешающая', () {
      expect(
        compareCells(requested: 150, v3CleanRate: null, legacyCleanRate: 1.0),
        MatrixComparisonVerdict.notDecisive,
      );
    });
  });

  group('различимые слоты (разбор partial)', () {
    test('188 — полный набор из 47 единиц', () {
      expect(looksLikeSlotCapacity(188), isTrue);
      expect(unitsOfSlots(188), 47);
      expect(unitsOfSlots(188) * kSlotsPerUnit, 188);
    });

    test('299 не кратно четырём: у части единиц не все углы', () {
      expect(looksLikeSlotCapacity(299), isFalse);
      expect(looksLikeSlotCapacity(0), isFalse);
    });
  });

  group('сопоставимая база (срез 14, часть 2)', () {
    // Известное пересечение: u1 и u2 есть у обоих путей, u3 — только у
    // legacy, u4 — только у v3.
    const List<ProducedCardRef> legacy = <ProducedCardRef>[
      ProducedCardRef(unitId: 'u1', clean: true, salience: 0.9),
      ProducedCardRef(unitId: 'u2', clean: false, salience: 0.4),
      ProducedCardRef(unitId: 'u3', clean: true, salience: 0.1),
    ];
    const List<ProducedCardRef> v3 = <ProducedCardRef>[
      ProducedCardRef(unitId: 'u1', clean: false, salience: 0.9),
      ProducedCardRef(unitId: 'u2', clean: true, salience: 0.4),
      ProducedCardRef(unitId: 'u2', clean: true, salience: 0.4),
      ProducedCardRef(unitId: 'u4', clean: true, salience: 0.3),
    ];

    test('matchedSubset — только единицы, где оба пути дали карточку', () {
      final MatchedSubset matched = MatchedSubset.of(legacy: legacy, v3: v3);

      expect(matched.unitIds, <String>{'u1', 'u2'});
      expect(matched.legacyGenerated, 2, reason: 'u3 выпадает: у v3 её нет');
      expect(matched.v3Generated, 3, reason: 'u4 выпадает: у legacy её нет');
      expect(matched.legacyClean, 1);
      expect(matched.v3Clean, 2);
      expect(matched.legacyCleanRate, closeTo(1 / 2, 1e-9));
      expect(matched.v3CleanRate, closeTo(2 / 3, 1e-9));
    });

    test('топ-80 по salience отбирает верх материала детерминированно', () {
      final MatchedSubset top = MatchedSubset.of(
        legacy: legacy,
        v3: v3,
        topUnits: 1,
      );

      expect(top.unitIds, <String>{'u1'}, reason: 'u1 значимее u2');
      expect(top.legacyGenerated, 1);
      expect(top.v3Generated, 1);
      expect(top.v3CleanRate, 0, reason: 'единственная карточка v3 — грязная');
    });

    test('агрегаты: coverage == 1 — база равна произведённому', () {
      expect(
        cleanRateMatchedFromCoverage(clean: 185, generated: 189, coverage: 1),
        closeTo(185 / 189, 1e-9),
      );
      expect(
        cleanRateMatchedFromCoverage(clean: 8, generated: 10, coverage: 0.6),
        isNull,
        reason:
            'при неполном покрытии пер-юнитная база из агрегатов '
            'невосстановима — это не догадка',
      );
      expect(
        cleanRateMatchedFromCoverage(clean: 0, generated: 0, coverage: 1),
        isNull,
      );
    });

    test('критерий флага: 95 % и объём на решающих ячейках', () {
      expect(
        flagCriterion(
          requested: 300,
          v3CleanRateMatched: 0.979,
          v3AbsoluteClean: 185,
          legacyAbsoluteClean: 15,
        ),
        FlagCriterionVerdict.met,
      );
      expect(
        flagCriterion(
          requested: 300,
          v3CleanRateMatched: 0.949,
          v3AbsoluteClean: 185,
          legacyAbsoluteClean: 15,
        ),
        FlagCriterionVerdict.notMet,
        reason: 'доля ниже порога 95 %',
      );
      expect(
        flagCriterion(
          requested: 150,
          v3CleanRateMatched: 1.0,
          v3AbsoluteClean: 10,
          legacyAbsoluteClean: 15,
        ),
        FlagCriterionVerdict.notMet,
        reason: 'чистых меньше legacy — доли недостаточно',
      );
      expect(
        flagCriterion(
          requested: 20,
          v3CleanRateMatched: 1.0,
          v3AbsoluteClean: 20,
          legacyAbsoluteClean: 10,
        ),
        FlagCriterionVerdict.notDecisive,
      );
    });
  });
}
