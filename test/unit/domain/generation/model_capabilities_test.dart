import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// TASK 02A: возможности провайдера и модели (раздел C аудита).
///
/// Главные инварианты: у значения есть источник, неизвестное — `null` (а не 0
/// и не типовое число), окно контекста пользовательской модели не выдумывается
/// из константы-заглушки аккаунта.
void main() {
  group('ModelCapabilities', () {
    test('известные характеристики: все поля и источники сохранены', () {
      const ModelCapabilities capabilities = ModelCapabilities(
        contextWindowTokens: 128000,
        maxInputTokens: 120000,
        maxOutputTokens: 8192,
        maxCardsPerRequest: 20,
        maxImagesPerRequest: 8,
        maxImageBytesPerImage: 5 * 1024 * 1024,
        maxImageBytesPerRequest: 20 * 1024 * 1024,
        maxImageSidePx: 2048,
        maxRequestBytes: 25 * 1024 * 1024,
        supportsVision: true,
        supportsPdfDocumentPart: true,
        supportsStrictJsonSchema: true,
        tokenizer: TokenizerKind.exact,
        imageTokens: _FakeImageTokenModel(),
        pricing: GenerationPricing(
          inputPerMillion: 1,
          outputPerMillion: 2,
          currency: 'USD',
        ),
        contextSource: CapabilitySource.officialCatalog,
        outputSource: CapabilitySource.officialCatalog,
        imageSource: CapabilitySource.officialCatalog,
        pricingSource: CapabilitySource.officialCatalog,
      );
      expect(capabilities.contextWindowTokens, 128000);
      expect(capabilities.maxInputTokens, 120000);
      expect(capabilities.maxOutputTokens, 8192);
      expect(capabilities.maxCardsPerRequest, 20);
      expect(capabilities.maxImagesPerRequest, 8);
      expect(capabilities.maxImageBytesPerImage, 5 * 1024 * 1024);
      expect(capabilities.maxImageBytesPerRequest, 20 * 1024 * 1024);
      expect(capabilities.maxImageSidePx, 2048);
      expect(capabilities.maxRequestBytes, 25 * 1024 * 1024);
      expect(capabilities.supportsVision, isTrue);
      expect(capabilities.supportsPdfDocumentPart, isTrue);
      expect(capabilities.supportsStrictJsonSchema, isTrue);
      expect(capabilities.tokenizer, TokenizerKind.exact);
      expect(capabilities.imageTokens, isNotNull);
      expect(
        capabilities.imageTokens!.estimate(bytes: 1),
        123,
        reason: 'оценщик изображений сохраняется как есть',
      );
      expect(capabilities.pricingState, PricingState.complete);
      expect(capabilities.hasContextWindow, isTrue);
      expect(capabilities.unknownFields, isEmpty);
    });

    test('неизвестные характеристики — null и явный источник unknown', () {
      const ModelCapabilities capabilities = ModelCapabilities();
      expect(capabilities.contextWindowTokens, isNull);
      expect(capabilities.maxInputTokens, isNull);
      expect(capabilities.maxOutputTokens, isNull);
      expect(capabilities.maxCardsPerRequest, isNull);
      expect(capabilities.maxImagesPerRequest, isNull);
      expect(capabilities.maxImageBytesPerImage, isNull);
      expect(capabilities.maxImageBytesPerRequest, isNull);
      expect(capabilities.maxImageSidePx, isNull);
      expect(capabilities.maxRequestBytes, isNull);
      expect(capabilities.supportsStrictJsonSchema, isNull);
      expect(capabilities.imageTokens, isNull);
      expect(capabilities.pricing, isNull);
      expect(capabilities.pricingState, PricingState.unknown);
      expect(capabilities.hasContextWindow, isFalse);
      expect(capabilities.contextSource, CapabilitySource.unknown);
      expect(capabilities.outputSource, CapabilitySource.unknown);
      expect(capabilities.imageSource, CapabilitySource.unknown);
      expect(capabilities.pricingSource, CapabilitySource.unknown);
      expect(capabilities.tokenizer, TokenizerKind.unknown);
      expect(capabilities.unknownFields, <String>[
        ModelCapabilities.unknownContextWindow,
        ModelCapabilities.unknownOutputTokens,
        ModelCapabilities.unknownImageLimits,
        ModelCapabilities.unknownPricing,
      ]);
    });

    test('unknownFields перечисляет только неизвестные группы', () {
      const ModelCapabilities capabilities = ModelCapabilities(
        contextWindowTokens: 32000,
        contextSource: CapabilitySource.officialCatalog,
      );
      expect(
        capabilities.unknownFields,
        containsAll(<String>[
          ModelCapabilities.unknownOutputTokens,
          ModelCapabilities.unknownImageLimits,
          ModelCapabilities.unknownPricing,
        ]),
      );
      expect(
        capabilities.unknownFields,
        isNot(contains(ModelCapabilities.unknownContextWindow)),
      );
    });

    test('CapabilitySource разбирается из wire-имени, мусор — unknown', () {
      expect(CapabilitySource.fromWire('verified'), CapabilitySource.officialCatalog);
      expect(CapabilitySource.fromWire('preset'), CapabilitySource.officialCatalog);
      expect(CapabilitySource.fromWire('user'), CapabilitySource.userConfigured);
      expect(CapabilitySource.fromWire('inferred'), CapabilitySource.assumption);
      expect(CapabilitySource.fromWire('unknown'), CapabilitySource.unknown);
      expect(CapabilitySource.fromWire('magic'), CapabilitySource.unknown);
      expect(CapabilitySource.fromWire(null), CapabilitySource.unknown);
      expect(CapabilitySource.fromWire(1), CapabilitySource.unknown);
      expect(CapabilitySource.unknown.isKnown, isFalse);
      expect(CapabilitySource.officialCatalog.isKnown, isTrue);
    });

    test('ADR-039: новые wire-имена и приоритет источников', () {
      expect(
        CapabilitySource.fromWire('user_configured'),
        CapabilitySource.userConfigured,
      );
      expect(
        CapabilitySource.fromWire('provider_api'),
        CapabilitySource.providerApi,
      );
      expect(
        CapabilitySource.fromWire('official_catalog'),
        CapabilitySource.officialCatalog,
      );
      expect(
        CapabilitySource.fromWire('assumption'),
        CapabilitySource.assumption,
      );
      expect(
        CapabilitySource.fromWire('user_configured').wireName,
        'user_configured',
      );
      // Приоритет слияния: пользователь → API → каталог → допущение.
      expect(
        CapabilitySource.userConfigured.priority,
        greaterThan(CapabilitySource.providerApi.priority),
      );
      expect(
        CapabilitySource.providerApi.priority,
        greaterThan(CapabilitySource.officialCatalog.priority),
      );
      expect(
        CapabilitySource.officialCatalog.priority,
        greaterThan(CapabilitySource.assumption.priority),
      );
      expect(CapabilitySource.assumption.priority, greaterThan(0));
    });
  });

  group('resolveModelCapabilities', () {
    test('аккаунт из пресета: окно — из каталога, источник preset', () {
      final ProviderAccount account = ProviderAccount.fromPreset(
        providerPresetById('deepseek')!,
        id: 'deepseek',
      );
      final ModelCapabilities capabilities = resolveModelCapabilities(account);
      expect(capabilities.contextWindowTokens, 1000000);
      expect(capabilities.contextSource, CapabilitySource.officialCatalog);
      expect(capabilities.maxOutputTokens, isNull);
      expect(capabilities.maxImagesPerRequest, isNull);
      expect(capabilities.pricing, isNull);
      expect(capabilities.supportsVision, isTrue);
      expect(capabilities.supportsPdfDocumentPart, isFalse);
      expect(capabilities.supportsStrictJsonSchema, isNull);
      expect(capabilities.tokenizer, TokenizerKind.unknown);
      expect(capabilities.imageTokens, isNull);
      expect(capabilities.outputSource, CapabilitySource.unknown);
      expect(capabilities.pricingSource, CapabilitySource.unknown);
    });

    test('vision и PDF берутся из аккаунта и протокола', () {
      final ModelCapabilities openAi = resolveModelCapabilities(
        ProviderAccount.fromPreset(providerPresetById('openai')!, id: 'openai'),
      );
      expect(openAi.supportsVision, isTrue);
      expect(openAi.supportsPdfDocumentPart, isFalse);

      final ModelCapabilities anthropic = resolveModelCapabilities(
        ProviderAccount.fromPreset(
          providerPresetById('anthropic')!,
          id: 'anthropic',
        ),
      );
      expect(anthropic.supportsVision, isTrue);
      expect(anthropic.supportsPdfDocumentPart, isTrue);
      expect(anthropic.contextWindowTokens, 200000);

      final ModelCapabilities gemini = resolveModelCapabilities(
        ProviderAccount.fromPreset(
          providerPresetById('gemini')!,
          id: 'gemini',
          modelId: 'gemini-2.5-flash',
        ),
      );
      expect(gemini.contextWindowTokens, 1048576);
      expect(gemini.supportsPdfDocumentPart, isTrue);
    });

    test(
      'пользовательская модель: окно неизвестно, а не 16000 из аккаунта',
      () {
        const ProviderAccount account = ProviderAccount(
          id: 'my-server',
          label: 'Мой сервер',
          protocol: ProviderProtocol.openaiCompletions,
          baseUrl: 'http://localhost:1234/v1',
          modelId: 'qwen2.5',
        );
        expect(account.contextTokens, kCustomProviderContextTokens);
        final ModelCapabilities capabilities = resolveModelCapabilities(
          account,
        );
        expect(
          capabilities.contextWindowTokens,
          isNull,
          reason: '16 000 — заглушка приложения, а не окно модели (L-18)',
        );
        expect(capabilities.contextSource, CapabilitySource.unknown);
        expect(
          capabilities.unknownFields,
          contains(ModelCapabilities.unknownContextWindow),
        );
      },
    );

    test('пользовательские значения: значения и источник user', () {
      final ProviderAccount account =
          ProviderAccount.fromPreset(
            providerPresetById('deepseek')!,
            id: 'deepseek',
          ).copyWith(
            maxOutputTokens: 16384,
            maxImagesPerRequest: 8,
            maxImageBytes: 5 * 1024 * 1024,
            maxRequestBytes: 25 * 1024 * 1024,
            pricing: const GenerationPricing(
              inputPerMillion: 0.27,
              outputPerMillion: 1.1,
              currency: 'USD',
            ),
            capabilitiesSource: CapabilitySource.userConfigured,
          );
      final ModelCapabilities capabilities = resolveModelCapabilities(account);
      expect(capabilities.contextWindowTokens, 1000000);
      expect(capabilities.contextSource, CapabilitySource.officialCatalog);
      expect(capabilities.maxOutputTokens, 16384);
      expect(capabilities.outputSource, CapabilitySource.userConfigured);
      expect(capabilities.maxImagesPerRequest, 8);
      expect(capabilities.maxImageBytesPerImage, 5 * 1024 * 1024);
      expect(capabilities.maxRequestBytes, 25 * 1024 * 1024);
      expect(capabilities.imageSource, CapabilitySource.userConfigured);
      expect(capabilities.pricingState, PricingState.complete);
      expect(capabilities.pricingSource, CapabilitySource.userConfigured);
      expect(
        capabilities.unknownFields,
        isNot(contains(ModelCapabilities.unknownPricing)),
      );
      expect(
        capabilities.unknownFields,
        isNot(contains(ModelCapabilities.unknownOutputTokens)),
      );
      expect(
        capabilities.unknownFields,
        contains(ModelCapabilities.unknownImageLimits),
        reason: 'лимиты на запрос и сторону изображения пока не хранятся',
      );
    });

    test('явный источник preset сохраняется для пользовательских полей', () {
      final ProviderAccount account = const ProviderAccount(
        id: 'x',
        label: 'X',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://x.test',
        modelId: 'm',
        maxOutputTokens: 4096,
        capabilitiesSource: CapabilitySource.officialCatalog,
      );
      final ModelCapabilities capabilities = resolveModelCapabilities(account);
      expect(capabilities.maxOutputTokens, 4096);
      expect(capabilities.outputSource, CapabilitySource.officialCatalog);
    });

    test('без значений источник остаётся unknown даже при user', () {
      final ProviderAccount account = ProviderAccount.fromPreset(
        providerPresetById('deepseek')!,
        id: 'deepseek',
      ).copyWith(capabilitiesSource: CapabilitySource.userConfigured);
      final ModelCapabilities capabilities = resolveModelCapabilities(account);
      expect(capabilities.maxOutputTokens, isNull);
      expect(capabilities.outputSource, CapabilitySource.unknown);
      expect(capabilities.imageSource, CapabilitySource.unknown);
      expect(capabilities.pricingSource, CapabilitySource.unknown);
    });

    test('JSON round-trip аккаунта сохраняет возможности и цены', () {
      final ProviderAccount account =
          ProviderAccount.fromPreset(
            providerPresetById('deepseek')!,
            id: 'deepseek',
          ).copyWith(
            maxOutputTokens: 16384,
            maxImagesPerRequest: 6,
            maxImageBytes: 4 * 1024 * 1024,
            maxRequestBytes: 20 * 1024 * 1024,
            pricing: const GenerationPricing(
              inputPerMillion: 0.5,
              outputPerMillion: null,
              currency: 'USD',
            ),
            capabilitiesSource: CapabilitySource.userConfigured,
          );
      final ProviderAccount? restored = ProviderAccount.fromJson(
        account.toJson(),
      );
      expect(restored, account);
      final ModelCapabilities capabilities = resolveModelCapabilities(
        restored!,
      );
      expect(capabilities.maxOutputTokens, 16384);
      expect(capabilities.maxImagesPerRequest, 6);
      expect(capabilities.maxImageBytesPerImage, 4 * 1024 * 1024);
      expect(capabilities.maxRequestBytes, 20 * 1024 * 1024);
      expect(capabilities.pricing!.inputPerMillion, 0.5);
      expect(capabilities.pricing!.outputPerMillion, isNull);
      expect(capabilities.pricingState, PricingState.incomplete);
      expect(capabilities.pricingSource, CapabilitySource.userConfigured);
    });

    test('старый JSON аккаунта: возможности неизвестны', () {
      final ProviderAccount? account = ProviderAccount.fromJson(
        <String, Object?>{
          'id': 'deepseek',
          'preset_id': 'deepseek',
          'protocol': 'openai-completions',
          'base_url': 'https://api.deepseek.com',
          'model': 'deepseek-chat',
          'context_tokens': 128000,
          'requires_api_key': true,
          'supports_vision': false,
        },
      );
      expect(account, isNotNull);
      final ModelCapabilities capabilities = resolveModelCapabilities(account!);
      // Legacy deepseek-chat остаётся в каталоге с окном 128k.
      expect(capabilities.contextWindowTokens, 128000);
      expect(capabilities.maxOutputTokens, isNull);
      expect(capabilities.pricing, isNull);
      expect(account.capabilitiesSource, CapabilitySource.unknown);
    });
  });
}

/// Фиктивная реализация интерфейса оценки изображений (E.4).
class _FakeImageTokenModel implements ImageTokenModel {
  const _FakeImageTokenModel();

  @override
  int estimate({int? width, int? height, required int bytes}) => 123;

  @override
  String get source => 'test_formula';
}
