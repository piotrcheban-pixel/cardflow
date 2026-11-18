import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Модель изображения документа (итерация L76, ADR-037): источник, положение
/// на странице и порядок — расширение без ломки DOCX/PPTX/ODT-поведения.
void main() {
  Uint8List bytes([int seed = 1]) =>
      Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, seed]);

  DocumentImage image() => DocumentImage(
    fileName: 'лекция.pdf',
    bytes: bytes(),
    mediaType: AttachmentMediaType.png,
    caption: 'Рис. 2 Схема фермы',
    context: 'Раздел о фермах',
    page: 3,
    width: 600,
    height: 400,
    source: DocumentImageSource.croppedRegion,
    rect: DocumentImageRect(left: 0.1, top: 0.2, width: 0.5, height: 0.4),
    order: 2,
  );

  test(
    'по умолчанию источник embedded и нет координат (DOCX-совместимость)',
    () {
      final DocumentImage plain = DocumentImage(
        fileName: 'статика.docx',
        bytes: bytes(),
        mediaType: AttachmentMediaType.jpeg,
      );
      expect(plain.source, DocumentImageSource.embedded);
      expect(plain.rect, isNull);
      expect(plain.order, 0);
      expect(plain.page, isNull);
      expect(plain.mimeType, 'image/jpeg');
      expect(plain.sourceLabel, isNull);
    },
  );

  test('прямоугольник клампятся в 0..1 и считает площадь', () {
    final DocumentImageRect rect = DocumentImageRect(
      left: -0.5,
      top: 0.25,
      width: 2,
      height: 0.4,
    );
    expect(rect.left, 0);
    expect(rect.top, 0.25);
    expect(rect.width, 1);
    expect(rect.height, 0.4);
    expect(rect.areaFraction, closeTo(0.4, 1e-9));
    expect(rect.toJson(), <String, Object?>{
      'left': 0.0,
      'top': 0.25,
      'width': 1.0,
      'height': 0.4,
    });
  });

  test('NaN в координатах не ломает модель', () {
    final DocumentImageRect rect = DocumentImageRect(
      left: double.nan,
      top: 0,
      width: 0.5,
      height: 0.5,
    );
    expect(rect.left, 0);
  });

  test('coversPage: почти вся страница', () {
    expect(
      DocumentImageRect(left: 0, top: 0, width: 1, height: 1).coversPage(),
      isTrue,
    );
    expect(
      DocumentImageRect(left: 0, top: 0, width: 0.5, height: 0.5).coversPage(),
      isFalse,
    );
    expect(
      DocumentImageRect(left: 0, top: 0, width: 0.9, height: 0.95).coversPage(),
      isTrue,
    );
    expect(
      DocumentImageRect(left: 0, top: 0, width: 0.9, height: 0.4).coversPage(),
      isFalse,
    );
  });

  test('sourceLabel описывает страницу и происхождение', () {
    expect(image().sourceLabel, 'стр. 3, область скана');
    expect(
      image()
          .withSectionIndex(0)
          .withId('img1')
          .withContext(context: null)
          .sourceLabel,
      'стр. 3, область скана',
    );
    DocumentImage withSource(DocumentImageSource source) => DocumentImage(
      fileName: 'лекция.pdf',
      bytes: bytes(),
      mediaType: AttachmentMediaType.png,
      page: 1,
      source: source,
    );
    expect(withSource(DocumentImageSource.embedded).sourceLabel, 'стр. 1');
    expect(
      withSource(DocumentImageSource.renderedPage).sourceLabel,
      'стр. 1, страница скана',
    );
  });

  test('withId/withSectionIndex/withContext сохраняют новые поля', () {
    final DocumentImage copy = image()
        .withId('img7')
        .withSectionIndex(4)
        .withContext(caption: 'Рис. 9', context: 'Другой текст');

    expect(copy.id, 'img7');
    expect(copy.sectionIndex, 4);
    expect(copy.caption, 'Рис. 9');
    expect(copy.context, 'Другой текст');
    expect(copy.page, 3);
    expect(copy.source, DocumentImageSource.croppedRegion);
    expect(copy.order, 2);
    expect(copy.rect!.width, 0.5);
    expect(copy.width, 600);
    expect(copy.height, 400);
    expect(copy.bytes, bytes());
    expect(copy.toString(), contains('source: croppedRegion'));
  });

  test('withContext без аргументов сохраняет прежние значения', () {
    final DocumentImage copy = image().withContext();
    expect(copy.caption, 'Рис. 2 Схема фермы');
    expect(copy.context, 'Раздел о фермах');
  });
}
