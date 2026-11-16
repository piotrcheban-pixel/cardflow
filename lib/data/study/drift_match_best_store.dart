/// Лучшие результаты «Подбора пар» в `app_settings` (итерация 7.16).
library;

import 'dart:convert';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/study/match_best_store.dart';

/// JSON v1 результатов игры; схема БД не меняется.
class DriftMatchBestStore implements MatchBestStore {
  /// Создаёт хранилище поверх БД.
  DriftMatchBestStore(this.database);

  /// БД приложения.
  final AppDatabase database;

  /// Ключ `app_settings`.
  static const String settingsKey = 'study.match.best';

  /// Версия формата.
  static const int formatVersion = 1;

  @override
  Future<int?> bestMs(String deckId) async {
    final Map<String, int> decks = await _read();
    return decks[deckId];
  }

  @override
  Future<void> saveIfBetter(String deckId, int milliseconds) async {
    if (milliseconds <= 0) return;
    final Map<String, int> decks = await _read();
    final int? current = decks[deckId];
    if (current != null && current <= milliseconds) return;
    decks[deckId] = milliseconds;
    final String value = jsonEncode(<String, Object?>{
      'version': formatVersion,
      'decks': decks,
    });
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: settingsKey, valueJson: value),
        );
  }

  Future<Map<String, int>> _read() async {
    final AppSettingRow? row = await (database.select(
      database.appSettings,
    )..where((table) => table.key.equals(settingsKey))).getSingleOrNull();
    if (row == null) return <String, int>{};
    try {
      final Object? json = jsonDecode(row.valueJson);
      if (json is! Map) return <String, int>{};
      final Object? version = json['version'];
      if (version is int && version > formatVersion) return <String, int>{};
      final Object? decks = json['decks'];
      if (decks is! Map) return <String, int>{};
      return <String, int>{
        for (final MapEntry<Object?, Object?> entry in decks.entries)
          if (entry.key is String && entry.value is num)
            entry.key! as String: (entry.value! as num).toInt(),
      };
    } on FormatException {
      return <String, int>{};
    }
  }
}
