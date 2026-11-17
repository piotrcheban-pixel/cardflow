/// Экран «Настройки» (SPEC A6.6, ADR-019; REDESIGN-SPEC §9.16).
///
/// Блоки: внешний вид, обучение, доступность, API и «О приложении». Каждый
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
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/settings/about_links.dart';
import 'package:cardflow/ui/settings/provider_labels.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Экран настроек приложения.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Создаёт экран.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _update(AppSettings settings) async {
    try {
      await ref.read(appSettingsProvider.notifier).save(settings);
    } on Object {
      if (mounted) {
        showAppMessage(context, AppLocalizations.of(context).settingsSaveError);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AppSettings> settings = ref.watch(appSettingsProvider);
    return NcGlassGroup(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NcTopBar(
                title: l10n.settingsScreenTitle,
                largeTitle: l10n.settingsScreenTitle,
                scrollController: _scrollController,
              ),
              Expanded(
                child: settings.when(
                  loading: () => const _SettingsSkeleton(),
                  error: (Object error, StackTrace stackTrace) => NcErrorState(
                    message: l10n.settingsLoadError,
                    retryLabel: l10n.retry,
                    onRetry: () => ref.invalidate(appSettingsProvider),
                  ),
                  data: (AppSettings value) => ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: <Widget>[
                      NcSection(
                        title: l10n.settingsAppearanceTitle,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: _AppearanceSection(
                              settings: value,
                              onChanged: _update,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      NcSection(
                        title: l10n.settingsLearningTitle,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: _LearningSection(
                              settings: value,
                              onChanged: _update,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      NcSection(
                        title: l10n.settingsAccessibilityTitle,
                        children: <Widget>[
                          _AccessibilitySection(
                            settings: value,
                            onChanged: _update,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ApiSection(),
                      const SizedBox(height: 16),
                      _AboutSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Внешний вид: тема, dynamic color, движение, дислексия и размер текста.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.settings, required this.onChanged});

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _BlockTitle(l10n.settingsThemeTitle),
        const SizedBox(height: 8),
        NcSegmented<AppThemePreference>(
          key: const ValueKey<String>('settings-theme'),
          value: settings.theme,
          onChanged: (AppThemePreference value) =>
              onChanged(settings.copyWith(theme: value)),
          segments: <NcSegment<AppThemePreference>>[
            NcSegment<AppThemePreference>(
              value: AppThemePreference.light,
              label: l10n.settingsThemeLight,
              leading: const _ThemeDot(dark: false),
            ),
            NcSegment<AppThemePreference>(
              value: AppThemePreference.dark,
              label: l10n.settingsThemeDark,
              leading: const _ThemeDot(dark: true),
            ),
            NcSegment<AppThemePreference>(
              value: AppThemePreference.system,
              label: l10n.settingsThemeSystem,
            ),
          ],
        ),
        const SizedBox(height: 8),
        NcListRow(
          key: const ValueKey<String>('settings-dynamic-color'),
          title: Text(l10n.settingsDynamicColor),
          subtitle: Text(l10n.settingsDynamicColorHint),
          onTap: () => onChanged(
            settings.copyWith(dynamicColor: !settings.dynamicColor),
          ),
          trailing: NcSwitch(
            value: settings.dynamicColor,
            onChanged: (bool value) =>
                onChanged(settings.copyWith(dynamicColor: value)),
            semanticLabel: l10n.settingsDynamicColor,
          ),
        ),
        const SizedBox(height: 8),
        _BlockTitle(l10n.settingsMotionTitle),
        const SizedBox(height: 8),
        NcSegmented<MotionPreference>(
          key: const ValueKey<String>('settings-motion'),
          value: settings.motion,
          onChanged: (MotionPreference value) =>
              onChanged(settings.copyWith(motion: value)),
          segments: <NcSegment<MotionPreference>>[
            NcSegment<MotionPreference>(
              value: MotionPreference.expressive,
              label: l10n.settingsMotionExpressive,
            ),
            NcSegment<MotionPreference>(
              value: MotionPreference.standard,
              label: l10n.settingsMotionStandard,
            ),
          ],
        ),
        NcListRow(
          key: const ValueKey<String>('settings-dyslexia-font'),
          title: Text(l10n.settingsDyslexiaFont),
          onTap: () => onChanged(
            settings.copyWith(dyslexiaFont: !settings.dyslexiaFont),
          ),
          trailing: NcSwitch(
            value: settings.dyslexiaFont,
            onChanged: (bool value) =>
                onChanged(settings.copyWith(dyslexiaFont: value)),
            semanticLabel: l10n.settingsDyslexiaFont,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          key: const ValueKey<String>('settings-text-scale'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _BlockTitle(l10n.settingsTextScaleTitle)),
                Text(
                  l10n.settingsTextScaleValue(
                    (settings.textScale * 100).round(),
                  ),
                  style: theme.typography.monoM.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
            NcSlider(
              value: settings.textScale.clamp(
                AppSettings.minTextScale,
                AppSettings.maxTextScale,
              ),
              min: AppSettings.minTextScale,
              max: AppSettings.maxTextScale,
              divisions: 12,
              valueLabel: (double value) =>
                  l10n.settingsTextScaleValue((value * 100).round()),
              onChanged: (double value) =>
                  onChanged(settings.copyWith(textScale: value)),
            ),
            Text(
              l10n.settingsTextScalePreview,
              style: theme.typography.bodyL.copyWith(
                color: theme.colors.textPrimary,
                fontSize: 16 * settings.textScale,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Точка-превью темы в сегменте (§9.16).
class _ThemeDot extends StatelessWidget {
  const _ThemeDot({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final NcColors colors = NcTheme.of(context).colors;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: dark ? colors.ink0 : colors.ink5,
        shape: BoxShape.circle,
        border: Border.all(color: colors.aurum, width: 1.5),
      ),
    );
  }
}

/// Обучение: удержание, шаги, дневные лимиты.
class _LearningSection extends StatelessWidget {
  const _LearningSection({required this.settings, required this.onChanged});

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Column(
          key: const ValueKey<String>('settings-retention'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _BlockTitle(l10n.settingsRetentionTitle)),
                Text(
                  l10n.settingsRetentionValue(
                    (settings.desiredRetention * 100).round(),
                  ),
                  style: theme.typography.monoL.copyWith(
                    color: theme.colors.aurum,
                  ),
                ),
              ],
            ),
            NcSlider(
              value: settings.desiredRetention,
              min: AppSettings.minRetention,
              max: AppSettings.maxRetention,
              divisions: 25,
              valueLabel: (double value) =>
                  l10n.settingsRetentionValue((value * 100).round()),
              onChanged: (double value) =>
                  onChanged(settings.copyWith(desiredRetention: value)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _BlockTitle(l10n.settingsLearningStepsTitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Duration step in settings.learningSteps)
              NcChip(
                key: ValueKey<String>('learning-step-${step.inMinutes}'),
                label: l10n.settingsLearningStepValue(step.inMinutes),
                variant: NcChipVariant.tag,
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
                deleteTooltip: l10n.settingsLearningStepDeleteTooltip,
              ),
            NcButton(
              key: const ValueKey<String>('learning-step-add'),
              label: l10n.settingsLearningStepAdd,
              variant: NcButtonVariant.ghost,
              size: NcButtonSize.s,
              icon: Icons.add_rounded,
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
        const SizedBox(height: 4),
        _DailyLimitRow(
          key: const ValueKey<String>('settings-review-limit'),
          id: 'review-limit',
          title: l10n.settingsDailyReviewLimitTitle,
          value: settings.dailyReviewLimit,
          onChanged: (int value) =>
              onChanged(settings.copyWith(dailyReviewLimit: value)),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.settingsDailyLimitZeroHint,
          style: theme.typography.bodyS.copyWith(
            color: theme.colors.textSecondary,
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
    final int? minutes = await _showLearningStepDialog(context);
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

/// Строка дневного лимита со степпером (ключи `settings-<id>-*`).
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
    final NcTheme theme = NcTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: theme.typography.bodyM.copyWith(
                color: theme.colors.textPrimary,
              ),
            ),
          ),
          NcStepper(
            value: value,
            minusKey: ValueKey<String>('settings-$id-minus'),
            valueKey: ValueKey<String>('settings-$id-value'),
            plusKey: ValueKey<String>('settings-$id-plus'),
            minValue: 0,
            maxValue: AppSettings.maxDailyLimit,
            onDecrement: () => onChanged(value - 1),
            onIncrement: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

/// Доступность: тактильный отклик и повышенный контраст.
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
        NcListRow(
          key: const ValueKey<String>('settings-haptics'),
          title: Text(l10n.settingsHapticsTitle),
          subtitle: Text(l10n.settingsHapticsHint),
          onTap: () => onChanged(settings.copyWith(haptics: !settings.haptics)),
          trailing: NcSwitch(
            value: settings.haptics,
            onChanged: (bool value) =>
                onChanged(settings.copyWith(haptics: value)),
            semanticLabel: l10n.settingsHapticsTitle,
          ),
        ),
        NcListRow(
          key: const ValueKey<String>('settings-high-contrast'),
          title: Text(l10n.settingsHighContrast),
          showDivider: false,
          onTap: () => onChanged(
            settings.copyWith(highContrast: !settings.highContrast),
          ),
          trailing: NcSwitch(
            value: settings.highContrast,
            onChanged: (bool value) =>
                onChanged(settings.copyWith(highContrast: value)),
            semanticLabel: l10n.settingsHighContrast,
          ),
        ),
      ],
    );
  }
}

/// Блок «API»: сводка настроенных провайдеров и переход к их настройке.
///
/// В итерации 7.5 отдельные строки OpenAI/Gemini/Anthropic и «модель по
/// умолчанию» удалены: провайдеры и модели живут на экране
/// `/settings/generation` (ADR-020), а основного провайдера выбирает генерация.
class _ApiSection extends ConsumerWidget {
  const _ApiSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final AsyncValue<ProviderAccounts> accounts = ref.watch(
      providerAccountsProvider,
    );
    final AsyncValue<int> tokens = ref.watch(weeklyTokensProvider);
    return NcSection(
      title: l10n.settingsApiTitle,
      children: <Widget>[
        accounts.when(
          loading: () => NcListRow(
            title: Text(l10n.settingsApiProvidersTitle),
            trailing: const NcSpinner(),
          ),
          error: (Object error, StackTrace stackTrace) => NcListRow(
            title: Text(l10n.settingsLoadError),
            showDivider: false,
          ),
          data: (ProviderAccounts value) {
            if (value.isEmpty) {
              return NcListRow(
                title: Text(
                  l10n.providersEmptyTitle,
                  key: const ValueKey<String>('settings-providers-empty'),
                ),
                showDivider: false,
              );
            }
            final ProviderAccount? active = value.active;
            return Column(
              children: <Widget>[
                for (final ProviderAccount account in value.accounts)
                  NcListRow(
                    leading: Icon(providerProtocolIcon(account.protocol)),
                    title: Text(
                      providerSummary(l10n, account),
                      key: ValueKey<String>('settings-provider-${account.id}'),
                    ),
                    trailing: active?.id == account.id
                        ? NcBadge(
                            label: l10n.providersActive,
                            tone: NcBadgeTone.jade,
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
        NcListRow(
          key: const ValueKey<String>('settings-open-generation'),
          leading: const Icon(Icons.key_outlined),
          title: Text(l10n.settingsApiOpenGeneration),
          trailing: Icon(Icons.chevron_right, color: theme.colors.textTertiary),
          onTap: () => context.push(AppRoutes.generationSettingsPath),
        ),
        tokens.when(
          loading: () => const SizedBox.shrink(),
          error: (Object error, StackTrace stackTrace) =>
              const SizedBox.shrink(),
          data: (int count) => NcListRow(
            title: Text(
              l10n.settingsApiTokensWeek(count),
              key: const ValueKey<String>('settings-weekly-tokens'),
            ),
            showDivider: false,
          ),
        ),
      ],
    );
  }
}

/// «О приложении»: версия, лицензии и политика приватности.
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
    final NcTheme theme = NcTheme.of(context);
    return NcSection(
      title: l10n.settingsAboutTitle,
      children: <Widget>[
        NcListRow(
          key: const ValueKey<String>('settings-about-version'),
          title: Text(l10n.settingsAboutVersion(appVersion)),
        ),
        NcListRow(
          key: const ValueKey<String>('settings-about-licenses'),
          title: Text(l10n.settingsAboutLicenses),
          trailing: Icon(Icons.chevron_right, color: theme.colors.textTertiary),
          onTap: () => showLicensePage(
            context: context,
            applicationName: l10n.appTitle,
            applicationVersion: appVersion,
          ),
        ),
        NcListRow(
          key: const ValueKey<String>('settings-about-privacy'),
          title: Text(l10n.settingsAboutPrivacy),
          showDivider: false,
          trailing: Icon(
            Icons.open_in_new,
            size: 18,
            color: theme.colors.textTertiary,
          ),
          onTap: () => _openPrivacy(context, ref),
        ),
      ],
    );
  }
}

/// Заголовок поля внутри секции.
class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Text(
      title,
      style: theme.typography.bodyM.copyWith(color: theme.colors.textSecondary),
    );
  }
}

/// Диалог шага обучения; `null` — отмена.
Future<int?> _showLearningStepDialog(BuildContext context) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final GlobalKey<_LearningStepFieldState> fieldKey =
      GlobalKey<_LearningStepFieldState>();

  void submit() {
    final int? minutes = fieldKey.currentState?.trySubmit();
    if (minutes == null) return;
    Navigator.of(context).pop(minutes);
  }

  return showNcDialog<int>(
    context,
    title: l10n.settingsLearningStepDialogTitle,
    content: _LearningStepField(key: fieldKey),
    actions: <Widget>[
      NcButton(
        label: l10n.cancel,
        variant: NcButtonVariant.ghost,
        onPressed: () => Navigator.of(context).pop(),
      ),
      NcButton(
        key: const ValueKey<String>('learning-step-save'),
        label: l10n.save,
        onPressed: submit,
      ),
    ],
  );
}

/// Поле шага обучения с валидацией диапазона.
class _LearningStepField extends StatefulWidget {
  const _LearningStepField({super.key});

  @override
  State<_LearningStepField> createState() => _LearningStepFieldState();
}

class _LearningStepFieldState extends State<_LearningStepField> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Возвращает минуты или `null` при невалидном значении.
  int? trySubmit() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int? minutes = int.tryParse(_controller.text.trim());
    if (minutes == null ||
        minutes < AppSettings.minLearningStepMinutes ||
        minutes > AppSettings.maxLearningStepMinutes) {
      setState(() => _error = l10n.settingsLearningStepInvalid);
      return null;
    }
    return minutes;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NcTextField(
      key: const ValueKey<String>('learning-step-input'),
      controller: _controller,
      autofocus: true,
      label: l10n.settingsLearningStepDialogLabel,
      errorText: _error,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      onSubmitted: (String value) {
        final int? minutes = trySubmit();
        if (minutes != null) Navigator.of(context).pop(minutes);
      },
    );
  }
}

/// Загрузка настроек: skeleton-секции.
class _SettingsSkeleton extends StatelessWidget {
  const _SettingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const <Widget>[
        NcSkeleton(height: 72, radius: NcRadii.l),
        SizedBox(height: 12),
        NcSkeleton(height: 220, radius: NcRadii.l),
        SizedBox(height: 12),
        NcSkeleton(height: 160, radius: NcRadii.l),
      ],
    );
  }
}
