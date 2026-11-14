// Drift-реализация пресетов конструктора (SPEC A5 `session_presets`, A6.7,
// ADR-018). Схема БД не меняется: таблица создана в schemaVersion = 1.
//
// `config_json` — контракт ADR-018 §1 (`version = 1`). Строка с битым или
// чужим JSON пропускается: один повреждённый пресет не ломает экран.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_preset.dart';
import 'package:cardflow/domain/session/session_preset_repository.dart';

/// Репозиторий пресетов поверх drift-БД (`session_presets`).
class DriftSessionPresetRepository implements SessionPresetRepository {
  /// Создаёт репозиторий поверх БД.
  DriftSessionPresetRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  static const Uuid _uuid = Uuid();

  @override
  Future<List<SessionPreset>> presets() async {
    final List<SessionPresetRow> rows =
        await (database.select(database.sessionPresets)
              ..orderBy(<OrderingTerm Function($SessionPresetsTable)>[
                (table) => OrderingTerm.asc(table.createdAt),
                (table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    final List<SessionPreset> result = <SessionPreset>[];
    for (final SessionPresetRow row in rows) {
      final SessionPreset? preset = _mapRow(row);
      if (preset != null) result.add(preset);
    }
    return List<SessionPreset>.unmodifiable(result);
  }

  @override
  Future<SessionPreset> savePreset({
    required String name,
    required SessionConfig config,
    required DateTime createdAt,
  }) async {
    final SessionPreset preset = SessionPreset(
      id: _uuid.v4(),
      name: name,
      config: config,
      createdAt: createdAt.toUtc(),
    );
    await database
        .into(database.sessionPresets)
        .insert(
          SessionPresetsCompanion.insert(
            id: preset.id,
            name: preset.name,
            configJson: jsonEncode(config.toJson()),
            createdAt: toEpochMs(preset.createdAt),
          ),
        );
    return preset;
  }

  @override
  Future<void> deletePreset(String presetId) async {
    await (database.delete(
      database.sessionPresets,
    )..where(($SessionPresetsTable table) => table.id.equals(presetId))).go();
  }

  SessionPreset? _mapRow(SessionPresetRow row) {
    try {
      final Object? decoded = jsonDecode(row.configJson);
      if (decoded is! Map<String, Object?>) return null;
      return SessionPreset(
        id: row.id,
        name: row.name,
        config: SessionConfig.fromJson(decoded),
        createdAt: fromEpochMs(row.createdAt),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
