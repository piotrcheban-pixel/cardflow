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
import 'package:cardflow/ui/components/app_dialogs.dart';
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

  /// Результат последней проверки по аккаунту: показывается inline, а не только
  /// снекбаром (аудит 2.0, P2-15).
  final Map<String, (ApiKeyCheckStatus, String)> _checkResults =
      <String, (ApiKeyCheckStatus, String)>{};
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
          // Аудит 2.0 (P2-16): нижний пункт обрезался кромкой на 720 px.
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext context) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xs,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          l10n.providersSheetSubtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
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
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
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
    final ThemeData theme = Theme.of(context);
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      title: l10n.providersDeleteTitle,
      subtitle: l10n.providersDeleteBody,
      bodyBuilder: (BuildContext dialogContext) => const SizedBox.shrink(),
      // F12/V8: destructive — error-заливка, безопасное — нейтральный текст;
      // один компонент AppDialog вместо сырого AlertDialog.
      actionsBuilder: (BuildContext dialogContext) => <Widget>[
        TextButton(
          key: const ValueKey<String>('provider-delete-cancel'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('provider-delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.providersDelete),
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
      });
      showAppMessage(context, l10n.providersDeleted);
    } on Object {
      if (!mounted) return;
      showAppMessage(context, l10n.providersSaveError);
    }
  }

  Future<void> _setActive(ProviderAccount account) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Находка F7: невалидный аккаунт (пустой адрес/модель) не может стать
    // основным — иначе генерация недоступна без видимой причины.
    if (!account.isConfigured) {
      showAppMessage(context, l10n.settingsProvidersCannotBePrimary);
      return;
    }
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
    setState(() => _checking.add(account.id));
    try {
      final ApiKeyCheckResult result = await ref
          .read(apiKeyVerifierProvider)
          .check(account);
      if (!mounted) return;
      final MaterialLocalizations material = MaterialLocalizations.of(context);
      final String time = material.formatTimeOfDay(
        TimeOfDay.now(),
        alwaysUse24HourFormat: true,
      );
      setState(() {
        _checkResults[account.id] = (result.status, time);
      });
    } on Object {
      if (!mounted) return;
      final MaterialLocalizations material = MaterialLocalizations.of(context);
      final String time = material.formatTimeOfDay(
        TimeOfDay.now(),
        alwaysUse24HourFormat: true,
      );
      setState(() {
        _checkResults[account.id] = (ApiKeyCheckStatus.unexpected, time);
      });
    } finally {
      if (mounted) setState(() => _checking.remove(account.id));
    }
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
                      constraints: BoxConstraints(
                        maxWidth: AppSizes.wideFormWidth(context),
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
      return const SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSkeleton(width: 260, height: 34),
            SizedBox(height: AppSpacing.md),
            AppSkeleton(height: 96),
            SizedBox(height: AppSpacing.sm),
            AppSkeleton(height: 96),
            SizedBox(height: AppSpacing.sm),
            AppSkeleton(height: 96),
          ],
        ),
      );
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
        constraints: BoxConstraints(maxWidth: AppSizes.wideFormWidth(context)),
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
                    checkResult: _checkResults[account.id],
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

/// Сообщение о результате проверки подключения (ARB, без сырых ошибок).
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
///
/// Аудит 2.0 (P2-14/P2-15): статусы («основной», «ключ сохранён») — бейджи, а
/// не кнопки и не синий текст; действия — кнопки с иконками; «Удалить» —
/// danger-стиль; проверка подключения показывает inline-результат со временем,
/// а не только исчезающий снекбар.
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
    this.checkResult,
  });

  final ProviderAccount account;
  final bool active;
  final bool keyConfigured;
  final bool checking;
  final VoidCallback onCheck;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onActivate;

  /// Последний результат проверки подключения (статус и время).
  final (ApiKeyCheckStatus, String)? checkResult;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool keyOk = keyConfigured || !account.requiresApiKey;
    final (ApiKeyCheckStatus, String)? result = checkResult;
    return AppPanel(
      key: ValueKey<String>('provider-card-${account.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadii.input,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconBadge(
                icon: providerProtocolIcon(account.protocol),
                color: scheme.primary,
                size: 36,
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                AppStatusChip(
                  key: ValueKey<String>('provider-active-${account.id}'),
                  label: l10n.providersActive,
                  tone: AppStatusTone.success,
                  icon: Icons.check_circle_outline,
                  dense: true,
                ),
            ],
          ),
          if (!account.isConfigured)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                l10n.providersIncompleteHint,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              AppStatusChip(
                key: ValueKey<String>('provider-key-status-${account.id}'),
                label: account.requiresApiKey
                    ? (keyConfigured
                          ? l10n.settingsKeyConfigured
                          : l10n.settingsKeyMissing)
                    : l10n.providersKeyNotRequired,
                tone: keyOk ? AppStatusTone.neutral : AppStatusTone.warning,
                icon: keyOk ? Icons.key_outlined : Icons.key_off_outlined,
                dense: true,
              ),
              Text(
                account.supportsVision
                    ? l10n.providersVisionSupported
                    : l10n.providersVisionNotSupported,
                key: ValueKey<String>('provider-vision-${account.id}'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _ProviderCheckResult(
              key: ValueKey<String>('provider-check-result-${account.id}'),
              status: result.$1,
              time: result.$2,
              message: _statusMessage(l10n, result.$1),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                key: ValueKey<String>('provider-check-${account.id}'),
                onPressed: checking ? null : onCheck,
                icon: checking
                    ? const SizedBox(
                        width: AppSizes.iconSmall,
                        height: AppSizes.iconSmall,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.wifi_tethering,
                        size: AppSizes.iconSmall,
                      ),
                label: Text(l10n.providersCheck),
              ),
              if (!active)
                OutlinedButton(
                  key: ValueKey<String>('provider-activate-${account.id}'),
                  onPressed: onActivate,
                  child: Text(l10n.providersMakeActive),
                ),
              OutlinedButton(
                key: ValueKey<String>('provider-edit-${account.id}'),
                onPressed: onEdit,
                child: Text(l10n.providersEdit),
              ),
              TextButton.icon(
                key: ValueKey<String>('provider-delete-${account.id}'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  size: AppSizes.iconSmall,
                ),
                label: Text(l10n.providersDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline-результат проверки подключения со временем.
class _ProviderCheckResult extends StatelessWidget {
  const _ProviderCheckResult({
    required this.status,
    required this.time,
    required this.message,
    super.key,
  });

  final ApiKeyCheckStatus status;
  final String time;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool ok = status == ApiKeyCheckStatus.valid;
    final Color color = ok ? scheme.secondary : scheme.error;
    return Row(
      children: <Widget>[
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          size: AppSizes.iconSmall,
          color: color,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            ok
                ? '${AppLocalizations.of(context).providersCheckInlineOk} · $time'
                : '${AppLocalizations.of(context).providersCheckInlineFail} · $time',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        Tooltip(
          message: message,
          child: Icon(
            Icons.info_outline,
            size: AppSizes.iconSmall,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
