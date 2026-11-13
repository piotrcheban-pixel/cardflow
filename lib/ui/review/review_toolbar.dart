import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_interval_format.dart';

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

/// Панель оценок классического режима (SPEC A7.2).
///
/// Четыре кнопки в порядке [Rating.values]: над каждой — прогноз интервала,
/// посчитанный планировщиком для текущей карточки. Цвета ролей:
/// `errorContainer`, `secondaryContainer`, `primary`, `tertiaryContainer`.
class ReviewToolbar extends StatelessWidget {
  /// Создаёт панель оценок.
  const ReviewToolbar({
    required this.preview,
    required this.enabled,
    required this.onRating,
    super.key,
  });

  /// Прогноз интервалов над кнопками; `null` — прогноза нет.
  final Map<Rating, Duration>? preview;

  /// Доступны ли кнопки (не идёт запись в БД).
  final bool enabled;

  /// Обработчик оценки.
  final ValueChanged<Rating> onRating;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final Rating rating in Rating.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _RatingButton(
                    rating: rating,
                    interval: preview?[rating],
                    enabled: enabled,
                    onPressed: () => onRating(rating),
                  ),
                ),
              ),
          ],
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String label = switch (rating) {
      Rating.again => l10n.ratingAgain,
      Rating.hard => l10n.ratingHard,
      Rating.good => l10n.ratingGood,
      Rating.easy => l10n.ratingEasy,
    };
    final (Color background, Color foreground) = switch (rating) {
      Rating.again => (scheme.errorContainer, scheme.onErrorContainer),
      Rating.hard => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      Rating.good => (scheme.primary, scheme.onPrimary),
      Rating.easy => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
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
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 4),
        FilledButton(
          key: ValueKey<String>('review-rating-${rating.name}'),
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            // SPEC A4.3: кнопки оценок — pill (full).
            shape: const StadiumBorder(),
          ),
          onPressed: enabled ? onPressed : null,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
