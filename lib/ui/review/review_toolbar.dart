import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_interval_format.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Подпись прогноза интервала для кнопки оценки (SPEC A7.2).
String reviewIntervalLabel(AppLocalizations l10n, Duration interval) {
  final ReviewIntervalText text = formatReviewInterval(interval);
  return switch (text.unit) {
    ReviewIntervalUnit.lessThanMinute => l10n.reviewIntervalLessThanMinute,
    ReviewIntervalUnit.minutes => l10n.reviewIntervalMinutes(text.count),
    ReviewIntervalUnit.hours => l10n.reviewIntervalHours(text.count),
    ReviewIntervalUnit.days => l10n.reviewIntervalDays(text.count),
  };
}

/// Панель оценок сессии (SPEC A7.2, ADR-038; аудит v7 — G1/G2/G6/G9).
///
/// Панель **существует только после раскрытия ответа** (G1): вызывающий экран
/// не строит её в состоянии «вопрос», поэтому здесь нет ни `disabled`-вида, ни
/// подсказки «оценки откроются…» — недоступное действие скрыто, а не серое (G5).
///
/// Оформление — один тон-ряд (F11): четыре спокойные тонировки одной светлоты,
/// общая нейтральная граница контрола (≥3:1), подписи интервалов — один
/// вторичный цвет, различие оценки — цветом подписи и цифры-клавиши.
///
/// Размеры из шкалы (G2/G6): кнопка не ниже [AppSizes.ratingButtonHeight] (56)
/// на любом размере окна, кегль подписи — [AppSizes.ratingLabelBase] (18) с
/// адаптивным множителем, зазор — не меньше 12 лог. px.
class ReviewToolbar extends StatelessWidget {
  /// Создаёт панель оценок.
  const ReviewToolbar({
    required this.preview,
    required this.onRating,
    this.enabled = true,
    this.compact = false,
    super.key,
  });

  /// Прогноз интервалов над кнопками; `null` — прогноза нет (тренировка).
  final Map<Rating, Duration>? preview;

  /// Доступны ли кнопки (в основном — не идёт запись в БД).
  final bool enabled;

  /// Компактный вид для низких окон (аудит v8, G10).
  ///
  /// На окне 844×390 физических px (562×260 лог.) панель в сетку 2×2
  /// переполняла карточку: две оценки уходили за нижнюю кромку. В компактном
  /// виде — один ряд из четырёх кнопок без подсказки клавиши.
  final bool compact;

  /// Обработчик оценки.
  final ValueChanged<Rating> onRating;

  /// Множитель контролов окна: 1,0 / 1,24 / 1,45 (клампится 1,0–1,2).
  static double controlScale(BuildContext context) =>
      AppAdaptive.factorForContext(context)
          .clamp(1.0, AppSizes.ratingButtonMaxScale);

  @override
  Widget build(BuildContext context) {
    final Map<Rating, Duration>? previews = preview;
    final double scale = controlScale(context);
    final double gap = math.max(AppSpacing.sm, AppSpacing.md * scale);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // На узком экране четыре кнопки в ряд нечитаемы — сетка 2×2. Но в
        // низком окне два ряда не помещаются в карточку (G10) — тогда один ряд.
        final int columns = compact || width >= 640 ? 4 : 2;
        final double buttonWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Rating rating in Rating.values)
              SizedBox(
                width: buttonWidth,
                child: _RatingButton(
                  rating: rating,
                  interval: previews?[rating],
                  enabled: enabled,
                  scale: scale,
                  compact: compact,
                  onPressed: () => onRating(rating),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Роль оценки для цветов темы (тема не знает доменный `Rating`).
RatingRole _roleOf(Rating rating) => switch (rating) {
  Rating.again => RatingRole.again,
  Rating.hard => RatingRole.hard,
  Rating.good => RatingRole.good,
  Rating.easy => RatingRole.easy,
};

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.rating,
    required this.interval,
    required this.enabled,
    required this.scale,
    required this.onPressed,
    this.compact = false,
  });

  final Rating rating;
  final Duration? interval;
  final bool enabled;
  final double scale;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final RatingRole role = _roleOf(rating);
    final String label = switch (rating) {
      Rating.again => l10n.ratingAgain,
      Rating.hard => l10n.ratingHard,
      Rating.good => l10n.ratingGood,
      Rating.easy => l10n.ratingEasy,
    };
    final Color background = AppColors.ratingSurface(scheme, role);
    final Color foreground = AppColors.ratingForeground(scheme, role);
    final Duration? intervalValue = interval;
    // Подсказка клавиши — обозначение клавиатуры, а не пользовательский текст.
    final String keyHint = '${rating.index + 1}';
    // Три корзины движения: отклик на hover/pressed — 120–160 мс.
    final double fontSize = AppSizes.ratingLabelBase * scale;
    final double height = compact
        ? AppSizes.ratingButtonHeight
        : (60 * scale).clamp(AppSizes.ratingButtonHeight, 68.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Прогноз интервала виден на всех размерах окна (G2, V7-18) и во всех
        // режимах; подпись — один вторичный цвет (F11). В совсем низком окне
        // (compact) строка прогноза скрыта: иначе панель не помещается в
        // карточку, а прогноз остаётся в подсказке кнопки.
        SizedBox(
          height: compact ? 0 : 22 * scale,
          child: intervalValue == null || compact
              ? null
              : Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      reviewIntervalLabel(l10n, intervalValue),
                      key: ValueKey<String>('review-interval-${rating.name}'),
                      maxLines: 1,
                      style: AppTypography.caption(
                        context,
                        color: AppColors.intervalForeground(scheme),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        FilledButton(
          key: ValueKey<String>('review-rating-${rating.name}'),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith<Color>((
              Set<WidgetState> states,
            ) {
              if (states.contains(WidgetState.pressed)) {
                return Color.alphaBlend(
                  foreground.withValues(alpha: 0.12),
                  background,
                );
              }
              if (states.contains(WidgetState.hovered)) {
                return Color.alphaBlend(
                  foreground.withValues(alpha: 0.06),
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
              EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // G2: кегль подписи не ниже 16 даже при пользовательском
                // масштабе текста 90 % (18 × 0,9 = 16,2 на FullHD).
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: fontSize,
                  color: foreground,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // Подсказка клавиши занимает место — в компактном окне её нет.
              if (!compact) ...<Widget>[
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                  ),
                  child: Text(
                    keyHint,
                    style: AppTypography.caption(
                      context,
                      color: foreground.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
