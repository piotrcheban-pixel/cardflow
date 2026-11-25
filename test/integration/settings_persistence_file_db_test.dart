import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_opener.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Owner-note 1.0.1, шаг 2 (ADR-047): «настройки не сохраняются».
///
/// Проводка production-графа на **файловой** drift-БД: изменение → `save` →
/// закрытие БД → повторное открытие → `read` → значения совпадают.
/// In-memory тест эту ошибку класса «файл/права/блокировка» не ловит.
void main() {
  late Directory tempDir;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('cardflow_settings_flow_');
    db = await openAppDatabase(baseDirectory: tempDir);
    container = ProviderContainer(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<AppSettings> readAfterReopen() async {
    // Новое соединение к тому же файлу — как при перезапуске приложения.
    final AppDatabase reopened = await openAppDatabase(baseDirectory: tempDir);
    final ProviderContainer fresh = ProviderContainer(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(reopened)],
    );
    addTearDown(() async {
      fresh.dispose();
      await reopened.close();
    });
    return fresh.read(appSettingsProvider.future);
  }

  test('изменение → сохранение → чтение из БД → значения совпадают', () async {
    expect(
      await container.read(appSettingsProvider.future),
      AppSettings.defaults,
    );

    final AppSettings changed = AppSettings.defaults.copyWith(
      theme: AppThemePreference.dark,
      dynamicColor: true,
      motion: MotionPreference.standard,
      dyslexiaFont: true,
      textScale: 1.2,
      highContrast: true,
      haptics: false,
      desiredRetention: 0.85,
      learningSteps: <Duration>[Duration(minutes: 2), Duration(minutes: 15)],
      dailyNewLimit: 35,
      dailyReviewLimit: 140,
    );

    await container.read(appSettingsProvider.notifier).save(changed);

    // 1. Значение в памяти применилось сразу (экраны не ждут записи).
    expect(container.read(effectiveAppSettingsProvider), changed);

    // 2. Значение реально в файле: новое соединение видит его.
    expect(await readAfterReopen(), changed);
  });

  test('дневные лимиты и удержание сохраняются по одному полю', () async {
    final AppSettingsController controller = container.read(
      appSettingsProvider.notifier,
    );
    await container.read(appSettingsProvider.future);
    await controller.save(AppSettings.defaults.copyWith(dailyNewLimit: 5));
    await controller.save(
      AppSettings.defaults.copyWith(dailyNewLimit: 5, dailyReviewLimit: 55),
    );
    await controller.save(
      AppSettings.defaults.copyWith(
        dailyNewLimit: 5,
        dailyReviewLimit: 55,
        desiredRetention: 0.8,
      ),
    );

    final AppSettings stored = await readAfterReopen();
    expect(stored.dailyNewLimit, 5);
    expect(stored.dailyReviewLimit, 55);
    expect(stored.desiredRetention, 0.8);
  });

  test(
    'закрытая БД: запись не «успешна», предыдущее значение не теряется',
    () async {
      final AppSettingsController controller = container.read(
        appSettingsProvider.notifier,
      );
      await container.read(appSettingsProvider.future);
      await controller.save(AppSettings.defaults.copyWith(dailyNewLimit: 12));

      await db.close();

      await expectLater(
        controller.save(AppSettings.defaults.copyWith(dailyNewLimit: 13)),
        throwsA(anything),
        reason: 'Запись в закрытую БД обязана сообщить об ошибке',
      );
      // Состояние откатилось к последнему сохранённому значению.
      expect(container.read(effectiveAppSettingsProvider).dailyNewLimit, 12);

      final AppSettings stored = await readAfterReopen();
      expect(stored.dailyNewLimit, 12);
    },
  );

  test('файл БД лежит в каталоге данных приложения', () async {
    // drift открывает файл лениво — сначала реальный запрос.
    await container.read(appSettingsProvider.future);
    final File file = File(
      p.join(tempDir.path, appDataDirectoryName, appDatabaseFileName),
    );
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(0));
  });
}
