import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';
import 'package:cardflow/ui/review/review_card_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// TASK 04, часть 7: анимации переворота не должны перестраивать содержимое
/// карточки и пересчитывать тяжёлую тень каждый кадр.
///
/// Что проверяется:
/// * тяжёлое содержимое (`CardContentView`) внутри `RepaintBoundary`;
/// * экземпляр содержимого не пересобирается между кадрами анимации;
/// * `BoxShadow` выключена во время движения и возвращается в покое;
/// * изображение декодируется с ограничением `cacheWidth` по слоту.
void main() {
  const String question = 'Какой органоид синтезирует АТФ?';

  final Uint8List png = Uint8List.fromList(
    img.encodePng(img.Image(width: 1600, height: 1200)),
  );

  Card cardWithImage() => makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: question,
    back: 'Митохондрия',
    mediaIds: const <String>['media-1'],
  );

  /// Все тени внутри поддерева карточки.
  List<BoxShadow> shadowsIn(WidgetTester tester, Finder root) {
    final Iterable<DecoratedBox> boxes = tester.widgetList<DecoratedBox>(
      find.descendant(of: root, matching: find.byType(DecoratedBox)),
    );
    return <BoxShadow>[
      for (final DecoratedBox box in boxes)
        if (box.decoration is BoxDecoration)
          ...?((box.decoration as BoxDecoration).boxShadow),
    ];
  }

  Widget host({
    required Widget Function(bool revealed, VoidCallback onTap) builder,
    Size size = const Size(390, 844),
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: _ToggleHost(builder: builder),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpClassic(WidgetTester tester) async {
    final Card card = cardWithImage();
    await tester.pumpWidget(
      host(
        builder: (bool revealed, VoidCallback onTap) => ReviewCardView(
          front: card.front,
          back: card.back,
          revealed: revealed,
          onTap: onTap,
          card: card,
          mediaBytes: <String, Uint8List>{'media-1': png},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpFeed(WidgetTester tester) async {
    final Card card = cardWithImage();
    await tester.pumpWidget(
      host(
        builder: (bool revealed, VoidCallback onTap) => FeedCardView(
          front: card.front,
          back: card.back,
          revealed: revealed,
          onTap: onTap,
          card: card,
          mediaBytes: <String, Uint8List>{'media-1': png},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cardContentIn(Finder cardFinder) =>
      find.descendant(of: cardFinder, matching: find.byType(CardContentView));

  testWidgets('классика: содержимое в RepaintBoundary и не пересобирается', (
    WidgetTester tester,
  ) async {
    await pumpClassic(tester);
    final Finder cardFinder = find.byType(ReviewCardView);
    expect(
      find.descendant(
        of: cardFinder,
        matching: find.ancestor(
          of: find.byType(CardContentView),
          matching: find.byType(RepaintBoundary),
        ),
      ),
      findsWidgets,
      reason: 'содержимое карточки изолировано для растеризации',
    );

    await tester.tap(find.text(question));
    await tester.pump();
    // Первая сборка после смены revealed штатная: дальше кадры анимации не
    // должны пересобирать содержимое.
    final CardContentView frameOne = tester.widget<CardContentView>(
      cardContentIn(cardFinder),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final CardContentView frameTwo = tester.widget<CardContentView>(
      cardContentIn(cardFinder),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final CardContentView frameThree = tester.widget<CardContentView>(
      cardContentIn(cardFinder),
    );
    expect(
      identical(frameOne, frameTwo),
      isTrue,
      reason: 'кадры анимации двигают только Transform',
    );
    expect(
      identical(frameTwo, frameThree),
      isTrue,
      reason: 'содержимое не пересобирается на каждом кадре',
    );
    await tester.pumpAndSettle();
    expect(find.text('Митохондрия'), findsOneWidget);
  });

  testWidgets('классика: тень выключена в движении и есть в покое', (
    WidgetTester tester,
  ) async {
    await pumpClassic(tester);
    final Finder cardFinder = find.byType(ReviewCardView);
    expect(
      shadowsIn(tester, cardFinder),
      isNotEmpty,
      reason: 'в покое карточка с тенью',
    );

    await tester.tap(find.text(question));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      shadowsIn(tester, cardFinder),
      isEmpty,
      reason: 'BoxShadow не пересчитывается каждый кадр анимации',
    );

    await tester.pumpAndSettle();
    expect(
      shadowsIn(tester, cardFinder),
      isNotEmpty,
      reason: 'после остановки тень возвращается',
    );
  });

  testWidgets('лента: содержимое в RepaintBoundary и не пересобирается', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester);
    final Finder cardFinder = find.byType(FeedCardView);
    expect(
      find.descendant(
        of: cardFinder,
        matching: find.ancestor(
          of: find.byType(CardContentView),
          matching: find.byType(RepaintBoundary),
        ),
      ),
      findsWidgets,
    );
    await tester.tap(find.text(question));
    await tester.pump();
    final CardContentView frameOne = tester.widget<CardContentView>(
      cardContentIn(cardFinder),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final CardContentView frameTwo = tester.widget<CardContentView>(
      cardContentIn(cardFinder),
    );
    expect(
      identical(frameOne, frameTwo),
      isTrue,
      reason: 'кадры ленты не пересобирают CardContentView',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('лента: тень выключена в движении и есть в покое', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester);
    final Finder cardFinder = find.byType(FeedCardView);
    expect(shadowsIn(tester, cardFinder), isNotEmpty);
    await tester.tap(find.text(question));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      shadowsIn(tester, cardFinder),
      isEmpty,
      reason: 'лента тоже не рисует тень каждый кадр',
    );
    await tester.pumpAndSettle();
    expect(shadowsIn(tester, cardFinder), isNotEmpty);
  });

  testWidgets('изображение декодируется с cacheWidth по слоту (4K → слот)', (
    WidgetTester tester,
  ) async {
    await pumpClassic(tester);
    final Finder cardFinder = find.byType(ReviewCardView);
    final Size slot = tester.getSize(cardContentIn(cardFinder));
    final Image image = tester.widget<Image>(find.byType(Image));
    expect(
      image.image,
      isA<ResizeImage>(),
      reason: 'без ResizeImage 4K-файл декодировался бы целиком',
    );
    final int? width = (image.image as ResizeImage).width;
    expect(width, isNotNull);
    // В widget-тестах DPR по умолчанию 3; слот ограничен экраном.
    final int limit = math.min(4096, (slot.width * 3).ceil() + 1);
    expect(
      width,
      lessThanOrEqualTo(limit),
      reason: 'декодирование ограничено размером слота на экране',
    );
  });
}

/// Хост с переключением «показать ответ» по тапу.
class _ToggleHost extends StatefulWidget {
  const _ToggleHost({required this.builder});

  final Widget Function(bool revealed, VoidCallback onTap) builder;

  @override
  State<_ToggleHost> createState() => _ToggleHostState();
}

class _ToggleHostState extends State<_ToggleHost> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      _revealed,
      () => setState(() => _revealed = !_revealed),
    );
  }
}
