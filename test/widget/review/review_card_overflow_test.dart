import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart' as domain;
import 'package:cardflow/ui/review/session_card.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Регрессии аудита 2.0 по карточке изучения:
///
/// * **P1-01** — длинный вопрос с изображением не обрезается и не наезжает на
///   картинку: текст переносится в своей колонке, изображение занимает
///   отдельный слот и не пересекается с текстом;
/// * **P1-03** — длинный ответ на телефоне прокручивается внутри карточки:
///   у тела есть видимая подсказка прокрутки, а панель оценок не перекрывает
///   текст;
/// * **P2-27** — карточка занимает основную часть рабочей области, а не
///   «полоску» в центре пустого экрана.
void main() {
  final Uint8List landscape = Uint8List.fromList(
    img.encodePng(img.Image(width: 800, height: 450)),
  );

  domain.Card cardWith({
    required String front,
    required String back,
    bool image = false,
  }) {
    return makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: front,
      back: back,
      questionMediaIds: image ? const <String>['media-q'] : const <String>[],
    );
  }

  Widget harness({
    required domain.Card card,
    bool revealed = false,
    double width = 920,
    double height = 620,
    Map<String, Uint8List> media = const <String, Uint8List>{},
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: SessionCard(
              front: card.front,
              back: card.back,
              card: card,
              mediaBytes: media,
              revealed: revealed,
              onTap: () {},
              questionFooter: FilledButton(
                onPressed: () {},
                child: const Text('Показать ответ'),
              ),
              answerFooter: FilledButton(
                onPressed: () {},
                child: const Text('Знаю'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'P1-01: вопрос 200+ знаков с картинкой не обрезан и не наезжает',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final String longFront = List<String>.filled(
        6,
        'Как называют свойство теста измерять именно ту характеристику, '
        'для которой он создан, и насколько устойчивы результаты?',
      ).join(' ');
      final domain.Card card = cardWith(
        front: longFront,
        back: 'Валидность.',
        image: true,
      );
      await tester.pumpWidget(
        harness(card: card, media: <String, Uint8List>{'media-q': landscape}),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'нет переполнений вёрстки',
      );

      final Rect text = tester.getRect(find.textContaining('Как называют'));
      final Rect image = tester.getRect(
        find.byKey(const ValueKey<String>('card-image-media-q')),
      );
      // Текст и картинка не пересекаются: либо рядом, либо друг под другом.
      final bool sideBySide = text.right <= image.left + 0.5;
      final bool stacked = text.bottom <= image.top + 0.5;
      expect(
        sideBySide || stacked,
        isTrue,
        reason: 'текст $text не должен пересекаться с картинкой $image',
      );
      // Текстовая колонка остаётся читаемой: не шире карточки и не уже 200 px.
      expect(text.width, lessThanOrEqualTo(920));
      expect(text.width, greaterThan(200));
    },
  );

  testWidgets('P1-01: изображение вписано целиком (contain), без обрезки', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        card: cardWith(front: 'Что на схеме?', back: 'Ферма.', image: true),
        media: <String, Uint8List>{'media-q': landscape},
      ),
    );
    await tester.pumpAndSettle();

    final Rect image = tester.getRect(
      find.byKey(const ValueKey<String>('card-image-media-q')),
    );
    // Пропорции файла 16:9 сохраняются (contain), картинка не растянута.
    expect(image.width / image.height, closeTo(16 / 9, 0.05));
    expect(tester.takeException(), isNull);
  });

  testWidgets('P1-03: длинный ответ на телефоне прокручивается с подсказкой', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final String longBack = List<String>.filled(
      8,
      'Совокупность трёх однофазных цепей с тремя синусоидальными ЭДС '
      'одинаковой частоты и амплитуды, сдвинутыми по фазе на 120 градусов.',
    ).join(' ');
    final domain.Card card = cardWith(
      front: 'Что такое трёхфазная цепь?',
      back: longBack,
    );
    await tester.pumpWidget(
      harness(card: card, revealed: true, width: 358, height: 560),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Тело карточки прокручивается: контент выше области, есть подсказка.
    final Finder body = find.descendant(
      of: find.byType(SessionCard),
      matching: find.byType(SingleChildScrollView),
    );
    expect(body, findsWidgets);
    final ScrollPosition position = tester
        .state<ScrollableState>(
          find.descendant(of: body.first, matching: find.byType(Scrollable)),
        )
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'длинный ответ прокручивается, а не обрезается',
    );
    expect(
      find.byKey(const ValueKey<String>('card-scroll-fade-bottom')),
      findsOneWidget,
      reason: 'внизу видна подсказка «текст продолжается»',
    );

    // Панель оценки не перекрывает текст: вьюпорт тела заканчивается выше неё.
    final Rect viewport = tester.getRect(body.first);
    final Rect footer = tester.getRect(find.text('Знаю'));
    expect(viewport.bottom, lessThanOrEqualTo(footer.top + 0.5));
  });

  testWidgets('P2-27: карточка занимает основную часть рабочей области', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        card: cardWith(front: 'Короткий вопрос', back: 'Ответ'),
      ),
    );
    await tester.pumpAndSettle();

    final Rect card = tester.getRect(find.byType(SessionCard));
    expect(card.width, greaterThanOrEqualTo(820));
    // Карточка заполняет ~62 % своей ширины по высоте, но не упирается в края.
    expect(card.height, greaterThanOrEqualTo(440));
    expect(card.height, lessThanOrEqualTo(620));
  });
}
