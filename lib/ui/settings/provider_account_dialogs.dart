/// Диалоги добавления и изменения провайдера (ADR-020).
///
/// Два пути, как в DSH: «Сторонний поставщик» — выбор из каталога с
/// автозаполнением адреса и модели; «Пользовательская модель API» — ручной
/// ввод названия, адреса, протокола и модели. Ключ API в диалоге только
/// записывается в `ApiKeyStore` (secure storage): значение не подставляется в
/// поле, не показывается и не логируется (SPEC 3.4). Ошибки — только из ARB.
library;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/providers/provider_endpoint.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';

import 'provider_labels.dart';

/// Результат диалога: аккаунт и действие с ключом.
class ProviderAccountDraft {
  /// Создаёт черновик.
  const ProviderAccountDraft({
    required this.account,
    this.apiKey,
    this.deleteKey = false,
  });

  /// Настроенный аккаунт (id уже назначен).
  final ProviderAccount account;

  /// Новый ключ; `null` — не менять сохранённый.
  final String? apiKey;

  /// Удалить сохранённый ключ.
  final bool deleteKey;
}

/// Диалог «Сторонний поставщик»: каталог, модель, ключ.
///
/// [initial] — изменяемый аккаунт (пресет зафиксирован), [takenIds] — занятые
/// id (для новых аккаунтов), [hasStoredKey] — можно удалить сохранённый ключ.
Future<ProviderAccountDraft?> showPresetProviderDialog(
  BuildContext context, {
  required String Function(String presetId) nextIdFor,
  ProviderAccount? initial,
  bool hasStoredKey = false,
}) {
  return showDialog<ProviderAccountDraft>(
    context: context,
    builder: (BuildContext context) => _PresetProviderDialog(
      nextIdFor: nextIdFor,
      initial: initial,
      hasStoredKey: hasStoredKey,
    ),
  );
}

/// Диалог «Пользовательская модель API»: название, адрес, протокол, модель, ключ.
Future<ProviderAccountDraft?> showCustomProviderDialog(
  BuildContext context, {
  required String Function(String label) nextIdFor,
  ProviderAccount? initial,
  bool hasStoredKey = false,
}) {
  return showDialog<ProviderAccountDraft>(
    context: context,
    builder: (BuildContext context) => _CustomProviderDialog(
      nextIdFor: nextIdFor,
      initial: initial,
      hasStoredKey: hasStoredKey,
    ),
  );
}

/// Общая часть диалога: заголовок, поля ключа и кнопки действий.
///
/// V8: единый `AppDialog` вместо сырого `AlertDialog` — та же ширина, отступы,
/// заголовок и порядок кнопок, что у диалогов подтверждения.
class _ProviderDialogChrome extends StatelessWidget {
  const _ProviderDialogChrome({
    required this.title,
    required this.l10n,
    required this.fields,
    required this.onSave,
    required this.hasStoredKey,
    required this.onDeleteKey,
    required this.deleteKey,
  });

