import 'dart:ui' show PathMetric;

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
    final BorderRadius shape = BorderRadius.circular(radius);
    final Widget content = Padding(padding: padding, child: child);
    // Material, а не только DecoratedBox: внутри панели живут ListTile/Switch,
    // которым для фона и splash нужен Material-предок.
    final Widget surface = Material(
      color: color ?? scheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: shape,
        side: BorderSide(
          color: borderColor ?? scheme.outlineVariant,
          width: AppSizes.borderWidth,
        ),
      ),
      child: onTap == null && onLongPress == null
          ? content
          : _InteractiveSurface(
              onTap: onTap,
              onLongPress: onLongPress,
              radius: radius,
              child: content,
            ),
    );
    final Widget decorated = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: surface,
    );
    if (semanticLabel == null) return decorated;
    return Semantics(
      label: semanticLabel,
      container: true,
      button: onTap != null || onLongPress != null,
      child: decorated,
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
                  maxLines: 3,
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
    // F16/V6: чип-статус растёт вместе с типографикой (12→17 на 4K).
    final double control = AppAdaptive.factorForContext(context)
        .clamp(1.0, 1.45);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (dense ? AppSpacing.xs : AppSpacing.xs + 2) * control,
        vertical: (dense ? 1 : 3) * control,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: (dense ? 12 : 14) * control, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                // Аудит v5 (V5-13): кегль не ниже минимального 13.
                color: foreground,
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

/// Полоса прогресса дизайн-системы: 6 px, скруглённая, цвет из темы.
///
/// Внутри — стандартный `LinearProgressIndicator`: widget-тесты и скринридеры
/// продолжают видеть знакомый тип, а форма/цвет задаются токенами.
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
    return LinearProgressIndicator(
      value: value.clamp(0, 1),
      minHeight: height,
      borderRadius: BorderRadius.circular(height / 2),
      color: color ?? scheme.primary,
      backgroundColor: trackColor ?? scheme.surfaceContainer,
      semanticsLabel: semanticsLabel,
    );
  }
}

