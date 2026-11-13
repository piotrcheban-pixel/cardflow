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
    super.dispose();
  }

  /// Читает сохранённые настройки и наличие ключа.
  Future<void> _load() async {
    try {
      final OpenAiCompatibleSettings settings = await ref
          .read(generationSettingsStoreProvider)
          .readOpenAiCompatible();
      final String? apiKey = await ref
          .read(apiKeyStoreProvider)
          .read(GenerationProvider.openaiCompatible);
      if (!mounted) return;
      setState(() {
        _baseUrlController.text = settings.baseUrl;
        _modelController.text = settings.model;
        _apiKeyController.clear();
        _keyConfigured = apiKey != null;
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
      ],
    );
  }

  /// Рамка полей — форма из общего UI-стиля экранов колод.
  static final OutlineInputBorder _fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
  );
}
