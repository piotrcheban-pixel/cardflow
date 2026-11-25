import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// TASK 04 / ADR-046, M-04/M-05/M-13: переворот карточки ленты.
///
/// Контракт:
/// * после переворота виден только ответ — вопроса и его изображений нет;
/// * повторный тап возвращает вопрос;
/// * в дереве всегда ровно одна грань;
/// * длинный ответ не обрезается под кнопкой: «Открыть полностью» стоит в
///   нижней полосе, ниже тела карточки, а не поверх текста;
/// * reduced motion — переключение мгновенное.
void main() {
  final Uint8List png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  Widget host({
    required String front,
    required String back,
    required bool revealed,
    Card? card,
    VoidCallback? onTap,
    double width = 390,
    double height = 700,
    bool disableAnimations = false,
    Map<String, Uint8List> media = const <String, Uint8List>{},
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
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
                mediaBytes: media,
                revealed: revealed,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('тап: только ответ; повторный тап возвращает вопрос', (
    WidgetTester tester,
  ) async {
    bool revealed = false;
    late StateSetter setOuter;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          setOuter = setState;
          return host(
            front: 'Что такое ток?',
            back: 'Движение заряда',
            revealed: revealed,
            onTap: () {
              setOuter(() => revealed = !revealed);
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Что такое ток?'), findsOneWidget);
    expect(find.text('Движение заряда'), findsNothing);
    expect(find.byKey(const ValueKey<String>('feed-face')), findsOneWidget);

    await tester.tap(find.text('Что такое ток?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // TASK 04 (M-04): вопроса на обороте нет — только ответ.
    expect(find.text('Что такое ток?'), findsNothing);
    expect(find.text('Движение заряда'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('feed-nav-hint')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('feed-card-reveal')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('feed-face')),
      findsOneWidget,
      reason: 'в дереве должна быть ровно одна грань',
    );

    await tester.tap(find.text('Движение заряда'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Что такое ток?'), findsOneWidget);
    expect(find.text('Движение заряда'), findsNothing);
    expect(find.byKey(const ValueKey<String>('feed-face')), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('изображения вопроса не дублируются на обороте', (
    WidgetTester tester,
  ) async {
    final Card card = makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Вопрос с картинкой',
      back: 'Ответ с картинкой',
      questionMediaIds: <String>['q1'],
      answerMediaIds: <String>['a1'],
    );
    bool revealed = false;
    late StateSetter setOuter;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          setOuter = setState;
          return host(
            front: card.front,
            back: card.back,
            card: card,
            media: <String, Uint8List>{'q1': png, 'a1': png},
            revealed: revealed,
            onTap: () => setOuter(() => revealed = !revealed),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('card-image-q1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('card-image-a1')), findsNothing);

    await tester.tap(find.text('Вопрос с картинкой'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey<String>('card-image-a1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('card-image-q1')),
      findsNothing,
      reason: 'изображение вопроса не должно повторяться на обороте',
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
    'длинный ответ: «Открыть полностью» ниже тела, не поверх текста',
    (WidgetTester tester) async {
      final String longBack = List<String>.filled(
        80,
        'Очень длинный ответ, который не помещается в карточку',
      ).join(' ');
      await tester.pumpWidget(
        host(
          front: 'Вопрос',
          back: longBack,
          revealed: true,
          width: 360,
          height: 520,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      final AppLocalizations l10n = l10nOf(tester);
      final Finder readFull = find.byKey(
        const ValueKey<String>('feed-read-full'),
      );
      expect(
        readFull,
        findsOneWidget,
        reason: 'переполнение должно быть видно',
      );
      expect(find.text(l10n.feedReadFullText), findsOneWidget);

      final Rect body = tester.getRect(
        find.byKey(const ValueKey<String>('feed-face')),
      );
      final Rect button = tester.getRect(readFull);
      // Кнопка находится в нижней полосе — ниже контента, а не над ним.
      expect(
        button.top,
        greaterThanOrEqualTo(body.bottom - 1),
        reason: 'кнопка перекрывает текст карточки',
      );
      expect(
        find.byKey(const ValueKey<String>('feed-body-fade')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  testWidgets('reduced motion: переворот мгновенный', (
    WidgetTester tester,
  ) async {
    bool revealed = false;
    late StateSetter setOuter;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          setOuter = setState;
          return host(
            front: 'Вопрос',
            back: 'Ответ',
            revealed: revealed,
            disableAnimations: true,
            onTap: () => setOuter(() => revealed = !revealed),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вопрос'));
    await tester.pump();
    expect(find.text('Ответ'), findsOneWidget);
    expect(find.text('Вопрос'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 120)));
}
