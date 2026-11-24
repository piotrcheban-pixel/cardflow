import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Панель оценок классической сессии (SPEC A7.2, ADR-045).
///
/// Что изменилось в дизайн-системе v3:
///
/// * на кнопках только название действия — без номеров клавиш, без прогноза
///   интервалов и без технических обозначений FSRS (требование владельца);
/// * прогноз интервалов продолжает считаться движком (`ReviewSessionState.
///   preview`) и учитывается FSRS, но интерфейс его не показывает: решение
///   принимается по знанию, а не по числу на кнопке;
/// * цифры `1`–`4` остаются рабочими горячими клавишами (см.
///   `session_keyboard.dart`), но внутри кнопок не печатаются;
/// * четыре кнопки имеют общую геометрию и одну иерархию действия:
///   «Знаю» — единственная залитая, остальные — тонированные/нейтральные.
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
  ///
  /// В низком окне четыре кнопки в строку не читаются — используется один
  /// ряд с уменьшенной высотой; в остальных случаях — ряд на широкой карточке
  /// или сетка 2×2 на узкой.
  final bool compact;

  /// Обработчик оценки.
  final ValueChanged<Rating> onRating;

  /// Кегль подписи: 18 базовых, не уже 16 при масштабе текста 90 %.
  static const double labelSize = AppSizes.ratingLabelBase;

  @override
  Widget build(BuildContext context) {
    final double scale = AppSizes.controlScale(context);
    final double gap = compact
        ? AppSpacing.xs
        : math.max(AppSpacing.sm, AppSpacing.md * scale);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // На узком экране четыре кнопки в ряд нечитаемы — сетка 2×2. В низком
        // окне второй ряд не помещается — остаётся один ряд (G10).
        final int columns = compact || width >= 560 ? 4 : 2;
        final double buttonWidth = (width - gap * (columns - 1)) / columns;
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
/// hover/pressed/focused/disabled.
class RatingButton extends StatelessWidget {
  /// Создаёт кнопку.
  const RatingButton({
    required this.rating,
    required this.enabled,
    required this.onPressed,
    this.compact = false,
    this.scale = 1,
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
    final double height = compact
        ? AppSizes.ratingButtonCompactHeight
        : (62 * scale).clamp(AppSizes.ratingButtonHeight, 70.0);
    final double fontSize = ReviewToolbar.labelSize * scale;
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: fontSize,
              color: labelColor,
              height: 1.15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
