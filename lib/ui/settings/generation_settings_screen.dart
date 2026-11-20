/// Экран «Провайдеры»: единый список аккаунтов генерации (ADR-020).
///
/// Переписан в итерации 7.5 по замечанию владельца: вместо отдельных полей
/// OpenAI/Gemini/Anthropic и «OpenAI-совместимого сервера» — карточки
/// провайдеров и кнопка «+ Добавить провайдера» с двумя путями (каталог или
/// пользовательская модель API). Ключ API пишется только в `ApiKeyStore`
/// (secure storage, SPEC 3.4) и отдельно от настроек: сохраняется по одному
/// нажатию, без обязательного адреса/модели. После записи ключ читается
/// обратно — «Сохранено» показывается только если хранилище действительно
/// вернуло значение (диагностика D3).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/generation/api_key_verifier.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/decks/deck_actions.dart' show showAppMessage;
import 'package:cardflow/api/models/model_capability_service.dart';
import 'package:cardflow/ui/settings/model_capability_section.dart';
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

  /// Сохраняет изменённый активный аккаунт и обновляет локальное состояние.
  ///
  /// Без локального обновления блок характеристик продолжил бы показывать
  /// старую дату/источник: `ref.invalidate` пересобирает провайдер, но не
  /// состояние этого экрана (ретроспектива итерации 7: проверяется применение).
  Future<void> _saveActiveAccount(ProviderAccount updated) async {
    final ProviderAccounts next = _accounts.withAccount(updated);
    try {
      await ref.read(providerAccountsProvider.notifier).save(next);
      ref.invalidate(providerAccountsProvider);
      if (mounted) setState(() => _accounts = next);
    } on Object {
      if (mounted) setState(() => _loadFailed = true);
      rethrow;
    }
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
    final _AddProviderChoice? choice =
        await showModalBottomSheet<_AddProviderChoice>(
          context: context,
          builder: (BuildContext context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  key: const ValueKey<String>('providers-add-preset'),
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(l10n.providersAddPreset),
                  subtitle: Text(l10n.providersAddPresetSubtitle),
                  onTap: () =>
                      Navigator.of(context).pop(_AddProviderChoice.preset),
                ),
                ListTile(
                  key: const ValueKey<String>('providers-add-custom'),
                  leading: const Icon(Icons.tune_outlined),
                  title: Text(l10n.providersAddCustom),
                  subtitle: Text(l10n.providersAddCustomSubtitle),
                  onTap: () =>
                      Navigator.of(context).pop(_AddProviderChoice.custom),
                ),
              ],
            ),
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
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.providersDeleteTitle),
        content: Text(l10n.providersDeleteBody),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('provider-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey<String>('provider-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.providersDelete),
          ),
        ],
      ),
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.providersTitle)),
      body: _buildBody(l10n),
      bottomNavigationBar: _loading || _loadFailed
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSizes.formMaxWidth,
                      ),
                      child: FilledButton.icon(
                        key: const ValueKey<String>('providers-add'),
                        onPressed: _openAddMenu,
                        icon: const Icon(Icons.add, size: AppSizes.icon),
                        label: Text(l10n.providersAdd),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.dialogMaxWidth,
            ),
            child: AppErrorState(
              message: l10n.settingsLoadError,
              retryLabel: l10n.retry,
              onRetry: _retryLoad,
            ),
          ),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.formMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          children: <Widget>[
            Text(
              l10n.providersDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_accounts.isEmpty)
              _EmptyProviders(l10n: l10n)
            else
              for (final ProviderAccount account in _accounts.accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ProviderCard(
                    account: account,
                    active: _accounts.active?.id == account.id,
                    keyConfigured: _keyConfigured[account.id] ?? false,
                    checking: _checking.contains(account.id),
                    onCheck: () => _check(account),
                    onEdit: () => _edit(account),
                    onDelete: () => _delete(account),
                    onActivate: () => _setActive(account),
                  ),
                ),
            if (_accounts.active != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              ModelCapabilitySection(
                account: _accounts.active!,
                loadLimits: () => ref
                    .read(modelCapabilityServiceProvider)
                    .limitsFor(_accounts.active!),
                refresh: () async {
                  final CapabilityRefresh result = await ref
                      .read(modelCapabilityServiceProvider)
                      .refresh(_accounts.active!);
                  return result.result.isSuccess;
                },
                save: (CapabilityDraft draft) async {
                  final ProviderAccount account = _accounts.active!;
                  final ProviderAccount updated = draft.isEmpty
                      ? account.withAutomaticCapabilities()
                      : account.withConfiguredCapabilities(
                          // Пустой контекст — «не задан пользователем»: 16 000 —
                          // исторический маркер отсутствия значения (L-18).
                          contextTokens:
                              draft.contextTokens ??
                              kCustomProviderContextTokens,
                          maxInputTokens: draft.maxInputTokens,
                          maxOutputTokens: draft.maxOutputTokens,
                          configuredAt: DateTime.now().toUtc(),
                        );
                  await _saveActiveAccount(updated);
                },
                reset: () async {
                  await _saveActiveAccount(
                    _accounts.active!.withAutomaticCapabilities(),
                  );
                },
              ),
            ],
          ],
        ),
      ),
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

/// Пустой список провайдеров.
class _EmptyProviders extends StatelessWidget {
  const _EmptyProviders({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.key_off_outlined,
      title: l10n.providersEmptyTitle,
      message: l10n.providersEmptyDescription,
    );
  }
}

/// Карточка одного провайдера со статусом ключа и действиями.
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.account,
    required this.active,
    required this.keyConfigured,
    required this.checking,
    required this.onCheck,
    required this.onEdit,
    required this.onDelete,
    required this.onActivate,
  });

  final ProviderAccount account;
  final bool active;
  final bool keyConfigured;
  final bool checking;
  final VoidCallback onCheck;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String keyStatus = account.requiresApiKey
        ? (keyConfigured ? l10n.settingsKeyConfigured : l10n.settingsKeyMissing)
        : l10n.providersKeyNotRequired;
    return AppPanel(
      key: ValueKey<String>('provider-card-${account.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadii.input,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconBadge(
                icon: providerProtocolIcon(account.protocol),
                color: theme.colorScheme.primary,
                size: 32,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      providerAccountLabel(l10n, account),
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      providerSummary(l10n, account),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      account.baseUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Chip(
                  key: ValueKey<String>('provider-active-${account.id}'),
                  label: Text(l10n.providersActive),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (!account.isConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.providersIncompleteHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            keyStatus,
            style: theme.textTheme.labelSmall?.copyWith(
              color: keyConfigured || !account.requiresApiKey
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            account.supportsVision
                ? l10n.providersVisionSupported
                : l10n.providersVisionNotSupported,
            key: ValueKey<String>('provider-vision-${account.id}'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              TextButton(
                key: ValueKey<String>('provider-check-${account.id}'),
                onPressed: checking ? null : onCheck,
                child: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.providersCheck),
              ),
              if (!active)
                TextButton(
                  key: ValueKey<String>('provider-activate-${account.id}'),
                  onPressed: onActivate,
                  child: Text(l10n.providersMakeActive),
                ),
              TextButton(
                key: ValueKey<String>('provider-edit-${account.id}'),
                onPressed: onEdit,
                child: Text(l10n.providersEdit),
              ),
              TextButton(
                key: ValueKey<String>('provider-delete-${account.id}'),
                onPressed: onDelete,
                child: Text(l10n.providersDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
