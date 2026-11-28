// Срез 15, часть 3 (TASK п. 7–9): `matchedSubset` строится из **пер-юнитных**
// данных отчёта, а не из агрегата `coverage`. Живые пути различаются
// пространством id единиц (v3 — единицы карты `ku:…`, legacy — разделы), общий
// ключ — раздел материала; при равном пространстве id база строится по единице.
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/matrix_comparison.dart';

void main() {
  group('MatchedUnitBase: база из пер-юнитных данных', () {
    // u1/u2 — общие разделы, sec3 — только у v3: из базы выпадает.
    const List<ProductionUnit> legacy = <ProductionUnit>[
      ProductionUnit(unitId: 's1', sectionId: 'sec1', produced: 3, clean: 2),
      ProductionUnit(unitId: 's2', sectionId: 'sec2', produced: 4, clean: 4),
    ];
    const List<ProductionUnit> v3 = <ProductionUnit>[
      ProductionUnit(
        unitId: 'ku:sec1#0',
        sectionId: 'sec1',
        salience: 0.9,
        produced: 2,
        clean: 1,
      ),
      ProductionUnit(
        unitId: 'ku:sec1#1',
        sectionId: 'sec1',
        salience: 0.3,
        produced: 1,
        clean: 1,
      ),
      ProductionUnit(
        unitId: 'ku:sec2#0',
        sectionId: 'sec2',
        salience: 0.5,
        produced: 2,
        clean: 2,
      ),
      ProductionUnit(
        unitId: 'ku:sec3#0',
        sectionId: 'sec3',
        salience: 0.95,
        produced: 1,
        clean: 1,
      ),
    ];

    test('пересечение по разделу: только где оба пути произвели карточки', () {
      final MatchedUnitBase base = MatchedUnitBase.of(legacy: legacy, v3: v3);

      expect(base.keys, <String>{'sec1', 'sec2'});
      expect(base.sectionCount, 2);
      // «Единицы» базы — единицы карты v3 внутри сопоставимых разделов.
      expect(base.v3UnitCount, 3);
      expect(base.legacyUnitCount, 2);
      expect(base.legacyProduced, 7);
      expect(base.legacyClean, 6);
      expect(base.v3Produced, 5);
      expect(base.v3Clean, 4);
      expect(base.legacyCleanRate, closeTo(6 / 7, 1e-9));
      expect(base.v3CleanRate, closeTo(4 / 5, 1e-9));
    });

    test(
      'топ-N по salience: значимость раздела — максимум значимости единиц',
      () {
        final MatchedUnitBase top = MatchedUnitBase.of(
          legacy: legacy,
          v3: v3,
          topUnits: 1,
        );

        expect(top.keys, <String>{'sec1'});
        expect(top.legacyProduced, 3);
        expect(top.legacyClean, 2);
        expect(top.v3Produced, 3);
        expect(top.v3Clean, 2);
        expect(top.v3UnitCount, 2);
      },
    );

    test('нет общего ключа — пустая база, а не выдуманное число', () {
      final MatchedUnitBase base = MatchedUnitBase.of(
        legacy: const <ProductionUnit>[
          ProductionUnit(unitId: 'a', sectionId: 'x', produced: 2, clean: 2),
        ],
        v3: const <ProductionUnit>[
          ProductionUnit(unitId: 'b', sectionId: 'y', produced: 2, clean: 2),
        ],
      );

      expect(base.sectionCount, 0);
      expect(base.v3UnitCount, 0);
      expect(base.legacyCleanRate, isNull);
      expect(base.v3CleanRate, isNull);
      expect(base.isDecisive, isFalse);
    });

    test('меньше 10 единиц в базе — ячейка нерешающая (TASK п. 9)', () {
      final MatchedUnitBase base = MatchedUnitBase.of(legacy: legacy, v3: v3);
      expect(base.isDecisive, isFalse, reason: '3 единицы < 10');
    });

    test('без sectionId сопоставление идёт по id единицы', () {
      final MatchedUnitBase base = MatchedUnitBase.of(
        legacy: const <ProductionUnit>[
          ProductionUnit(unitId: 'u1', produced: 2, clean: 1),
          ProductionUnit(unitId: 'u3', produced: 1, clean: 1),
        ],
        v3: const <ProductionUnit>[
          ProductionUnit(unitId: 'u1', produced: 3, clean: 3),
          ProductionUnit(unitId: 'u4', produced: 1, clean: 1),
        ],
      );

      expect(base.keys, <String>{'u1'});
      expect(base.legacyProduced, 2);
      expect(base.v3Produced, 3);
      expect(base.legacyCleanRate, closeTo(1 / 2, 1e-9));
      expect(base.v3CleanRate, closeTo(1.0, 1e-9));
    });
  });

  group('критерий флага с порогом единиц', () {
    test('matchedSubset < 10 единиц — notDecisive, даже при числах', () {
      expect(
        flagCriterion(
          requested: 300,
          v3CleanRateMatched: 0.99,
          v3AbsoluteClean: 200,
          legacyAbsoluteClean: 50,
          matchedUnits: 4,
        ),
        FlagCriterionVerdict.notDecisive,
      );
    });

    test('10 и больше единиц — критерий считается по числам', () {
      expect(
        flagCriterion(
          requested: 300,
          v3CleanRateMatched: 0.96,
          v3AbsoluteClean: 200,
          legacyAbsoluteClean: 50,
          matchedUnits: 12,
        ),
        FlagCriterionVerdict.met,
      );
    });
  });
}
