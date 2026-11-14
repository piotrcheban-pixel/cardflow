import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/providers/openai_compatible_endpoint.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart' show showAppMessage;
import 'package:cardflow/ui/state/app_providers.dart';

/// Экран «Настройки генерации», блок OpenAI-совместимого сервера (ADR-013).
///
/// Пользователь задаёт базовый адрес сервера и модель (они сохраняются в
/// `app_settings` через `GenerationSettingsStore`) и, при необходимости, ключ
/// доступа. Ключ живёт только в `ApiKeyStore` (secure storage, SPEC 3.4):
/// в БД и `app_settings` он не попадает, значение не выводится на экран и не
/// логируется. Пустое поле ключа при сохранении удаляет сохранённый ключ —
/// локальным серверам ключ не нужен. Адрес проверяется до записи через
/// `OpenAiCompatibleEndpoint.parse`; тексты ошибок и сообщений — только из ARB.
class GenerationSettingsScreen extends ConsumerStatefulWidget {
  /// Создаёт экран.
  const GenerationSettingsScreen({super.key});

  @override
  ConsumerState<GenerationSettingsScreen> createState() =>
      _GenerationSettingsScreenState();
}

class _GenerationSettingsScreenState
    extends ConsumerState<GenerationSettingsScreen> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  /// Ключи трёх облачных провайдеров (A6.8: «ключ не задан — ведём в настройки»).
  static const List<GenerationProvider> _cloudProviders = <GenerationProvider>[
    GenerationProvider.openai,
    GenerationProvider.gemini,
    GenerationProvider.anthropic,
  ];

  final Map<GenerationProvider, TextEditingController> _cloudKeyControllers =
      <GenerationProvider, TextEditingController>{
        for (final GenerationProvider provider in _cloudProviders)
          provider: TextEditingController(),
      };
  final Map<GenerationProvider, bool> _cloudKeyConfigured =
      <GenerationProvider, bool>{};
  final Map<GenerationProvider, String?> _cloudKeyErrors =
      <GenerationProvider, String?>{};

  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _keyConfigured = false;

  String? _baseUrlError;
  String? _modelError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    for (final TextEditingController controller
        in _cloudKeyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Читает сохранённые настройки и наличие всех ключей.
  Future<void> _load() async {
    try {
      final OpenAiCompatibleSettings settings = await ref
          .read(generationSettingsStoreProvider)
          .readOpenAiCompatible();
      final ApiKeyStore apiKeyStore = ref.read(apiKeyStoreProvider);
      final String? apiKey = await apiKeyStore.read(
        GenerationProvider.openaiCompatible,
      );
      final Map<GenerationProvider, bool> cloudConfigured =
          <GenerationProvider, bool>{};
      for (final GenerationProvider provider in _cloudProviders) {
        final String? key = await apiKeyStore.read(provider);
        cloudConfigured[provider] = key != null && key.trim().isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _baseUrlController.text = settings.baseUrl;
        _modelController.text = settings.model;
        _apiKeyController.clear();
        _keyConfigured = apiKey != null;
        _cloudKeyConfigured
          ..clear()
          ..addAll(cloudConfigured);
        for (final TextEditingController controller
            in _cloudKeyControllers.values) {
          controller.clear();
        }
        _cloudKeyErrors.clear();
        _baseUrlError = null;
        _modelError = null;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Повторная загрузка после ошибки.
  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    _load();
  }

  /// Проверяет поля, сохраняет настройки и ключ; ошибки — только из ARB.
  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String baseUrl = _baseUrlController.text.trim();
    final String model = _modelController.text.trim();
    final OpenAiCompatibleEndpoint endpoint = OpenAiCompatibleEndpoint.parse(
      baseUrl,
    );

    final String? baseUrlError;
    if (endpoint.error == OpenAiCompatibleEndpointError.empty) {
      baseUrlError = l10n.settingsAddressEmptyError;
    } else if (!endpoint.isValid) {
      baseUrlError = l10n.settingsAddressInvalidError;
    } else {
      baseUrlError = null;
    }
    final String? modelError = model.isEmpty
        ? l10n.settingsModelEmptyError
        : null;
    if (baseUrlError != null || modelError != null) {
      setState(() {
        _baseUrlError = baseUrlError;
        _modelError = modelError;
      });
      return;
    }

    final String apiKey = _apiKeyController.text.trim();
    setState(() {
      _baseUrlError = null;
      _modelError = null;
      _saving = true;
    });
    try {
      await ref
          .read(generationSettingsStoreProvider)
          .writeOpenAiCompatible(
            OpenAiCompatibleSettings(baseUrl: baseUrl, model: model),
          );
      final ApiKeyStore apiKeyStore = ref.read(apiKeyStoreProvider);
      if (apiKey.isEmpty) {
        await apiKeyStore.delete(GenerationProvider.openaiCompatible);
      } else {
        await apiKeyStore.write(GenerationProvider.openaiCompatible, apiKey);
      }
      final String? storedKey = await apiKeyStore.read(
        GenerationProvider.openaiCompatible,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _keyConfigured = storedKey != null;
        _baseUrlController.text = baseUrl;
        _modelController.text = model;
        _apiKeyController.clear();
      });
      showAppMessage(context, l10n.settingsSaved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, l10n.settingsSaveError);
    }
  }

  /// Сохраняет ключ облачного провайдера (только secure storage, 3.4).
  Future<void> _saveCloudKey(GenerationProvider provider) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String key = _cloudKeyControllers[provider]!.text.trim();
    if (key.isEmpty) {
      setState(() => _cloudKeyErrors[provider] = l10n.settingsKeyEmptyError);
      return;
    }
    try {
      final ApiKeyStore apiKeyStore = ref.read(apiKeyStoreProvider);
      await apiKeyStore.write(provider, key);
      final String? stored = await apiKeyStore.read(provider);
      if (!mounted) return;
      setState(() {
        _cloudKeyConfigured[provider] = stored != null && stored.isNotEmpty;
        _cloudKeyErrors[provider] = null;
        _cloudKeyControllers[provider]!.clear();
      });
      showAppMessage(context, l10n.settingsKeySaved);
    } catch (_) {
      if (!mounted) return;
      showAppMessage(context, l10n.settingsSaveError);
    }
  }

  /// Удаляет сохранённый ключ облачного провайдера.
  Future<void> _deleteCloudKey(GenerationProvider provider) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      await ref.read(apiKeyStoreProvider).delete(provider);
      if (!mounted) return;
      setState(() {
        _cloudKeyConfigured[provider] = false;
        _cloudKeyErrors[provider] = null;
        _cloudKeyControllers[provider]!.clear();
      });
      showAppMessage(context, l10n.settingsKeyDeleted);
    } catch (_) {
      if (!mounted) return;
      showAppMessage(context, l10n.settingsSaveError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(l10n.settingsLoadError, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _retryLoad, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          l10n.settingsOpenAiCompatibleTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.settingsOpenAiCompatibleDescription,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey<String>('settings-base-url'),
          controller: _baseUrlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.settingsServerAddressLabel,
            hintText: l10n.settingsServerAddressHint,
            errorText: _baseUrlError,
            border: _fieldBorder,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey<String>('settings-model'),
          controller: _modelController,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.settingsModelLabel,
            hintText: l10n.settingsModelHint,
            errorText: _modelError,
            border: _fieldBorder,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey<String>('settings-api-key'),
          controller: _apiKeyController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.settingsApiKeyLabel,
            helperText: l10n.settingsApiKeyHelper,
            helperMaxLines: 3,
            border: _fieldBorder,
          ),
        ),
        if (_keyConfigured)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.settingsApiKeyConfigured)),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const ValueKey<String>('settings-save'),
            onPressed: _saving ? null : _save,
            child: Text(l10n.save),
          ),
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Text(l10n.settingsApiKeysTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.settingsApiKeysDescription, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        for (final GenerationProvider provider in _cloudProviders) ...<Widget>[
          _CloudKeySection(
            provider: provider,
            label: _providerLabel(l10n, provider),
            configured: _cloudKeyConfigured[provider] ?? false,
            controller: _cloudKeyControllers[provider]!,
            errorText: _cloudKeyErrors[provider],
            onSave: () => _saveCloudKey(provider),
            onDelete: () => _deleteCloudKey(provider),
            l10n: l10n,
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  String _providerLabel(AppLocalizations l10n, GenerationProvider provider) {
    return switch (provider) {
      GenerationProvider.openai => l10n.generationProviderOpenAi,
      GenerationProvider.gemini => l10n.generationProviderGemini,
      GenerationProvider.anthropic => l10n.generationProviderAnthropic,
      GenerationProvider.openaiCompatible =>
        l10n.generationProviderOpenAiCompatible,
    };
  }

  /// Рамка полей — форма из общего UI-стиля экранов колод.
  static final OutlineInputBorder _fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
  );
}

/// Блок ключа одного облачного провайдера на экране настроек генерации.
class _CloudKeySection extends StatelessWidget {
  const _CloudKeySection({
    required this.provider,
    required this.label,
    required this.configured,
    required this.controller,
    required this.errorText,
    required this.onSave,
    required this.onDelete,
    required this.l10n,
  });

  final GenerationProvider provider;
  final String label;
  final bool configured;
  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            Text(
              configured ? l10n.settingsKeyConfigured : l10n.settingsKeyMissing,
              style: theme.textTheme.labelSmall?.copyWith(
                color: configured
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: ValueKey<String>('settings-key-${provider.wireName}'),
          controller: controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.settingsCloudKeyLabel,
            errorText: errorText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            FilledButton(
              key: ValueKey<String>('settings-save-key-${provider.wireName}'),
              onPressed: onSave,
              child: Text(l10n.settingsKeySave),
            ),
            if (configured) ...<Widget>[
              const SizedBox(width: 8),
              TextButton(
                key: ValueKey<String>(
                  'settings-delete-key-${provider.wireName}',
                ),
                onPressed: onDelete,
                child: Text(l10n.settingsKeyDelete),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
