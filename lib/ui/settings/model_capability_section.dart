/// Блок характеристик модели в настройках провайдеров (ADR-039 §6).
///
/// Показывает лимиты с происхождением и датой проверки; действия — «Обновить
/// характеристики» (discovery провайдера) и «Сбросить к автоматическому»
/// (каталог/неизвестность вместо пользовательских значений). Значения без
/// источника честно называются «неизвестно», а не «типовыми».
library;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/settings/provider_labels.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Тип загрузчика лимитов.
typedef CapabilityLimitsLoader = Future<ModelLimits> Function();

/// Тип обновления характеристик.
typedef CapabilityRefresher = Future<bool> Function();

/// Тип сброса пользовательских значений.
typedef CapabilityResetter = Future<void> Function();

/// Блок «Характеристики модели» для активного аккаунта.
class ModelCapabilitySection extends StatefulWidget {
  /// Создаёт блок.
  const ModelCapabilitySection({
    required this.account,
    required this.loadLimits,
    required this.refresh,
    required this.reset,
    super.key,
  });

  /// Аккаунт, характеристики которого показываются.
  final ProviderAccount account;

  /// Загрузка лимитов (кэш/каталог, без сети).
  final CapabilityLimitsLoader loadLimits;

  /// Обновление через API провайдера; `true` — успех.
  final CapabilityRefresher refresh;

  /// Сброс к автоматическим значениям.
  final CapabilityResetter reset;

  @override
  State<ModelCapabilitySection> createState() => _ModelCapabilitySectionState();
}

class _ModelCapabilitySectionState extends State<ModelCapabilitySection> {
  ModelLimits? _limits;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ModelCapabilitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id ||
        oldWidget.account.modelId != widget.account.modelId) {
      _reload();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final ModelLimits limits = await widget.loadLimits();
      if (!mounted) return;
      setState(() {
        _limits = limits;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    bool ok = false;
    try {
      ok = await widget.refresh();
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _message = ok
          ? l10n.settingsCapabilitiesRefreshDone
          : l10n.settingsCapabilitiesRefreshFailed;
    });
    await _reload();
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.reset();
      if (!mounted) return;
      setState(() {
        _message = AppLocalizations.of(context).settingsCapabilitiesResetDone;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _message = AppLocalizations.of(context)
            .settingsCapabilitiesRefreshFailed;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ModelLimits? limits = _limits;
    return AppPanel(
      key: ValueKey<String>('model-capabilities-${widget.account.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadii.input,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.settingsCapabilitiesTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.settingsCapabilitiesDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_failed)
            Text(
              l10n.settingsCapabilitiesLoadFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (limits != null) ...<Widget>[
            _CapabilityRow(
              label: l10n.settingsCapabilitiesContext,
              value: limits.contextTokens,
              l10n: l10n,
            ),
            _CapabilityRow(
              label: l10n.settingsCapabilitiesOutput,
              value: limits.maxOutputTokens,
              l10n: l10n,
            ),
            _CapabilityRow(
              label: l10n.settingsCapabilitiesImages,
              value: limits.maxImagesPerRequest,
              l10n: l10n,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  _message!,
                  key: const ValueKey<String>('capabilities-message'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                OutlinedButton.icon(
                  key: const ValueKey<String>('capabilities-refresh'),
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: AppSizes.icon),
                  label: Text(l10n.settingsCapabilitiesRefresh),
                ),
                TextButton.icon(
                  key: const ValueKey<String>('capabilities-reset'),
                  onPressed: _busy ? null : _reset,
                  icon: const Icon(
                    Icons.settings_backup_restore,
                    size: AppSizes.icon,
                  ),
                  label: Text(l10n.settingsCapabilitiesReset),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.value,
    required this.l10n,
  });

  final String label;
  final Sourced<int> value;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String text = value.value == null
        ? l10n.settingsCapabilitiesUnknown
        : _formatTokens(value.value!);
    final String source = capabilitySourceLabel(l10n, value.source);
    final DateTime? observed = value.observedAt;
    final String date = observed == null
        ? ''
        : ' · ${l10n.settingsCapabilitiesCheckedAt(_date(observed))}';
    final String line = '$text — $source$date';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              line,
              key: ValueKey<String>('capability-$label'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: value.isKnown
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTokens(int value) {
    final String digits = value.toString();
    final StringBuffer buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(' ');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }

  static String _date(DateTime value) {
    final DateTime local = value.toLocal();
    final String month = local.month.toString().padLeft(2, '0');
    final String day = local.day.toString().padLeft(2, '0');
    return '$day.$month.${local.year}';
  }
}
