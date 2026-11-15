import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/api/parsers/document_images.dart';
import 'package:cardflow/api/parsers/odt_parser.dart';
import 'package:cardflow/api/parsers/pptx_parser.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import 'fixtures/document_fixtures.dart';

/// Извлечение изображений из документов с контекстом (fix-gen, Д3).
void main() {
  test(
    'DOCX: изображение из word/media с подписью, абзацем и разделом',
    () async {
      final Uint8List bytes = buildDocxWithImage(
        paragraphs: <String>['Статика', 'Две силы уравновешены.'],
        imageBytes: pngFixture(),
        caption: 'Рис. 1. Тело под действием двух сил',
      );
      final ParsedDocument document = await const DocxParser().parse(
        bytes,
        fileName: 'статика.docx',
      );

      expect(document.images, hasLength(1));
      final DocumentImage image = document.images.single;
      expect(image.fileName, 'статика.docx');
      expect(image.mediaType.name, 'png');
      expect(image.caption, contains('Рис. 1'));
      expect(image.width, 200);
      expect(image.height, 150);
      expect(image.sectionIndex, 0);
    },
  );

  test('DOCX: мусор меньше порога не извлекается', () async {
    // 40×40 PNG: иконка, а не иллюстрация.
    final Uint8List bytes = buildDocxWithImage(
      paragraphs: <String>['Текст'],
      imageBytes: pngFixture(width: 40, height: 40, seed: 3),
    );
    final ParsedDocument document = await const DocxParser().parse(
      bytes,
      fileName: 'иконки.docx',
    );
    expect(document.images, isEmpty);
  });

  test('DOCX: повтор того же изображения отбрасывается по хешу', () async {
    final List<int> picture = pngFixture(seed: 11);
    final Uint8List bytes = buildDocxWithImage(
      paragraphs: <String>['Первый абзац'],
      imageBytes: picture,
    );
    // Второй рисунок с тем же содержимым — отдельная связь/запись.
    final Uint8List doubled = buildDocxWithImage(
      paragraphs: <String>['Первый абзац', 'Второй абзац'],
      imageBytes: picture,
      caption: 'Рис. 2. Копия',
    );
    final ParsedDocument document = await const DocxParser().parse(
      doubled,
      fileName: 'копии.docx',
    );
    expect(document.images, hasLength(1));
    expect(bytes, isNotEmpty);
  });

  test('PPTX: изображение слайда с номером слайда и заголовком', () async {
    final Uint8List bytes = buildPptxWithImage(
      slideTexts: <List<String>>[
        <String>['Фермы', 'Стержни и узлы'],
        <String>['Вывод'],
      ],
      imageBytes: pngFixture(seed: 5),
    );
    final ParsedDocument document = await const PptxParser().parse(
      bytes,
      fileName: 'фермы.pptx',
    );

    expect(document.images, hasLength(1));
    final DocumentImage image = document.images.single;
    expect(image.page, 1);
    expect(image.context, contains('Фермы'));
    expect(image.sectionIndex, 0);
  });

  test('ODT: изображение из Pictures/ с соседним текстом', () async {
    final Uint8List bytes = buildOdtWithImage(
      blocks: <({String text, bool heading})>[
        (text: 'Аксиомы статики', heading: true),
        (text: 'Связи и реакции связей', heading: false),
      ],
      imageBytes: pngFixture(seed: 9),
      caption: 'Рис. 3. Связь в виде стержня',
    );
    final ParsedDocument document = await const OdtParser().parse(
      bytes,
      fileName: 'аксиомы.odt',
    );

    expect(document.images, hasLength(1));
    final DocumentImage image = document.images.single;
    expect(image.caption, contains('Рис. 3'));
    expect(image.context, isNotNull);
  });

  test('documentImageMediaType: поддержаны JPEG/PNG, прочее — null', () {
    expect(documentImageMediaType('word/media/a.png')?.name, 'png');
    expect(documentImageMediaType('word/media/a.JPG')?.name, 'jpeg');
    expect(documentImageMediaType('word/media/a.emf'), isNull);
    expect(documentImageMediaType('word/media/a.svg'), isNull);
  });

  test('imagePixelSize: PNG и JPEG читаются по заголовку', () {
    final Uint8List png = pngFixture(width: 120, height: 80, seed: 2);
    final ({int width, int height})? size = imagePixelSize(png);
    expect(size, isNotNull);
    expect(size!.width, 120);
    expect(size.height, 80);
  });

  test('imagePixelSize: JPEG SOF0 — размеры 200×100', () {
    final Uint8List jpeg = jpegFixture(width: 200, height: 100);
    final ({int width, int height})? size = imagePixelSize(jpeg);
    expect(size, isNotNull);
    expect(size!.width, 200);
    expect(size.height, 100);
  });

  test('коллектор принимает JPEG и отбрасывает неверную сигнатуру', () {
    final DocumentImageCollector collector = DocumentImageCollector();
    final DocumentImage? jpeg = collector.add(
      entryName: 'word/media/image1.jpg',
      bytes: jpegFixture(width: 200, height: 100),
      fileName: 'док.docx',
      sectionIndex: 0,
      context: 'Схема',
    );
    expect(jpeg, isNotNull);
    expect(jpeg!.mediaType.name, 'jpeg');

    final DocumentImageCollector second = DocumentImageCollector();
    final Uint8List broken = Uint8List.fromList(<int>[
      0x00,
      0x01,
      ...List<int>.filled(5000, 0),
    ]);
    expect(
      second.add(
        entryName: 'word/media/image2.png',
        bytes: broken,
        fileName: 'док.docx',
        sectionIndex: 0,
      ),
      isNull,
    );
  });

  test('looksLikeImageCaption: «Рис. N», «Figure N», прочее — нет', () {
    expect(looksLikeImageCaption('Рис. 4. Схема'), isTrue);
    expect(looksLikeImageCaption('Рисунок 2 — график'), isTrue);
    expect(looksLikeImageCaption('Figure 3: cell'), isTrue);
    expect(looksLikeImageCaption('Формула момента силы'), isFalse);
  });
}
