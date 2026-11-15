import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Итерация 7.8: вложение генерации (картинка/PDF-скан) и его тип.
void main() {
  test('JPG/JPEG/PNG распознаются по имени без учёта регистра', () {
    expect(
      attachmentMediaTypeForFileName('фото.JPG'),
      AttachmentMediaType.jpeg,
    );
    expect(
      attachmentMediaTypeForFileName('скан.jpeg'),
      AttachmentMediaType.jpeg,
    );
    expect(
      attachmentMediaTypeForFileName('схема.png'),
      AttachmentMediaType.png,
    );
    expect(attachmentMediaTypeForFileName('лекция.pdf'), isNull);
    expect(attachmentMediaTypeForFileName('текст.txt'), isNull);
    expect(attachmentMediaTypeForFileName('без_расширения'), isNull);
  });

  test('сигнатуры картинок проверяются по магическим байтам', () {
    final Uint8List png = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
    ]);
    final Uint8List jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1]);
    final Uint8List junk = Uint8List.fromList(<int>[1, 2, 3, 4]);

    expect(hasValidAttachmentSignature(AttachmentMediaType.png, png), isTrue);
    expect(hasValidAttachmentSignature(AttachmentMediaType.jpeg, jpeg), isTrue);
    expect(hasValidAttachmentSignature(AttachmentMediaType.png, jpeg), isFalse);
    expect(hasValidAttachmentSignature(AttachmentMediaType.jpeg, png), isFalse);
    expect(hasValidAttachmentSignature(AttachmentMediaType.png, junk), isFalse);
  });

  test('PDF-вложение помечается как документ, а не картинка', () {
    final attachment = GenerationAttachment(
      fileName: 'скан.pdf',
      mediaType: AttachmentMediaType.pdf,
      bytes: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x2D]),
    );
    expect(attachment.isPdf, isTrue);
    expect(attachment.mimeType, 'application/pdf');

    final image = GenerationAttachment(
      fileName: 'схема.png',
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
    );
    expect(image.isPdf, isFalse);
    expect(image.mimeType, 'image/png');
  });

  test('страница PDF-скана: pageNumber, groupKey, isPdfPage', () {
    final page = GenerationAttachment(
      fileName: 'скан.pdf',
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
      pageNumber: 2,
      groupKey: '/tmp/скан.pdf',
    );
    expect(page.isPdfPage, isTrue);
    expect(page.isPdf, isFalse);
    expect(page.pageNumber, 2);
    expect(page.groupKey, '/tmp/скан.pdf');

    final plain = GenerationAttachment(
      fileName: 'схема.png',
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
    );
    expect(plain.isPdfPage, isFalse);
  });
}
