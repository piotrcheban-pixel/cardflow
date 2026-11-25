import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Высота компактной кнопки оценки на телефоне (TASK 04, M-01).
///
/// 48 px — основная кнопка мобильной системы; цель нажатия при этом не
/// меньше 44 px (`AppSizes.minTouchTarget`).
const double kRatingButtonMobileHeight = 48;

/// Ширина, до которой панель оценок — сетка 2×2 (телефон/узкая карточка).
const double kRatingPanelSingleRowWidth = 520;

/// Панель оценок классической сессии (SPEC A7.2, ADR-045, TASK 04).
///
/// Что изменилось в TASK 04:
///
/// * на телефоне — компактная сетка 2×2 высотой 48, а не четыре огромные
///   кнопки 62 px, которые отнимали у карточки 22 % экрана и обрезали
///   «Затрудняюсь» (измерено на 360/320 px);
/// * подпись кнопки никогда не обрезается многоточием: при нехватке ширины
///   `FittedBox` равномерно уменьшает текст (нижний предел читаемости задан
///   пользовательским масштабом, а не `ellipsis`); текст центрируется строго
///   по горизонтали и вертикали;
/// * кнопки имеют общую геометрию и одну иерархию действия: «Знаю» —
///   единственная залитая primary, «Легко» — спокойная тонировка secondary,
///   «Затрудняюсь» — нейтральная поверхность, «Не знаю» — тихая тонировка
///   error;
/// * никаких номеров клавиш, интервалов и технических обозначений FSRS:
///   прогноз продолжает считаться движком, но не печатается.
///
/// Панель существует только после раскрытия ответа (G1): вызывающий экран не
/// строит её в состоянии «вопрос».
class ReviewToolbar extends StatelessWidget {
  /// Создаёт панель оценок.
  const ReviewToolbar({
    required this.onRating,
    this.enabled = true,
    this.compact = false,
    super.key,
  });

  /// Доступны ли кнопки (в основном — не идёт запись в БД).
  final bool enabled;

  /// Компактный вид для низких окон (аудит v8, G10).
  final bool compact;

  /// Обработчик оценки.
  final ValueChanged<Rating> onRating;

  /// Кегль подписи на узкой сетке (телефон).
  static const double labelSize = 16;

  /// Кегль подписи на широкой карточке.
  static const double labelSizeWide = 18;

  @override
  Widget build(BuildContext context) {
    final double scale = AppSizes.controlScale(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final bool narrow = width < kRatingPanelSingleRowWidth;
        final int columns = compact || !narrow ? 4 : 2;
        // На телефоне сетка 2×2: меньше промежуток, чтобы кнопке досталось
        // максимум ширины под подпись.
        final double gap = compact
            ? AppSpacing.xs
            : narrow
            ? AppSpacing.xs
            : math.max(AppSpacing.sm, AppSpacing.md * scale);
        final double buttonWidth = (width - gap * (columns - 1)) / columns;
        final double height = compact || narrow
            ? kRatingButtonMobileHeight
            : (56 * scale).clamp(AppSizes.ratingButtonHeight, 68.0);
        final double fontSize = narrow || compact ? labelSize : labelSizeWide;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Rating rating in Rating.values)
              SizedBox(
                width: buttonWidth,
                child: RatingButton(
                  rating: rating,
                  enabled: enabled,
                  compact: compact,
                  scale: scale,
                  height: height,
                  fontSize: fontSize,
                  onPressed: () => onRating(rating),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Кнопка одной оценки: только название действия и состояния взаимодействия.
///
/// Общий компонент для всех режимов, где оценка влияет на расписание
/// (классика, тренировка, конструктор): одна геометрия, одни состояния
/// hover/pressed/focused/disabled, текст строго по центру.
class RatingButton extends StatelessWidget {
  /// Создаёт кнопку.
  const RatingButton({
    required this.rating,
    required this.enabled,
    required this.onPressed,
    this.compact = false,
    this.scale = 1,
    this.height = kRatingButtonMobileHeight,
    this.fontSize = ReviewToolbar.labelSize,
    super.key,
  });

  /// Оценка, которую ставит кнопка.
  final Rating rating;

  /// Доступна ли кнопка.
  final bool enabled;

  /// Обработчик нажатия.
  final VoidCallback onPressed;

  /// Низкое окно: уменьшенная высота.
  final bool compact;

  /// Адаптивный множитель контролов (1,0–1,2).
  final double scale;

  /// Высота кнопки.
  final double height;

  /// Кегль подписи до пользовательского масштаба.
  final double fontSize;

  /// Роль цвета для темы (тема не знает доменный `Rating`).
  static RatingRole roleOf(Rating rating) => switch (rating) {
    Rating.again => RatingRole.again,
    Rating.hard => RatingRole.hard,
    Rating.good => RatingRole.good,
    Rating.easy => RatingRole.easy,
  };

  /// Название действия для оценки (ARB).
  static String labelOf(AppLocalizations l10n, Rating rating) =>
      switch (rating) {
        Rating.again => l10n.ratingAgain,
        Rating.hard => l10n.ratingHard,
        Rating.good => l10n.ratingGood,
        Rating.easy => l10n.ratingEasy,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final RatingRole role = roleOf(rating);
    final String label = labelOf(l10n, rating);
    final Color background = AppColors.ratingSurface(scheme, role);
    final Color foreground = AppColors.ratingForeground(scheme, role);
    final Color labelColor = enabled
        ? foreground
        : scheme.onSurfaceVariant.withValues(alpha: 0.7);
    return SizedBox(
      height: height,
      child: FilledButton(
        key: ValueKey<String>('review-rating-${rating.name}'),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return Color.alphaBlend(
                scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                scheme.surfaceContainerLowest,
              );
            }
            if (states.contains(WidgetState.pressed)) {
              return Color.alphaBlend(
                foreground.withValues(alpha: 0.16),
                background,
              );
            }
            if (states.contains(WidgetState.hovered)) {
              return Color.alphaBlend(
                foreground.withValues(alpha: 0.08),
                background,
              );
            }
            return background;
          }),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          minimumSize: WidgetStatePropertyAll<Size>(Size(0, height)),
          maximumSize: WidgetStatePropertyAll<Size>(Size.infinite),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          ),
          elevation: const WidgetStatePropertyAll<double>(0),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
            ),
          ),
          side: WidgetStateProperty.resolveWith<BorderSide>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: scheme.onSurface, width: 2);
            }
            if (states.contains(WidgetState.hovered)) {
              return BorderSide(color: foreground, width: 1.5);
            }
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: scheme.outlineVariant);
            }
            // У залитой «Знаю» граница тоньше и того же тона — кнопка не
            // получает вторую рамку поверх собственной заливки.
            if (rating == Rating.good) {
              return BorderSide(
                color: scheme.primary,
                width: AppSizes.borderWidth,
              );
            }
            return BorderSide(
              color: AppColors.controlBorder(scheme),
              width: AppSizes.borderWidth,
            );
          }),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.pressed)) {
              return foreground.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered)) {
              return foreground.withValues(alpha: 0.05);
            }
            return null;
          }),
        ),
        onPressed: enabled ? onPressed : null,
        child: Center(
          // FittedBox вместо ellipsis: подпись либо помещается целиком, либо
          // равномерно уменьшается. Обрезка названия действия запрещена (M-01).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              key: ValueKey<String>('review-rating-label-${rating.name}'),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: fontSize * scale,
                color: labelColor,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
