import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Итерация 7.9: найденная картинка — MIME, расширение и отладочная строка.
void main() {
  GeneratedCardImage image(AttachmentMediaType type) => GeneratedCardImage(
    bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]),
    mediaType: type,
    query: 'diagram',
    sourceUrl: 'https://example.test/image',
    attribution: 'CC BY-SA',
  );

  test('JPEG → image/jpeg и .jpg', () {
    final value = image(AttachmentMediaType.jpeg);
    expect(value.mimeType, 'image/jpeg');
    expect(value.fileExtension, 'jpg');
    expect(value.query, 'diagram');
    expect(value.sourceUrl, contains('example.test'));
    expect(value.attribution, 'CC BY-SA');
    expect(value.toString(), contains('image/jpeg'));
  });

  test('PNG → image/png и .png', () {
    final value = image(AttachmentMediaType.png);
    expect(value.mimeType, 'image/png');
    expect(value.fileExtension, 'png');
  });
}
