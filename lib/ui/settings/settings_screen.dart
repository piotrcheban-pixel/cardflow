/// Экран «Настройки» (SPEC A6.6, ADR-019, ADR-038).
///
/// Поднавигация по секциям закреплена в `SliverPersistentHeader` (V30):
/// «Обучение и FSRS», «Внешний вид», «Доступность», «ИИ и модели»,
/// «О приложении» остаются на виду при прокрутке, активный раздел подсвечен.
/// Каждый элемент меняет `AppSettings` и сохраняется через
/// `AppSettingsController` (ошибка записи — сообщение из ARB, состояние
/// откатывается). Ключи API сюда не попадают: только статус present/absent и
/// переход в настройки генерации (ADR-013). «Проверить» выполняет реальный
/// минимальный запрос через `ApiKeyVerifier` (ADR-019 §5).
library;

import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
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

  /// Контроллер вертикальной прокрутки: нужен, чтобы прокрутка к разделу
  /// учитывала закреплённую панель вкладок (V30) и вела себя одинаково на
  /// любой платформе.
  final ScrollController _scrollController = ScrollController();

  /// Активный раздел (находка D22): вкладки и список показывают, где пользователь.
  GlobalKey? _activeSection;

  @override
  void initState() {
    super.initState();
    // Первый раздел активен по умолчанию — подсветка видна сразу.
    _activeSection = _learningKey;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Разделы последнего построения — для подсветки при прокрутке.
  List<_SettingsNavItem>? _lastItems;

  /// Синхронизация активного раздела уже запланирована на конец кадра.
  bool _scrollSyncScheduled = false;

  /// Подсветка «придержана» на выбранной вручную вкладке, пока страница стоит
  /// на месте: последний раздел не всегда может доехать до верха, и слежение
  /// без этого переключало бы подсветку на предыдущий раздел.
  bool _spySuppressed = false;

  /// Идёт программная анимация прокрутки к разделу.
  bool _spyAnimating = false;

  /// Позиция, на которой остановилась программная прокрутка.
  double _spyAnchor = 0;

  Future<void> _update(AppSettings settings) async {
    try {
      await ref.read(appSettingsProvider.notifier).save(settings);
    } on Object {
      if (mounted) {
        showAppMessage(context, AppLocalizations.of(context).settingsSaveError);
      }
    }
  }

  /// Высота закреплённой панели вкладок: 44 px контрол + поля 16 px.
  ///
  /// Считается тем же адаптивным множителем, что и высоты контролов темы
  /// (аудит v4, V38/V40), поэтому на 2K/4K подписи не обрезаются.
  static double _navBarHeight(BuildContext context) {
    final double control = AppAdaptive.factorForContext(context)
        .clamp(1.0, 1.3);
    final double width = MediaQuery.sizeOf(context).width;
    // Аудит v5 (V5-2): на узком окне ряд из пяти разделов не помещается —
    // вкладки переносятся (Wrap), панель выше на число рядов.
    final int rows = width < 480
        ? 3
        : width < 900
        ? 2
        : 1;
    return AppSizes.buttonHeight * control * rows +
        AppSpacing.xs * (rows - 1) +
        AppSpacing.md;
  }

  /// Горизонтальные поля страницы — те же, что у `AppPageScaffold`.
  static double _pageHorizontalPadding(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppSizes.sidebarBreakpoint
      ? AppSpacing.xl
      : AppSpacing.md;

  /// Сливер контента с шириной и полями страницы.
  static Widget _pageSliver(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return SliverToBoxAdapter(
      child: AppContentWidth(
        // F09: та же контентная колонка, что у остальных страниц (1280 на
        // FullHD, до 2600 на 4K).
        maxWidth: AppSizes.pageWidth(context),
        padding:
            padding ??
            EdgeInsets.fromLTRB(
              _pageHorizontalPadding(context),
              0,
              _pageHorizontalPadding(context),
              0,
            ),
        child: child,
      ),
    );
  }

  void _scrollTo(GlobalKey key) {
    setState(() => _activeSection = key);
    final BuildContext? target = key.currentContext;
    if (target == null) return;
    final RenderObject? renderObject = target.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final RenderAbstractViewport? viewport = RenderAbstractViewport.maybeOf(
      renderObject,
    );
    if (viewport == null || !_scrollController.hasClients) {
      Scrollable.ensureVisible(
        target,
        duration: AppDurations.slow,
        curve: Curves.easeOutCubic,
        alignment: 0,
      );
      return;
    }
    // `getOffsetToReveal` уже учитывает закреплённые сливеры (высота панели
    // вычитается им самим), поэтому здесь — только воздух между панелью и
    // заголовком раздела.
    final ScrollPosition position = _scrollController.position;
    final double reveal = viewport.getOffsetToReveal(renderObject, 0).offset;
    final double offset = (reveal - AppSpacing.xs)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    // Пока страница стоит на выбранном разделе, слежение не перебивает
    // подсветку: последний раздел может не доехать до верхней кромки.
    _spySuppressed = true;
    _spyAnchor = offset;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _spyAnimating = false;
      position.jumpTo(offset);
      return;
    }
    _spyAnimating = true;
    _scrollController
        .animateTo(
          offset,
          duration: AppDurations.slow,
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          _spyAnimating = false;
          // Анимацию прервали прокруткой — подсветка снова следует за ней.
          if ((_scrollController.offset - _spyAnchor).abs() > AppSpacing.xxs) {
            _spySuppressed = false;
          }
        });
  }

  /// Раздел у верхней кромки (под закреплённой панелью) — подсвечивается при
  /// прокрутке. Берётся ближайший сверху раздел, а не «самый близкий по
  /// расстоянию»: иначе на длинных секциях подсветка перескакивала бы.
  void _syncActiveSectionFromScroll(List<_SettingsNavItem> items) {
    if (items.isEmpty) return;
    // У нижней кромки активен последний раздел: до верха он может не доехать,
    // но пользователь видит именно его.
    if (_scrollController.hasClients) {
      final ScrollPosition position = _scrollController.position;
      if (position.hasPixels &&
          position.hasContentDimensions &&
          position.pixels >= position.maxScrollExtent - AppSpacing.xxs) {
        final GlobalKey last = items.last.key;
        if (last != _activeSection) {
          setState(() => _activeSection = last);
        }
        return;
      }
    }
    final double threshold = _navBarHeight(context) + AppSpacing.md;
    GlobalKey? nearest;
    double bestTop = double.negativeInfinity;
    for (final _SettingsNavItem item in items) {
      final BuildContext? context = item.key.currentContext;
      if (context == null) continue;
      final RenderObject? box = context.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final double top = box.localToGlobal(Offset.zero).dy;
      if (top <= threshold && top > bestTop) {
        bestTop = top;
        nearest = item.key;
      }
    }
    nearest ??= items.first.key;
    if (nearest != _activeSection) {
      setState(() => _activeSection = nearest);
    }
  }

  List<_SettingsNavItem> _navItems(AppLocalizations l10n) {
    return <_SettingsNavItem>[
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
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AppSettings> settings = ref.watch(appSettingsProvider);
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.depth != 0) return false;
          // Ручная прокрутка (перетаскивание, колесо) снимает «придержку»
          // подсветки: дальше активный раздел снова следует за страницей.
          if (notification is UserScrollNotification &&
              notification.direction != ScrollDirection.idle) {
            _spySuppressed = false;
          }
          if (_spySuppressed) {
            if (_spyAnimating) return false;
            // Пока страница стоит на выбранном разделе, подсветку не трогаем.
            if ((_scrollController.offset - _spyAnchor).abs() <=
                AppSpacing.xxs) {
              return false;
            }
            _spySuppressed = false;
          }
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
            if (!mounted || _spySuppressed) return;
            _syncActiveSectionFromScroll(sections);
          });
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: <Widget>[
            _pageSliver(
              context,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: AppPageHeader(
                title: l10n.settingsScreenTitle,
                // Вторые «хлебные крошки» не дублируем: раздел уже показан в
                // шапке оболочки, здесь — только контекст страницы.
                overline: Text(l10n.settingsOverline.toUpperCase()),
                subtitle: Text(l10n.settingsSubtitle),
              ),
            ),
            ...settings.when<List<Widget>>(
              loading: () => <Widget>[
                _pageSliver(
                  context,
                  padding: EdgeInsets.fromLTRB(
                    _pageHorizontalPadding(context),
                    AppSpacing.md,
                    _pageHorizontalPadding(context),
                    AppSpacing.md,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.huge),
                    child: _SettingsLoading(),
                  ),
                ),
              ],
              error: (Object error, StackTrace stackTrace) => <Widget>[
                _pageSliver(
                  context,
                  padding: EdgeInsets.fromLTRB(
                    _pageHorizontalPadding(context),
                    AppSpacing.md,
                    _pageHorizontalPadding(context),
                    AppSpacing.md,
                  ),
                  child: AppErrorState(
                    message: l10n.settingsLoadError,
                    retryLabel: l10n.retry,
                    onRetry: () => ref.invalidate(appSettingsProvider),
                  ),
                ),
              ],
              data: (AppSettings value) {
                final List<_SettingsNavItem> items = _navItems(l10n);
                _lastItems = items;
                return <Widget>[
                  // V30: панель вкладок закреплена при прокрутке и подсвечивает
                  // активный раздел; на узком экране прокручивается по
                  // горизонтали, не обрезая подписи.
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SettingsNavHeaderDelegate(
                      items: items,
                      activeKey: _activeSection,
                      onSelect: _scrollTo,
                      height: _navBarHeight(context),
                      horizontalPadding: _pageHorizontalPadding(context),
                    ),
                  ),
                  _pageSliver(
                    context,
                    padding: EdgeInsets.fromLTRB(
                      _pageHorizontalPadding(context),
                      AppSpacing.md,
                      _pageHorizontalPadding(context),
                      AppSpacing.xxl,
                    ),
                    child: _buildSections(context, l10n, value, items),
                  ),
                ];
              },
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
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.settingsLearningStepsHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Чипы шагов — одна высота и одни отступы (8 px), иконки по шкале
          // 16/20/24, зона касания не меньше 44 px (V38/V39).
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final Duration step in settings.learningSteps)
                InputChip(
                  key: ValueKey<String>('learning-step-${step.inMinutes}'),
                  label: Text(l10n.settingsLearningStepValue(step.inMinutes)),
                  deleteIcon: const Icon(Icons.close, size: AppSizes.iconSmall),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
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
                avatar: const Icon(Icons.add, size: AppSizes.iconSmall),
                materialTapTargetSize: MaterialTapTargetSize.padded,
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
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.settingsThemeHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // V31: сегменты — по содержимому (не шире 360 px) и по левому краю,
          // а не на всю ширину панели: иначе переключатель выглядит таблицей.
          // На узком экране те же выборы показываются чипами.
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
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SegmentedButton<AppThemePreference>(
                    key: const ValueKey<String>('settings-theme'),
                    showSelectedIcon: false,
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
                        _update(settings.copyWith(theme: selection.single)),
                  ),
                ),
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
          const SizedBox(height: AppSpacing.xxs),
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
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SegmentedButton<MotionPreference>(
                    key: const ValueKey<String>('settings-motion'),
                    showSelectedIcon: false,
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
                  ),
                ),
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

