/// Экран «Настройки» (SPEC A6.6, ADR-019).
///
/// Блоки: внешний вид, API, обучение, доступность, «О приложении». Каждый
/// элемент меняет `AppSettings` и сохраняется через `AppSettingsController`
/// (ошибка записи — сообщение из ARB, состояние откатывается). Ключи API
/// сюда не попадают: только статус present/absent и переход в настройки
/// генерации (ADR-013). «Проверить» выполняет реальный минимальный запрос
/// через `ApiKeyVerifier` (ADR-019 §5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/settings/about_links.dart';
import 'package:cardflow/ui/settings/provider_labels.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Экран настроек приложения.
class SettingsScreen extends ConsumerWidget {
  /// Создаёт экран.
  const SettingsScreen({super.key});

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    try {
      await ref.read(appSettingsProvider.notifier).save(settings);
    } on Object {
      if (context.mounted) {
        showAppMessage(context, AppLocalizations.of(context).settingsSaveError);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AppSettings> settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsScreenTitle)),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => _SettingsLoadError(
          onRetry: () => ref.invalidate(appSettingsProvider),
        ),
        data: (AppSettings value) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            _SectionTitle(l10n.settingsAppearanceTitle),
            _AppearanceSection(
              settings: value,
              onChanged: (AppSettings next) => _update(context, ref, next),
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.settingsApiTitle),
            const _ApiSection(),
            const SizedBox(height: 24),
            _SectionTitle(l10n.settingsLearningTitle),
            _LearningSection(
              settings: value,
              onChanged: (AppSettings next) => _update(context, ref, next),
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.settingsAccessibilityTitle),
            _AccessibilitySection(
              settings: value,
              onChanged: (AppSettings next) => _update(context, ref, next),
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.settingsAboutTitle),
            const _AboutSection(),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.settings, required this.onChanged});

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.settingsThemeTitle),
        const SizedBox(height: 8),
        SegmentedButton<AppThemePreference>(
          key: const ValueKey<String>('settings-theme'),
          segments: <ButtonSegment<AppThemePreference>>[
            ButtonSegment<AppThemePreference>(
              value: AppThemePreference.light,
              label: Text(l10n.settingsThemeLight),
            ),
            ButtonSegment<AppThemePreference>(
              value: AppThemePreference.dark,
              label: Text(l10n.settingsThemeDark),
            ),
            ButtonSegment<AppThemePreference>(
              value: AppThemePreference.system,
              label: Text(l10n.settingsThemeSystem),
            ),
          ],
          selected: <AppThemePreference>{settings.theme},
          onSelectionChanged: (Set<AppThemePreference> selection) =>
              onChanged(settings.copyWith(theme: selection.single)),
        ),
        SwitchListTile(
          key: const ValueKey<String>('settings-dynamic-color'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.settingsDynamicColor),
          subtitle: Text(l10n.settingsDynamicColorHint),
          value: settings.dynamicColor,
          onChanged: (bool value) =>
              onChanged(settings.copyWith(dynamicColor: value)),
        ),
        const SizedBox(height: 8),
        Text(l10n.settingsMotionTitle),
        const SizedBox(height: 8),
        SegmentedButton<MotionPreference>(
          key: const ValueKey<String>('settings-motion'),
          segments: <ButtonSegment<MotionPreference>>[
            ButtonSegment<MotionPreference>(
              value: MotionPreference.expressive,
              label: Text(l10n.settingsMotionExpressive),
            ),
            ButtonSegment<MotionPreference>(
              value: MotionPreference.standard,
              label: Text(l10n.settingsMotionStandard),
            ),
          ],
          selected: <MotionPreference>{settings.motion},
          onSelectionChanged: (Set<MotionPreference> selection) =>
              onChanged(settings.copyWith(motion: selection.single)),
        ),
        SwitchListTile(
          key: const ValueKey<String>('settings-dyslexia-font'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.settingsDyslexiaFont),
          value: settings.dyslexiaFont,
          onChanged: (bool value) =>
              onChanged(settings.copyWith(dyslexiaFont: value)),
        ),
        _PercentSlider(
          key: const ValueKey<String>('settings-text-scale'),
          title: l10n.settingsTextScaleTitle,
          value: settings.textScale,
          min: AppSettings.minTextScale,
          max: AppSettings.maxTextScale,
          divisions: 12,
          label: l10n.settingsTextScaleValue(
            (settings.textScale * 100).round(),
          ),
          onChangedEnd: (double value) =>
              onChanged(settings.copyWith(textScale: value)),
        ),
      ],
    );
  }
}

