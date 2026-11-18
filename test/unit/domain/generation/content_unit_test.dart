import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/text/document_format.dart';

/// TASK 02A: единицы содержимого (раздел E.1 аудита).
///
/// Проверяются стабильные id, связи «раздел ↔ изображение», каталог документа
/// (ни одно изображение не выпадает) и единицы вложений/страниц.
void main() {
  const String fileName = 'lecture.docx';
  const String documentId = 'doc:lecture.docx';
  const String sectionId = 'doc:lecture.docx#1';

  DocumentImage image({
    int sectionIndex = 1,
    int order = 0,
    int? page = 2,
    String? caption,
    String? context,
    DocumentImageRect? rect,
  }) {
    return DocumentImage(
      fileName: fileName,
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      mediaType: AttachmentMediaType.png,
      caption: caption,
      context: context,
      page: page,
      sectionIndex: sectionIndex,
      order: order,
      width: 10,
      height: 10,
      rect: rect,
    );
  }

  ImageRef imageRef({
    int index = 0,
    String? refSectionId = sectionId,
    int imageSectionIndex = 1,
    String? caption,
    String? context,
    int order = 0,
    int tokens = 1000,
    DocumentImageRect? rect,
  }) {
    return ImageRef(
      id: contentImageId(fileName, index),
      image: image(
        sectionIndex: imageSectionIndex,
        order: order,
        caption: caption,
        context: context,
        rect: rect,
      ),
      sectionId: refSectionId,
      tokens: tokens,
    );
  }

  TextPiece paragraph({
    required String id,
    required int order,
    required String text,
    required int start,
    required int tokens,
  }) {
    return TextPiece(
      id: id,
      kind: TextPieceKind.paragraph,
      order: order,
      text: text,
      start: start,
      end: start + text.length,
      tokens: tokens,
    );
  }

  group('Стабильные идентификаторы', () {
    test('document/section/piece/image/attachment/page', () {
      expect(contentDocumentId('a.docx'), 'doc:a.docx');
      expect(contentSectionId(documentId, 2), 'doc:lecture.docx#2');
      expect(
        contentTextPieceId('doc:lecture.docx#2', 3),
        'doc:lecture.docx#2#3',
      );
      expect(contentImageId('a.docx', 1), 'img:a.docx#1');
      expect(
        contentAttachmentId('scan.pdf', groupKey: 'scan.pdf#g'),
        'att:scan.pdf#g',
      );
      expect(contentAttachmentId('photo.png'), 'att:photo.png');
      expect(contentPageId('att:scan.pdf', 2), 'att:scan.pdf#p2');
      expect(contentPageId('att:photo.png', null), 'att:photo.png');
    });
  });

  group('TextPiece', () {
    test('границы, порядок и токены сохраняются', () {
      final TextPiece piece = paragraph(
        id: contentTextPieceId(sectionId, 0),
        order: 0,
        text: 'Абзац один.',
        start: 0,
        tokens: 4,
      );
      expect(piece.id, 'doc:lecture.docx#1#0');
      expect(piece.kind, TextPieceKind.paragraph);
      expect(piece.order, 0);
      expect(piece.text, 'Абзац один.');
      expect(piece.start, 0);
      expect(piece.end, 11);
      expect(piece.length, 11);
      expect(piece.tokens, 4);
    });

    test('отрицательные токены/смещения — ошибка программиста', () {
      expect(
        () => TextPiece(
          id: 'doc:a#0#0',
          kind: TextPieceKind.line,
          order: 0,
          text: 'x',
          start: -1,
          end: 1,
          tokens: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => TextPiece(
          id: 'doc:a#0#0',
          kind: TextPieceKind.line,
          order: 0,
          text: 'x',
          start: 0,
          end: 1,
          tokens: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ImageRef', () {
    test('строится поверх DocumentImage без изменения сущности', () {
      final ImageRef ref = imageRef(
        caption: 'Рис. 3. Схема',
        context: 'Абзац с рисунком',
        order: 2,
        rect: DocumentImageRect(left: 0.1, top: 0.2, width: 0.3, height: 0.4),
      );
      expect(ref.id, 'img:lecture.docx#0');
      expect(ref.documentId, fileName);
      expect(ref.sectionId, sectionId);
      expect(ref.sectionIndex, 1);
      expect(ref.page, 2);
      expect(ref.order, 2);
      expect(ref.caption, 'Рис. 3. Схема');
      expect(ref.context, 'Абзац с рисунком');
      expect(ref.rect, isNotNull);
      expect(ref.image.bytes, hasLength(4));
      expect(ref.isOrphan, isFalse);
      expect(ref.tokens, 1000);
    });

    test('изображение без раздела помечается orphan', () {
      final ImageRef ref = imageRef(index: 3, refSectionId: null);
      expect(ref.isOrphan, isTrue);
      expect(ref.sectionId, isNull);

      final OrphanImageUnit orphan = OrphanImageUnit(image: ref);
      expect(orphan.id, 'img:lecture.docx#3');
      expect(orphan.fileName, fileName);
    });

    test('orphan-единица требует изображение без раздела', () {
      expect(
        () => OrphanImageUnit(image: imageRef()),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('DocumentUnit и каталог', () {
    test('разделы сохраняют порядок, каталог собирает их изображения', () {
      final ImageRef first = imageRef(index: 0);
      final ImageRef second = imageRef(
        index: 1,
        refSectionId: 'doc:lecture.docx#2',
        imageSectionIndex: 2,
        order: 1,
      );
      final SectionUnit sectionOne = SectionUnit(
        id: sectionId,
        index: 1,
        title: 'Введение',
        text: 'Абзац один.',
        tokens: 4,
        pieces: <TextPiece>[
          paragraph(
            id: contentTextPieceId(sectionId, 0),
            order: 0,
            text: 'Абзац один.',
            start: 0,
            tokens: 4,
          ),
        ],
        images: <ImageRef>[first],
      );
      final SectionUnit sectionTwo = SectionUnit(
        id: 'doc:lecture.docx#2',
        index: 2,
        text: 'Абзац два.',
        tokens: 4,
        images: <ImageRef>[second],
      );
      final DocumentUnit document = DocumentUnit(
        id: documentId,
        fileName: fileName,
        format: DocumentFormat.docx,
        pageCount: 3,
        sections: <SectionUnit>[sectionOne, sectionTwo],
      );

      expect(document.sections.map((SectionUnit s) => s.index), <int>[1, 2]);
      expect(document.sectionByIndex(2)?.text, 'Абзац два.');
      expect(document.sectionByIndex(3), isNull);
      expect(document.catalog.documentId, documentId);
      expect(document.catalog.images.map((ImageRef ref) => ref.id), <String>[
        'img:lecture.docx#0',
        'img:lecture.docx#1',
      ]);
      expect(document.catalog.imageById('img:lecture.docx#1'), isNotNull);
      expect(document.catalog.imageById('img:lecture.docx#9'), isNull);
      expect(document.pageCount, 3);
      expect(document.images, hasLength(2));
    });

    test(
      'внешний каталог объединяется с изображениями разделов без дублей',
      () {
        final ImageRef sectionImage = imageRef(index: 0);
        final ImageRef catalogOnly = imageRef(index: 9, refSectionId: null);
        final DocumentUnit document = DocumentUnit(
          id: documentId,
          fileName: fileName,
          format: DocumentFormat.docx,
          sections: <SectionUnit>[
            SectionUnit(
              id: sectionId,
              index: 1,
              text: 'Текст',
              tokens: 1,
              images: <ImageRef>[sectionImage],
            ),
          ],
          catalog: DocumentCatalog(
            documentId: documentId,
            images: <ImageRef>[catalogOnly, sectionImage],
          ),
        );
        expect(document.catalog.images, hasLength(2));
        expect(
          document.catalog.images.map((ImageRef ref) => ref.id),
          containsAll(<String>['img:lecture.docx#0', 'img:lecture.docx#9']),
        );
      },
    );

    test('каталог другого документа — ошибка программиста', () {
      expect(
        () => DocumentUnit(
          id: documentId,
          fileName: fileName,
          format: DocumentFormat.docx,
          catalog: DocumentCatalog(documentId: 'doc:other.docx'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('списки разделов и частей неизменяемы', () {
      final SectionUnit section = SectionUnit(
        id: sectionId,
        index: 1,
        text: 'Текст',
        tokens: 1,
      );
      expect(
        () => section.pieces.add(
          paragraph(id: 'doc:a#0#0', order: 0, text: 'x', start: 0, tokens: 1),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('AttachmentUnit', () {
    test('страницы сохраняют порядок, id и суммарные оценки', () {
      final PageUnit pageOne = PageUnit(
        id: contentPageId('att:scan.pdf', 1),
        pageNumber: 1,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        tokens: 700,
      );
      final PageUnit pageTwo = PageUnit(
        id: contentPageId('att:scan.pdf', 2),
        pageNumber: 2,
        bytes: Uint8List.fromList(<int>[4, 5]),
        tokens: 800,
      );
      final AttachmentUnit attachment = AttachmentUnit(
        id: contentAttachmentId('scan.pdf', groupKey: 'scan.pdf#g'),
        fileName: 'scan.pdf',
        mediaType: AttachmentMediaType.pdf,
        groupKey: 'scan.pdf#g',
        pages: <PageUnit>[pageOne, pageTwo],
      );
      expect(attachment.id, 'att:scan.pdf#g');
      expect(attachment.mediaType, AttachmentMediaType.pdf);
      expect(attachment.groupKey, 'scan.pdf#g');
      expect(attachment.pages.map((PageUnit p) => p.pageNumber), <int>[1, 2]);
      expect(attachment.totalTokens, 1500);
      expect(attachment.byteLength, 5);
      expect(attachment.pageByNumber(2)?.id, 'att:scan.pdf#p2');
      expect(attachment.pageByNumber(3), isNull);
      expect(() => attachment.pages.add(pageOne), throwsUnsupportedError);
    });

    test('страница без номера допустима (одиночное изображение)', () {
      final PageUnit page = PageUnit(
        id: contentAttachmentId('photo.png'),
        bytes: Uint8List.fromList(<int>[1]),
        tokens: 10,
      );
      expect(page.pageNumber, isNull);
    });
  });

  group('ContentInventory', () {
    test('пустой перечень', () {
      expect(ContentInventory.empty.isEmpty, isTrue);
      expect(ContentInventory.empty.imageCount, 0);
      expect(ContentInventory.empty.allImages, isEmpty);
      expect(ContentInventory.empty.imageById('img:x#0'), isNull);
    });

    test('изображения документов и orphan-единиц не теряются', () {
      final ImageRef sectionImage = imageRef(index: 0);
      final ImageRef orphanImage = imageRef(index: 5, refSectionId: null);
      final DocumentUnit document = DocumentUnit(
        id: documentId,
        fileName: fileName,
        format: DocumentFormat.pdf,
        sections: <SectionUnit>[
          SectionUnit(
            id: sectionId,
            index: 1,
            text: 'Текст',
            tokens: 1,
            images: <ImageRef>[sectionImage],
          ),
        ],
      );
      final ContentInventory inventory = ContentInventory(
        documents: <DocumentUnit>[document],
        orphanImages: <OrphanImageUnit>[OrphanImageUnit(image: orphanImage)],
      );
      expect(inventory.isEmpty, isFalse);
      expect(inventory.imageCount, 2);
      expect(inventory.allImages.map((ImageRef ref) => ref.id), <String>[
        'img:lecture.docx#0',
        'img:lecture.docx#5',
      ]);
      expect(inventory.imageById('img:lecture.docx#5'), same(orphanImage));
    });
  });

  group('PageRange', () {
    test('длина диапазона и валидация', () {
      const PageRange range = PageRange(firstPage: 2, lastPage: 4);
      expect(range.length, 3);
      expect(
        () => PageRange(firstPage: 0, lastPage: 2),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PageRange(firstPage: 3, lastPage: 2),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('Диагностика единиц (toString)', () {
    test('toString описывает ids, типы и размеры', () {
      final TextPiece piece = paragraph(
        id: contentTextPieceId(sectionId, 0),
        order: 0,
        text: 'Абзац один.',
        start: 0,
        tokens: 4,
      );
      expect(piece.toString(), contains('doc:lecture.docx#1#0'));

      final ImageRef ref = imageRef();
      expect(ref.toString(), contains('img:lecture.docx#0'));

      final SectionUnit section = SectionUnit(
        id: sectionId,
        index: 1,
        text: 'Текст',
        tokens: 1,
        pieces: <TextPiece>[piece],
        images: <ImageRef>[ref],
      );
      expect(section.toString(), contains(sectionId));

      final DocumentUnit document = DocumentUnit(
        id: documentId,
        fileName: fileName,
        format: DocumentFormat.docx,
        sections: <SectionUnit>[section],
      );
      expect(document.toString(), contains('docx'));
      expect(document.catalog.isEmpty, isFalse);
      expect(document.catalog.toString(), contains(documentId));

      final DocumentCatalog emptyCatalog = DocumentCatalog(
        documentId: documentId,
      );
      expect(emptyCatalog.isEmpty, isTrue);

      final PageUnit page = PageUnit(
        id: contentPageId('att:scan.pdf', 1),
        pageNumber: 1,
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        tokens: 1,
      );
      expect(page.toString(), contains('4 байт'));

      final AttachmentUnit attachment = AttachmentUnit(
        id: 'att:scan.pdf',
        fileName: 'scan.pdf',
        mediaType: AttachmentMediaType.pdf,
        pages: <PageUnit>[page],
      );
      expect(attachment.toString(), contains('att:scan.pdf'));

      final OrphanImageUnit orphan = OrphanImageUnit(
        image: imageRef(index: 4, refSectionId: null),
      );
      expect(orphan.toString(), contains('img:lecture.docx#4'));

      final ContentInventory inventory = ContentInventory(
        documents: <DocumentUnit>[document],
        orphanImages: <OrphanImageUnit>[orphan],
      );
      expect(inventory.toString(), contains('documents: 1'));

      const PageRange range = PageRange(firstPage: 2, lastPage: 4);
      expect(range.toString(), contains('2..4'));
    });
  });
}
