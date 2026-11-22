/// Экран «Настройки» (SPEC A6.6, ADR-019, ADR-038).
///
/// Двухколоночная раскладка макета: поднавигация по секциям и карточки
/// «Обучение и FSRS», «Внешний вид», «Доступность», «ИИ и модели»,
/// «О приложении». Каждый элемент меняет `AppSettings` и сохраняется через
/// `AppSettingsController` (ошибка записи — сообщение из ARB, состояние
/// откатывается). Ключи API сюда не попадают: только статус present/absent и
/// переход в настройки генерации (ADR-013). «Проверить» выполняет реальный
/// минимальный запрос через `ApiKeyVerifier` (ADR-019 §5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_layout.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/settings/about_links.dart';
import 'package:cardflow/ui/settings/provider_banner.dart';
import 'package:cardflow/ui/settings/provider_labels.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Экран настроек приложения.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Создаёт экран.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final GlobalKey _learningKey = GlobalKey();
  final GlobalKey _appearanceKey = GlobalKey();
  final GlobalKey _accessibilityKey = GlobalKey();
  final GlobalKey _aiKey = GlobalKey();
  final GlobalKey _aboutKey = GlobalKey();

  /// Активный раздел (находка D22): чипы и список показывают, где пользователь.
  GlobalKey? _activeSection;

  /// Разделы последнего построения — для подсветки при прокрутке.
  List<_SettingsNavItem>? _lastItems;

  /// Синхронизация активного раздела уже запланирована на конец кадра.
  bool _scrollSyncScheduled = false;

  Future<void> _update(AppSettings settings) async {
    try {
      await ref.read(appSettingsProvider.notifier).save(settings);
    } on Object {
      if (mounted) {
        showAppMessage(context, AppLocalizations.of(context).settingsSaveError);
      }
    }
  }

  void _scrollTo(GlobalKey key) {
    setState(() => _activeSection = key);
    final BuildContext? target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: AppDurations.slow,
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  /// Ближайший к верху области раздел — подсвечивается при прокрутке.
  void _syncActiveSectionFromScroll(
    List<_SettingsNavItem> items,
    ScrollNotification notification,
  ) {
    if (notification.depth != 0) return;
    GlobalKey? nearest;
    double nearestDistance = double.infinity;
    for (final _SettingsNavItem item in items) {
      final BuildContext? context = item.key.currentContext;
      if (context == null) continue;
      final RenderObject? box = context.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final double top = box.localToGlobal(Offset.zero).dy;
      final double distance = top < 0 ? -top + 200 : top;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = item.key;
      }
    }
    if (nearest != null && nearest != _activeSection) {
      setState(() => _activeSection = nearest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AppSettings> settings = ref.watch(appSettingsProvider);
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.depth != 0) return false;
          if (notification is! ScrollUpdateNotification &&
              notification is! ScrollEndNotification) {
            return false;
          }
          final List<_SettingsNavItem>? sections = _lastItems;
          if (sections == null || _scrollSyncScheduled) return false;
          // Читать позиции RenderBox нельзя во время layout — только после
          // кадра, иначе Flutter падает на sizeAccessAllowed.
          _scrollSyncScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollSyncScheduled = false;
            if (!mounted) return;
            _syncActiveSectionFromScroll(sections, notification);
          });
          return false;
        },
        child: AppPageScaffold(
          header: AppPageHeader(
            title: l10n.settingsScreenTitle,
            // Вторые «хлебные крошки» не дублируем: раздел уже показан в шапке
            // оболочки, здесь — только контекст страницы.
            overline: Text(l10n.settingsOverline.toUpperCase()),
            subtitle: Text(l10n.settingsSubtitle),
          ),
          slivers: <Widget>[
            settings.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.huge),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object error, StackTrace stackTrace) => AppErrorState(
                message: l10n.settingsLoadError,
                retryLabel: l10n.retry,
                onRetry: () => ref.invalidate(appSettingsProvider),
              ),
              data: (AppSettings value) => LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 1024;
                  final List<_SettingsNavItem> items = <_SettingsNavItem>[
                    _SettingsNavItem(
                      label: l10n.settingsNavLearning,
                      icon: Icons.psychology_outlined,
                      key: _learningKey,
                    ),
                    _SettingsNavItem(
                      label: l10n.settingsNavAppearance,
                      icon: Icons.palette_outlined,
                      key: _appearanceKey,
                    ),
                    _SettingsNavItem(
                      label: l10n.settingsNavAccessibility,
                      icon: Icons.accessibility_new,
                      key: _accessibilityKey,
                    ),
                    _SettingsNavItem(
                      label: l10n.settingsNavAi,
                      icon: Icons.auto_awesome_outlined,
                      key: _aiKey,
                    ),
                    _SettingsNavItem(
                      label: l10n.settingsNavAbout,
                      icon: Icons.info_outline,
                      key: _aboutKey,
                    ),
                  ];
                  final Widget nav = _SettingsSubNav(
                    items: items,
                    onSelect: _scrollTo,
                    horizontal: !wide,
                    activeKey: _activeSection,
                  );
                  _lastItems = items;
                  final Widget sections = _buildSections(
                    context,
                    l10n,
                    value,
                    items,
                  );
                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        nav,
                        const SizedBox(height: AppSpacing.md),
                        sections,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(width: 260, child: nav),
                      const SizedBox(width: AppSpacing.xxl),
                      Expanded(child: sections),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSections(
    BuildContext context,
    AppLocalizations l10n,
    AppSettings settings,
    List<_SettingsNavItem> items,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget learning = AppSectionCard(
      key: items[0].key,
      title: l10n.settingsFsrsTitle,
      subtitle: l10n.settingsLearningSubtitle,
      icon: Icons.tune,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PercentSlider(
            key: const ValueKey<String>('settings-retention'),
            title: l10n.settingsRetentionTitle,
            hint: l10n.settingsRetentionHint,
            value: settings.desiredRetention,
            min: AppSettings.minRetention,
            max: AppSettings.maxRetention,
            divisions: 25,
            label: l10n.settingsRetentionValue(
              (settings.desiredRetention * 100).round(),
            ),
            onChangedEnd: (double value) =>
                _update(settings.copyWith(desiredRetention: value)),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.settingsLearningStepsTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsLearningStepsHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final Duration step in settings.learningSteps)
                InputChip(
                  key: ValueKey<String>('learning-step-${step.inMinutes}'),
                  label: Text(l10n.settingsLearningStepValue(step.inMinutes)),
                  onDeleted: settings.learningSteps.length <= 1
                      ? null
                      : () => _update(
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
                onPressed: () => _addStep(settings),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.settingsDailyLimitsTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          _DailyLimitRow(
            key: const ValueKey<String>('settings-new-limit'),
            id: 'new-limit',
            title: l10n.settingsDailyNewLimitTitle,
            hint: l10n.settingsDailyNewLimitHint,
            value: settings.dailyNewLimit,
            onChanged: (int value) =>
                _update(settings.copyWith(dailyNewLimit: value)),
          ),
          _DailyLimitRow(
            key: const ValueKey<String>('settings-review-limit'),
            id: 'review-limit',
            title: l10n.settingsDailyReviewLimitTitle,
            hint: l10n.settingsDailyReviewLimitHint,
            value: settings.dailyReviewLimit,
            onChanged: (int value) =>
                _update(settings.copyWith(dailyReviewLimit: value)),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.settingsDailyLimitZeroHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final Widget appearance = AppSectionCard(
      key: items[1].key,
      title: l10n.settingsAppearanceTitle,
      subtitle: l10n.settingsAppearanceSubtitle,
      icon: Icons.palette_outlined,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.settingsThemeTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            l10n.settingsThemeHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // На узком экране сегменты не помещаются (перенос по слогам):
          // те же три выбора показываются чипами.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool narrow = constraints.maxWidth < 420;
              if (narrow) {
                return Wrap(
                  key: const ValueKey<String>('settings-theme'),
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    for (final AppThemePreference preference
                        in AppThemePreference.values)
                      ChoiceChip(
                        label: Text(switch (preference) {
                          AppThemePreference.light => l10n.settingsThemeLight,
                          AppThemePreference.dark => l10n.settingsThemeDark,
                          AppThemePreference.system => l10n.settingsThemeSystem,
                        }),
                        selected: settings.theme == preference,
                        onSelected: (_) =>
                            _update(settings.copyWith(theme: preference)),
                      ),
                  ],
                );
              }
              return SegmentedButton<AppThemePreference>(
                key: const ValueKey<String>('settings-theme'),
                segments: <ButtonSegment<AppThemePreference>>[
                  ButtonSegment<AppThemePreference>(
                    value: AppThemePreference.light,
                    label: Text(l10n.settingsThemeLight),
                    icon: const Icon(Icons.light_mode_outlined, size: 16),
                  ),
                  ButtonSegment<AppThemePreference>(
                    value: AppThemePreference.dark,
                    label: Text(l10n.settingsThemeDark),
                    icon: const Icon(Icons.dark_mode_outlined, size: 16),
                  ),
                  ButtonSegment<AppThemePreference>(
                    value: AppThemePreference.system,
                    label: Text(l10n.settingsThemeSystem),
                    icon: const Icon(Icons.brightness_auto_outlined, size: 16),
                  ),
                ],
                selected: <AppThemePreference>{settings.theme},
                onSelectionChanged: (Set<AppThemePreference> selection) =>
                    _update(settings.copyWith(theme: selection.single)),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          SwitchListTile(
            key: const ValueKey<String>('settings-dynamic-color'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsDynamicColor),
            subtitle: Text(l10n.settingsDynamicColorHint),
            value: settings.dynamicColor,
            onChanged: (bool value) =>
                _update(settings.copyWith(dynamicColor: value)),
          ),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.settingsMotionTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            l10n.settingsMotionHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool narrow = constraints.maxWidth < 420;
              if (narrow) {
                return Wrap(
                  key: const ValueKey<String>('settings-motion'),
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    for (final MotionPreference preference
                        in MotionPreference.values)
                      ChoiceChip(
                        label: Text(switch (preference) {
                          MotionPreference.expressive =>
                            l10n.settingsMotionExpressive,
                          MotionPreference.standard =>
                            l10n.settingsMotionStandard,
                        }),
                        selected: settings.motion == preference,
                        onSelected: (_) =>
                            _update(settings.copyWith(motion: preference)),
                      ),
                  ],
                );
              }
              return SegmentedButton<MotionPreference>(
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
                    _update(settings.copyWith(motion: selection.single)),
              );
            },
          ),
        ],
      ),
    );

    final Widget accessibility = AppSectionCard(
      key: items[2].key,
      title: l10n.settingsAccessibilityTitle,
      subtitle: l10n.settingsAccessibilitySubtitle,
      icon: Icons.accessibility_new,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            key: const ValueKey<String>('settings-dyslexia-font'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsDyslexiaFont),
            value: settings.dyslexiaFont,
            onChanged: (bool value) =>
                _update(settings.copyWith(dyslexiaFont: value)),
          ),
          SwitchListTile(
            key: const ValueKey<String>('settings-haptics'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsHapticsTitle),
            subtitle: Text(l10n.settingsHapticsHint),
            value: settings.haptics,
            onChanged: (bool value) =>
                _update(settings.copyWith(haptics: value)),
          ),
          SwitchListTile(
            key: const ValueKey<String>('settings-high-contrast'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsHighContrast),
            value: settings.highContrast,
            onChanged: (bool value) =>
                _update(settings.copyWith(highContrast: value)),
          ),
          const SizedBox(height: AppSpacing.xs),
          _PercentSlider(
            key: const ValueKey<String>('settings-text-scale'),
            title: l10n.settingsTextScaleTitle,
            hint: l10n.settingsTextScaleHint,
            value: settings.textScale,
            min: AppSettings.minTextScale,
            max: AppSettings.maxTextScale,
            divisions: 12,
            label: l10n.settingsTextScaleValue(
              (settings.textScale * 100).round(),
            ),
            onChangedEnd: (double value) =>
                _update(settings.copyWith(textScale: value)),
          ),
        ],
      ),
    );

    final Widget ai = AppSectionCard(
      key: items[3].key,
      title: l10n.settingsApiTitle,
      subtitle: l10n.settingsAiSubtitle,
      icon: Icons.auto_awesome_outlined,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: const _ApiSection(),
    );

    final Widget about = AppSectionCard(
      key: items[4].key,
      title: l10n.settingsAboutTitle,
      subtitle: l10n.settingsAboutSubtitle,
      icon: Icons.info_outline,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: const _AboutSection(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        learning,
        const SizedBox(height: AppSpacing.md),
        appearance,
        const SizedBox(height: AppSpacing.md),
        accessibility,
        const SizedBox(height: AppSpacing.md),
        ai,
        const SizedBox(height: AppSpacing.md),
        about,
      ],
    );
  }

  Future<void> _addStep(AppSettings settings) async {
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
    await _update(
      settings.copyWith(
        learningSteps: <Duration>[
          ...settings.learningSteps,
          Duration(minutes: minutes),
        ],
      ),
    );
  }
}

