import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/models/model_capability_service.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_capability_discovery.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Сервис характеристик: кэш, обновление и инвалидация (ADR-039 §4).
void main() {
  final DateTime now = DateTime.utc(2026, 11, 20, 12);

  ProviderAccount deepseek() => ProviderAccount.fromPreset(
    providerPresetById('deepseek')!,
    id: 'deepseek',
  );

  late _FakeCache cache;
  late _FakeDiscovery discovery;
  late ModelCapabilityService service;

  ModelLimits apiLimits({int context = 200000}) => ModelLimits(
    contextTokens: Sourced<int>(
      context,
      source: CapabilitySource.providerApi,
      observedAt: now,
      sourceRef: 'https://api.deepseek.com/models',
    ),
  );

  setUp(() {
    cache = _FakeCache();
    discovery = _FakeDiscovery();
    service = ModelCapabilityService(
      dio: Dio(),
      readApiKey: (String id) async => 'test-key',
      cache: cache,
      now: () => now,
    );
  });

  test('limitsFor читает только кэш: сеть не вызывается', () async {
    cache.records.add(
      ModelCapabilityRecord(
        accountId: 'deepseek',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        fetchedAt: now,
        limits: apiLimits(),
      ),
    );
    final ModelLimits limits = await service.limitsFor(deepseek());
    expect(limits.contextTokens.value, 200000);
    expect(limits.contextTokens.source, CapabilitySource.providerApi);
  });

  test('успешное обновление пишет запись с датой и ссылкой', () async {
    final ModelCapabilityService local = ModelCapabilityService(
      dio: Dio(),
      readApiKey: (String id) async => 'test-key',
      cache: cache,
      now: () => now,
      discoveryOverride: (ProviderAccount account) => discovery,
    );
    final CapabilityRefresh refresh = await local.refresh(deepseek());
    expect(refresh.result.isSuccess, isTrue);
    expect(refresh.record!.limits.contextTokens.value, 200000);
    expect(refresh.record!.checkedAt, '2026-11-20');
    expect(refresh.record!.sourceRef, 'https://api.deepseek.com/models');
    expect(cache.records, hasLength(1));
  });

  test('ошибка обновления не стирает последнее удачное значение', () async {
    final ModelCapabilityRecord previous = ModelCapabilityRecord(
      accountId: 'deepseek',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      fetchedAt: now.subtract(const Duration(days: 1)),
      limits: apiLimits(context: 100000),
    );
    cache.records.add(previous);
    final ModelCapabilityService local = ModelCapabilityService(
      dio: Dio(),
      readApiKey: (String id) async => 'test-key',
      cache: cache,
      now: () => now,
      discoveryOverride: (ProviderAccount account) => discovery
        ..result = const DiscoveryResult(
          status: DiscoveryStatus.timeout,
          accountId: 'deepseek',
          model: 'deepseek-flash',
          errorCode: 'timeout',
        ),
    );
    final CapabilityRefresh refresh = await local.refresh(deepseek());
    expect(refresh.result.isSuccess, isFalse);
    expect(refresh.record!.limits.contextTokens.value, 100000);
    expect(refresh.record!.lastErrorCode, 'timeout');
    expect(cache.records, hasLength(1));
  });

  test('инвалидация аккаунта удаляет записи', () async {
    cache.records.add(
      ModelCapabilityRecord(
        accountId: 'deepseek',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        fetchedAt: now,
        limits: apiLimits(),
      ),
    );
    await service.invalidateAccount('deepseek');
    expect(cache.records, isEmpty);
  });
}

class _FakeCache implements ModelCapabilityCache {
  final List<ModelCapabilityRecord> records = <ModelCapabilityRecord>[];

  @override
  Future<void> invalidateAccount(String accountId) async {
    records.removeWhere((ModelCapabilityRecord r) => r.accountId == accountId);
  }

  @override
  Future<ModelCapabilityRecord?> read({
    required String accountId,
    required ProviderProtocol protocol,
    required String baseUrl,
    required String model,
  }) async {
    for (final ModelCapabilityRecord record in records) {
      if (record.accountId == accountId &&
          record.protocol == protocol &&
          record.model == model) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<List<ModelCapabilityRecord>> readAll() async =>
      List<ModelCapabilityRecord>.of(records);

  @override
  Future<void> write(ModelCapabilityRecord record) async {
    records.removeWhere(
      (ModelCapabilityRecord r) =>
          r.accountId == record.accountId && r.model == record.model,
    );
    records.add(record);
  }
}

class _FakeDiscovery implements ModelCapabilityDiscovery {
  DiscoveryResult result = DiscoveryResult(
    status: DiscoveryStatus.success,
    accountId: 'deepseek',
    model: 'deepseek-flash',
    limits: ModelLimits(
      contextTokens: Sourced<int>(
        200000,
        source: CapabilitySource.providerApi,
        observedAt: DateTime.utc(2026, 11, 20),
        sourceRef: 'https://api.deepseek.com/models',
      ),
    ),
    fetchedAt: DateTime.utc(2026, 11, 20),
    sourceRef: 'https://api.deepseek.com/models',
  );

  @override
  Future<DiscoveryResult> discover(ProviderAccount account) async => result;
}
