/// Хранение пользовательских настроек в `app_settings` (SPEC A5, ADR-019).
library;

import 'dart:convert';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/domain/settings/app_settings_store.dart';

/// Хранит настройки одной строкой `app_settings` с ключом [settingKey].
class DriftAppSettingsStore implements AppSettingsStore {
  /// Создаёт хранилище поверх [db].
  DriftAppSettingsStore(this.db);

  /// БД приложения.
  final AppDatabase db;

  /// Ключ строки настроек в `app_settings`.
  static const String settingKey = 'app.settings';

  @override
  Future<AppSettings> read() async {
    final AppSettingRow? row = await (db.select(
      db.appSettings,
    )..where((table) => table.key.equals(settingKey))).getSingleOrNull();
    if (row == null) return AppSettings.defaults;
    try {
      final Object? decoded = jsonDecode(row.valueJson);
      if (decoded is! Map<String, Object?>) return AppSettings.defaults;
      return AppSettings.fromJson(decoded);
    } on FormatException {
      // Повреждённое значение не должно ломать приложение: работаем на
      // значениях по умолчанию и даём пользователю перезаписать настройки.
      return AppSettings.defaults;
    }
  }

  @override
  Future<void> write(AppSettings settings) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: settingKey,
            valueJson: jsonEncode(settings.toJson()),
          ),
        );
  }
}
