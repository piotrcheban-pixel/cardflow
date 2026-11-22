// Остаток дневных лимитов для экранов колоды и сессии (A6.6, ADR-019 §8).
//
// Один и тот же расчёт обязателен и предварительной проверке на экране колоды,
// и сборке очереди сессии: иначе пользователь нажимает «Начать сессию», а внутри
// видит пустую сессию без причины (итерация 7.11). Функция принимает `WidgetRef`
// и потому живёт в UI-слое; сам расчёт — чистая арифметика `RemainingReviewLimits`.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Читает расход дня и возвращает остаток дневных лимитов на [now].
///
/// Настройки недоступны — берутся значения по умолчанию (ADR-019 §1); ошибка
/// журнала повторений пробрасывается вызывающему экрану.
Future<RemainingReviewLimits> readRemainingReviewLimits(
  WidgetRef ref, {
  DateTime? now,
}) async {
  AppSettings settings;
  try {
    settings = await ref.read(appSettingsProvider.future);
  } on Object {
    settings = AppSettings.defaults;
  }
  final DailyReviewUsage usage = await ref
      .read(dailyUsageRepositoryProvider)
      .usageOnDay(now ?? DateTime.now());
  return RemainingReviewLimits.of(
    newLimit: settings.dailyNewLimit,
    reviewLimit: settings.dailyReviewLimit,
    usage: usage,
  );
}

/// Остаток дневных лимитов для экранов, которые читают его декларативно.
///
/// Находка N8 аудита: экран колоды должен предупреждать об исчерпанном
/// дневном лимите **до** выбора режима, а не после. Семейство по id колоды
/// (пересоздаётся при смене колоды), ошибки хранилища не ломают экран:
/// предупреждение просто не показывается.
final deckRemainingLimitsProvider =
    FutureProvider.family<RemainingReviewLimits, String>((ref, deckId) async {
      AppSettings settings;
      try {
        settings = await ref.watch(appSettingsProvider.future);
      } on Object {
        settings = AppSettings.defaults;
      }
      final DailyReviewUsage usage = await ref
          .read(dailyUsageRepositoryProvider)
          .usageOnDay(DateTime.now());
      return RemainingReviewLimits.of(
        newLimit: settings.dailyNewLimit,
        reviewLimit: settings.dailyReviewLimit,
        usage: usage,
      );
    });
