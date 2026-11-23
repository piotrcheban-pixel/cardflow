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
/// Размеры из шкалы, а не из компактного режима (G2/G6): кнопка не ниже
/// [AppSizes.ratingButtonHeight] (56) на любом размере окна, кегль подписи —
/// [AppSizes.ratingLabelBase] (18) с адаптивным множителем, зазор — не меньше
/// 12 лог. px (раньше в компактном режиме было 8).
///
/// Цвета ролей — дизайн-система: Again — errorContainer, Hard —
/// surfaceContainer, Good — secondaryContainer, Easy — primaryFixed.
class ReviewToolbar extends StatelessWidget {
  /// Создаёт панель оценок.
  const ReviewToolbar({
    required this.preview,
    required this.onRating,
    this.enabled = true,
    super.key,
  });

  /// Прогноз интервалов над кнопками; `null` — прогноза нет (тренировка).
  final Map<Rating, Duration>? preview;

  /// Доступны ли кнопки (в основном — не идёт запись в БД).
  final bool enabled;

  /// Обработчик оценки.
  final ValueChanged<Rating> onRating;

  /// Множитель контролов окна: 1,0 / 1,24 / 1,45 (клампится 1,0–1,2).
  static double controlScale(BuildContext context) =>
      AppAdaptive.factorForContext(context).clamp(1.0, AppSizes.ratingButtonMaxScale);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<Rating, Duration>? previews = preview;
    final double scale = controlScale(context);
    final double gap = math.max(AppSpacing.sm, AppSpacing.sm * scale);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // На узком экране четыре кнопки в ряд нечитаемы — сетка 2×2.
        final int columns = width < 640 ? 2 : 4;
        final double buttonWidth =
            (width - gap * (columns - 1)) / columns;
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
                  onPressed: () => onRating(rating),
                  textTheme: theme,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.rating,
    required this.interval,
    required this.enabled,
    required this.scale,
    required this.onPressed,
    required this.textTheme,
  });

  final Rating rating;
  final Duration? interval;
  final bool enabled;
  final double scale;
  final VoidCallback onPressed;
  final ThemeData textTheme;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = textTheme;
    final ColorScheme scheme = theme.colorScheme;
    final String label = switch (rating) {
      Rating.again => l10n.ratingAgain,
      Rating.hard => l10n.ratingHard,
      Rating.good => l10n.ratingGood,
      Rating.easy => l10n.ratingEasy,
    };
    final (Color background, Color foreground) = switch (rating) {
      Rating.again => (
        AppColors.ratingAgainBackground(scheme),
        AppColors.ratingAgainForeground(scheme),
      ),
      Rating.hard => (
        AppColors.ratingHardBackground(scheme),
        AppColors.ratingHardForeground(scheme),
      ),
      Rating.good => (
        AppColors.ratingGoodBackground(scheme),
        AppColors.ratingGoodForeground(scheme),
      ),
      Rating.easy => (
        AppColors.ratingEasyBackground(scheme),
        AppColors.ratingEasyForeground(scheme),
      ),
    };
    final Color intervalColor = switch (rating) {
      Rating.again => scheme.tertiary,
      Rating.hard => scheme.onSurfaceVariant,
      Rating.good => scheme.secondary,
      Rating.easy => scheme.primary,
    };
    final Duration? intervalValue = interval;
    // Подсказка клавиши: не пользовательский текст, а обозначение клавиши.
    final String keyHint = '[${rating.index + 1}]';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Прогноз интервала виден на всех размерах окна (G2, V7-18): раньше в
        // компактном режиме он исчезал — ключевая функция FSRS пропадала.
        SizedBox(
          height: 20 * scale,
          child: intervalValue == null
              ? null
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    reviewIntervalLabel(l10n, intervalValue),
                    key: ValueKey<String>('review-interval-${rating.name}'),
                    maxLines: 1,
                    style: AppTypography.caption(context, color: intervalColor),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        FilledButton(
          key: ValueKey<String>('review-rating-${rating.name}'),
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            minimumSize: Size(0, AppSizes.ratingButtonHeight * scale),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
            ),
            side: BorderSide(color: foreground.withValues(alpha: 0.18)),
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
                  fontSize: AppSizes.ratingLabelBase * scale,
                  color: foreground,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                keyHint,
                style: AppTypography.caption(
                  context,
                  color: foreground.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
