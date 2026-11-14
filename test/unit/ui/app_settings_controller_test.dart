import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/settings_fakes.dart';

void main() {
  late FakeAppSettingsStore store;
  late ProviderContainer container;

  setUp(() {
    store = FakeAppSettingsStore();
    container = ProviderContainer(
      overrides: <Override>[appSettingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
  });

  group('AppSettingsController', () {
    test('читает настройки из store', () async {
      store.settings = AppSettings.defaults.copyWith(
        theme: AppThemePreference.dark,
      );
      final AppSettings settings = await container.read(
        appSettingsProvider.future,
      );
      expect(settings.theme, AppThemePreference.dark);
      expect(container.read(effectiveAppSettingsProvider), settings);
    });

    test('save обновляет состояние и пишет в store', () async {
      await container.read(appSettingsProvider.future);
      final AppSettings next = AppSettings.defaults.copyWith(
        haptics: false,
        desiredRetention: 0.8,
      );
      await container.read(appSettingsProvider.notifier).save(next);

      expect(container.read(appSettingsProvider).value, next);
      expect(store.settings, next);
      expect(store.writeCount, 1);
    });

    test(
      'ошибка записи откатывает состояние и пробрасывает исключение',
      () async {
        await container.read(appSettingsProvider.future);
        final AppSettings before = container.read(appSettingsProvider).value!;
        store.failWrites = true;
        final AppSettings next = AppSettings.defaults.copyWith(haptics: false);

        await expectLater(
          container.read(appSettingsProvider.notifier).save(next),
          throwsStateError,
        );
        expect(container.read(effectiveAppSettingsProvider), before);
      },
    );
  });

  group('Настройки влияют на планировщик (A6.6, ADR-019 §2)', () {
    test('шаги обучения из настроек меняют прогноз Again', () async {
      store.settings = AppSettings.defaults.copyWith(
        learningSteps: <Duration>[Duration(minutes: 5)],
      );
      await container.read(appSettingsProvider.future);
      final Scheduler scheduler = container.read(schedulerProvider);
      final DateTime now = DateTime.utc(2026, 11, 14, 12);
      final SchedulingCard card = SchedulingCard.newCard(
        cardId: 'card-1',
        now: now,
      );

      expect(
        scheduler.previewIntervals(card, now: now)[Rating.again],
        const Duration(minutes: 5),
      );
      expect(
        FsrsScheduler().previewIntervals(card, now: now)[Rating.again],
        const Duration(minutes: 1),
      );
    });

    test(
      'желаемое удержание меняет интервал Good для повторяемой карточки',
      () async {
        final DateTime now = DateTime.utc(2026, 11, 14, 12);
        store.settings = AppSettings.defaults.copyWith(desiredRetention: 0.7);
        await container.read(appSettingsProvider.future);
        final Duration lowRetention = container
            .read(schedulerProvider)
            .previewIntervals(
              SchedulingCard(
                cardId: 'card-1',
                state: CardState.review,
                due: now.subtract(const Duration(days: 1)),
                stability: 10,
                difficulty: 5,
                lastReview: now.subtract(const Duration(days: 10)),
              ),
              now: now,
            )[Rating.good]!;

        final Duration highRetention = FsrsScheduler(desiredRetention: 0.95)
            .previewIntervals(
              SchedulingCard(
                cardId: 'card-1',
                state: CardState.review,
                due: now.subtract(const Duration(days: 1)),
                stability: 10,
                difficulty: 5,
                lastReview: now.subtract(const Duration(days: 10)),
              ),
              now: now,
            )[Rating.good]!;

        expect(
          lowRetention,
          greaterThan(highRetention),
          reason: 'ниже desiredRetention — длиннее интервал (FSRS)',
        );
      },
    );
  });
}
