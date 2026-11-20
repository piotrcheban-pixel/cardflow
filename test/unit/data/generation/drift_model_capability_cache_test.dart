import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Кэш `generation.model_capabilities` v1 поверх `app_settings` (ADR-039 §4).
void main() {
  late AppDatabase db;
  late DriftModelCapabilityCache cache;
  final DateTime now = DateTime.utc(2026, 11, 20, 12);

  ModelCapabilityRecord record({
    String baseUrl = 'https://api.deepseek.com',
    String model = 'deepseek-flash',
    DateTime? fetchedAt,
    String? error,
  }) => ModelCapabilityRecord(
    accountId: 'deepseek',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: baseUrl,
    model: model,
    fetchedAt: fetchedAt ?? now,
    checkedAt: '2026-11-20',
    sourceRef: 'https://api.deepseek.com/models',
    limits: ModelLimits(
      contextTokens: Sourced<int>(
        1000000,
        source: CapabilitySource.providerApi,
        observedAt: now,
        sourceRef: 'https://api.deepseek.com/models',
      ),
      maxOutputTokens: Sourced<int>(
        16384,
        source: CapabilitySource.providerApi,
        observedAt: now,
        sourceRef: 'https://api.deepseek.com/models',
      ),
    ),
    lastErrorCode: error,
  );

  setUp(() {
    db = AppDatabase.inMemory();
    cache = DriftModelCapabilityCache(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('пустой кэш — пустой список', () async {
    expect(await cache.readAll(), isEmpty);
    expect(
      await cache.read(
        accountId: 'deepseek',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
      ),
      isNull,
    );
  });

  test('write → read: лимиты, источник и метаданные сохраняются', () async {
    await cache.write(record(error: 'timeout'));
    final List<ModelCapabilityRecord> records = await cache.readAll();
    expect(records, hasLength(1));
    final ModelCapabilityRecord loaded = records.single;
    expect(loaded.limits.contextTokens.value, 1000000);
    expect(loaded.limits.contextTokens.source, CapabilitySource.providerApi);
    expect(loaded.limits.contextTokens.observedAt, now);
    expect(loaded.limits.maxOutputTokens.value, 16384);
    expect(loaded.checkedAt, '2026-11-20');
    expect(loaded.sourceRef, 'https://api.deepseek.com/models');
    expect(loaded.lastErrorCode, 'timeout');
    expect(loaded.key, record().key);
  });

  test('upsert по ключу: та же модель обновляется, другие живут', () async {
    await cache.write(record());
    await cache.write(record(model: 'deepseek-chat'));
    await cache.write(
      ModelCapabilityRecord(
        accountId: 'deepseek',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        fetchedAt: now.add(const Duration(days: 1)),
        limits: const ModelLimits.absent(),
      ),
    );
    final List<ModelCapabilityRecord> records = await cache.readAll();
    expect(records, hasLength(2));
    final ModelCapabilityRecord flash = records.firstWhere(
      (ModelCapabilityRecord r) => r.model == 'deepseek-flash',
    );
    expect(flash.fetchedAt, now.add(const Duration(days: 1)));
  });

  test('смена baseUrl или модели — другая запись', () async {
    await cache.write(record());
    expect(
      await cache.read(
        accountId: 'deepseek',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://proxy.test/v1',
        model: 'deepseek-flash',
      ),
      isNull,
    );
    expect(
      await cache.read(
        accountId: 'deepseek',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://api.deepseek.com/',
        model: 'deepseek-flash',
      ),
      isNotNull,
      reason: 'хвостовой слэш и регистр не создают новую запись',
    );
  });

  test('инвалидация аккаунта удаляет только его записи', () async {
    await cache.write(record());
    await cache.write(
      ModelCapabilityRecord(
        accountId: 'other',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        fetchedAt: now,
        limits: const ModelLimits.absent(),
      ),
    );
    await cache.invalidateAccount('deepseek');
    final List<ModelCapabilityRecord> records = await cache.readAll();
    expect(records, hasLength(1));
    expect(records.single.accountId, 'other');
  });

  test('JSON v1, без ключей и тел запросов', () async {
    await cache.write(record());
    final AppSettingRow row = (await db.select(db.appSettings).get()).single;
    expect(row.key, 'generation.model_capabilities');
    final Map<String, Object?> json =
        jsonDecode(row.valueJson) as Map<String, Object?>;
    expect(json['version'], 1);
    expect(json['records'], isA<List<Object?>>());
    for (final String forbidden in <String>[
      'api_key',
      'apiKey',
      'Authorization',
      'Bearer',
      'body',
    ]) {
      expect(row.valueJson, isNot(contains(forbidden)));
    }
  });

  test('битый JSON и битые записи не ломают кэш', () async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: DriftModelCapabilityCache.settingKey,
            valueJson: '{not json',
          ),
        );
    expect(await cache.readAll(), isEmpty);

    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: DriftModelCapabilityCache.settingKey,
            valueJson: jsonEncode(<String, Object?>{
              'version': 1,
              'records': <Object?>[
                <String, Object?>{'account_id': 'broken'},
                record().toJson(),
              ],
            }),
          ),
        );
    final List<ModelCapabilityRecord> records = await cache.readAll();
    expect(records, hasLength(1));
  });
}
