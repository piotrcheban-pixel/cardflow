import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/settings/drift_app_settings_store.dart';
import 'package:cardflow/domain/settings/app_settings.dart';

void main() {
  late AppDatabase db;
  late DriftAppSettingsStore store;

  setUp(() {
    db = AppDatabase.inMemory();
    store = DriftAppSettingsStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DriftAppSettingsStore', () {
    test('без строки возвращает значения по умолчанию', () async {
      expect(await store.read(), AppSettings.defaults);
    });

    test('запись и чтение сохраняют все поля', () async {
      final AppSettings settings = AppSettings.defaults.copyWith(
        theme: AppThemePreference.dark,
        dynamicColor: true,
        motion: MotionPreference.standard,
        dyslexiaFont: true,
        textScale: 1.25,
        highContrast: true,
        haptics: false,
        desiredRetention: 0.82,
        learningSteps: <Duration>[Duration(minutes: 3)],
        dailyNewLimit: 10,
        dailyReviewLimit: 120,
      );
      await store.write(settings);
      expect(await store.read(), settings);

      final AppSettingRow row =
          await (db.select(db.appSettings)..where(
                (table) => table.key.equals(DriftAppSettingsStore.settingKey),
              ))
              .getSingle();
      final Map<String, Object?> decoded =
          jsonDecode(row.valueJson) as Map<String, Object?>;
      expect(decoded['version'], AppSettings.version);
      expect(decoded['theme'], 'dark');
    });

    test('повторная запись перезаписывает единственную строку', () async {
      await store.write(
        AppSettings.defaults.copyWith(theme: AppThemePreference.light),
      );
      await store.write(
        AppSettings.defaults.copyWith(theme: AppThemePreference.dark),
      );
      final List<AppSettingRow> rows = await db.select(db.appSettings).get();
      expect(rows.length, 1);
      expect((await store.read()).theme, AppThemePreference.dark);
    });

    test(
      'повреждённый JSON — значения по умолчанию, строка не удаляется',
      () async {
        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: DriftAppSettingsStore.settingKey,
                valueJson: '{not json',
              ),
            );
        expect(await store.read(), AppSettings.defaults);
        final List<AppSettingRow> rows = await db.select(db.appSettings).get();
        expect(rows.length, 1);
      },
    );

    test('неизвестная версия — значения по умолчанию', () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: DriftAppSettingsStore.settingKey,
              valueJson: '{"version": 99, "theme": "dark"}',
            ),
          );
      expect(await store.read(), AppSettings.defaults);
    });

    test('значение неверного типа — значения по умолчанию', () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: DriftAppSettingsStore.settingKey,
              valueJson: '[1, 2, 3]',
            ),
          );
      expect(await store.read(), AppSettings.defaults);
    });
  });
}
