/// Экран «Провайдеры»: единый список аккаунтов генерации (ADR-020;
/// REDESIGN-SPEC §9.17).
///
/// Карточки провайдеров — `NcSurface` с монохромным глифом протокола в круге
/// `irisSoft`, бейджами «Активен»/«Vision» и рядом действий `Wrap`; проверка
/// ключа показывает `NcSpinner` и бейдж результата. Ключ API пишется только в
/// `ApiKeyStore` (secure storage, SPEC 3.4) и отдельно от настроек:
/// сохраняется по одному нажатию, без обязательного адреса/модели. После
/// записи ключ читается обратно — «Сохранено» показывается только если
/// хранилище действительно вернуло значение (диагностика D3). Значение ключа
/// нигде не отображается.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/generation/api_key_verifier.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart' show showAppMessage;
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/settings/provider_account_dialogs.dart';
import 'package:cardflow/ui/settings/provider_labels.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Экран настройки провайдеров генерации.
class GenerationSettingsScreen extends ConsumerStatefulWidget {
  /// Создаёт экран.
  const GenerationSettingsScreen({super.key});

  @override
  ConsumerState<GenerationSettingsScreen> createState() =>
      _GenerationSettingsScreenState();
}

class _GenerationSettingsScreenState
    extends ConsumerState<GenerationSettingsScreen> {
  ProviderAccounts _accounts = ProviderAccounts.empty;
  Map<String, bool> _keyConfigured = <String, bool>{};
  final Set<String> _checking = <String>{};
  final Map<String, ApiKeyCheckStatus> _checkResults =
      <String, ApiKeyCheckStatus>{};
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Читает список провайдеров и наличие их ключей (present/absent).
  Future<void> _load() async {
    try {
      final ProviderAccounts accounts = await ref.read(
        providerAccountsProvider.future,
      );
      final ApiKeyStore keyStore = ref.read(apiKeyStoreProvider);
      final Map<String, bool> configured = <String, bool>{};
      for (final ProviderAccount account in accounts.accounts) {
        final String? key = await keyStore.read(account.id);
        configured[account.id] = key != null && key.isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _keyConfigured = configured;
        _loading = false;
        _loadFailed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _retryLoad() {
    ref.invalidate(providerAccountsProvider);
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    _load();
  }

  /// Следующий свободный id аккаунта для пресета (id === ключ secure storage).
  String _nextIdForPreset(String presetId) {
    return uniqueProviderAccountId(
      presetId,
      _accounts.accounts.map((ProviderAccount account) => account.id),
    );
  }

  /// Следующий свободный id для пользовательского аккаунта.
  String _nextIdForLabel(String label) {
    return uniqueProviderAccountId(
      label,
      _accounts.accounts.map((ProviderAccount account) => account.id),
    );
  }

  /// Меню «+ Добавить провайдера»: каталог или пользовательская модель.
  Future<void> _openAddMenu() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final _AddProviderChoice? choice = await showNcSheet<_AddProviderChoice>(
      context,
      title: l10n.providersAdd,
      closeTooltip: l10n.commonClose,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcListRow(
            key: const ValueKey<String>('providers-add-preset'),
            leading: const Icon(Icons.storefront_outlined),
            title: Text(l10n.providersAddPreset),
            subtitle: Text(l10n.providersAddPresetSubtitle),
            onTap: () =>
                Navigator.of(sheetContext).pop(_AddProviderChoice.preset),
          ),
          NcListRow(
            key: const ValueKey<String>('providers-add-custom'),
            leading: const Icon(Icons.tune_outlined),
            title: Text(l10n.providersAddCustom),
            subtitle: Text(l10n.providersAddCustomSubtitle),
            showDivider: false,
            onTap: () =>
                Navigator.of(sheetContext).pop(_AddProviderChoice.custom),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _AddProviderChoice.preset:
        await _addPreset();
      case _AddProviderChoice.custom:
        await _addCustom();
    }
  }

  Future<void> _addPreset() async {
    final ProviderAccountDraft? draft = await showPresetProviderDialog(
      context,
      nextIdFor: _nextIdForPreset,
    );
    if (draft == null || !mounted) return;
    await _persistDraft(draft);
  }

  Future<void> _addCustom() async {
    final ProviderAccountDraft? draft = await showCustomProviderDialog(
      context,
      nextIdFor: _nextIdForLabel,
    );
    if (draft == null || !mounted) return;
    await _persistDraft(draft);
  }

  Future<void> _edit(ProviderAccount account) async {
    final bool hasStoredKey = _keyConfigured[account.id] ?? false;
    final ProviderAccountDraft? draft = account.presetId == null
        ? await showCustomProviderDialog(
            context,
            nextIdFor: _nextIdForLabel,
            initial: account,
            hasStoredKey: hasStoredKey,
          )
        : await showPresetProviderDialog(
            context,
            nextIdFor: _nextIdForPreset,
            initial: account,
            hasStoredKey: hasStoredKey,
          );
    if (draft == null || !mounted) return;
    await _persistDraft(draft);
  }

  /// Сохраняет ключ (с проверкой записи), затем список провайдеров.
  Future<void> _persistDraft(ProviderAccountDraft draft) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiKeyStore keyStore = ref.read(apiKeyStoreProvider);
    try {
      final String? apiKey = draft.apiKey;
      if (draft.deleteKey) {
        await keyStore.delete(draft.account.id);
      } else if (apiKey != null) {
        await keyStore.write(draft.account.id, apiKey);
        final String? stored = await keyStore.read(draft.account.id);
        if (stored == null || stored != apiKey.trim()) {
          if (!mounted) return;
          showAppMessage(context, l10n.providersKeyStoreError);
          return;
        }
      }
      final ProviderAccounts updated = _accounts.withAccount(draft.account);
      await ref.read(providerAccountsProvider.notifier).save(updated);
      final String? stored = await keyStore.read(draft.account.id);
      if (!mounted) return;
      setState(() {
        _accounts = updated;
        _keyConfigured = <String, bool>{
          ..._keyConfigured,
          draft.account.id: stored != null && stored.isNotEmpty,
        };
      });
      showAppMessage(context, l10n.providersSaved);
    } on Object {
      if (!mounted) return;
      showAppMessage(context, l10n.providersSaveError);
    }
  }

  Future<void> _delete(ProviderAccount account) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showNcDialog<bool>(
      context,
      title: l10n.providersDeleteTitle,
      message: l10n.providersDeleteBody,
      icon3dName: 'shield_error',
      actions: <Widget>[
        NcButton(
          key: const ValueKey<String>('provider-delete-cancel'),
          label: l10n.cancel,
          variant: NcButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NcButton(
          key: const ValueKey<String>('provider-delete-confirm'),
          label: l10n.providersDelete,
          variant: NcButtonVariant.destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(apiKeyStoreProvider).delete(account.id);
      final ProviderAccounts updated = _accounts.withoutAccount(account.id);
      await ref.read(providerAccountsProvider.notifier).save(updated);
      if (!mounted) return;
      setState(() {
        _accounts = updated;
        _keyConfigured = <String, bool>{..._keyConfigured}..remove(account.id);
        _checkResults.remove(account.id);
      });
      showAppMessage(context, l10n.providersDeleted);
    } on Object {
      if (!mounted) return;
      showAppMessage(context, l10n.providersSaveError);
    }
  }

  Future<void> _setActive(ProviderAccount account) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ProviderAccounts updated = _accounts.withActive(account.id);
    try {
      await ref.read(providerAccountsProvider.notifier).save(updated);
      if (!mounted) return;
      setState(() => _accounts = updated);
      showAppMessage(
        context,
        l10n.providersActiveSaved(providerAccountLabel(l10n, account)),
      );
    } on Object {
      if (!mounted) return;
      showAppMessage(context, l10n.providersSaveError);
    }
  }

  Future<void> _check(ProviderAccount account) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _checking.add(account.id));
    try {
      final ApiKeyCheckResult result = await ref
          .read(apiKeyVerifierProvider)
          .check(account);
      if (!mounted) return;
      setState(() => _checkResults[account.id] = result.status);
      showAppMessage(context, _statusMessage(l10n, result.status));
    } on Object {
      if (!mounted) return;
      showAppMessage(context, l10n.settingsApiCheckUnexpected);
    } finally {
      if (mounted) setState(() => _checking.remove(account.id));
    }
  }

  String _statusMessage(AppLocalizations l10n, ApiKeyCheckStatus status) {
    return switch (status) {
      ApiKeyCheckStatus.valid => l10n.providersCheckValid,
      ApiKeyCheckStatus.invalidKey => l10n.providersCheckInvalid,
      ApiKeyCheckStatus.missingKey => l10n.settingsApiCheckMissing,
      ApiKeyCheckStatus.noConnection => l10n.settingsApiCheckNoConnection,
      ApiKeyCheckStatus.rateLimited => l10n.settingsApiCheckRateLimited,
      ApiKeyCheckStatus.providerNotConfigured =>
        l10n.settingsApiCheckNotConfigured,
      ApiKeyCheckStatus.unexpected => l10n.settingsApiCheckUnexpected,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NcGlassGroup(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NcTopBar(
                title: l10n.providersTitle,
                largeTitle: l10n.providersTitle,
                actions: <Widget>[
                  NcIconButton(
                    key: const ValueKey<String>('providers-add'),
                    icon: Icons.add_rounded,
                    tooltip: l10n.providersAdd,
                    onPressed: _openAddMenu,
                  ),
                ],
              ),
              Expanded(child: _buildBody(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          NcSkeleton(height: 28, radius: NcRadii.s),
          SizedBox(height: 16),
          NcSkeleton(height: 160, radius: NcRadii.l),
          SizedBox(height: 12),
          NcSkeleton(height: 160, radius: NcRadii.l),
        ],
      );
    }
    if (_loadFailed) {
      return NcErrorState(
        message: l10n.settingsLoadError,
        retryLabel: l10n.retry,
        onRetry: _retryLoad,
      );
    }

    final NcTheme theme = NcTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        Text(
          l10n.providersDescription,
          style: theme.typography.bodyS.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        if (_accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: NcEmptyState(
              iconName: 'key',
              title: l10n.providersEmptyTitle,
              message: l10n.providersEmptyDescription,
            ),
          )
        else
          for (final ProviderAccount account in _accounts.accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProviderCard(
                account: account,
                active: _accounts.active?.id == account.id,
                keyConfigured: _keyConfigured[account.id] ?? false,
                checking: _checking.contains(account.id),
                checkStatus: _checkResults[account.id],
                onCheck: () => _check(account),
                onEdit: () => _edit(account),
                onDelete: () => _delete(account),
                onActivate: () => _setActive(account),
              ),
            ),
      ],
    );
  }
}

/// Выбор способа добавления провайдера.
enum _AddProviderChoice {
  /// Сторонний поставщик из каталога.
  preset,

  /// Пользовательская модель API.
  custom,
}

/// Карточка одного провайдера со статусом ключа и действиями.
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.account,
    required this.active,
    required this.keyConfigured,
    required this.checking,
    required this.checkStatus,
    required this.onCheck,
    required this.onEdit,
    required this.onDelete,
    required this.onActivate,
  });

  final ProviderAccount account;
  final bool active;
  final bool keyConfigured;
  final bool checking;
  final ApiKeyCheckStatus? checkStatus;
  final VoidCallback onCheck;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final bool narrow = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final String keyStatus = account.requiresApiKey
        ? (keyConfigured ? l10n.settingsKeyConfigured : l10n.settingsKeyMissing)
        : l10n.providersKeyNotRequired;
    return NcSurface(
      key: ValueKey<String>('provider-card-${account.id}'),
      radius: NcRadii.l,
      level: 1,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colors.irisSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  providerProtocolIcon(account.protocol),
                  size: 20,
                  color: theme.colors.iris,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      providerAccountLabel(l10n, account),
                      style: theme.typography.titleM.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                    ),
                    Text(
                      providerSummary(l10n, account),
                      style: theme.typography.monoM.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                    Text(
                      account.baseUrl,
                      style: theme.typography.bodyS.copyWith(
                        color: theme.colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!narrow) ...<Widget>[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    if (active)
                      NcBadge(
                        key: ValueKey<String>('provider-active-${account.id}'),
                        label: l10n.providersActive,
                        tone: NcBadgeTone.jade,
                      ),
                    const SizedBox(height: 4),
                    if (account.supportsVision)
                      NcBadge(
                        key: ValueKey<String>('provider-vision-${account.id}'),
                        label: l10n.providersVisionSupported,
                        tone: NcBadgeTone.iris,
                      )
                    else
                      Text(
                        l10n.providersVisionNotSupported,
                        key: ValueKey<String>('provider-vision-${account.id}'),
                        style: theme.typography.labelM.copyWith(
                          color: theme.colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          if (narrow) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (active)
                  NcBadge(
                    key: ValueKey<String>('provider-active-${account.id}'),
                    label: l10n.providersActive,
                    tone: NcBadgeTone.jade,
                  ),
                NcBadge(
                  key: ValueKey<String>('provider-vision-${account.id}'),
                  label: account.supportsVision
                      ? l10n.providersVisionShort
                      : l10n.providersVisionNotSupportedShort,
                  tone: account.supportsVision
                      ? NcBadgeTone.iris
                      : NcBadgeTone.neutral,
                ),
              ],
            ),
          ],
          if (!account.isConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.providersIncompleteHint,
                style: theme.typography.bodyS.copyWith(
                  color: theme.colors.ember,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  keyStatus,
                  style: theme.typography.labelM.copyWith(
                    color: keyConfigured || !account.requiresApiKey
                        ? theme.colors.jade
                        : theme.colors.textSecondary,
                  ),
                ),
              ),
              if (checkStatus != null)
                NcBadge(
                  key: ValueKey<String>('provider-check-result-${account.id}'),
                  label: checkStatus == ApiKeyCheckStatus.valid
                      ? l10n.providersCheckWorks
                      : l10n.providersCheckFailed,
                  tone: checkStatus == ApiKeyCheckStatus.valid
                      ? NcBadgeTone.jade
                      : NcBadgeTone.ember,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: narrow
                ? <Widget>[
                    NcIconButton(
                      key: ValueKey<String>('provider-check-${account.id}'),
                      icon: Icons.wifi_tethering,
                      tooltip: l10n.providersCheck,
                      variant: NcIconButtonVariant.tonal,
                      size: 36,
                      onPressed: checking ? null : onCheck,
                    ),
                    if (!active)
                      NcIconButton(
                        key: ValueKey<String>(
                          'provider-activate-${account.id}',
                        ),
                        icon: Icons.star_outline_rounded,
                        tooltip: l10n.providersMakeActive,
                        size: 36,
                        onPressed: onActivate,
                      ),
                    NcIconButton(
                      key: ValueKey<String>('provider-edit-${account.id}'),
                      icon: Icons.edit_outlined,
                      tooltip: l10n.providersEdit,
                      size: 36,
                      onPressed: onEdit,
                    ),
                    NcIconButton(
                      key: ValueKey<String>('provider-delete-${account.id}'),
                      icon: Icons.delete_outline,
                      tooltip: l10n.providersDelete,
                      size: 36,
                      onPressed: onDelete,
                    ),
                  ]
                : <Widget>[
                    NcButton(
                      key: ValueKey<String>('provider-check-${account.id}'),
                      label: l10n.providersCheck,
                      variant: NcButtonVariant.secondary,
                      size: NcButtonSize.s,
                      loading: checking,
                      onPressed: checking ? null : onCheck,
                    ),
                    if (!active)
                      NcButton(
                        key: ValueKey<String>(
                          'provider-activate-${account.id}',
                        ),
                        label: l10n.providersMakeActive,
                        variant: NcButtonVariant.ghost,
                        size: NcButtonSize.s,
                        onPressed: onActivate,
                      ),
                    NcButton(
                      key: ValueKey<String>('provider-edit-${account.id}'),
                      label: l10n.providersEdit,
                      variant: NcButtonVariant.ghost,
                      size: NcButtonSize.s,
                      onPressed: onEdit,
                    ),
                    NcButton(
                      key: ValueKey<String>('provider-delete-${account.id}'),
                      label: l10n.providersDelete,
                      variant: NcButtonVariant.ghost,
                      size: NcButtonSize.s,
                      onPressed: onDelete,
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}
