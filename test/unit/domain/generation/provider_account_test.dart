import 'package:flutter_test/flutter_test.dart';

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
        expect(account.modelId, 'deepseek-chat');
        expect(account.contextTokens, 128000);
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
}
