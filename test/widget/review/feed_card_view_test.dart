import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Карточка ленты: один вопрос, одно действие, никаких оценок (ADR-044).
void main() {
  Widget host({
    required String front,
    required String back,
    required bool revealed,
    VoidCallback? onTap,
    Card? card,
    Size size = const Size(560, 640),
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: FeedCardView(
              front: front,
              back: back,
              card:
                  card ??
                  makeCard(
                    id: 'card-1',
                    deckId: 'deck-1',
                    front: front,
                    back: back,
                  ),
              revealed: revealed,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'лицевая сторона: вопрос и «Показать ответ», без ответа и оценок',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        host(front: 'Что такое ток?', back: 'Движение заряда', revealed: false),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      expect(find.text('Что такое ток?'), findsOneWidget);
      expect(find.text('Движение заряда'), findsNothing);
      expect(find.text(l10n.reviewRevealAction), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('feed-card-reveal')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('feed-nav-hint')), findsNothing);
      for (final String rating in <String>['again', 'hard', 'good', 'easy']) {
        expect(
          find.byKey(ValueKey<String>('review-rating-$rating')),
          findsNothing,
        );
      }
    },
  );

  testWidgets('оборот: только ответ и подсказка навигации, без вопроса-эха', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(front: 'Что такое ток?', back: 'Движение заряда', revealed: true),
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    // TASK 04 (M-04): на обороте ленты вопроса и его изображений нет —
    // состояния вопроса и ответа визуально разделены.
    expect(find.text('Что такое ток?'), findsNothing);
    expect(find.text('Движение заряда'), findsOneWidget);
    expect(find.text(l10n.reviewRevealAction), findsNothing);
    expect(find.byKey(const ValueKey<String>('feed-nav-hint')), findsOneWidget);
  });

  testWidgets('тап по карточке вызывает onTap (раскрыть/скрыть)', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      host(
        front: 'Вопрос',
        back: 'Ответ',
        revealed: false,
        onTap: () => taps++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Вопрос'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets(
    'длинный текст: карточка не прокручивается, есть «Открыть полностью»',
    (WidgetTester tester) async {
      final String longFront = List<String>.filled(
        60,
        'Очень длинный вопрос',
      ).join(' ');
      await tester.pumpWidget(
        host(
          front: longFront,
          back: 'Ответ',
          revealed: false,
          size: const Size(420, 360),
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      expect(
        find.byKey(const ValueKey<String>('feed-read-full')),
        findsOneWidget,
      );
      expect(find.text(l10n.feedReadFullText), findsOneWidget);
      // Вложенной пользовательской прокрутки в карточке нет: иначе
      // вертикальный свайп ленты перехватывался бы текстом (дефект ленты).
      final SingleChildScrollView body = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(FeedCardView),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(body.physics, isA<NeverScrollableScrollPhysics>());

      await tester.tap(find.byKey(const ValueKey<String>('feed-read-full')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.feedFullTextTitle), findsOneWidget);
    },
  );

  testWidgets('карточка с разметкой: cloze-пропуск раскрывается тапом', (
    WidgetTester tester,
  ) async {
    final Card value = makeCard(
      id: 'cloze',
      deckId: 'deck-1',
      front: 'А {{c1::Б}} и {{c2::В}}',
      back: '',
      cardType: CardType.cloze,
    );
    await tester.pumpWidget(
      host(front: value.front, back: value.back, card: value, revealed: false),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('cloze-gap-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('cloze-gap-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('cloze-answer-1')),
      findsOneWidget,
    );
  });
}