  final String title;
  final AppLocalizations l10n;
  final List<Widget> fields;
  final VoidCallback onSave;
  final bool hasStoredKey;
  final VoidCallback onDeleteKey;
  final bool deleteKey;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: title,
      bodyBuilder: (BuildContext dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...fields,
          if (hasStoredKey)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey<String>('provider-delete-key'),
                onPressed: onDeleteKey,
                icon: Icon(
                  deleteKey ? Icons.undo : Icons.delete_outline,
                  size: 18,
                ),
                label: Text(
                  deleteKey
                      ? l10n.providersKeyUndoDelete
                      : l10n.settingsKeyDelete,
                ),
              ),
            ),
        ],
      ),
      actionsBuilder: (BuildContext dialogContext) => <Widget>[
        TextButton(
          key: const ValueKey<String>('provider-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('provider-save'),
          onPressed: onSave,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _PresetProviderDialog extends StatefulWidget {
  const _PresetProviderDialog({
    required this.nextIdFor,
    this.initial,
    required this.hasStoredKey,
  });

  final String Function(String presetId) nextIdFor;
  final ProviderAccount? initial;
  final bool hasStoredKey;

  @override
  State<_PresetProviderDialog> createState() => _PresetProviderDialogState();
}

class _PresetProviderDialogState extends State<_PresetProviderDialog> {
  final TextEditingController _apiKeyController = TextEditingController();
  ProviderPreset? _preset;
  String? _modelId;
  String? _keyError;
  bool _deleteKey = false;

  @override
  void initState() {
    super.initState();
    final ProviderAccount? initial = widget.initial;
    if (initial != null && initial.preset != null) {
      _preset = initial.preset;
      _modelId = initial.modelId;
    } else {
      _preset = kProviderPresets.first;
      _modelId = _preset!.defaultModel.id;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  String? get _resolvedModelId {
    final ProviderPreset? preset = _preset;
    if (preset == null) return null;
    final String? selected = _modelId;
    if (selected != null && preset.modelById(selected) != null) return selected;
    return preset.defaultModel.id;
  }

  void _save() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ProviderPreset? preset = _preset;
    if (preset == null) return;
    final String apiKey = _apiKeyController.text.trim();
    if (preset.requiresApiKey &&
        apiKey.isEmpty &&
        !widget.hasStoredKey &&
        !_deleteKey) {
      setState(() => _keyError = l10n.settingsKeyEmptyError);
      return;
    }
    final String modelId = _resolvedModelId ?? preset.defaultModel.id;
    final ProviderAccount account = ProviderAccount.fromPreset(
      preset,
      id: widget.initial?.id ?? widget.nextIdFor(preset.id),
      modelId: modelId,
    );
    Navigator.of(context).pop(
      ProviderAccountDraft(
        account: account,
        apiKey: apiKey.isEmpty ? null : apiKey,
        deleteKey: _deleteKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ProviderPreset? preset = _preset;
    final bool locked = widget.initial != null;
    return _ProviderDialogChrome(
      title: locked ? l10n.providersEditTitle : l10n.providersAddPreset,
      l10n: l10n,
      hasStoredKey: widget.hasStoredKey,
      deleteKey: _deleteKey,
      onDeleteKey: () => setState(() => _deleteKey = !_deleteKey),
      onSave: _save,
      fields: <Widget>[
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: const ValueKey<String>('provider-preset-select'),
          initialValue: preset?.id,
          decoration: InputDecoration(
            labelText: l10n.providersPresetLabel,
            border: _fieldBorder,
          ),
          items: <DropdownMenuItem<String>>[
            for (final ProviderPreset item in kProviderPresets)
              DropdownMenuItem<String>(value: item.id, child: Text(item.label)),
          ],
          onChanged: locked
              ? null
              : (String? presetId) {
                  if (presetId == null) return;
                  setState(() {
                    _preset = providerPresetById(presetId);
                    _modelId = _preset?.defaultModel.id;
                    _keyError = null;
                  });
                },
        ),
        const SizedBox(height: 12),
        InputDecorator(
          key: const ValueKey<String>('provider-base-url'),
          decoration: InputDecoration(
            labelText: l10n.settingsServerAddressLabel,
            border: _fieldBorder,
          ),
          child: Text(preset?.baseUrl ?? ''),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey<String>('provider-model-select-${preset?.id}'),
          initialValue: _resolvedModelId,
          decoration: InputDecoration(
            labelText: l10n.settingsModelLabel,
            border: _fieldBorder,
          ),
          items: <DropdownMenuItem<String>>[
            for (final ProviderPresetModel model
                in preset?.models ?? const <ProviderPresetModel>[])
              DropdownMenuItem<String>(
                value: model.id,
                child: Text(model.label),
              ),
          ],
          onChanged: (String? modelId) => setState(() => _modelId = modelId),
        ),
        const SizedBox(height: 4),
        Text(
          (preset?.modelById(_resolvedModelId ?? '')?.supportsVision ?? false)
              ? l10n.providersVisionSupported
              : l10n.providersVisionNotSupported,
          key: const ValueKey<String>('provider-preset-vision'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey<String>('provider-key'),
          controller: _apiKeyController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.settingsCloudKeyLabel,
            helperText: widget.hasStoredKey
                ? l10n.providersKeyKeep
                : l10n.providersKeyHelper,
            helperMaxLines: 3,
            errorText: _keyError,
            border: _fieldBorder,
          ),
        ),
      ],
    );
  }
}

class _CustomProviderDialog extends StatefulWidget {
  const _CustomProviderDialog({
    required this.nextIdFor,
    this.initial,
    required this.hasStoredKey,
  });

  final String Function(String label) nextIdFor;
  final ProviderAccount? initial;
  final bool hasStoredKey;

  @override
  State<_CustomProviderDialog> createState() => _CustomProviderDialogState();
}

class _CustomProviderDialogState extends State<_CustomProviderDialog> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  ProviderProtocol _protocol = ProviderProtocol.openaiCompletions;
  String? _labelError;
  String? _baseUrlError;
  String? _modelError;
  bool _deleteKey = false;
  bool _supportsVision = false;
  bool _visionTouched = false;

  @override
  void initState() {
    super.initState();
    final ProviderAccount? initial = widget.initial;
    if (initial == null) return;
    _labelController.text = initial.label;
    _baseUrlController.text = initial.baseUrl;
    _modelController.text = initial.modelId;
    _protocol = initial.protocol == ProviderProtocol.openai
        ? ProviderProtocol.openaiCompletions
        : initial.protocol;
    _supportsVision = initial.supportsVision;
    _visionTouched = true;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _save() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = _labelController.text.trim();
    final String baseUrl = _baseUrlController.text.trim();
    final String model = _modelController.text.trim();
    final ProviderEndpoint endpoint = ProviderEndpoint.parse(
      protocol: _protocol,
      baseUrl: baseUrl,
      model: model,
    );
    final String? baseUrlError;
    if (endpoint.error == ProviderEndpointError.empty) {
      baseUrlError = l10n.settingsAddressEmptyError;
    } else if (!endpoint.isValid) {
      baseUrlError = l10n.settingsAddressInvalidError;
    } else {
      baseUrlError = null;
    }
    final String? modelError = model.isEmpty
        ? l10n.settingsModelEmptyError
        : null;
    final String? labelError = label.isEmpty
        ? l10n.providersNameEmptyError
        : null;
    if (baseUrlError != null || modelError != null || labelError != null) {
      setState(() {
        _labelError = labelError;
        _baseUrlError = baseUrlError;
        _modelError = modelError;
      });
      return;
    }

    final ProviderAccount account = ProviderAccount(
      id: widget.initial?.id ?? widget.nextIdFor(label),
      label: label,
      protocol: _protocol,
      baseUrl: baseUrl,
      modelId: model,
      supportsVision: _supportsVision,
    );
    final String apiKey = _apiKeyController.text.trim();
    Navigator.of(context).pop(
      ProviderAccountDraft(
        account: account,
        apiKey: apiKey.isEmpty ? null : apiKey,
        deleteKey: _deleteKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _ProviderDialogChrome(
      title: widget.initial == null
          ? l10n.providersAddCustom
          : l10n.providersEditTitle,
      l10n: l10n,
      hasStoredKey: widget.hasStoredKey,
      deleteKey: _deleteKey,
      onDeleteKey: () => setState(() => _deleteKey = !_deleteKey),
      onSave: _save,
      fields: <Widget>[
        TextField(
          key: const ValueKey<String>('provider-name'),
          controller: _labelController,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.providersNameLabel,
            errorText: _labelError,
            border: _fieldBorder,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ProviderProtocol>(
          isExpanded: true,
          key: const ValueKey<String>('provider-protocol-select'),
          initialValue: _protocol,
          decoration: InputDecoration(
            labelText: l10n.providersProtocolLabel,
            border: _fieldBorder,
          ),
          items: <DropdownMenuItem<ProviderProtocol>>[
            for (final ProviderProtocol protocol
                in ProviderProtocol.customProtocols)
              DropdownMenuItem<ProviderProtocol>(
                value: protocol,
                child: Text(providerProtocolLabel(l10n, protocol)),
              ),
          ],
          onChanged: (ProviderProtocol? protocol) {
            if (protocol == null) return;
            setState(() => _protocol = protocol);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey<String>('provider-base-url'),
          controller: _baseUrlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.settingsServerAddressLabel,
            hintText: l10n.providersBaseUrlHint,
            errorText: _baseUrlError,
            border: _fieldBorder,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey<String>('provider-model'),
          controller: _modelController,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          onChanged: (String value) {
            if (_visionTouched) return;
            final bool inferred = inferSupportsVisionFromModelId(value);
            if (inferred == _supportsVision) return;
            setState(() => _supportsVision = inferred);
          },
          decoration: InputDecoration(
            labelText: l10n.settingsModelLabel,
            hintText: l10n.providersModelHint,
            errorText: _modelError,
            border: _fieldBorder,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          key: const ValueKey<String>('provider-supports-vision'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.providersVisionLabel),
          subtitle: Text(l10n.providersVisionHint),
          value: _supportsVision,
          onChanged: (bool value) => setState(() {
            _supportsVision = value;
            _visionTouched = true;
          }),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey<String>('provider-key'),
          controller: _apiKeyController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.settingsCloudKeyLabel,
            helperText: widget.hasStoredKey
                ? l10n.providersKeyKeep
                : l10n.providersKeyOptionalHint,
            helperMaxLines: 3,
            border: _fieldBorder,
          ),
        ),
      ],
    );
  }
}

/// Рамка полей диалогов — общая форма экранов настроек.
final OutlineInputBorder _fieldBorder = OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
);
