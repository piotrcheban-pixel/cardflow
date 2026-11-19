import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Белая панель дизайн-системы (ADR-038): скругление 16, тонкая граница
/// `outlineVariant`, деликатная тень в светлой теме и без тени в тёмной.
class AppPanel extends StatelessWidget {
  /// Создаёт панель.
  const AppPanel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadii.card,
    this.color,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.borderColor,
    super.key,
  });

  /// Содержимое.
  final Widget child;

  /// Внутренние отступы.
  final EdgeInsetsGeometry padding;

  /// Скругление.
  final double radius;

  /// Цвет поверхности; по умолчанию `surfaceContainerLowest`.
  final Color? color;

  /// Обработчик нажатия (панель становится интерактивной).
  final VoidCallback? onTap;

  /// Обработчик долгого нажатия (контекстное меню).
  final VoidCallback? onLongPress;

  /// Семантическая подпись для озвучивания.
  final String? semanticLabel;

  /// Цвет границы; по умолчанию `outlineVariant`.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget surface = AnimatedContainer(
      duration: AppDurations.quick,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? scheme.outlineVariant,
          width: AppSizes.borderWidth,
        ),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null && onLongPress == null) {
      return semanticLabel == null
          ? surface
          : Semantics(label: semanticLabel, container: true, child: surface);
    }
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(radius),
          child: surface,
        ),
      ),
    );
  }
}

/// Панель-секция с заголовком: иконка, заголовок, пояснение и хвостовой
/// элемент, затем разделитель и содержимое.
class AppSectionCard extends StatelessWidget {
  /// Создаёт секцию.
  const AppSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.trailing,
    this.headerTrailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.contentPadding = EdgeInsets.zero,
    this.accentColor,
    super.key,
  });

  /// Заголовок секции.
  final String title;

  /// Пояснение под заголовком.
  final String? subtitle;

  /// Иконка слева от заголовка.
  final IconData? icon;

  /// Элемент справа от заголовка (например, чип статуса).
  final Widget? trailing;

  /// Элемент справа от блока заголовка (в строке с иконкой).
  final Widget? headerTrailing;

  /// Отступы всей панели.
  final EdgeInsetsGeometry padding;

  /// Отступы содержимого под разделителем.
  final EdgeInsetsGeometry contentPadding;

  /// Акцентный цвет иконки/заголовка.
  final Color? accentColor;

  /// Содержимое секции.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color accent = accentColor ?? scheme.primary;
    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: AppSizes.navIcon, color: accent),
                  const SizedBox(width: AppSpacing.xs + 2),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          if (headerTrailing != null) ...<Widget>[
                            const SizedBox(width: AppSpacing.xs),
                            headerTrailing!,
                          ],
                        ],
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  trailing!,
                ],
              ],
            ),
          ),
          Divider(height: AppSizes.borderWidth, color: scheme.outlineVariant),
          Padding(padding: contentPadding, child: child),
        ],
      ),
    );
  }
}

/// Плитка показателя (KPI): надзаголовок, крупное значение, единица/пометка и
/// необязательная иконка-бейдж справа.
class AppStatTile extends StatelessWidget {
  /// Создаёт плитку.
  const AppStatTile({
    required this.label,
    required this.value,
    this.unit,
    this.helper,
    this.helperColor,
    this.icon,
    this.iconColor,
    this.trailing,
    super.key,
  });

  /// Подпись (upper case, 11 px).
  final String label;

  /// Значение (крупная цифра).
  final String value;

  /// Единица измерения рядом со значением.
  final String? unit;

  /// Мелкое пояснение под значением.
  final Widget? helper;

  /// Цвет пояснения.
  final Color? helperColor;

  /// Иконка-бейдж в правом верхнем углу.
  final IconData? icon;

  /// Цвет иконки-бейджа.
  final Color? iconColor;

