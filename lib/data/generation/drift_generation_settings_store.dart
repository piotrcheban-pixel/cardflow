/// Репозиторий настроек OpenAI-совместимого сервера поверх `app_settings`
/// (SPEC A5, ADR-013). Ключ API в БД не хранится (SPEC 3.4).
library;

import 'dart:convert';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/generation/generation_settings_store.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';

/// Хранит адрес и модель OpenAI-совместимого сервера в одной строке
/// `app_settings` с ключом [settingKey] и JSON-значением.
class DriftGenerationSettingsStore implements GenerationSettingsStore {
  /// Создаёт репозиторий поверх [db].
  DriftGenerationSettingsStore(this.db);

  /// БД приложения.
  final AppDatabase db;

  /// Ключ единственной строки настроек в `app_settings`.
  static const String settingKey = 'generation.openai_compatible';

  @override
  Future<OpenAiCompatibleSettings> readOpenAiCompatible() async {
    final row = await (db.select(
      db.appSettings,
    )..where((table) => table.key.equals(settingKey))).getSingleOrNull();
    if (row == null) return const OpenAiCompatibleSettings();
    try {
      return OpenAiCompatibleSettings.fromJson(jsonDecode(row.valueJson));
    } on FormatException {
      // Повреждённое значение не должно ломать экран настроек/генерацию:
      // трактуем как «не настроено» (пользователь настроит заново).
      return const OpenAiCompatibleSettings();
    }
  }

  @override
  Future<void> writeOpenAiCompatible(OpenAiCompatibleSettings settings) async {
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
