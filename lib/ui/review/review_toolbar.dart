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

/// Панель оценок всех режимов сессии (SPEC A7.2, ADR-038).
///
/// Четыре кнопки в порядке [Rating.values]: над каждой — прогноз интервала,
/// посчитанный планировщиком для текущей карточки. Цвета ролей взяты из
/// дизайн-системы: Again — errorContainer, Hard — surfaceContainer,
/// Good — secondaryContainer, Easy — primaryFixed (как в макете Gemini).
class ReviewToolbar extends StatelessWidget {
  /// Создаёт панель оценок.
  const ReviewToolbar({
    required this.preview,
    required this.enabled,
    required this.onRating,
    this.hint,
    super.key,
  });

  /// Прогноз интервалов над кнопками; `null` — прогноза нет.
  final Map<Rating, Duration>? preview;

  /// Доступны ли кнопки (ответ раскрыт и не идёт запись в БД).
  final bool enabled;

  /// Обработчик оценки.
  final ValueChanged<Rating> onRating;

  /// Пояснение над панелью, когда оценки ещё недоступны (F1: до раскрытия
  /// ответа оценка не ставится).
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? hintText = enabled ? null : hint;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.studyCardMaxWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (hintText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      hintText,
                      key: const ValueKey<String>('review-rating-hint'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final int columns = constraints.maxWidth < 520 ? 2 : 4;
                    final double gap = AppSpacing.sm;
                    final double width =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: <Widget>[
                        for (final Rating rating in Rating.values)
                          SizedBox(
                            width: width,
                            child: _RatingButton(
                              rating: rating,
                              interval: preview?[rating],
                              enabled: enabled,
                              onPressed: () => onRating(rating),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.rating,
    required this.interval,
    required this.enabled,
    required this.onPressed,
  });

  final Rating rating;
  final Duration? interval;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
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
    final String keyHint = '[${rating.index + 1}]';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (interval != null)
          Text(
            reviewIntervalLabel(l10n, interval!),
            key: ValueKey<String>('review-interval-${rating.name}'),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: intervalColor,
              fontFeatures: AppTypography.tabularFigures,
            ),
          ),
        const SizedBox(height: AppSpacing.xxs + 2),
        FilledButton(
          key: ValueKey<String>('review-rating-${rating.name}'),
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background.withValues(alpha: 0.5),
            disabledForegroundColor: foreground.withValues(alpha: 0.6),
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
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
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                keyHint,
                style: TextStyle(
                  fontSize: 11,
                  fontFeatures: AppTypography.tabularFigures,
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
