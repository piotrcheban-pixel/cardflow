/// Диалоги добавления и изменения провайдера (ADR-020; REDESIGN-SPEC §9.17).
///
/// Два пути, как в DSH: «Сторонний поставщик» — выбор из каталога с
/// автозаполнением адреса и модели; «Пользовательская модель API» — ручной
/// ввод названия, адреса, протокола и модели. Ключ API в диалоге только
/// записывается в `ApiKeyStore` (secure storage): значение не подставляется в
/// поле, не показывается и не логируется (SPEC 3.4); после сохранения поле
/// всегда пустое. Ошибки — только из ARB.
library;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/providers/provider_endpoint.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';

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
  return _showProviderDialog<ProviderAccountDraft>(
    context,
    _PresetProviderDialog(
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
  return _showProviderDialog<ProviderAccountDraft>(
    context,
    _CustomProviderDialog(
      nextIdFor: nextIdFor,
      initial: initial,
      hasStoredKey: hasStoredKey,
    ),
  );
}

/// Оболочка диалога: `Dialog` с `NcSurface`-монолитом 560 px (§9.17).
Future<T?> _showProviderDialog<T>(BuildContext context, Widget child) {
  final NcTheme theme = NcTheme.of(context);
  return showDialog<T>(
    context: context,
    barrierColor: theme.colors.scrim,
    builder: (BuildContext dialogContext) => Dialog(
      backgroundColor: NcColors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.9,
        ),
        child: SingleChildScrollView(
          child: NcSurface(
            tone: NcSurfaceTone.monolith,
            radius: NcRadii.xl,
            level: 3,
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Общая часть диалога: поля ключа и кнопки действий.
class _ProviderDialogChrome extends StatelessWidget {
  const _ProviderDialogChrome({
    required this.l10n,
    required this.fields,
    required this.onSave,
    required this.onCancel,
    required this.hasStoredKey,
    required this.onDeleteKey,
    required this.deleteKey,
  });

  final AppLocalizations l10n;
  final List<Widget> fields;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final bool hasStoredKey;
  final VoidCallback onDeleteKey;
  final bool deleteKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...fields,
        if (hasStoredKey)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: NcButton(
              key: const ValueKey<String>('provider-delete-key'),
              label: deleteKey
                  ? l10n.providersKeyUndoDelete
                  : l10n.settingsKeyDelete,
              variant: NcButtonVariant.ghost,
              size: NcButtonSize.s,
              icon: deleteKey ? Icons.undo : Icons.delete_outline,
              onPressed: onDeleteKey,
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            NcButton(
              key: const ValueKey<String>('provider-cancel'),
              label: l10n.cancel,
              variant: NcButtonVariant.ghost,
              onPressed: onCancel,
            ),
            NcButton(
              key: const ValueKey<String>('provider-save'),
              label: l10n.save,
              onPressed: onSave,
            ),
          ],
        ),
      ],
    );
  }
}

/// Поле ключа с «глазом»; после сохранения значение не подставляется.
class _ProviderKeyField extends StatelessWidget {
  const _ProviderKeyField({
    required this.controller,
    required this.visible,
    required this.onToggleVisibility,
    required this.label,
    required this.helper,
    this.errorText,
  });

  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggleVisibility;
  final String label;
  final String helper;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NcTextField(
      key: const ValueKey<String>('provider-key'),
      controller: controller,
      obscureText: !visible,
      label: label,
      helper: helper,
      errorText: errorText,
      suffix: NcIconButton(
        icon: visible
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        tooltip: visible ? l10n.providersKeyHide : l10n.providersKeyShow,
        size: 32,
        onPressed: onToggleVisibility,
      ),
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
  bool _keyVisible = false;

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
    final NcTheme theme = NcTheme.of(context);
    final ProviderPreset? preset = _preset;
    final bool locked = widget.initial != null;
    final bool vision =
        preset?.modelById(_resolvedModelId ?? '')?.supportsVision ?? false;
    return _ProviderDialogChrome(
      l10n: l10n,
      hasStoredKey: widget.hasStoredKey,
      deleteKey: _deleteKey,
      onDeleteKey: () => setState(() => _deleteKey = !_deleteKey),
      onSave: _save,
      onCancel: () => Navigator.of(context).pop(),
      fields: <Widget>[
        Text(
          locked ? l10n.providersEditTitle : l10n.providersAddPreset,
          style: theme.typography.titleL.copyWith(
            color: theme.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        NcDropdown<String>(
          key: const ValueKey<String>('provider-preset-select'),
          label: l10n.providersPresetLabel,
          value: preset?.id,
          enabled: !locked,
          items: <NcDropdownItem<String>>[
            for (final ProviderPreset item in kProviderPresets)
              NcDropdownItem<String>(value: item.id, label: item.label),
          ],
          onChanged: (String? presetId) {
            if (presetId == null) return;
            setState(() {
              _preset = providerPresetById(presetId);
              _modelId = _preset?.defaultModel.id;
              _keyError = null;
            });
          },
        ),
        const SizedBox(height: 12),
        NcListRow(
          key: const ValueKey<String>('provider-base-url'),
          title: Text(
            preset?.baseUrl ?? '',
            style: theme.typography.monoM.copyWith(
              color: theme.colors.textPrimary,
            ),
          ),
          subtitle: Text(l10n.settingsServerAddressLabel),
          showDivider: false,
        ),
        const SizedBox(height: 12),
        NcDropdown<String>(
          key: ValueKey<String>('provider-model-select-${preset?.id}'),
          label: l10n.settingsModelLabel,
          value: _resolvedModelId,
          items: <NcDropdownItem<String>>[
            for (final ProviderPresetModel model
                in preset?.models ?? const <ProviderPresetModel>[])
              NcDropdownItem<String>(value: model.id, label: model.label),
          ],
          onChanged: (String? modelId) => setState(() => _modelId = modelId),
        ),
        const SizedBox(height: 8),
        NcBadge(
          key: const ValueKey<String>('provider-preset-vision'),
          label: vision
              ? l10n.providersVisionSupported
              : l10n.providersVisionNotSupported,
          tone: vision ? NcBadgeTone.iris : NcBadgeTone.neutral,
        ),
        const SizedBox(height: 12),
        _ProviderKeyField(
          controller: _apiKeyController,
          visible: _keyVisible,
          onToggleVisibility: () => setState(() => _keyVisible = !_keyVisible),
          label: l10n.settingsCloudKeyLabel,
          helper: widget.hasStoredKey
              ? l10n.providersKeyKeep
              : l10n.providersKeyHelper,
          errorText: _keyError,
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
  bool _keyVisible = false;

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
    final NcTheme theme = NcTheme.of(context);
    return _ProviderDialogChrome(
      l10n: l10n,
      hasStoredKey: widget.hasStoredKey,
      deleteKey: _deleteKey,
      onDeleteKey: () => setState(() => _deleteKey = !_deleteKey),
      onSave: _save,
      onCancel: () => Navigator.of(context).pop(),
      fields: <Widget>[
        Text(
          widget.initial == null
              ? l10n.providersAddCustom
              : l10n.providersEditTitle,
          style: theme.typography.titleL.copyWith(
            color: theme.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        NcTextField(
          key: const ValueKey<String>('provider-name'),
          controller: _labelController,
          label: l10n.providersNameLabel,
          errorText: _labelError,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        NcDropdown<ProviderProtocol>(
          key: const ValueKey<String>('provider-protocol-select'),
          label: l10n.providersProtocolLabel,
          value: _protocol,
          items: <NcDropdownItem<ProviderProtocol>>[
            for (final ProviderProtocol protocol
                in ProviderProtocol.customProtocols)
              NcDropdownItem<ProviderProtocol>(
                value: protocol,
                label: providerProtocolLabel(l10n, protocol),
              ),
          ],
          onChanged: (ProviderProtocol? protocol) {
            if (protocol == null) return;
            setState(() => _protocol = protocol);
          },
        ),
        const SizedBox(height: 12),
        NcTextField(
          key: const ValueKey<String>('provider-base-url'),
          controller: _baseUrlController,
          label: l10n.settingsServerAddressLabel,
          hint: l10n.providersBaseUrlHint,
          errorText: _baseUrlError,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        NcTextField(
          key: const ValueKey<String>('provider-model'),
          controller: _modelController,
          label: l10n.settingsModelLabel,
          hint: l10n.providersModelHint,
          errorText: _modelError,
          textInputAction: TextInputAction.next,
          onChanged: (String value) {
            if (_visionTouched) return;
            final bool inferred = inferSupportsVisionFromModelId(value);
            if (inferred == _supportsVision) return;
            setState(() => _supportsVision = inferred);
          },
        ),
        const SizedBox(height: 8),
        NcListRow(
          key: const ValueKey<String>('provider-supports-vision'),
          title: Text(l10n.providersVisionLabel),
          subtitle: Text(l10n.providersVisionHint),
          showDivider: false,
          onTap: () => setState(() {
            _supportsVision = !_supportsVision;
            _visionTouched = true;
          }),
          trailing: NcSwitch(
            value: _supportsVision,
            semanticLabel: l10n.providersVisionLabel,
            onChanged: (bool value) => setState(() {
              _supportsVision = value;
              _visionTouched = true;
            }),
          ),
        ),
        const SizedBox(height: 8),
        _ProviderKeyField(
          controller: _apiKeyController,
          visible: _keyVisible,
          onToggleVisibility: () => setState(() => _keyVisible = !_keyVisible),
          label: l10n.settingsCloudKeyLabel,
          helper: widget.hasStoredKey
              ? l10n.providersKeyKeep
              : l10n.providersKeyOptionalHint,
        ),
      ],
    );
  }
}