class _LearningSection extends StatelessWidget {
  const _LearningSection({required this.settings, required this.onChanged});

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PercentSlider(
          key: const ValueKey<String>('settings-retention'),
          title: l10n.settingsRetentionTitle,
          value: settings.desiredRetention,
          min: AppSettings.minRetention,
          max: AppSettings.maxRetention,
          divisions: 25,
          label: l10n.settingsRetentionValue(
            (settings.desiredRetention * 100).round(),
          ),
          onChangedEnd: (double value) =>
              onChanged(settings.copyWith(desiredRetention: value)),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.settingsLearningStepsTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Duration step in settings.learningSteps)
              InputChip(
                key: ValueKey<String>('learning-step-${step.inMinutes}'),
                label: Text(l10n.settingsLearningStepValue(step.inMinutes)),
                onDeleted: settings.learningSteps.length <= 1
                    ? null
                    : () => onChanged(
                        settings.copyWith(
                          learningSteps: <Duration>[
                            for (final Duration existing
                                in settings.learningSteps)
                              if (existing != step) existing,
                          ],
                        ),
                      ),
                deleteButtonTooltipMessage:
                    l10n.settingsLearningStepDeleteTooltip,
              ),
            ActionChip(
              key: const ValueKey<String>('learning-step-add'),
              avatar: const Icon(Icons.add, size: 18),
              label: Text(l10n.settingsLearningStepAdd),
              onPressed: () => _addStep(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DailyLimitRow(
          key: const ValueKey<String>('settings-new-limit'),
          id: 'new-limit',
          title: l10n.settingsDailyNewLimitTitle,
          value: settings.dailyNewLimit,
          onChanged: (int value) =>
              onChanged(settings.copyWith(dailyNewLimit: value)),
        ),
        _DailyLimitRow(
          key: const ValueKey<String>('settings-review-limit'),
          id: 'review-limit',
          title: l10n.settingsDailyReviewLimitTitle,
          value: settings.dailyReviewLimit,
          onChanged: (int value) =>
              onChanged(settings.copyWith(dailyReviewLimit: value)),
        ),
        Text(
          l10n.settingsDailyLimitZeroHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _addStep(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (settings.learningSteps.length >= AppSettings.maxLearningSteps) {
      showAppMessage(context, l10n.settingsLearningStepLimit);
      return;
    }
    final int? minutes = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => const _LearningStepDialog(),
    );
    if (minutes == null) return;
    onChanged(
      settings.copyWith(
        learningSteps: <Duration>[
          ...settings.learningSteps,
          Duration(minutes: minutes),
        ],
      ),
    );
  }
}

class _DailyLimitRow extends StatelessWidget {
  const _DailyLimitRow({
    required this.id,
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String id;
  final String title;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(title)),
        IconButton(
          key: ValueKey<String>('settings-$id-minus'),
          icon: const Icon(Icons.remove),
          onPressed: value <= 0 ? null : () => onChanged(value - 1),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toString(),
            key: ValueKey<String>('settings-$id-value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: ValueKey<String>('settings-$id-plus'),
          icon: const Icon(Icons.add),
          onPressed: value >= AppSettings.maxDailyLimit
              ? null
              : () => onChanged(value + 1),
        ),
      ],
    );
  }
}

class _AccessibilitySection extends StatelessWidget {
  const _AccessibilitySection({
    required this.settings,
    required this.onChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        SwitchListTile(
          key: const ValueKey<String>('settings-haptics'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.settingsHapticsTitle),
          subtitle: Text(l10n.settingsHapticsHint),
          value: settings.haptics,
          onChanged: (bool value) =>
              onChanged(settings.copyWith(haptics: value)),
        ),
        SwitchListTile(
          key: const ValueKey<String>('settings-high-contrast'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.settingsHighContrast),
          value: settings.highContrast,
          onChanged: (bool value) =>
              onChanged(settings.copyWith(highContrast: value)),
        ),
      ],
    );
  }
}

