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
    this.compact = false,
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

  /// Компактный вид для низких окон (находка D2: 800×600 — логические 533×400
  /// при масштабе 150 %): одна строка кнопок без прогноза интервалов и
  /// клавиатурных подсказок, чтобы карточка не сжималась до полоски.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? hintText = enabled ? null : hint;
    // Аудит v4 (V24): прогнозы интервалов не показываются, пока ответ не
    // раскрыт — иначе пользователь видит числа у недоступных кнопок.
    final Map<Rating, Duration>? visiblePreview = enabled ? preview : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          compact ? AppSpacing.xxs : AppSpacing.xs,
          AppSpacing.md,
          compact ? AppSpacing.xs : AppSpacing.md,
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
                    final int columns =
                        (constraints.maxWidth < (compact ? 400 : 520)) ? 2 : 4;
                    final double gap = compact ? AppSpacing.xs : AppSpacing.sm;
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
                              interval: compact
                                  ? null
                                  : visiblePreview?[rating],
                              enabled: enabled,
                              compact: compact,
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
    this.compact = false,
  });

  final Rating rating;
  final Duration? interval;
  final bool enabled;
  final VoidCallback onPressed;
  final bool compact;

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
            style: AppTypography.caption(context, color: intervalColor),
          ),
        const SizedBox(height: AppSpacing.xxs + 2),
        FilledButton(
          key: ValueKey<String>('review-rating-${rating.name}'),
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background.withValues(alpha: 0.5),
            disabledForegroundColor: foreground.withValues(alpha: 0.65),
            minimumSize: Size(
              0,
              compact
                  ? AppSizes.minTouchTarget
                  : AppSizes.buttonHeightLarge *
                        AppAdaptive.factorForContext(context).clamp(1.0, 1.3),
            ),
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
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                ),
              ),
              if (!compact) ...<Widget>[
                const SizedBox(height: 1),
                Text(
                  keyHint,
                  style: AppTypography.caption(
                    context,
                    color: foreground.withValues(alpha: 0.7),
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
