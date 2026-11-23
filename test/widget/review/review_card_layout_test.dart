import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  testWidgets('G5: undo скрыт, а не серый', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 720));
    expect(
      find.byKey(const ValueKey<String>('review-undo')),
      findsNothing,
      reason: 'без истории отката кнопки нет в дереве',
    );
  });

  testWidgets('G2/G3: оценки находятся внутри карточки, а не полосой под ней', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(800, 600), reveal: true);

    final Rect card = tester.getRect(
      find.byKey(const ValueKey<String>('review-card')),
    );
    final Rect toolbar = tester.getRect(find.byType(ReviewToolbar));

    expect(card.height, greaterThanOrEqualTo(250));
    expect(
      toolbar.top,
      greaterThanOrEqualTo(card.top),
      reason: 'панель оценок — часть карточки (низ), а не отдельный блок',
    );
    expect(
      toolbar.bottom,
      lessThanOrEqualTo(card.bottom + 0.5),
      reason: 'панель не выходит за нижнюю кромку карточки',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('G2: в 533×400 карточка читаема, оценки ≥56 px', (
    WidgetTester tester,
  ) async {
    // Аудит снимал 800×600 физических пикселей при DPI 150 % — это 533×400
    // логических (800×600 при 150 %). Панель оценок теперь живёт в карточке.
    await pumpAt(tester, const Size(533, 400), reveal: true);

    final Rect card = tester.getRect(
      find.byKey(const ValueKey<String>('review-card')),
    );
    expect(card.height, greaterThanOrEqualTo(140));
    expect(find.textContaining('Сила тока на участке'), findsOneWidget);
    for (final String name in <String>['again', 'hard', 'good', 'easy']) {
      final Size button = tester.getSize(
        find.byKey(ValueKey<String>('review-rating-$name')),
      );
      expect(
        button.height,
        greaterThanOrEqualTo(AppSizes.ratingButtonHeight),
        reason: 'G2: «$name» не ниже 56 на 533×400',
      );
    }
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

    final Rect card = tester.getRect(
      find.byKey(const ValueKey<String>('review-card')),
    );
    expect(card.width, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
    final Rect toolbar = tester.getRect(find.byType(ReviewToolbar));
    expect(
      toolbar.bottom,
      lessThanOrEqualTo(card.bottom + 0.5),
      reason: 'панель оценок внутри карточки',
    );
  });

  // Аудит v7 (G3): карточка — не фиксированные 960, а ≥60 % ширины окна.
  for (final (String label, Size size) in <(String, Size)>[
    ('FullHD', const Size(1920, 1080)),
    ('2K', const Size(2560, 1440)),
    ('4K', const Size(3840, 2160)),
  ]) {
    testWidgets('G3: ширина карточки ≥60 % окна на $label', (
      WidgetTester tester,
    ) async {
      await pumpAt(tester, size);
      final Size card = tester.getSize(
        find.byKey(const ValueKey<String>('review-card')),
      );
      expect(
        card.width / size.width,
        greaterThanOrEqualTo(0.6),
        reason: '$label: карточка ${card.width} из ${size.width}',
      );
      // Карточка — основной объект экрана, а не полоса.
      expect(card.height / size.height, greaterThanOrEqualTo(0.5));
      expect(tester.takeException(), isNull);
    });
  }

  test('ширина карточки выросла относительно макета 640 (D1)', () {
    expect(AppSizes.studyCardMaxWidth, greaterThanOrEqualTo(880));
    // Адаптив G3: доля окна и нижняя граница 60 %.
    expect(AppSizes.studyCardWidth(1920), greaterThanOrEqualTo(1920 * 0.6));
    expect(AppSizes.studyCardWidth(2560), greaterThanOrEqualTo(2560 * 0.6));
    expect(AppSizes.studyCardWidth(3840), greaterThanOrEqualTo(3840 * 0.6));
    expect(AppSizes.studyCardWidth(390), lessThanOrEqualTo(390));
  });
  testWidgets('D1 v2: 533×400 — длинный вопрос прокручивается клавишами '
      'и индикатор прокрутки виден', (WidgetTester tester) async {
    final String longFront = List<String>.filled(
      18,
      'Длинный вопрос карточки для проверки прокрутки',
    ).join(' ');
    tester.view.physicalSize = const Size(533, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(
            summaries: <DeckSummary>[
              makeSummary(id: 'deck-1', name: 'Физика', totalCards: 1),
            ],
          ),
          cardRepository: FakeCardRepository(
            cards: <Card>[
              makeCard(id: 'card-1', deckId: 'deck-1', front: longFront),
            ],
          ),
          reviewRepository: FakeReviewRepository(),
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/study',
      ),
    );
    await tester.pumpAndSettle();

    final Finder card = find.byKey(const ValueKey<String>('review-card'));
    expect(card, findsOneWidget);
    // Контент не влезает в карточку — значит, должен быть видимый индикатор.
    final Scrollbar scrollbar = tester.widget<Scrollbar>(
      find.descendant(of: card, matching: find.byType(Scrollbar)),
    );
    expect(scrollbar.thumbVisibility, isTrue);

    final Finder question = find.textContaining('Длинный вопрос карточки');
    final double before = tester.getTopLeft(question).dy;
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final double after = tester.getTopLeft(question).dy;
    expect(
      after,
      lessThan(before),
      reason: 'PageDown прокручивает текст карточки (аудит v2, D1)',
    );
  });
}
