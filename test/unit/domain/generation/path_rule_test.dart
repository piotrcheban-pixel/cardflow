import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/path_rule.dart';

/// Срез 17, часть 2: правило выбора пути выводится **числами** из уже
/// оплаченных ячеек (`live-s16/cells/*.json`), без новых запросов.
///
/// Величины — замороженные определения части 0; сопоставимость объёма —
/// п. 3 TASK (отношение принятых ≥ 0,8, иначе `volume_mismatch` и ячейка в
/// критерий не идёт).
void main() {
  PathOutcome outcome({
    required int accepted,
    required int clean,
    required int duplicates,
    int unique = -1,
    int attempted = -1,
    int blocked = 0,
  }) => PathOutcome(
    attempted: attempted < 0 ? accepted + duplicates : attempted,
    accepted: accepted,
    unique: unique < 0 ? accepted : unique,
    clean: clean,
    duplicates: duplicates,
    blocked: blocked,
  );

  test('доли замороженного набора в офлайн-пересчёте те же, что в коде', () {
    final PathOutcome legacy = outcome(
      accepted: 57,
      clean: 57,
      duplicates: 2,
      unique: 57,
      attempted: 59,
    );
    expect(legacy.cleanRate, closeTo(1, 1e-12));
    expect(legacy.dupRate, closeTo(2 / 57, 1e-12));
    expect(legacy.blockRate, closeTo(0, 1e-12));
    expect(legacy.acceptanceRate, closeTo(57 / 59, 1e-12));
    expect(legacy.absoluteClean, 57);
  });

  test(
    'объём сопоставим при отношении принятых ≥ 0,8 и не сопоставим ниже',
    () {
      expect(
        comparableVolumeRatio(acceptedA: 13, acceptedB: 16),
        closeTo(13 / 16, 1e-12),
      );
      expect(comparableVolume(acceptedA: 13, acceptedB: 16), isTrue);
      expect(comparableVolume(acceptedA: 12, acceptedB: 16), isFalse);
      expect(comparableVolume(acceptedA: 47, acceptedB: 57), isTrue);
      expect(comparableVolume(acceptedA: 0, acceptedB: 0), isFalse);
      expect(comparableVolumeRatio(acceptedA: 0, acceptedB: 0), isNull);
    },
  );

  test('N* — первый объём, с которого v3 не проигрывает по всем величинам', () {
    final PathThresholdResult result = derivePathThreshold(<MaterialPathPoint>[
      MaterialPathPoint(
        units: 10,
        legacy: outcome(accepted: 17, clean: 17, duplicates: 0),
        v3: outcome(accepted: 13, clean: 13, duplicates: 0),
      ),
      MaterialPathPoint(
        units: 33,
        legacy: outcome(accepted: 50, clean: 50, duplicates: 0),
        v3: outcome(accepted: 52, clean: 52, duplicates: 0),
      ),
      MaterialPathPoint(
        units: 60,
        legacy: outcome(accepted: 60, clean: 60, duplicates: 4),
        v3: outcome(accepted: 62, clean: 62, duplicates: 0),
      ),
    ]);
    expect(result.thresholdUnits, 33);
    expect(result.reason, PathThresholdReason.crossover);
    expect(result.winningUnits, <int>[33, 60]);
  });

  test('нет разрыва данные не дают → порог null и явная причина', () {
    final PathThresholdResult result = derivePathThreshold(<MaterialPathPoint>[
      MaterialPathPoint(
        units: 10,
        legacy: outcome(accepted: 17, clean: 17, duplicates: 0),
        v3: outcome(accepted: 13, clean: 13, duplicates: 0),
      ),
      MaterialPathPoint(
        units: 33,
        legacy: outcome(accepted: 57, clean: 57, duplicates: 2),
        v3: outcome(accepted: 47, clean: 47, duplicates: 24),
      ),
    ]);
    expect(result.thresholdUnits, isNull);
    expect(result.reason, PathThresholdReason.noCrossover);
    expect(result.winningUnits, isEmpty);
  });

  test(
    'выигрыш на малом объёме и проигрыш на большем → правило «≥ N» неверно',
    () {
      final PathThresholdResult result = derivePathThreshold(
        <MaterialPathPoint>[
          MaterialPathPoint(
            units: 10,
            legacy: outcome(accepted: 10, clean: 10, duplicates: 0),
            v3: outcome(accepted: 12, clean: 12, duplicates: 0),
          ),
          MaterialPathPoint(
            units: 40,
            legacy: outcome(accepted: 40, clean: 40, duplicates: 0),
            v3: outcome(accepted: 38, clean: 38, duplicates: 2),
          ),
        ],
      );
      expect(result.thresholdUnits, isNull);
      expect(result.reason, PathThresholdReason.notMonotonic);
    },
  );

  test('сравнение по объёму: absoluteClean v3 ниже — не выигрыш', () {
    final PathThresholdResult result = derivePathThreshold(<MaterialPathPoint>[
      MaterialPathPoint(
        units: 12,
        legacy: outcome(accepted: 16, clean: 16, duplicates: 0),
        v3: outcome(accepted: 16, clean: 15, duplicates: 0),
      ),
    ]);
    expect(result.reason, PathThresholdReason.noCrossover);
  });

  test('пустой список — не ошибка, а noCrossover без чисел', () {
    final PathThresholdResult result = derivePathThreshold(
      const <MaterialPathPoint>[],
    );
    expect(result.thresholdUnits, isNull);
    expect(result.reason, PathThresholdReason.noCrossover);
  });
}