/// Состояние «пусто»: иконка, заголовок, пояснение и действия.
///
/// [hero] — полноэкранный вариант для состояний сессии (F07): крупная иконка,
/// заголовок 30–38, метрика/пояснение, одно основное действие и широкие поля.
/// Панель занимает ширину карточки сессии, поэтому «завершено» и «пусто» —
/// полноценный экран-итог, а не миниатюра в центре пустого окна.
class AppEmptyState extends StatelessWidget {
  /// Создаёт пустое состояние.
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const <Widget>[],
    this.metric,
    this.compact = false,
    this.hero = false,
    super.key,
  });

  /// Иконка.
  final IconData icon;

  /// Заголовок.
  final String title;

  /// Пояснение.
  final String message;

  /// Крупная метрика над заголовком (например, «12 оценено»).
  final Widget? metric;

  /// Кнопки под сообщением.
  final List<Widget> actions;

  /// Компактный вариант (меньше отступы).
  final bool compact;

  /// Полноэкранный вариант состояния сессии.
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final EdgeInsets padding = hero
        ? const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxxl,
            vertical: AppSpacing.xxl + AppSpacing.xs,
          )
        : EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl);
    return AppPanel(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: hero
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (metric != null) ...<Widget>[
            DefaultTextStyle.merge(
              style: AppTypography.kpiLarge(context)
                  .copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
              child: metric!,
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppIconBadge(
            icon: icon,
            color: scheme.primary,
            size: hero ? 72 : (compact ? 44 : 48),
          ),
          SizedBox(height: hero ? AppSpacing.lg : AppSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: hero
                ? theme.textTheme.displaySmall?.copyWith(height: 1.2)
                : theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: hero ? 560 : 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style:
                  (hero
                          ? theme.textTheme.bodyLarge
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (actions.isNotEmpty) ...<Widget>[
            SizedBox(height: hero ? AppSpacing.xl : AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
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
    this.hero = false,
    super.key,
  });

  /// Сообщение (строка ARB).
  final String message;

  /// Повторить операцию.
  final VoidCallback onRetry;

  /// Подпись кнопки повтора.
  final String retryLabel;

  /// Полноэкранный вариант состояния сессии.
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return AppPanel(
      padding: EdgeInsets.symmetric(
        horizontal: hero ? AppSpacing.xxxl : AppSpacing.xxl,
        vertical: hero ? AppSpacing.xxxl : AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AppIconBadge(
            icon: Icons.error_outline,
            color: scheme.error,
            size: hero ? 72 : 48,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: (hero
                ? theme.textTheme.titleLarge
                : theme.textTheme.titleMedium),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}

/// Скелетон загрузки: тихий блок геометрии контента вместо голого спиннера.
///
/// F22: загрузка показывала только `CircularProgressIndicator` в пустом поле,
/// после чего контент «прыгал». Скелетон сразу задаёт геометрию будущего
/// контента (карточка/строки/плитки), поэтому layout не смещается. Появление —
/// короткий fade (не повторяющаяся анимация: widget-тесты с `pumpAndSettle`
/// остаются стабильными, reduced motion не нарушается).
class AppSkeleton extends StatelessWidget {
  /// Создаёт блок скелетона.
  const AppSkeleton({
    this.width = double.infinity,
    this.height = 16,
    this.radius = AppRadii.sm,
    this.opacity = 1,
    super.key,
  });

  /// Ширина блока.
  final double width;

  /// Высота блока.
  final double height;

  /// Скругление.
  final double radius;

  /// Множитель непрозрачности (иерархия скелетона).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.7 * opacity),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Скелетон карточки сессии: та же геометрия, что у `ReviewCardView`.
class AppCardSkeleton extends StatelessWidget {
  /// Создаёт скелетон карточки.
  const AppCardSkeleton({required this.width, this.height, super.key});

  /// Ширина карточки.
  final double width;

  /// Высота; `null` — 62 % рабочей области.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final double cardHeight = height ?? AppSizes.studyCardMinHeightFor(context);
    final bool compact = cardHeight < 300;
    return Container(
      width: width,
      height: cardHeight,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: AppShadows.card(Theme.of(context).brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSkeleton(width: compact ? 64 : 88, height: compact ? 10 : 14),
          SizedBox(height: compact ? 6 : AppSpacing.xl),
          AppSkeleton(width: double.infinity, height: compact ? 16 : 28),
          SizedBox(height: compact ? 6 : AppSpacing.xs),
          AppSkeleton(width: compact ? 220 : 320, height: compact ? 16 : 28),
          if (!compact) ...<Widget>[
            const Spacer(),
            AppSkeleton(
              width: AppSizes.revealButtonMaxWidth,
              height: AppSizes.revealButtonHeight,
              radius: AppRadii.input,
            ),
          ],
        ],
      ),
    );
  }
}

/// Пунктирная рамка поверхностей (зона загрузки файлов в макете).
///
/// Собственный `CustomPainter` вместо новой зависимости: рисует скруглённый
/// прямоугольник штрихами по длине пути.
class AppDashedBorder extends StatelessWidget {
  /// Создаёт рамку.
  const AppDashedBorder({
    required this.child,
    this.color,
    this.radius = AppRadii.input,
    this.strokeWidth = 2,
    this.dashLength = 6,
    this.gapLength = 5,
    super.key,
  });

  /// Содержимое внутри рамки.
  final Widget child;

  /// Цвет штриха; по умолчанию `outlineVariant`.
  final Color? color;

  /// Радиус скругления.
  final double radius;

  /// Толщина.
  final double strokeWidth;

  /// Длина штриха.
  final double dashLength;

  /// Длина промежутка.
  final double gapLength;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      // Пунктир поверх содержимого: у зоны загрузки есть фон, painter рисует
      // под ним и был бы невидим.
      foregroundPainter: _DashedBorderPainter(
        color: color ?? Theme.of(context).colorScheme.outlineVariant,
        radius: radius,
        strokeWidth: strokeWidth,
        dashLength: dashLength,
        gapLength: gapLength,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            strokeWidth / 2,
            strokeWidth / 2,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = (distance + dashLength).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.gapLength != gapLength;
}

/// Интерактивная поверхность панели с видимым клавиатурным фокусом.
///
/// Находка A3 аудита: `InkWell` без `focusColor` не показывал, где находится
/// клавиатурный фокус. Здесь фокус рисуется кольцом 2 px поверх панели
/// (вёрстка не сдвигается: кольцо живёт в `Stack` и не занимает места).
class _InteractiveSurface extends StatefulWidget {
  const _InteractiveSurface({
    required this.child,
    required this.radius,
    required this.onTap,
    required this.onLongPress,
  });

  final Widget child;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_InteractiveSurface> createState() => _InteractiveSurfaceState();
}

class _InteractiveSurfaceState extends State<_InteractiveSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius shape = BorderRadius.circular(widget.radius);
    return Stack(
      children: <Widget>[
        InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: shape,
          onFocusChange: (bool value) {
            if (_focused == value) return;
            setState(() => _focused = value);
          },
          child: widget.child,
        ),
        if (_focused)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey<String>('app-focus-ring'),
                decoration: BoxDecoration(
                  borderRadius: shape,
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