/// Закреплённая панель поднавигации настроек (находка V30).
///
/// Панель живёт в `SliverPersistentHeader(pinned: true)`: после клика по
/// вкладке и при любой прокрутке список разделов не уносит навигацию вверх,
/// поэтому активный раздел всегда виден и подсвечен.
class _SettingsNavHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SettingsNavHeaderDelegate({
    required this.items,
    required this.activeKey,
    required this.onSelect,
    required this.height,
    required this.horizontalPadding,
  });

  final List<_SettingsNavItem> items;
  final GlobalKey? activeKey;
  final ValueChanged<GlobalKey> onSelect;

  /// Высота панели вместе с полями контрола.
  final double height;

  /// Горизонтальные поля страницы (совпадают с полями секций).
  final double horizontalPadding;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // Непрозрачный фон обязателен: под закреплённой панелью прокручивается
    // контент. Полоса-разделитель отделяет её от секций.
    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant,
              width: AppSizes.borderWidth,
            ),
          ),
        ),
        child: SizedBox(
          height: height,
          child: AppContentWidth(
            maxWidth: AppSizes.contentMaxWidth,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _SettingsSubNav(
                items: items,
                activeKey: activeKey,
                onSelect: onSelect,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SettingsNavHeaderDelegate oldDelegate) =>
      oldDelegate.activeKey != activeKey ||
      oldDelegate.items != items ||
      oldDelegate.height != height ||
      oldDelegate.horizontalPadding != horizontalPadding;
}

/// Ряд вкладок поднавигации.
///
/// Выбранная вкладка залита `primary` (тема чипов) — активный раздел виден
/// всегда. На узком экране ряд прокручивается по горизонтали: подписи не
/// обрезаются и не ломаются по слогам (V30).
class _SettingsSubNav extends StatelessWidget {
  const _SettingsSubNav({
    required this.items,
    required this.onSelect,
    this.activeKey,
  });

  final List<_SettingsNavItem> items;
  final ValueChanged<GlobalKey> onSelect;

  /// Активный раздел (находка D22).
  final GlobalKey? activeKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    bool selected(_SettingsNavItem item) => activeKey == item.key;
    // Аудит v5 (V5-2): вместо горизонтальной прокрутки без индикатора —
    // перенос вкладок: все разделы (и выбранный) видны на любой ширине.
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final _SettingsNavItem item in items)
          ChoiceChip(
            key: ValueKey<String>('settings-nav-${item.label}'),
            avatar: Icon(
              item.icon,
              size: AppSizes.iconSmall,
              color: selected(item) ? scheme.onPrimary : scheme.primary,
            ),
            label: Text(item.label),
            selected: selected(item),
            // Аватар-иконка уже показывает раздел; галочка не нужна.
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => onSelect(item.key),
          ),
      ],
    );
  }
}

