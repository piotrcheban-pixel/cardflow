import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/review/daily_limits.dart';

/// Дневные лимиты A6.6 по календарному дню (ADR-019 §8, закрытие L45).
///
/// Тесты чистого домена: границы локального дня и остаток лимита. Ключевая
/// развилка — три состояния остатка: «без лимита» (`null`), «исчерпан» (`0`) и
/// «осталось n»: `0` нельзя переиспользовать как «без лимита».
void main() {
  group('DailyLimits.localDayUtc — границы локального календарного дня', () {
    test('полуинтервал [начало дня, начало следующего дня) в UTC', () {
      final ({DateTime from, DateTime to}) bounds = DailyLimits.localDayUtc(
        DateTime(2026, 11, 14, 20, 57),
      );
      expect(bounds.from, DateTime(2026, 11, 14).toUtc());
      expect(bounds.to, DateTime(2026, 11, 15).toUtc());
    });

    test('полночь принадлежит новому дню', () {
      final ({DateTime from, DateTime to}) bounds = DailyLimits.localDayUtc(
        DateTime(2026, 11, 14),
      );
      expect(bounds.from, DateTime(2026, 11, 14).toUtc());
    });

    test('переход месяца: 30 ноября → 1 декабря', () {
      final ({DateTime from, DateTime to}) bounds = DailyLimits.localDayUtc(
        DateTime(2026, 11, 30, 23, 59, 59),
      );
      expect(bounds.from, DateTime(2026, 11, 30).toUtc());
      expect(bounds.to, DateTime(2026, 12, 1).toUtc());
    });

    test('UTC-момент относится к своему локальному дню', () {
      final DateTime utcMoment = DateTime.utc(2026, 11, 14, 23, 30);
      final DateTime local = utcMoment.toLocal();
      final ({DateTime from, DateTime to}) bounds = DailyLimits.localDayUtc(
        utcMoment,
      );
      expect(bounds.from, DateTime(local.year, local.month, local.day).toUtc());
      expect(bounds.to.difference(bounds.from), isNot(Duration.zero));
    });
  });

  group('DailyLimits.remaining — остаток лимита', () {
    test('0 в настройках — лимита нет (null, «без ограничения»)', () {
      expect(DailyLimits.remaining(0, 0), isNull);
      expect(DailyLimits.remaining(0, 42), isNull);
    });

    test('отрицательная настройка — тоже «без лимита»', () {
      expect(DailyLimits.remaining(-5, 3), isNull);
    });

    test('остаток уменьшается расходом дня', () {
      expect(DailyLimits.remaining(20, 0), 20);
      expect(DailyLimits.remaining(20, 3), 17);
    });

    test('исчерпанный лимит — 0, а не «без лимита»', () {
      expect(DailyLimits.remaining(20, 20), 0);
      expect(DailyLimits.remaining(20, 25), 0);
    });
  });

  group('DailyReviewUsage', () {
    test('пустой расход и сумма', () {
      expect(DailyReviewUsage.empty.total, 0);
      expect(const DailyReviewUsage(newCards: 2, repeats: 3).total, 5);
    });

    test('равенство по значениям (кэш/сравнение в тестах)', () {
      expect(
        const DailyReviewUsage(newCards: 2, repeats: 1),
        const DailyReviewUsage(newCards: 2, repeats: 1),
      );
      expect(
        const DailyReviewUsage(newCards: 2),
        isNot(const DailyReviewUsage(newCards: 2, repeats: 1)),
      );
    });
  });

  group('RemainingReviewLimits.of — остаток для очереди сессии', () {
    test('настройки без лимитов → оба null', () {
      final RemainingReviewLimits limits = RemainingReviewLimits.of(
        newLimit: 0,
        reviewLimit: 0,
        usage: const DailyReviewUsage(newCards: 5, repeats: 50),
      );
      expect(limits.newCards, isNull);
      expect(limits.reviews, isNull);
    });

    test('расход дня вычитается из обеих настроек', () {
      final RemainingReviewLimits limits = RemainingReviewLimits.of(
        newLimit: 20,
        reviewLimit: 200,
        usage: const DailyReviewUsage(newCards: 3, repeats: 20),
      );
      expect(limits.newCards, 17);
      expect(limits.reviews, 180);
    });

    test('исчерпанный день → 0 (очередь пуста), а не безлимит', () {
      final RemainingReviewLimits limits = RemainingReviewLimits.of(
        newLimit: 2,
        reviewLimit: 1,
        usage: const DailyReviewUsage(newCards: 2, repeats: 9),
      );
      expect(limits.newCards, 0);
      expect(limits.reviews, 0);
    });
  });
}
