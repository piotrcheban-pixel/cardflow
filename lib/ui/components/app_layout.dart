import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Каркас страницы: шапка с заголовком и действиями + прокручиваемый контент
/// одной колонкой с максимальной шириной макета (1280 px).
///
/// Все основные экраны (колоды, колода, статистика, настройки, генерация,
/// конструктор) собираются из этих виджетов, поэтому отступы, ширина контента
/// и ритм вертикальных интервалов совпадают.
class AppPageScaffold extends StatelessWidget {
  /// Создаёт каркас страницы.
  const AppPageScaffold({
    required this.header,
    required this.slivers,
    this.maxWidth = AppSizes.contentMaxWidth,
    this.bottomPadding = AppSpacing.xxl,
    super.key,
  });

  /// Шапка страницы (обычно [AppPageHeader]).
  final Widget header;

  /// Прокручиваемое содержимое страницы.
  final List<Widget> slivers;

  /// Максимальная ширина контента.
  final double maxWidth;

  /// Нижний отступ списка.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: AppContentWidth(
            maxWidth: maxWidth,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: header,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            _horizontalPadding(context),
            AppSpacing.xs,
            _horizontalPadding(context),
            bottomPadding,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              for (final Widget sliver in slivers)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: sliver,
                ),
            ]),
          ),
        ),
      ],
    );
  }

  static double _horizontalPadding(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppSizes.sidebarBreakpoint
      ? AppSpacing.xl
      : AppSpacing.md;
}

/// Центрирует контент и ограничивает его ширину макета.
class AppContentWidth extends StatelessWidget {
  /// Создаёт ограничитель ширины.
  const AppContentWidth({
    required this.child,
    this.maxWidth = AppSizes.contentMaxWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    super.key,
  });

  /// Содержимое.
  final Widget child;

  /// Максимальная ширина.
  final double maxWidth;

  /// Внутренние отступы.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Шапка страницы: надзаголовок (breadcrumb/категория), название, пояснение и
/// действия. На узком экране действия переносятся под текст и прижимаются
/// к левому краю, чтобы не появлялось горизонтального скролла.
class AppPageHeader extends StatelessWidget {
  /// Создаёт шапку.
  const AppPageHeader({
    required this.title,
    this.breadcrumb,
    this.overline,
    this.subtitle,
    this.actions = const <Widget>[],
    this.titleTrailing,
    super.key,
  });

  /// Заголовок страницы (`display-mobile` 28/34 на телефоне, 32 px на ПК).
  final String title;

  /// Надзаголовок-«хлебные крошки» (например, «Рабочее пространство / Колоды»).
  final String? breadcrumb;

  /// Акцентный надзаголовок (иконка + текст в primary).
  final Widget? overline;

  /// Пояснение под заголовком.
  final Widget? subtitle;

  /// Кнопки/меню справа от заголовка.
  final List<Widget> actions;

  /// Элемент рядом с заголовком (например, чип версии).
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool wide =
        MediaQuery.sizeOf(context).width >= AppSizes.gridBreakpointTablet;
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (breadcrumb != null || overline != null) ...<Widget>[
          DefaultTextStyle.merge(
            style: AppTypography.overline(context),
            child: breadcrumb != null
                ? Text(breadcrumb!)
                : overline ?? const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontSize: wide ? 32 : 28,
                  height: wide ? 1.2 : 1.21,
                ),
              ),
            ),
            if (titleTrailing != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              titleTrailing!,
            ],
          ],
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            child: subtitle!,
          ),
        ],
      ],
    );

    if (actions.isEmpty) return titleBlock;
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          titleBlock,
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: actions,
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: titleBlock),
        const SizedBox(width: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.end,
          children: actions,
        ),
      ],
    );
  }
}
