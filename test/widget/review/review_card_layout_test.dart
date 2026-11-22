import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/ui/review/review_card_view.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Геометрия экрана карточки на ПК (находки D1/D2 аудита 1.0):
/// карточка — главный объект экрана, а не полоска 640×240; панель оценок не
/// перекрывает текст ни на одном из обязательных разрешений.
void main() {
  List<Override> overridesFor(List<Card> cards) {
    return decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Физика',
            totalCards: cards.length,
            newCards: cards.length,
          ),
        ],
      ),
      cardRepository: FakeCardRepository(cards: cards),
      reviewRepository: FakeReviewRepository(),
    );
  }

  List<Card> cards() => <Card>[
    makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Сформулируйте закон Ома для участка цепи',
      back:
          'Сила тока на участке цепи прямо пропорциональна напряжению '
          'и обратно пропорциональна сопротивлению участка.',
      createdAt: DateTime.utc(2026, 11, 20),
    ),
  ];

  Future<void> pumpAt(
    WidgetTester tester,
    Size logicalSize, {
    bool reveal = false,
  }) async {
    tester.view.physicalSize = logicalSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithRouter(
        overrides: overridesFor(cards()),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/study',
      ),
    );
    await tester.pumpAndSettle();
    if (reveal) {
      await tester.tap(find.byKey(const ValueKey<String>('review-card')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('D1: карточка занимает основную часть области (1280×720)', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1280, 720), reveal: true);

    final Size card = tester.getSize(
      find.byKey(const ValueKey<String>('review-card')),
    );
    final Size window = tester.view.physicalSize;
    final double areaFraction =
        (card.width * card.height) / (window.width * window.height);

    expect(card.width, greaterThanOrEqualTo(840), reason: 'ширина карточки');
    expect(card.height, greaterThanOrEqualTo(440), reason: 'высота карточки');
    expect(
      areaFraction,
      greaterThanOrEqualTo(0.40),
      reason: 'карточка — главный объект, а не 17 % площади как до аудита',
    );
  });

  testWidgets('D1: вопрос 24–32 px, ответ 18–22 px', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1280, 720));

    // Кегль измеряется по отрисованному абзацу: стиль приходит из
    // DefaultTextStyle карточки, у самого Text поле style пустое.
    double renderedFontSize(String text) {
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining(text),
      );
      final double? size = paragraph.text.style?.fontSize;
      expect(size, isNotNull, reason: 'у абзаца «$text» нет кегля');
      return size!;
    }

    expect(
      renderedFontSize('Сформулируйте закон Ома'),
      inInclusiveRange(24, 32),
    );

    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();

    expect(renderedFontSize('Сила тока на участке'), inInclusiveRange(18, 22));
  });

  testWidgets('D3: раскрытая карточка показывает вопрос и ответ', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1280, 720), reveal: true);

    expect(
      find.text('Сформулируйте закон Ома для участка цепи'),
      findsOneWidget,
      reason: 'вопрос остаётся видимым после раскрытия',
    );
    expect(find.textContaining('Сила тока на участке'), findsOneWidget);
  });

  testWidgets('D2: на 800×600 панель оценок не перекрывает карточку', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(800, 600), reveal: true);

    final Rect card = tester.getRect(
      find.byKey(const ValueKey<String>('review-card')),
    );
    final Rect toolbar = tester.getRect(find.byType(ReviewToolbar));

    expect(card.height, greaterThanOrEqualTo(250));
    expect(
      card.bottom,
      lessThanOrEqualTo(toolbar.top),
      reason: 'между карточкой и панелью оценок нет перекрытия',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('переворот длится 250–350 мс (SPEC A7.2 / D1)', (
    WidgetTester tester,
  ) async {
    expect(kReviewCardFlipDuration.inMilliseconds, inInclusiveRange(250, 350));
    await pumpAt(tester, const Size(1280, 720));
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Середина анимации: карточка ещё не перевернулась до ответа.
    expect(find.textContaining('Сила тока на участке'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Сила тока на участке'), findsOneWidget);
  });

  testWidgets('узкий экран 390×844: карточка адаптируется без переполнений', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(390, 844), reveal: true);

    final Size card = tester.getSize(
      find.byKey(const ValueKey<String>('review-card')),
    );
    expect(card.width, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(ReviewToolbar)).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey<String>('review-card'))).top,
      ),
    );
  });

  test('ширина карточки выросла относительно макета 640 (D1)', () {
    expect(AppSizes.studyCardMaxWidth, greaterThanOrEqualTo(880));
  });
}
