/// Репозиторий провайдеров генерации поверх `app_settings` (ADR-020).
///
/// Список аккаунтов — одно JSON-значение `generation.providers`; схема БД и
/// `schemaVersion` не меняются. При первом чтении пустого хранилища выполняется
/// миграция наследия итераций 3b–7: адрес/модель OpenAI-совместимого сервера
/// (`generation.openai_compatible`) и ключи облачных провайдеров превращаются в
/// аккаунты. Ключи копировать не нужно: id мигрируемых аккаунтов совпадают с
/// legacy-именами в secure storage (`openai`, `gemini`, `anthropic`,
/// `openai_compatible`). Ключ API в `app_settings` не попадает никогда.
library;

import 'dart:convert';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_settings_store.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_accounts_store.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Хранит провайдеров в строке `app_settings` с ключом [settingKey].
class DriftProviderAccountsStore implements ProviderAccountsStore {
  /// Создаёт репозиторий поверх [db].
  ///
  /// [apiKeyStore] нужен только для миграции: наличие legacy-ключа решает,
  /// создавать ли аккаунт облачного провайдера. [legacySettingsStore] читает
  /// старые настройки OpenAI-совместимого сервера.
  DriftProviderAccountsStore(
    this.db, {
    required this.apiKeyStore,
    this.legacySettingsStore,
  });

  /// БД приложения.
  final AppDatabase db;

  /// Хранилище ключей (present/absent legacy-ключей для миграции).
  final ApiKeyStore apiKeyStore;

  /// Старые настройки OpenAI-совместимого сервера (ADR-013); может быть `null`.
  final GenerationSettingsStore? legacySettingsStore;

  /// Ключ строки настроек в `app_settings`.
  static const String settingKey = 'generation.providers';

  /// Провайдеры, которые мигрируются по наличию legacy-ключа (без адреса).
  static const List<String> legacyKeyProviderIds = <String>[
    'openai',
    'gemini',
    'anthropic',
  ];

  @override
  Future<ProviderAccounts> read() async {
    final AppSettingRow? row = await (db.select(
      db.appSettings,
    )..where((table) => table.key.equals(settingKey))).getSingleOrNull();
    if (row != null) {
      try {
        return ProviderAccounts.fromJson(jsonDecode(row.valueJson));
      } on FormatException {
        // Повреждённое значение не должно ломать приложение: пользователь
        // настроит провайдеров заново.
        return ProviderAccounts.empty;
      }
    }
    return _migrateLegacy();
  }

  @override
  Future<void> write(ProviderAccounts accounts) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: settingKey,
            valueJson: jsonEncode(accounts.toJson()),
          ),
        );
  }

  /// Миграция наследия 3b–7; результат сразу сохраняется.
  Future<ProviderAccounts> _migrateLegacy() async {
    final List<ProviderAccount> migrated = <ProviderAccount>[];

    final OpenAiCompatibleSettings legacy = legacySettingsStore == null
        ? const OpenAiCompatibleSettings()
        : await legacySettingsStore!.readOpenAiCompatible();
    if (legacy.isConfigured) {
      migrated.add(_accountFromLegacySettings(legacy));
    } else {
      // Ключ без сохранённых адреса/модели (владелец ввёл только ключ —
      // ровно симптом итерации 7.5): аккаунт создаётся, чтобы ключ не
      // потерялся; адрес и модель пользователь дополнит в диалоге.
      final String? orphanKey = await apiKeyStore.read('openai_compatible');
      if (orphanKey != null) {
        migrated.add(
          ProviderAccount(
            id: 'openai_compatible',
            label: '',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: legacy.baseUrl,
            modelId: legacy.model,
          ),
        );
      }
    }

    for (final String presetId in legacyKeyProviderIds) {
      final String? key = await apiKeyStore.read(presetId);
      if (key == null) continue;
      final ProviderPreset? preset = providerPresetById(presetId);
      if (preset == null) continue;
      migrated.add(ProviderAccount.fromPreset(preset, id: presetId));
    }

    if (migrated.isEmpty) return ProviderAccounts.empty;
    final ProviderAccounts accounts = ProviderAccounts(
      accounts: List<ProviderAccount>.unmodifiable(migrated),
      activeAccountId: migrated.first.id,
    );
    await write(accounts);
    return accounts;
  }

  /// Аккаунт из старых настроек: адрес/модель + id, совпадающий с legacy-ключом.
  ProviderAccount _accountFromLegacySettings(OpenAiCompatibleSettings legacy) {
    final ProviderPreset? preset = providerPresetByBaseUrl(legacy.baseUrl);
    final ProviderPresetModel? model = preset?.modelById(legacy.model.trim());
    return ProviderAccount(
      id: 'openai_compatible',
      label: preset?.label ?? '',
      presetId: preset?.id,
      protocol: preset?.protocol ?? ProviderProtocol.openaiCompletions,
      baseUrl: legacy.baseUrl,
      modelId: legacy.model,
      contextTokens: model?.contextTokens ?? kCustomProviderContextTokens,
      requiresApiKey: preset?.requiresApiKey ?? false,
      supportsVision:
          model?.supportsVision ?? inferSupportsVisionFromModelId(legacy.model),
    );
  }
}
