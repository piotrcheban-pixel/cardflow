import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/model_limits_resolver.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// 7.18.1 §2.4: ручные характеристики модели — источник `userConfigured`,
/// приоритет над API/каталогом, дата проверки и сброс к автоматическим.
void main() {
  ProviderAccount account({
    CapabilitySource source = CapabilitySource.unknown,
    DateTime? configuredAt,
    int? maxInput,
    int? maxOutput,
    int context = kCustomProviderContextTokens,
  }) {
    return ProviderAccount(
      id: 'acc',
      label: 'Acc',
      protocol: ProviderProtocol.anthropicMessages,
      baseUrl: 'https://api.anthropic.com',
      modelId: 'claude-test',
      contextTokens: context,
      maxInputTokens: maxInput,
      maxOutputTokens: maxOutput,
      capabilitiesSource: source,
      capabilitiesConfiguredAt: configuredAt,
    );
  }

  test('withConfiguredCapabilities: userConfigured и дата проверки', () {
    final DateTime at = DateTime.utc(2026, 11, 21, 12);
    final ProviderAccount configured = account().withConfiguredCapabilities(
      contextTokens: 200000,
      maxInputTokens: 190000,
      maxOutputTokens: 16000,
      configuredAt: at,
    );
    expect(configured.contextTokens, 200000);
    expect(configured.maxInputTokens, 190000);
    expect(configured.maxOutputTokens, 16000);
    expect(configured.capabilitiesSource, CapabilitySource.userConfigured);
    expect(configured.capabilitiesConfiguredAt, at);
  });

  test('JSON: max_input_tokens и дата сохраняются и читаются', () {
    final DateTime at = DateTime.utc(2026, 11, 21, 12);
    final ProviderAccount configured = account().withConfiguredCapabilities(
      contextTokens: 200000,
      maxInputTokens: 190000,
      maxOutputTokens: 16000,
      configuredAt: at,
    );
    final ProviderAccount restored = ProviderAccount.fromJson(
      configured.toJson(),
    )!;
    expect(restored.maxInputTokens, 190000);
    expect(restored.capabilitiesConfiguredAt, at);
    expect(restored.capabilitiesSource, CapabilitySource.userConfigured);
    expect(restored.toJson()['max_input_tokens'], 190000);
  });

  test('ручные значения важнее providerApi, у каждого источника дата', () {
    final DateTime configuredAt = DateTime.utc(2026, 11, 20);
    final ModelCapabilityRecord cached = ModelCapabilityRecord(
      accountId: 'acc',
      protocol: ProviderProtocol.anthropicMessages,
      baseUrl: 'https://api.anthropic.com',
      model: 'claude-test',
      fetchedAt: DateTime.utc(2026, 11, 19),
      limits: ModelLimits(
        contextTokens: Sourced<int>(
          150000,
          source: CapabilitySource.providerApi,
          sourceRef: 'https://api.anthropic.com/v1/models',
          observedAt: DateTime.utc(2026, 11, 19),
        ),
        maxInputTokens: Sourced<int>(
          140000,
          source: CapabilitySource.providerApi,
          sourceRef: 'https://api.anthropic.com/v1/models',
        ),
      ),
    );
    final ModelLimits limits = resolveModelLimits(
      account: account(
        source: CapabilitySource.userConfigured,
        configuredAt: configuredAt,
        maxInput: 180000,
        context: 200000,
      ),
      cached: cached,
    );
    expect(limits.contextTokens.value, 200000);
    expect(limits.contextTokens.source, CapabilitySource.userConfigured);
    expect(limits.contextTokens.observedAt, configuredAt);
    expect(limits.maxInputTokens.value, 180000);
    expect(limits.maxInputTokens.source, CapabilitySource.userConfigured);
    expect(limits.maxInputTokens.observedAt, configuredAt);
  });

  test('сброс к автоматическому очищает ручные значения и дату', () {
    final ProviderPreset preset = providerPresetById('anthropic')!;
    final ProviderAccount configured =
        ProviderAccount.fromPreset(
          preset,
          id: 'acc',
        ).withConfiguredCapabilities(
          contextTokens: 200000,
          maxInputTokens: 190000,
          maxOutputTokens: 16000,
          configuredAt: DateTime.utc(2026, 11, 21),
        );
    final ProviderAccount automatic = configured.withAutomaticCapabilities();
    expect(automatic.maxInputTokens, isNull);
    expect(automatic.maxOutputTokens, isNull);
    expect(automatic.capabilitiesConfiguredAt, isNull);
    expect(automatic.capabilitiesSource, CapabilitySource.unknown);
    // Контекст возвращается к каталогу пресета (может совпасть числом — важно
    // происхождение, а не равенство), ручных значений и даты больше нет.
    final ProviderPresetModel model = preset.modelById(automatic.modelId)!;
    expect(automatic.contextTokens, model.contextTokens);
  });

  test('сброс к автоматическому не теряет Vision пользовательской модели', () {
    final ProviderAccount vision =
        ProviderAccount(
          id: 'custom',
          label: 'Свой сервер',
          protocol: ProviderProtocol.openaiCompletions,
          baseUrl: 'http://localhost:1234/v1',
          modelId: 'qwen2.5-vl',
          supportsVision: true,
          visionConfigured: true,
        ).withConfiguredCapabilities(
          contextTokens: 64000,
          maxInputTokens: 60000,
          maxOutputTokens: 8192,
          configuredAt: DateTime.utc(2026, 11, 21),
        );
    final ProviderAccount automatic = vision.withAutomaticCapabilities();
    expect(
      automatic.supportsVision,
      isTrue,
      reason: 'сброс лимитов не должен молча выключать изображения',
    );
    expect(automatic.visionConfigured, isTrue);
    expect(automatic.maxInputTokens, isNull);
    expect(automatic.capabilitiesConfiguredAt, isNull);
  });

  test('копирование аккаунта не теряет явно заданный Vision', () {
    final ProviderAccount configured =
        ProviderAccount.fromPreset(
          providerPresetById('deepseek')!,
          id: 'deepseek',
          modelId: 'deepseek-chat',
        ).copyWith(supportsVision: true, visionConfigured: true);
    expect(
      configured.visionConfigured,
      isTrue,
      reason: 'copyWith обязан переносить признак пользовательской настройки',
    );
    // Копия, как её делает экран генерации (модель/контекст/Vision).
    final ProviderAccount copied = configured.copyWith(
      modelId: 'deepseek-chat',
      supportsVision: configured.supportsVision,
    );
    expect(copied.visionConfigured, isTrue);
    final ModelLimits limits = resolveModelLimits(
      account: copied,
      preset: providerPresetById('deepseek'),
    );
    expect(limits.supportsImageInput.value, isTrue);
    expect(
      limits.supportsImageInput.source,
      CapabilitySource.userConfigured,
      reason: 'каталог не перекрывает явную настройку пользователя',
    );
  });

  test('пользовательский аккаунт без ручных значений: лимиты неизвестны', () {
    final ModelLimits limits = resolveModelLimits(account: account());
    expect(limits.contextTokens.value, isNull);
    expect(limits.maxInputTokens.value, isNull);
    expect(limits.maxOutputTokens.value, isNull);
  });
}