/// Слайдер с подписью; сохраняет значение по окончании перетаскивания.
class _PercentSlider extends StatefulWidget {
  const _PercentSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChangedEnd,
    super.key,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChangedEnd;

  @override
  State<_PercentSlider> createState() => _PercentSliderState();
}

class _PercentSliderState extends State<_PercentSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(_PercentSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(widget.label),
          ],
        ),
        Slider(
          value: _value.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: widget.label,
          onChanged: (double value) => setState(() => _value = value),
          onChangeEnd: widget.onChangedEnd,
        ),
      ],
    );
  }
}

/// Блок «API»: сводка настроенных провайдеров и переход к их настройке.
///
/// В итерации 7.5 отдельные строки OpenAI/Gemini/Anthropic и «модель по
/// умолчанию» удалены: провайдеры и модели живут на экране `/settings/generation`
/// (ADR-020), а основного провайдера выбирает генерация.
class _ApiSection extends ConsumerWidget {
  const _ApiSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ProviderAccounts> accounts = ref.watch(
      providerAccountsProvider,
    );
    final AsyncValue<int> tokens = ref.watch(weeklyTokensProvider);
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.settingsApiProvidersTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        accounts.when(
          loading: () => const LinearProgressIndicator(),
          error: (Object error, StackTrace stackTrace) => Text(
            l10n.settingsLoadError,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          data: (ProviderAccounts value) {
            if (value.isEmpty) {
              return Text(
                l10n.providersEmptyTitle,
                key: const ValueKey<String>('settings-providers-empty'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }
            final ProviderAccount? active = value.active;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final ProviderAccount account in value.accounts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: <Widget>[
                        Icon(providerProtocolIcon(account.protocol), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            providerSummary(l10n, account),
                            key: ValueKey<String>(
                              'settings-provider-${account.id}',
                            ),
                          ),
                        ),
                        if (active?.id == account.id)
                          Text(
                            l10n.providersActive,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey<String>('settings-open-generation'),
            onPressed: () => context.push(AppRoutes.generationSettingsPath),
            icon: const Icon(Icons.key_outlined),
            label: Text(l10n.settingsApiOpenGeneration),
          ),
        ),
        const SizedBox(height: 12),
        tokens.when(
          loading: () => const SizedBox.shrink(),
          error: (Object error, StackTrace stackTrace) =>
              const SizedBox.shrink(),
          data: (int count) => Text(
            l10n.settingsApiTokensWeek(count),
            key: const ValueKey<String>('settings-weekly-tokens'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  Future<void> _openPrivacy(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool opened = await ref
        .read(externalLinkLauncherProvider)
        .open(privacyPolicyUri);
    if (!opened && context.mounted) {
      showAppMessage(context, l10n.settingsAboutLinkError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          key: const ValueKey<String>('settings-about-version'),
          title: Text(l10n.settingsAboutVersion(appVersion)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          key: const ValueKey<String>('settings-about-licenses'),
          title: Text(l10n.settingsAboutLicenses),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: l10n.appTitle,
            applicationVersion: appVersion,
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          key: const ValueKey<String>('settings-about-privacy'),
          title: Text(l10n.settingsAboutPrivacy),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _openPrivacy(context, ref),
        ),
      ],
    );
  }
}

class _LearningStepDialog extends StatefulWidget {
  const _LearningStepDialog();

  @override
  State<_LearningStepDialog> createState() => _LearningStepDialogState();
}

class _LearningStepDialogState extends State<_LearningStepDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int? minutes = int.tryParse(_controller.text.trim());
    if (minutes == null ||
        minutes < AppSettings.minLearningStepMinutes ||
        minutes > AppSettings.maxLearningStepMinutes) {
      setState(() => _error = l10n.settingsLearningStepInvalid);
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsLearningStepDialogTitle),
      content: TextField(
        key: const ValueKey<String>('learning-step-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: l10n.settingsLearningStepDialogLabel,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('learning-step-save'),
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _SettingsLoadError extends StatelessWidget {
  const _SettingsLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(l10n.settingsLoadError, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
