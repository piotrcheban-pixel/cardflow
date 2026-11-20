import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/generation_fakes.dart';

import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Итерация 7.5, шаг 2 (ADR-020): аккаунт провайдера и список аккаунтов.
void main() {
  ProviderAccount deepseek({String id = 'deepseek'}) {
    return ProviderAccount.fromPreset(providerPresetById('deepseek')!, id: id);
  }

  ProviderAccount custom() {
    return const ProviderAccount(
      id: 'my-server',
      label: 'Мой сервер',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'http://localhost:1234/v1',
      modelId: 'qwen2.5',
    );
  }

  group('ProviderAccount', () {
    test(
      'из пресета: адрес, протокол, модель и лимит контекста из каталога',
      () {
        final ProviderAccount account = ProviderAccount.fromPreset(
          providerPresetById('deepseek')!,
          id: 'deepseek',
        );
        expect(account.id, 'deepseek');
        expect(account.label, 'DeepSeek');
        expect(account.presetId, 'deepseek');
        expect(account.preset?.label, 'DeepSeek');
        expect(account.protocol, ProviderProtocol.openaiCompletions);
        expect(account.baseUrl, 'https://api.deepseek.com');
        expect(account.modelId, 'deepseek-flash');
        expect(account.contextTokens, 1000000);
        expect(account.supportsVision, isTrue);
        expect(account.requiresApiKey, isTrue);
        expect(account.isConfigured, isTrue);
      },
    );

    test(
      'из пресета с явной моделью; несуществующая — модель по умолчанию',
      () {
        final ProviderPreset gemini = providerPresetById('gemini')!;
        expect(
          ProviderAccount.fromPreset(
            gemini,
            id: 'gemini',
            modelId: 'gemini-2.5-flash',
          ).modelId,
          'gemini-2.5-flash',
        );
        expect(
          ProviderAccount.fromPreset(
            gemini,
            id: 'gemini',
            modelId: 'nope',
          ).modelId,
          'gemini-2.0-flash',
        );
      },
    );

    test('у пользовательского провайдера нет пресета и ключ не обязателен', () {
      final ProviderAccount account = custom();
      expect(account.preset, isNull);
      expect(account.presetId, isNull);
      expect(account.requiresApiKey, isFalse);
      expect(account.contextTokens, kCustomProviderContextTokens);
      expect(account.isConfigured, isTrue);
    });

    test('пустой адрес или модель — не настроен', () {
      expect(custom().copyWith(baseUrl: '  ').isConfigured, isFalse);
      expect(custom().copyWith(modelId: '').isConfigured, isFalse);
    });

    test('copyWith меняет поля, но не id и не presetId', () {
      final ProviderAccount account = deepseek().copyWith(
        modelId: 'deepseek-reasoner',
        contextTokens: 64000,
      );
      expect(account.id, 'deepseek');
      expect(account.presetId, 'deepseek');
      expect(account.modelId, 'deepseek-reasoner');
      expect(account.contextTokens, 64000);
      expect(account, isNot(deepseek()));
    });

    test('JSON round-trip сохраняет все поля и не содержит ключа', () {
      final ProviderAccount account = deepseek().copyWith(
        label: 'DeepSeek (рабочий)',
      );
      final Map<String, Object?> json = account.toJson();
      expect(json.containsKey('api_key'), isFalse);
      expect(json['id'], 'deepseek');
      expect(json['preset_id'], 'deepseek');
      expect(json['protocol'], 'openai-completions');
      expect(ProviderAccount.fromJson(json), account);
    });

    test('JSON: повреждённые записи возвращают null', () {
      expect(ProviderAccount.fromJson(null), isNull);
      expect(ProviderAccount.fromJson('deepseek'), isNull);
      expect(ProviderAccount.fromJson(<String, Object?>{'id': ''}), isNull);
      expect(
        ProviderAccount.fromJson(<String, Object?>{
          'id': 'x',
          'protocol': 'grpc',
        }),
        isNull,
      );
    });

    test('JSON: неизвестные поля игнорируются, пустые подставляются', () {
      final ProviderAccount? account = ProviderAccount.fromJson(
        <String, Object?>{
          'id': 'x',
          'protocol': 'openai-completions',
          'base_url': 'https://x.test',
          'model': 'm',
          'extra': 1,
        },
      );
      expect(account, isNotNull);
      expect(account!.label, isEmpty);
      expect(account.presetId, isNull);
      expect(account.contextTokens, kCustomProviderContextTokens);
      expect(account.requiresApiKey, isFalse);
    });

    test('supportsVision: из пресета и явное поле JSON', () {
      final ProviderAccount openAi = ProviderAccount.fromPreset(
        providerPresetById('openai')!,
        id: 'openai',
      );
      expect(openAi.supportsVision, isTrue);
      // Модель DeepSeek по умолчанию — deepseek-flash: официальная страница
      // подтверждает Vision; legacy deepseek-chat остаётся текстовой.
      expect(deepseek().supportsVision, isTrue);
      final ProviderAccount legacy = ProviderAccount.fromPreset(
        providerPresetById('deepseek')!,
        id: 'deepseek-legacy',
        modelId: 'deepseek-chat',
      );
      expect(legacy.supportsVision, isFalse);
      expect(deepseek().copyWith(supportsVision: true).supportsVision, isTrue);
      expect(openAi.toJson()['supports_vision'], isTrue);
      expect(ProviderAccount.fromJson(openAi.toJson())!.supportsVision, isTrue);
    });

    test('supportsVision: старая запись без поля — пресет или имя модели', () {
      final ProviderAccount? preset = ProviderAccount.fromJson(
        <String, Object?>{
          'id': 'openai-2',
          'preset_id': 'openai',
          'protocol': 'openai',
          'base_url': 'https://api.openai.com/v1',
          'model': 'gpt-4o',
        },
      );
      expect(preset!.supportsVision, isTrue);

      final ProviderAccount? flash = ProviderAccount.fromJson(<String, Object?>{
        'id': 'custom',
        'protocol': 'openai-completions',
        'base_url': 'https://example.test',
        'model': 'deepseek-flash',
      });
      expect(flash!.supportsVision, isTrue, reason: 'аккаунт владельца');

      final ProviderAccount? text = ProviderAccount.fromJson(<String, Object?>{
        'id': 'custom-2',
        'protocol': 'openai-completions',
        'base_url': 'https://example.test',
        'model': 'qwen2.5',
      });
      expect(text!.supportsVision, isFalse);
    });
  });

  group('JSON v2: возможности и цены (TASK 02A)', () {
    test('старая запись v1 читается: новые поля неизвестны, а не 0', () {
      final ProviderAccount? account = ProviderAccount.fromJson(
        <String, Object?>{
          'id': 'legacy',
          'label': 'Legacy',
          'protocol': 'openai-completions',
          'base_url': 'https://example.test',
          'model': 'm',
          'context_tokens': 32000,
        },
      );
      expect(account, isNotNull);
      expect(account!.contextTokens, 32000);
      expect(account.maxOutputTokens, isNull);
      expect(account.maxImagesPerRequest, isNull);
      expect(account.maxImageBytes, isNull);
      expect(account.maxRequestBytes, isNull);
      expect(account.pricing, isNull);
      expect(account.capabilitiesSource, CapabilitySource.unknown);
    });

    test('JSON v2 round-trip сохраняет возможности и цены', () {
      final ProviderAccount account = deepseek().copyWith(
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
      final Map<String, Object?> json = account.toJson();
      expect(json['max_output_tokens'], 16384);
      expect(json['max_images_per_request'], 8);
      expect(json['max_image_bytes'], 5 * 1024 * 1024);
      expect(json['max_request_bytes'], 25 * 1024 * 1024);
      expect(json['capabilities_source'], 'user_configured');
      final Map<String, Object?> pricing =
          json['pricing']! as Map<String, Object?>;
      expect(pricing['input_per_mtok'], 0.27);
      expect(ProviderAccount.fromJson(json), account);
      // ADR-039: legacy wire-значение читается как новый источник.
      final Map<String, Object?> legacy = Map<String, Object?>.of(json)
        ..['capabilities_source'] = 'user';
      expect(
        ProviderAccount.fromJson(legacy)!.capabilitiesSource,
        CapabilitySource.userConfigured,
      );
    });

    test('нулевые и битые лимиты — неизвестны, а не 0', () {
      final ProviderAccount? account = ProviderAccount.fromJson(
        <String, Object?>{
          'id': 'x',
          'protocol': 'openai-completions',
          'base_url': 'https://x.test',
          'model': 'm',
          'max_output_tokens': 0,
          'max_images_per_request': -2,
          'max_image_bytes': '10',
          'max_request_bytes': null,
          'capabilities_source': 'user',
        },
      );
      expect(account, isNotNull);
      expect(account!.maxOutputTokens, isNull);
      expect(account.maxImagesPerRequest, isNull);
      expect(account.maxImageBytes, isNull);
      expect(account.maxRequestBytes, isNull);
      expect(account.capabilitiesSource, CapabilitySource.userConfigured);
    });

    test('pricing с null внутри читается как неполный, стоимость null', () {
      final ProviderAccount? account = ProviderAccount.fromJson(
        <String, Object?>{
          'id': 'x',
          'protocol': 'openai-completions',
          'base_url': 'https://x.test',
          'model': 'm',
          'pricing': <String, Object?>{
            'input_per_mtok': 1.5,
            'output_per_mtok': null,
            'currency': 'USD',
          },
        },
      );
      expect(account, isNotNull);
      expect(account!.pricing, isNotNull);
      expect(account.pricing!.state, PricingState.incomplete);
      expect(
        account.pricing!.costFor(inputTokens: 1000, outputTokens: 1000),
        isNull,
      );
    });

    test('неизвестный capabilities_source — unknown', () {
      final ProviderAccount? account = ProviderAccount.fromJson(
        <String, Object?>{
          'id': 'x',
          'protocol': 'openai-completions',
          'base_url': 'https://x.test',
          'model': 'm',
          'capabilities_source': 'magic',
        },
      );
      expect(account!.capabilitiesSource, CapabilitySource.unknown);
    });

    test('copyWith меняет новые значения и не теряет остальные', () {
      final ProviderAccount original = deepseek().copyWith(
        maxOutputTokens: 4096,
        pricing: const GenerationPricing(
          inputPerMillion: 1,
          outputPerMillion: 2,
          currency: 'USD',
        ),
      );
      final ProviderAccount updated = original.copyWith(maxOutputTokens: 8192);
      expect(updated.maxOutputTokens, 8192);
      expect(updated.pricing, original.pricing);
      expect(updated.capabilitiesSource, CapabilitySource.unknown);
      expect(updated.id, original.id);
      expect(updated.presetId, original.presetId);
    });

    test('ProviderAccounts пишет версию 2 и читает v1', () {
      final ProviderAccounts list = ProviderAccounts.empty.withAccount(
        deepseek(),
      );
      expect(list.toJson()['version'], 2);
      expect(ProviderAccounts.version, 2);

      final ProviderAccounts legacy = ProviderAccounts.fromJson(
        <String, Object?>{
          'version': 1,
          'accounts': <Object?>[
            <String, Object?>{
              'id': 'deepseek',
              'label': 'DeepSeek',
              'preset_id': 'deepseek',
              'protocol': 'openai-completions',
              'base_url': 'https://api.deepseek.com',
              'model': 'deepseek-chat',
              'context_tokens': 128000,
              'requires_api_key': true,
              'supports_vision': false,
            },
          ],
          'active_id': 'deepseek',
        },
      );
      expect(legacy.accounts, hasLength(1));
      expect(legacy.active?.id, 'deepseek');
      expect(legacy.active?.pricing, isNull);
      expect(legacy.active?.maxOutputTokens, isNull);
    });
  });

  group('ProviderAccounts', () {
    test('добавление сохраняет порядок и делает первый аккаунт основным', () {
      final ProviderAccounts list = ProviderAccounts.empty
          .withAccount(deepseek())
          .withAccount(custom());
      expect(list.accounts.map((ProviderAccount a) => a.id).toList(), <String>[
        'deepseek',
        'my-server',
      ]);
      expect(list.activeAccountId, 'deepseek');
      expect(list.active?.id, 'deepseek');
      expect(list.isEmpty, isFalse);
    });

    test('добавление с существующим id заменяет аккаунт на месте', () {
      final ProviderAccounts list = ProviderAccounts.empty
          .withAccount(deepseek())
          .withAccount(custom())
          .withAccount(deepseek().copyWith(modelId: 'deepseek-reasoner'));
      expect(list.accounts, hasLength(2));
      expect(list.accountById('deepseek')!.modelId, 'deepseek-reasoner');
      expect(list.accounts.first.id, 'deepseek');
    });

    test('основной аккаунт выбирается по id; неизвестный id игнорируется', () {
      final ProviderAccounts list = ProviderAccounts.empty
          .withAccount(deepseek())
          .withAccount(custom());
      expect(list.withActive('my-server').active?.id, 'my-server');
      expect(list.withActive('ghost').activeAccountId, isNull);
      expect(list.withActive('ghost').active?.id, 'deepseek');
      expect(
        list.withActive('ghost').withActive('my-server').active?.id,
        'my-server',
      );
    });

    test('удаление переключает основной на первый оставшийся', () {
      final ProviderAccounts list = ProviderAccounts.empty
          .withAccount(deepseek())
          .withAccount(custom());
      final ProviderAccounts without = list.withoutAccount('deepseek');
      expect(without.accounts.map((ProviderAccount a) => a.id), <String>[
        'my-server',
      ]);
      expect(without.activeAccountId, 'my-server');
      expect(without.withoutAccount('my-server').isEmpty, isTrue);
      expect(without.withoutAccount('my-server').activeAccountId, isNull);
    });

    test('JSON round-trip списка и основного аккаунта', () {
      final ProviderAccounts list = ProviderAccounts.empty
          .withAccount(deepseek())
          .withAccount(custom())
          .withActive('my-server');
      final Map<String, Object?> json = list.toJson();
      expect(json['version'], ProviderAccounts.version);
      expect(json['active_id'], 'my-server');
      expect(ProviderAccounts.fromJson(json), list);
    });

    test('JSON: мусор даёт пустой список, битые аккаунты пропускаются', () {
      expect(ProviderAccounts.fromJson(null).isEmpty, isTrue);
      expect(ProviderAccounts.fromJson(<String, Object?>{}).isEmpty, isTrue);
      expect(
        ProviderAccounts.fromJson(<String, Object?>{
          'accounts': <Object?>[
            deepseek().toJson(),
            <String, Object?>{'id': ''},
            'junk',
          ],
        }).accounts.map((ProviderAccount a) => a.id),
        <String>['deepseek'],
      );
      expect(
        ProviderAccounts.fromJson(<String, Object?>{
          'accounts': <Object?>[deepseek().toJson()],
          'active_id': 'ghost',
        }).active?.id,
        'deepseek',
        reason: 'Неизвестный основной аккаунт игнорируется',
      );
    });
  });

  group('Идентификаторы аккаунтов', () {
    test('slug: латиница/цифры, нижний регистр, дефисы', () {
      expect(slugifyProviderId('DeepSeek'), 'deepseek');
      expect(slugifyProviderId('  My Server  '), 'my-server');
      expect(slugifyProviderId('Моя модель'), isEmpty);
      expect(slugifyProviderId('a--b'), 'a-b');
    });

    test('уникальный id получает числовой суффикс', () {
      expect(uniqueProviderAccountId('deepseek', <String>[]), 'deepseek');
      expect(
        uniqueProviderAccountId('deepseek', <String>['deepseek']),
        'deepseek-2',
      );
      expect(
        uniqueProviderAccountId('deepseek', <String>['deepseek', 'deepseek-2']),
        'deepseek-3',
      );
      expect(
        uniqueProviderAccountId('Моя модель', <String>['provider']),
        'provider-2',
      );
    });
  });

  test('withAutomaticCapabilities: пресет → каталог, custom → unknown', () {
    final ProviderAccount preset = testProviderAccount(
      modelId: 'deepseek-chat',
    );
    final ProviderAccount auto = preset
        .copyWith(maxOutputTokens: 123)
        .copyWith(
          capabilitiesSource: CapabilitySource.userConfigured,
          supportsVision: true,
        )
        .withAutomaticCapabilities();
    expect(auto.maxOutputTokens, isNull);
    expect(auto.capabilitiesSource, CapabilitySource.unknown);
    expect(auto.contextTokens, preset.contextTokens);

    final ProviderAccount custom =
        testCustomProviderAccount(supportsVision: true).copyWith(
          maxOutputTokens: 100,
          maxImagesPerRequest: 2,
          capabilitiesSource: CapabilitySource.userConfigured,
        );
    final ProviderAccount customAuto = custom.withAutomaticCapabilities();
    expect(customAuto.maxOutputTokens, isNull);
    expect(customAuto.maxImagesPerRequest, isNull);
    expect(customAuto.supportsVision, isFalse);
    expect(customAuto.capabilitiesSource, CapabilitySource.unknown);
  });
}