/// Пункт поднавигации настроек.
class _SettingsNavItem {
  const _SettingsNavItem({
    required this.label,
    required this.icon,
    required this.key,
  });

  final String label;
  final IconData icon;
  final GlobalKey key;
}

/// Поднавигация по секциям настроек: вертикальная колонка (ПК) или чипы
/// (узкий экран). Нажатие прокручивает страницу к секции — действие реальное.
class _SettingsSubNav extends StatelessWidget {
  const _SettingsSubNav({
    required this.items,
    required this.onSelect,
    required this.horizontal,
    this.activeKey,
  });

  final List<_SettingsNavItem> items;
  final ValueChanged<GlobalKey> onSelect;
  final bool horizontal;

  /// Активный раздел (находка D22).
  final GlobalKey? activeKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    bool selected(_SettingsNavItem item) => activeKey == item.key;
    final Widget content = horizontal
        ? Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final _SettingsNavItem item in items)
                ChoiceChip(
                  key: ValueKey<String>('settings-nav-${item.label}'),
                  avatar: Icon(
                    item.icon,
                    size: 16,
                    color: selected(item) ? scheme.onPrimary : scheme.primary,
                  ),
                  label: Text(item.label),
                  selected: selected(item),
                  onSelected: (_) => onSelect(item.key),
                ),
            ],
          )
        : Container(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final _SettingsNavItem item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: selected(item)
                          ? scheme.surfaceContainerHigh
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: InkWell(
                        key: ValueKey<String>('settings-nav-${item.label}'),
                        onTap: () => onSelect(item.key),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm - 2,
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                item.icon,
                                size: AppSizes.icon,
                                color: selected(item)
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: selected(item)
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: selected(item)
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
    return content;
  }
}

