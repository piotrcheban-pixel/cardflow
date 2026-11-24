import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../helpers/pump_app.dart';

/// Панель оценок дизайн-системы v3 (ADR-045).
///
/// Владелец: на кнопках только названия действий — без номеров клавиш и без
/// прогнозов интервалов; сами оценки и FSRS при этом работают как раньше.
void main() {
  Widget host({
    ValueChanged<Rating>? onRating,
    bool enabled = true,
    double width = 760,
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ReviewToolbar(
              enabled: enabled,
              onRating: onRating ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('подписи — только названия действий, без цифр и интервалов', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    for (final String label in <String>[
      l10n.ratingAgain,
      l10n.ratingHard,
      l10n.ratingGood,
      l10n.ratingEasy,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Требование владельца: никаких «1»–«4», «<1 мин», «6 мин», «16 д».
    for (final String digit in <String>['1', '2', '3', '4']) {
      expect(find.text(digit), findsNothing, reason: 'номер клавиши $digit');
    }
    for (final String rating in <String>['again', 'hard', 'good', 'easy']) {
      expect(
        find.byKey(ValueKey<String>('review-interval-$rating')),
        findsNothing,
      );
    }
    expect(find.text(l10n.reviewIntervalLessThanMinute), findsNothing);
    expect(find.text(l10n.reviewIntervalMinutes(1)), findsNothing);
  });

  testWidgets('высота ≥ 56, текст по центру кнопки', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    for (final Rating rating in Rating.values) {
      final Finder button = find.byKey(
        ValueKey<String>('review-rating-${rating.name}'),
      );
      final Rect buttonRect = tester.getRect(button);
      expect(
        buttonRect.height,
        greaterThanOrEqualTo(AppSizes.ratingButtonHeight),
        reason: rating.name,
      );
      final Rect labelRect = tester.getRect(
        find.descendant(
          of: button,
          matching: find.text(RatingButton.labelOf(l10nOf(tester), rating)),
        ),
      );
      expect(
        labelRect.center.dx,
        closeTo(buttonRect.center.dx, 0.75),
        reason: '${rating.name}: по горизонтали',
      );
      expect(
        labelRect.center.dy,
        closeTo(buttonRect.center.dy, 0.75),
        reason: '${rating.name}: по вертикали',
      );
    }
  });

  testWidgets('иерархия: «Знаю» залита primary, «Не знаю» — error-текст', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final BuildContext context = tester.element(
      find.byKey(const ValueKey<String>('review-rating-good')),
    );
    final ColorScheme scheme = Theme.of(context).colorScheme;

    expect(AppColors.ratingSurface(scheme, RatingRole.good), scheme.primary);
    expect(
      AppColors.ratingForeground(scheme, RatingRole.good),
      scheme.onPrimary,
    );
    expect(AppColors.ratingForeground(scheme, RatingRole.again), scheme.error);
  });

  testWidgets('каждая кнопка отправляет свою оценку', (
    WidgetTester tester,
  ) async {
    final List<Rating> taps = <Rating>[];
    await tester.pumpWidget(host(onRating: taps.add));
    await tester.pumpAndSettle();

    for (final Rating rating in Rating.values) {
      await tester.tap(
        find.byKey(ValueKey<String>('review-rating-${rating.name}')),
      );
      await tester.pumpAndSettle();
    }
    expect(taps, Rating.values);
  });

  testWidgets('disabled: кнопки недоступны, но подписи не исчезают', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(enabled: false));
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.ratingGood), findsOneWidget);
    for (final Rating rating in Rating.values) {
      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(ValueKey<String>('review-rating-${rating.name}')),
      );
      expect(button.onPressed, isNull, reason: rating.name);
    }
  });

  testWidgets('узкая ширина: сетка 2×2 без переполнения', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(width: 320));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('review-rating-good')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
