import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/model_limits_resolver.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// ADR-039 §2/§5: слияние слоёв и миграция legacy.
void main() {
  final DateTime now = DateTime.utc(2026, 11, 20);

  ProviderAccount deepseek() => ProviderAccount.fromPreset(
    providerPresetById('deepseek')!,
    id: 'deepseek',
  );

  ModelCapabilityRecord cached({
    DateTime? fetchedAt,
    ModelLimits limits = const ModelLimits.absent(),
  }) => ModelCapabilityRecord(
    accountId: 'deepseek',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-flash',
    fetchedAt: fetchedAt ?? now,
    limits: limits,
  );

  test('пресет с датой и ссылкой — officialCatalog с датой', () {
    final ModelLimits limits = resolveModelLimits(
      account: deepseek(),
      preset: providerPresetById('deepseek'),
      now: now,
    );
    expect(limits.contextTokens.value, 1000000);
    expect(limits.contextTokens.source, CapabilitySource.officialCatalog);
    expect(limits.contextTokens.sourceRef, isNotNull);
    expect(limits.contextTokens.observedAt, DateTime.utc(2026, 11, 19));
    expect(limits.contextSemantics, ContextSemantics.totalInputPlusOutput);
    expect(limits.supportsImageInput.source, CapabilitySource.officialCatalog);
  });

  test('пресет без даты проверки — assumption, не факт', () {
    final ProviderAccount openai = ProviderAccount.fromPreset(
      providerPresetById('openai')!,
      id: 'openai',
    );
    final ModelLimits limits = resolveModelLimits(
      account: openai,
      preset: providerPresetById('openai'),
      now: now,
    );
    expect(limits.contextTokens.value, 128000);
    expect(limits.contextTokens.source, CapabilitySource.assumption);
    expect(limits.contextTokens.sourceRef, isNull);
  });

  test('API перекрывает каталог, пользователь перекрывает API', () {
    final ModelCapabilityRecord api = cached(
      limits: ModelLimits(
        contextTokens: Sourced<int>(
          200000,
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
    );
    final ModelLimits apiWins = resolveModelLimits(
      account: deepseek(),
      preset: providerPresetById('deepseek'),
      cached: api,
      now: now,
    );
    expect(apiWins.contextTokens.value, 200000);
    expect(apiWins.contextTokens.source, CapabilitySource.providerApi);
    expect(apiWins.maxOutputTokens.value, 16384);

    final ProviderAccount user = deepseek().copyWith(
      maxOutputTokens: 4096,
      capabilitiesSource: CapabilitySource.userConfigured,
    );
    final ModelLimits userWins = resolveModelLimits(
      account: user,
      preset: providerPresetById('deepseek'),
      cached: api,
      now: now,
    );
    expect(userWins.contextTokens.value, 200000);
    expect(userWins.contextTokens.source, CapabilitySource.providerApi);
    expect(userWins.maxOutputTokens.value, 4096);
    expect(userWins.maxOutputTokens.source, CapabilitySource.userConfigured);
  });

  test('значение контекста из пресета не считается пользовательским', () {
    final ModelLimits limits = resolveModelLimits(
      account: deepseek(),
      preset: providerPresetById('deepseek'),
      now: now,
    );
    expect(limits.contextTokens.source, CapabilitySource.officialCatalog);
  });

  test('пользовательская модель: окно неизвестно, эвристика → assumption', () {
    const ProviderAccount account = ProviderAccount(
      id: 'custom',
      label: 'Custom',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'https://example.test/v1',
      modelId: 'gpt-4o-custom',
      supportsVision: true,
    );
    final ModelLimits limits = resolveModelLimits(account: account, now: now);
    expect(limits.contextTokens.isKnown, isFalse);
    expect(limits.supportsImageInput.value, isTrue);
    expect(limits.supportsImageInput.source, CapabilitySource.assumption);
  });

  test('явный флаг Vision пользователя — userConfigured', () {
    const ProviderAccount account = ProviderAccount(
      id: 'custom',
      label: 'Custom',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'https://example.test/v1',
      modelId: 'm',
      supportsVision: false,
      visionConfigured: true,
    );
    final ModelLimits limits = resolveModelLimits(account: account, now: now);
    expect(limits.supportsImageInput.value, isFalse);
    expect(limits.supportsImageInput.source, CapabilitySource.userConfigured);

    const ProviderAccount noFlag = ProviderAccount(
      id: 'custom',
      label: 'Custom',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'https://example.test/v1',
      modelId: 'm',
    );
    expect(
      resolveModelLimits(account: noFlag, now: now).supportsImageInput.isKnown,
      isFalse,
    );
  });

  test('смена baseUrl/model/ключа меняет ключ записи', () {
    final ModelCapabilityRecord base = cached();
    expect(
      base.key,
      'deepseek|openai-completions|https://api.deepseek.com|deepseek-flash',
    );
    expect(cached(limits: const ModelLimits.absent()).key, base.key);
    final ModelCapabilityRecord otherModel = ModelCapabilityRecord(
      accountId: 'deepseek',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'https://api.deepseek.com/',
      model: 'DeepSeek-Flash',
      fetchedAt: now,
      limits: const ModelLimits.absent(),
    );
    expect(otherModel.key, base.key);
    final ModelCapabilityRecord moved = ModelCapabilityRecord(
      accountId: 'deepseek',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'https://proxy.test/v1',
      model: 'deepseek-flash',
      fetchedAt: now,
      limits: const ModelLimits.absent(),
    );
    expect(moved.key, isNot(base.key));
    expect(base.key, isNot(contains('?')));
  });

  test('TTL 7 дней и ошибка не стирают последнее удачное значение', () {
    final ModelCapabilityRecord record = cached(
      fetchedAt: now.subtract(const Duration(days: 6)),
      limits: ModelLimits(
        contextTokens: Sourced<int>(
          1000,
          source: CapabilitySource.providerApi,
          observedAt: now,
          sourceRef: 'https://api.deepseek.com/models',
        ),
      ),
    );
    expect(record.isFresh(now), isTrue);
    expect(
      record.isFresh(now.add(const Duration(days: 2))),
      isFalse,
      reason: 'запись используется, но подлежит обновлению',
    );
    final ModelCapabilityRecord errored = record.withError(
      'timeout',
      now.add(const Duration(hours: 1)),
    );
    expect(errored.limits.contextTokens.value, 1000);
    expect(errored.lastErrorCode, 'timeout');
    expect(errored.lastAttemptAt, isNotNull);
    expect(errored.fetchedAt, record.fetchedAt);
  });

  test('цены пользователя сохраняются со своим источником', () {
    final ProviderAccount account = deepseek().copyWith(
      pricing: const GenerationPricing(
        inputPerMillion: 0.5,
        outputPerMillion: 1.5,
        currency: 'USD',
      ),
      capabilitiesSource: CapabilitySource.userConfigured,
    );
    final ModelLimits limits = resolveModelLimits(
      account: account,
      preset: providerPresetById('deepseek'),
      now: now,
    );
    expect(limits.pricing.value!.inputPerMillion, 0.5);
    expect(limits.pricing.source, CapabilitySource.userConfigured);
  });
}