class _DailyLimitRow extends StatelessWidget {
  const _DailyLimitRow({
    required this.id,
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String id;
  final String title;
  final String hint;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.bodyLarge),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  key: ValueKey<String>('settings-$id-minus'),
                  icon: const Icon(Icons.remove, size: AppSizes.icon),
                  onPressed: value <= 0 ? null : () => onChanged(value - 1),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    value.toString(),
                    key: ValueKey<String>('settings-$id-value'),
                    textAlign: TextAlign.center,
                    style: AppTypography.numeric(context),
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('settings-$id-plus'),
                  icon: const Icon(Icons.add, size: AppSizes.icon),
                  onPressed: value >= AppSettings.maxDailyLimit
                      ? null
                      : () => onChanged(value + 1),
                ),
              ],
            ),
          ),
        ],
      ),
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
    this.hint,
    super.key,
  });

  final String title;
  final String? hint;
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(widget.title, style: theme.textTheme.titleSmall),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                widget.label,
                style: AppTypography.numeric(context, color: scheme.primary),
              ),
            ),
          ],
        ),
        if (widget.hint != null)
          Text(
            widget.hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
                  color: scheme.onSurfaceVariant,
                ),
              );
            }
            final ProviderAccount? active = value.active;
            // Находка F7: невалидный основной аккаунт — видимое предупреждение
            // с прямым переходом к исправлению, а не зелёный чип «Основной».
            final bool activeBroken = active != null && !active.isConfigured;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (activeBroken) ...<Widget>[
                  const PrimaryProviderBanner(),
                  const SizedBox(height: AppSpacing.xs),
                ],
                for (final ProviderAccount account in value.accounts)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs,
                    ),
                    child: Row(
                      children: <Widget>[
                        AppIconBadge(
                          icon: providerProtocolIcon(account.protocol),
                          color: scheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            providerSummary(l10n, account),
                            key: ValueKey<String>(
                              'settings-provider-${account.id}',
                            ),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (active?.id == account.id)
                          AppStatusChip(
                            label: l10n.providersActive,
                            tone: account.isConfigured
                                ? AppStatusTone.success
                                : AppStatusTone.danger,
                            dense: true,
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('settings-open-generation'),
            onPressed: () => context.push(AppRoutes.generationSettingsPath),
            icon: const Icon(Icons.key_outlined, size: 16),
            label: Text(l10n.settingsApiOpenGeneration),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        tokens.when(
          loading: () => const SizedBox.shrink(),
          error: (Object error, StackTrace stackTrace) =>
              const SizedBox.shrink(),
          data: (int count) => Text(
            l10n.settingsApiTokensWeek(count),
            key: const ValueKey<String>('settings-weekly-tokens'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
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
