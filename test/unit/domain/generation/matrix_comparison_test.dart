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
}
