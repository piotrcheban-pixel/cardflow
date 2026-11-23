import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/api/images/image_dimensions.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Картинка карточки: вид, полноэкранный просмотр с атрибуцией, overflow (7.14).
void main() {
  final Uint8List png = Uint8List.fromList(
    img.encodePng(img.Image(width: 800, height: 600)),
  );

  const MediaMetadata photoMetadata = MediaMetadata(
    provider: 'wikimedia',
    sourceUrl: 'https://upload.wikimedia.org/kremlin.jpg',
    author: 'Иван Петров',
    license: 'CC BY-SA 4.0',
    kind: GeneratedCardImageKind.photo,
  );

  Card cardWithImage({String? occlusionJson}) => makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Какой органоид синтезирует АТФ?',
    back: 'Митохондрия',
    mediaIds: const <String>['media-1'],
    occlusionJson: occlusionJson,
  );

  Widget contentView(Card card, {MediaMetadata? metadata}) {
    return CardContentView(
      card: card,
      side: card.front,
      revealed: false,
      faceKey: const ValueKey<String>('face'),
      mediaBytes: <String, Uint8List>{'media-1': png},
      mediaMetadata: <String, MediaMetadata>{'media-1': ?metadata},
    );
  }

  Future<void> pumpContent(
    WidgetTester tester, {
    required Widget child,
    Size size = const Size(800, 600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithHome(
        overrides: const <Override>[],
        home: Scaffold(
          body: SingleChildScrollView(child: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('фото: пропорции файла, contain, без обрезки и рамки 16:9 (G4)', (
    tester,
  ) async {
    await pumpContent(
      tester,
      child: contentView(cardWithImage(), metadata: photoMetadata),
    );
    expect(find.byType(CardImageView), findsOneWidget);
    // Аудит v7 (G4): рамка 16:9 и cover-обрезка удалены — размер строится из
    // фактических пропорций файла (PNG 800×600, AR 4:3).
    expect(
      find.descendant(
        of: find.byType(CardImageView),
        matching: find.byType(AspectRatio),
      ),
      findsNothing,
    );
    final Image image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('card-image-attempt-0')),
    );
    expect(image.fit, BoxFit.contain);
    final Size size = tester.getSize(find.byType(CardImageView));
    expect(size.width / size.height, closeTo(800 / 600, 0.02));
    expect(size.height, lessThanOrEqualTo(kCardImageMaxHeight));
  });

  testWidgets('схема: тот же contain и те же пропорции файла (G4)', (
    tester,
  ) async {
    await pumpContent(
      tester,
      child: contentView(
        cardWithImage(),
        metadata: photoMetadata.copyWith(kind: GeneratedCardImageKind.diagram),
      ),
    );
    final Image image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('card-image-attempt-0')),
    );
    expect(image.fit, BoxFit.contain);
    final Size size = tester.getSize(find.byType(CardImageView));
    expect(size.width / size.height, closeTo(800 / 600, 0.02));
  });

  testWidgets('высокое изображение 960×1371 вписывается целиком (G4)', (
    tester,
  ) async {
    final Uint8List tall = Uint8List.fromList(
      img.encodePng(img.Image(width: 960, height: 1371)),
    );
    await pumpContent(
      tester,
      child: CardContentView(
        card: cardWithImage(),
        side: 'Какой органоид синтезирует АТФ?',
        revealed: false,
        faceKey: const ValueKey<String>('face'),
        mediaBytes: <String, Uint8List>{'media-1': tall},
        mediaMetadata: const <String, MediaMetadata>{
          'media-1': photoMetadata,
        },
        imageMaxHeight: 400,
        imageMaxWidth: 900,
      ),
    );
    final Size size = tester.getSize(find.byType(CardImageView));
    // AR сохраняется: 960/1371 — обрезки нет (было 60,6 % по высоте).
    expect(size.width / size.height, closeTo(960 / 1371, 0.02));
    expect(size.height, closeTo(400, 1));
  });

  testWidgets('ошибка декодирования: явное состояние и повтор (7.19)', (
    tester,
  ) async {
    await pumpContent(
      tester,
      child: CardImageView(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
        onRetry: () {},
      ),
    );
    await tester.pump();
    expect(find.byKey(kCardImageErrorKey), findsOneWidget);
    expect(find.byKey(kCardImageRetryKey), findsOneWidget);
  });

  testWidgets('карточка без картинки — CardImageView нет', (tester) async {
    await pumpContent(
      tester,
      child: contentView(
        makeCard(id: 'c2', deckId: 'd', front: 'Вопрос', back: 'Ответ'),
      ),
    );
    expect(find.byType(CardImageView), findsNothing);
  });

  testWidgets('тап открывает полноэкранный просмотр с атрибуцией', (
    tester,
  ) async {
    await pumpContent(
      tester,
      child: contentView(cardWithImage(), metadata: photoMetadata),
    );
    await tester.tap(find.byType(CardImageView));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final l10n = l10nOf(tester);
    expect(
      find.byKey(const ValueKey<String>('card-image-fullscreen')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.cardImageAttribution('Иван Петров · CC BY-SA 4.0')),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.cardImageSourceUrl('https://upload.wikimedia.org/kremlin.jpg'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('card-image-fullscreen-close')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('card-image-fullscreen')),
      findsNothing,
    );
  });

  testWidgets('360×640: длинный LaTeX с картинкой не даёт overflow', (
    tester,
  ) async {
    const String longLatex =
        r'Как вычислить момент силы $\vec{F}$ относительно оси $z$ через '
        r'проекции силы и координаты точки её приложения, если известны '
        r'$\frac{a}{b}$, $\alpha$, $\int_0^1 x^2 dx$ и ещё много чего?';
    await pumpContent(
      tester,
      size: const Size(360, 640),
      child: contentView(
        makeCard(
          id: 'card-3',
          deckId: 'deck-1',
          front: longLatex,
          back: r'$M_z = x F_y - y F_x$',
          mediaIds: const <String>['media-1'],
        ),
        metadata: photoMetadata,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(CardImageView), findsOneWidget);
  });

  testWidgets('1280×800: длинный LaTeX с картинкой не даёт overflow', (
    tester,
  ) async {
    const String longLatex =
        r'Каким соотношением должны быть связаны число стержней $s$ и число '
        r'узлов $n$, чтобы плоская ферма была геометрически неизменяемой и '
        r'статически определимой, если $\frac{a}{b}$ и $\sum_{i=1}^{n} x_i$?';
    await pumpContent(
      tester,
      size: const Size(1280, 800),
      child: contentView(
        makeCard(
          id: 'card-4',
          deckId: 'deck-1',
          front: longLatex,
          back: r'$s = 2n - 3$',
          mediaIds: const <String>['media-1'],
        ),
        metadata: photoMetadata,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(CardImageView), findsOneWidget);
  });

  testWidgets('occlusion-карточка показывает маску, а не обычную картинку', (
    tester,
  ) async {
    await pumpContent(
      tester,
      child: contentView(
        cardWithImage(
          occlusionJson: '{"version":1,"masks":[{"x":0.3,"y":0.35,"width":0.4,"height":0.3,"shape":"rectangle"}]}',
        ),
      ),
    );
    expect(find.byType(CardImageView), findsNothing);
  });

  test('изображение имеет валидный размер', () {
    final dimensions = ImageDimensions.read(png);
    expect(dimensions, isNotNull);
    expect(dimensions!.isUsable, isTrue);
  });
}
