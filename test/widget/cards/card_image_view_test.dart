import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/api/images/image_dimensions.dart';
import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Картинка карточки: вид, полноэкранный просмотр с атрибуцией, overflow (7.14).
void main() {
  final Uint8List png = const PlaceholderImageGenerator()
      .generate(seed: 'test-image')
      .bytes;

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

  testWidgets('карточка с фото: картинка 16:9, ограничена по высоте', (
    tester,
  ) async {
    await pumpContent(
      tester,
      child: contentView(cardWithImage(), metadata: photoMetadata),
    );
    expect(find.byType(CardImageView), findsOneWidget);
    final aspect = tester.widget<AspectRatio>(
      find.descendant(
        of: find.byType(CardImageView),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(aspect.aspectRatio, closeTo(16 / 9, 0.01));
    final size = tester.getSize(find.byType(CardImageView));
    expect(size.height, lessThanOrEqualTo(kCardImageMaxHeight));
  });

  testWidgets('схема: пропорции 4:3 и BoxFit.contain', (tester) async {
    await pumpContent(
      tester,
      child: contentView(
        cardWithImage(),
        metadata: photoMetadata.copyWith(kind: GeneratedCardImageKind.diagram),
      ),
    );
    final aspect = tester.widget<AspectRatio>(
      find.descendant(
        of: find.byType(CardImageView),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(aspect.aspectRatio, closeTo(4 / 3, 0.01));
    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('card-image')),
    );
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('заглушка помечена для screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpContent(
      tester,
      child: contentView(
        cardWithImage(),
        metadata: const MediaMetadata(
          provider: 'placeholder',
          isPlaceholder: true,
        ),
      ),
    );
    final l10n = l10nOf(tester);
    expect(
      find.bySemanticsLabel(l10n.cardImagePlaceholderSemantics),
      findsOneWidget,
    );
    semantics.dispose();
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

  test('картинка-заглушка имеет валидный размер', () {
    final dimensions = ImageDimensions.read(png);
    expect(dimensions, isNotNull);
    expect(dimensions!.isUsable, isTrue);
  });
}
