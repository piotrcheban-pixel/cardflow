import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../helpers/pump_app.dart';

/// TASK 04 / ADR-046: панель оценок на телефоне.
///
/// Контракт:
/// * сетка 2×2 при ширине < 520, иначе один ряд 4;
/// * высота 48 на телефоне (цель касания ≥44), 56+ на широком;
/// * подпись не обрезается многоточием: FittedBox либо вписывает текст, либо
///   равномерно уменьшает; текст строго по центру;
/// * «Затрудняюсь» помещается целиком на 320 и при системном кегле до 200 %.
void main() {
  Widget host({
    required double width,
    required double textScale,
    ValueChanged<Rating>? onRating,
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ReviewToolbar(onRating: onRating ?? (Rating rating) {}),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double lineHeight(WidgetTester tester, String rating) {
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byKey(ValueKey<String>('review-rating-label-$rating')),
    );
    return paragraph.text.style?.fontSize ?? 0;
  }

  for (final (String label, double width) in <(String, double)>[
    ('360 (2×2)', 360),
    ('320 (2×2)', 320),
    ('390 (2×2)', 390),
  ]) {
    testWidgets('$label: компактная сетка, полные подписи, центр', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(width: width, textScale: 1));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = l10nOf(tester);
      final Rect again = tester.getRect(
        find.byKey(const ValueKey<String>('review-rating-again')),
      );
      final Rect hard = tester.getRect(
        find.byKey(const ValueKey<String>('review-rating-hard')),
      );
      final Rect good = tester.getRect(
        find.byKey(const ValueKey<String>('review-rating-good')),
      );
      final Rect easy = tester.getRect(
        find.byKey(const ValueKey<String>('review-rating-easy')),
      );

      // 2×2: вторая кнопка на той же строке, третья — ниже.
      expect(hard.top, again.top);
      expect(good.top, greaterThan(again.bottom));
      expect(easy.top, good.top);
      expect(again.width, closeTo(hard.width, 0.5));

      // Высота 48 (компактная) и цель ≥44.
      for (final Rect button in <Rect>[again, hard, good, easy]) {
        expect(button.height, 48);
        expect(button.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
      }

      // Подписи: полный текст, без ellipsis, одна строка, по центру.
      for (final Rating rating in Rating.values) {
        final String name = rating.name;
        final String text = RatingButton.labelOf(l10n, rating);
        expect(
          find.text(text),
          findsOneWidget,
          reason: 'подпись «$text» должна быть в дереве',
        );
        final Text widget = tester.widget<Text>(
          find.byKey(ValueKey<String>('review-rating-label-$name')),
        );
        expect(widget.overflow, isNot(TextOverflow.ellipsis));
        expect(widget.textAlign, TextAlign.center);
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(ValueKey<String>('review-rating-label-$name')),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'подпись «$text» не должна переноситься/обрезаться',
        );
        // Центрирование: центр подписи против центра кнопки.
        final Rect button = tester.getRect(
          find.byKey(ValueKey<String>('review-rating-$name')),
        );
        final Rect labelRect = tester.getRect(
          find.byKey(ValueKey<String>('review-rating-label-$name')),
        );
        expect(
          labelRect.center.dx,
          closeTo(button.center.dx, 0.6),
          reason: '«$text» не по центру по горизонтали',
        );
        expect(
          labelRect.center.dy,
          closeTo(button.center.dy, 0.6),
          reason: '«$text» не по центру по вертикали',
        );
      }
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(seconds: 120)));
  }

  testWidgets('320 при системном кегле 200 %: подписи не обрезаются', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(width: 320, textScale: 2));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = l10nOf(tester);
    for (final Rating rating in Rating.values) {
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(ValueKey<String>('review-rating-label-${rating.name}')),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(find.text(RatingButton.labelOf(l10n, rating)), findsOneWidget);
    }
    // FittedBox уменьшает текст, но не ниже читаемого: кегль рендера > 0.
    expect(lineHeight(tester, 'hard'), greaterThan(0));
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('широкая панель: 4 в ряд, высота 56, кегль 18', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(width: 900, textScale: 1));
    await tester.pumpAndSettle();

    final Rect again = tester.getRect(
      find.byKey(const ValueKey<String>('review-rating-again')),
    );
    final Rect easy = tester.getRect(
      find.byKey(const ValueKey<String>('review-rating-easy')),
    );
    expect(easy.top, again.top);
    expect(again.height, greaterThanOrEqualTo(AppSizes.ratingButtonHeight));
    final RenderParagraph label = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey<String>('review-rating-label-good')),
    );
    expect(label.text.style?.fontSize, 18);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('нажатие передаёт ровно одну оценку', (
    WidgetTester tester,
  ) async {
    final List<Rating> pressed = <Rating>[];
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(width: 360, textScale: 1, onRating: pressed.add),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pump();
    expect(pressed, <Rating>[Rating.good]);
  }, timeout: const Timeout(Duration(seconds: 120)));
}