/// Строка дневного лимита: подпись с пояснением и степпер −/+.
///
/// Строка ограничена по ширине и выровнена по левому краю (V31): на 1280 px
/// иначе между текстом и степпером оставалась пустота в сотни пикселей.
/// Кнопки степпера — 44×44 (доступность), сам контрол — 48 px, как чипы шагов
/// и сегментированные переключатели.
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
    final double control = AppAdaptive.factorForContext(context)
        .clamp(1.0, 1.3);
    // F15: строка использует ширину секции — подпись слева, контрол у правого
    // края, а не 560 px в левом углу панели на 1280.
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
          const SizedBox(width: AppSpacing.sm),
          Container(
            height: (AppSizes.buttonHeightLarge * control).clamp(44.0, 60.0),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(
                color: AppColors.controlBorder(scheme),
                width: AppSizes.borderWidth,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  key: ValueKey<String>('settings-$id-minus'),
                  icon: const Icon(Icons.remove, size: AppSizes.icon),
                  style: _stepperStyle(isFirst: true, control: control),
                  onPressed: value <= 0 ? null : () => onChanged(value - 1),
                ),
                SizedBox(
                  // Три разряда («200 повторений в день») обязаны влезать
                  // без переноса — аудит v4: «20» и «0» разъезжались.
                  width: 52 * control,
                  child: Text(
                    value.toString(),
                    key: ValueKey<String>('settings-$id-value'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: AppTypography.numeric(context),
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('settings-$id-plus'),
                  icon: const Icon(Icons.add, size: AppSizes.icon),
                  style: _stepperStyle(isFirst: false, control: control),
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

  /// Стиль кнопок степпера: квадрат 44–57, без лишних полей — контрол не
  /// «толще» соседних и даёт зону касания по нижней границе доступности.
  ButtonStyle _stepperStyle({required bool isFirst, required double control}) {
    final Radius radius = Radius.circular(AppRadii.control);
    final double side = (AppSizes.minTouchTarget * control).clamp(44.0, 60.0);
    return IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size(side, side),
      maximumSize: Size(side, side),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: isFirst ? radius : Radius.zero,
          right: isFirst ? Radius.zero : radius,
        ),
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
                vertical: AppSpacing.xxs,
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
            icon: const Icon(Icons.key_outlined, size: AppSizes.iconSmall),
            label: Text(l10n.settingsApiOpenGeneration),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        tokens.when(
          loading: () => const SizedBox.shrink(),
          error: (Object error, StackTrace stackTrace) =>
              const SizedBox.shrink(),
          data: (int count) => Text(
            l10n.settingsApiTokensWeek(
              NumberFormat.decimalPattern('ru').format(count),
            ),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppDialog(
      title: l10n.settingsLearningStepDialogTitle,
      bodyBuilder: (BuildContext dialogContext) => TextField(
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
      actionsBuilder: (BuildContext dialogContext) => <Widget>[
        TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
          onPressed: () => Navigator.of(dialogContext).pop(),
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

/// Скелетон настроек: разделы-панели вместо голого спиннера (F22).
class _SettingsLoading extends StatelessWidget {
  const _SettingsLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AppSkeleton(width: 260, height: 34),
          const SizedBox(height: AppSpacing.md),
          for (int index = 0; index < 3; index++) ...<Widget>[
            AppPanel(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const AppSkeleton(width: 220, height: 22),
                  const SizedBox(height: AppSpacing.sm),
                  const AppSkeleton(height: 14),
                  const SizedBox(height: AppSpacing.sm),
                  const AppSkeleton(width: 320, height: 14),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}
