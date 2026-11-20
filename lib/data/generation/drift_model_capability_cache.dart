/// Кэш характеристик модели поверх `app_settings` (ADR-039 §4).
///
/// Одно JSON-значение `generation.model_capabilities` версии 1; схема БД и
/// `schemaVersion` не меняются. Ключи API, их хэши и тела запросов сюда не
/// попадают: только лимиты с происхождением и метаданные обновления.
library;

import 'dart:convert';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Версия JSON-контракта кэша.
const int kModelCapabilityCacheVersion = 1;

/// Хранит записи характеристик в строке `app_settings`.
class DriftModelCapabilityCache implements ModelCapabilityCache {
  /// Создаёт кэш поверх [db].
  DriftModelCapabilityCache(this.db);

  /// БД приложения.
  final AppDatabase db;

  /// Ключ строки в `app_settings`.
  static const String settingKey = 'generation.model_capabilities';

  @override
  Future<List<ModelCapabilityRecord>> readAll() async {
    final AppSettingRow? row = await (db.select(
      db.appSettings,
    )..where((table) => table.key.equals(settingKey))).getSingleOrNull();
    if (row == null) return const <ModelCapabilityRecord>[];
    try {
      final Object? json = jsonDecode(row.valueJson);
      if (json is! Map) return const <ModelCapabilityRecord>[];
      final Object? records = json['records'];
      if (records is! List) return const <ModelCapabilityRecord>[];
      return <ModelCapabilityRecord>[
        for (final Object? item in records)
          if (ModelCapabilityRecord.fromJson(item)
              case final ModelCapabilityRecord record)
            record,
      ];
    } on FormatException {
      // Повреждённое значение не ломает план: считаем кэш пустым.
      return const <ModelCapabilityRecord>[];
    }
  }

  @override
  Future<ModelCapabilityRecord?> read({
    required String accountId,
    required ProviderProtocol protocol,
    required String baseUrl,
    required String model,
  }) async {
    final String key = ModelCapabilityRecord(
      accountId: accountId,
      protocol: protocol,
      baseUrl: baseUrl,
      model: model,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      limits: const ModelLimits.absent(),
    ).key;
    for (final ModelCapabilityRecord record in await readAll()) {
      if (record.key == key) return record;
    }
    return null;
  }

  @override
  Future<void> write(ModelCapabilityRecord record) async {
    final List<ModelCapabilityRecord> records = <ModelCapabilityRecord>[
      for (final ModelCapabilityRecord existing in await readAll())
        if (existing.key != record.key) existing,
      record,
    ];
    await _writeAll(records);
  }

  @override
  Future<void> invalidateAccount(String accountId) async {
    final String normalized = accountId.trim().toLowerCase();
    final List<ModelCapabilityRecord> records = <ModelCapabilityRecord>[
      for (final ModelCapabilityRecord record in await readAll())
        if (record.accountId.trim().toLowerCase() != normalized) record,
    ];
    await _writeAll(records);
  }

  Future<void> _writeAll(List<ModelCapabilityRecord> records) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: settingKey,
            valueJson: jsonEncode(<String, Object?>{
              'version': kModelCapabilityCacheVersion,
              'records': <Object?>[
                for (final ModelCapabilityRecord record in records)
                  record.toJson(),
              ],
            }),
          ),
        );
  }
}
