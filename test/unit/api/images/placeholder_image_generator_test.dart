import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/images/image_dimensions.dart';
import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Детерминированная заглушка карточки (7.14, шаг 3).
void main() {
  const generator = PlaceholderImageGenerator();

  test('одинаковый seed даёт идентичные байты', () {
    final first = generator.generate(seed: 'card-hash-1');
    final second = generator.generate(seed: 'card-hash-1');
    expect(first.bytes, second.bytes);
  });

  test('разные seed — разные картинки', () {
    final first = generator.generate(seed: 'card-hash-1');
    final second = generator.generate(seed: 'card-hash-2');
    expect(first.bytes, isNot(second.bytes));
  });

  test('заглушка — PNG 16:9, помечена флагом и провайдером', () {
    final image = generator.generate(
      seed: 'seed',
      kind: GeneratedCardImageKind.photo,
      query: 'truss bridge',
      fallbackQuery: 'bridge',
    );
    expect(image.mediaType, AttachmentMediaType.png);
    expect(image.fileExtension, 'png');
    expect(image.isPlaceholder, isTrue);
    expect(image.provider, 'placeholder');
    expect(image.kind, GeneratedCardImageKind.photo);
    expect(image.query, 'truss bridge');
    expect(image.fallbackQuery, 'bridge');
    final dimensions = ImageDimensions.read(image.bytes);
    expect(dimensions!.width, kPlaceholderWidth);
    expect(dimensions.height, 450);
  });

  test('схема рисуется 4:3 (выше, чем фото)', () {
    final diagram = generator.generate(
      seed: 'seed',
      kind: GeneratedCardImageKind.diagram,
    );
    final dimensions = ImageDimensions.read(diagram.bytes)!;
    expect(dimensions.width, kPlaceholderWidth);
    expect(dimensions.height, 600);
  });

  test('все 8 палитр дают валидный PNG', () {
    for (var index = 0; index < 64; index++) {
      final image = generator.generate(seed: 'seed-$index');
      final dimensions = ImageDimensions.read(image.bytes);
      expect(dimensions, isNotNull, reason: 'seed-$index');
      expect(image.bytes.length, greaterThan(1000));
    }
    expect(kPlaceholderPalettes, hasLength(8));
  });
}