  /// Дополнительный элемент в строке значения.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.overline(context),
                ),
              ),
              if (icon != null)
                AppIconBadge(icon: icon!, color: iconColor ?? scheme.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs + 2),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpacing.xs,
            runSpacing: 2,
            children: <Widget>[
              Text(
                value,
                style: AppTypography.kpi(context).copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (unit != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: trailing!,
                ),
            ],
          ),
          if (helper != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall?.copyWith(
                color: helperColor ?? scheme.onSurfaceVariant,
              ),
              child: helper!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Тона статусных чипов.
enum AppStatusTone {
  /// Нейтральный (синий контейнер).
  neutral,

  /// Информационный (primary).
  info,

  /// Успех (зелёный).
  success,

  /// Предупреждение (тертиарный).
  warning,

  /// Ошибка/просрочка.
  danger,
}

/// Компактный статусный чип (pill): «64 к повторению», «Все повторено» и т.п.
class AppStatusChip extends StatelessWidget {
  /// Создаёт чип.
  const AppStatusChip({
    required this.label,
    this.tone = AppStatusTone.neutral,
    this.icon,
    this.dense = false,
    super.key,
  });

  /// Текст чипа.
  final String label;

  /// Тон.
  final AppStatusTone tone;

  /// Иконка перед текстом.
  final IconData? icon;

  /// Компактная версия (11 px, меньше отступы).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final (Color background, Color foreground) = switch (tone) {
      AppStatusTone.neutral => (scheme.surfaceContainer, scheme.primary),
      AppStatusTone.info => (scheme.primaryFixed, scheme.onPrimaryFixed),
      AppStatusTone.success => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      AppStatusTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      AppStatusTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.xs : AppSpacing.xs + 2,
        vertical: dense ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 12 : 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground,
                fontSize: dense ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Квадратный бейдж с иконкой (фон — тонированная поверхность).
class AppIconBadge extends StatelessWidget {
  /// Создаёт бейдж.
  const AppIconBadge({
    required this.icon,
    required this.color,
    this.size = 32,
    this.background,
    super.key,
  });

  /// Иконка.
  final IconData icon;

  /// Цвет иконки.
  final Color color;

  /// Сторона квадрата.
  final double size;

  /// Фон; по умолчанию — тот же цвет с малой прозрачностью.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 3.2),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

/// Полоса прогресса дизайн-системы: 6 px, скруглённая, с плавным изменением.
class AppProgressBar extends StatelessWidget {
  /// Создаёт полосу.
  const AppProgressBar({
    required this.value,
    this.color,
    this.trackColor,
    this.height = AppSizes.progressHeight,
    this.semanticsLabel,
    super.key,
  });

  /// Доля 0..1.
  final double value;

  /// Цвет заполнения; по умолчанию `primary`.
  final Color? color;

  /// Цвет фона.
  final Color? trackColor;

  /// Толщина.
  final double height;

  /// Семантическая подпись.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ColoredBox(color: trackColor ?? scheme.surfaceContainer),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
              duration: AppDurations.slow,
              curve: Curves.easeOutCubic,
              builder: (BuildContext context, double animated, Widget? child) =>
                  FractionallySizedBox(
                    widthFactor: animated,
                    child: ColoredBox(
                      color: color ?? scheme.primary,
                      child: const SizedBox.expand(),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
    return semanticsLabel == null
        ? bar
        : Semantics(label: semanticsLabel, child: bar);
  }
}

/// Состояние «пусто»: иконка, заголовок, пояснение и действия.
class AppEmptyState extends StatelessWidget {
  /// Создаёт пустое состояние.
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const <Widget>[],
    this.compact = false,
    super.key,
  });

  /// Иконка.
  final IconData icon;

  /// Заголовок.
  final String title;

  /// Пояснение.
  final String message;

  /// Кнопки под сообщением.
  final List<Widget> actions;

  /// Компактный вариант (меньше отступы).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return AppPanel(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppIconBadge(
            icon: icon,
            color: scheme.primary,
            size: compact ? 40 : 48,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xxs + 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Состояние ошибки: иконка, сообщение из ARB и кнопка повтора.
class AppErrorState extends StatelessWidget {
  /// Создаёт состояние ошибки.
  const AppErrorState({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
    super.key,
  });

  /// Сообщение (строка ARB).
  final String message;

  /// Повторить операцию.
  final VoidCallback onRetry;

  /// Подпись кнопки повтора.
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppIconBadge(
            icon: Icons.error_outline,
            color: scheme.error,
            size: 48,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}

/// Скелетон загрузки: статичные тонированные блоки (без бесконечной анимации,
/// чтобы не нагружать кадры и не ломать `pumpAndSettle` в тестах).
class AppSkeleton extends StatelessWidget {
  /// Создаёт блок-заглушку.
  const AppSkeleton({
    this.height = 16,
    this.width,
    this.radius = AppRadii.sm,
    super.key,
  });

  /// Высота.
  final double height;

  /// Ширина; `null` — на всю доступную.
  final double? width;

  /// Скругление.
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Набор скелетонов списка/сетки, показываемый во время загрузки.
class AppLoadingPlaceholder extends StatelessWidget {
  /// Создаёт заглушку.
  const AppLoadingPlaceholder({this.rows = 4, super.key});

  /// Сколько строк нарисовать.
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int index = 0; index < rows; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppPanel(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const AppSkeleton(width: 160),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSkeleton(width: 96, height: 12),
                  const SizedBox(height: AppSpacing.sm),
                  const AppSkeleton(height: 8),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
