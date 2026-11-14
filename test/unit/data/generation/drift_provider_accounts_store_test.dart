import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_settings_store.dart';
import 'package:cardflow/data/generation/drift_provider_accounts_store.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Итерация 7.5 (ADR-020): провайдеры в `app_settings` + миграция наследия.
class _FakeKeyStore implements ApiKeyStore {
  _FakeKeyStore([Map<String, String>? keys])
    : keys = <String, String>{...?keys};

  final Map<String, String> keys;

  @override
  Future<String?> read(String providerId) async => keys[providerId];

  @override
  Future<void> write(String providerId, String apiKey) async {
    keys[providerId] = apiKey;
  }

  @override
  Future<void> delete(String providerId) async {
    keys.remove(providerId);
  }
}

void main() {
  late AppDatabase db;
  late _FakeKeyStore keys;

  setUp(() {
    db = AppDatabase.inMemory();
    keys = _FakeKeyStore();
  });

  tearDown(() async {
    await db.close();
  });

  ProviderAccount deepseek() => ProviderAccount.fromPreset(
    providerPresetById('deepseek')!,
    id: 'deepseek',
  );

  test('по умолчанию — пустой список провайдеров', () async {
    final store = DriftProviderAccountsStore(db, apiKeyStore: keys);
    expect(await store.read(), ProviderAccounts.empty);
  });

  test('write → read: аккаунты и основной сохраняются без ключей', () async {
    final store = DriftProviderAccountsStore(db, apiKeyStore: keys);
    final ProviderAccounts accounts = ProviderAccounts.empty
        .withAccount(deepseek())
        .withAccount(
          const ProviderAccount(
            id: 'local',
            label: 'Локальный',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: 'http://localhost:11434/v1',
            modelId: 'llama3.1',
          ),
        )
        .withActive('local');

    await store.write(accounts);
    expect(await store.read(), accounts);

    final rows = await db.select(db.appSettings).get();
    expect(rows, hasLength(1));
    expect(rows.single.key, 'generation.providers');
    final decoded = jsonDecode(rows.single.valueJson) as Map<String, Object?>;
    expect(decoded['version'], ProviderAccounts.version);
    expect(jsonEncode(decoded), isNot(contains('sk-')));
  });

  test('перезапись обновляет существующую строку', () async {
    final store = DriftProviderAccountsStore(db, apiKeyStore: keys);
    await store.write(ProviderAccounts.empty.withAccount(deepseek()));
    await store.write(ProviderAccounts.empty);
    expect(await store.read(), ProviderAccounts.empty);
    expect(await db.select(db.appSettings).get(), hasLength(1));
  });

  test('битый JSON — пустой список без исключения', () async {
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'generation.providers',
            valueJson: 'не json',
          ),
        );
    final store = DriftProviderAccountsStore(db, apiKeyStore: keys);
    expect(await store.read(), ProviderAccounts.empty);
  });

  group('Миграция наследия (ADR-020 §4)', () {
    test('адрес и модель OpenAI-совместимого сервера → аккаунт', () async {
      await DriftGenerationSettingsStore(db).writeOpenAiCompatible(
        const OpenAiCompatibleSettings(
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-chat',
        ),
      );
      keys.keys['openai_compatible'] = 'sk-legacy';

      final store = DriftProviderAccountsStore(
        db,
        apiKeyStore: keys,
        legacySettingsStore: DriftGenerationSettingsStore(db),
      );
      final ProviderAccounts accounts = await store.read();

      expect(accounts.accounts, hasLength(1));
      final ProviderAccount account = accounts.accounts.single;
      expect(account.id, 'openai_compatible');
      expect(account.label, 'DeepSeek');
      expect(account.presetId, 'deepseek');
      expect(account.protocol, ProviderProtocol.openaiCompletions);
      expect(account.baseUrl, 'https://api.deepseek.com');
      expect(account.modelId, 'deepseek-chat');
      expect(account.requiresApiKey, isTrue);
      expect(accounts.activeAccountId, 'openai_compatible');

      // Результат сразу сохранён: второй read не мигрирует заново.
      expect(await store.read(), accounts);
    });

    test(
      'неизвестный адрес — пользовательский аккаунт с тем же адресом',
      () async {
        await DriftGenerationSettingsStore(db).writeOpenAiCompatible(
          const OpenAiCompatibleSettings(
            baseUrl: 'https://llm.example.test/v1',
            model: 'custom-model',
          ),
        );
        final store = DriftProviderAccountsStore(
          db,
          apiKeyStore: keys,
          legacySettingsStore: DriftGenerationSettingsStore(db),
        );
        final ProviderAccount account = (await store.read()).accounts.single;
        expect(account.id, 'openai_compatible');
        expect(account.label, isEmpty);
        expect(account.presetId, isNull);
        expect(account.protocol, ProviderProtocol.openaiCompletions);
        expect(account.baseUrl, 'https://llm.example.test/v1');
        expect(account.modelId, 'custom-model');
        expect(account.requiresApiKey, isFalse);
      },
    );

    test('legacy-ключи облачных провайдеров → аккаунты каталога', () async {
      keys.keys['openai'] = 'sk-openai';
      keys.keys['anthropic'] = 'sk-ant';

      final store = DriftProviderAccountsStore(db, apiKeyStore: keys);
      final ProviderAccounts accounts = await store.read();

      expect(
        accounts.accounts.map((ProviderAccount a) => a.id).toList(),
        <String>['openai', 'anthropic'],
      );
      final ProviderAccount openai = accounts.accounts.first;
      expect(openai.label, 'OpenAI');
      expect(openai.protocol, ProviderProtocol.openai);
      expect(openai.modelId, 'gpt-4o-mini');
      expect(accounts.activeAccountId, 'openai');
    });

    test('наследия нет — пустой список, строка не создаётся', () async {
      final store = DriftProviderAccountsStore(
        db,
        apiKeyStore: keys,
        legacySettingsStore: DriftGenerationSettingsStore(db),
      );
      expect(await store.read(), ProviderAccounts.empty);
      expect(await db.select(db.appSettings).get(), isEmpty);
    });

    test('legacy-ключ без адреса и модели не теряется', () async {
      keys.keys['openai_compatible'] = 'sk-orphan';

      final store = DriftProviderAccountsStore(
        db,
        apiKeyStore: keys,
        legacySettingsStore: DriftGenerationSettingsStore(db),
      );
      final ProviderAccounts accounts = await store.read();

      expect(accounts.accounts, hasLength(1));
      final ProviderAccount account = accounts.accounts.single;
      expect(account.id, 'openai_compatible');
      expect(account.label, isEmpty);
      expect(account.baseUrl, isEmpty);
      expect(account.modelId, isEmpty);
      expect(account.isConfigured, isFalse);
      expect(account.requiresApiKey, isFalse);
    });

    test('незаполненный адрес legacy-настроек не мигрируется', () async {
      await DriftGenerationSettingsStore(db).writeOpenAiCompatible(
        const OpenAiCompatibleSettings(baseUrl: '  ', model: 'модель'),
      );
      final store = DriftProviderAccountsStore(
        db,
        apiKeyStore: keys,
        legacySettingsStore: DriftGenerationSettingsStore(db),
      );
      expect(await store.read(), ProviderAccounts.empty);
    });
  });
}
