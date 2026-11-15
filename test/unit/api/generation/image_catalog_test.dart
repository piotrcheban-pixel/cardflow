import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_images.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Каталог `<images>` для модели (fix-gen, Д3).
void main() {
  DocumentImage image({
    String id = '',
    String fileName = 'лекция.docx',
    String? caption,
    String? context,
  }) {
    return DocumentImage(
      id: id,
      fileName: fileName,
      bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
      mediaType: AttachmentMediaType.png,
      caption: caption,
      context: context,
    );
  }

  test('идентификаторы каталога img1…imgN назначаются по порядку', () {
    final images = withCatalogIds(<DocumentImage>[
      image(fileName: 'a.docx'),
      image(fileName: 'b.docx'),
    ]);
    expect(images.map((DocumentImage image) => image.id), <String>[
      'img1',
      'img2',
    ]);
  });

  test('строка каталога: id | файл | подпись | окружающий текст', () {
    final line = imageCatalogLine(
      image(id: 'img1', caption: 'Рис. 1', context: 'Две силы уравновешены'),
    );
    expect(line, 'img1 | лекция.docx | Рис. 1 | Две силы уравновешены');
  });

  test('пустые подпись и текст остаются пустыми полями', () {
    final line = imageCatalogLine(image(id: 'img2'));
    expect(line, 'img2 | лекция.docx |  | ');
  });

  test('разделитель | в подписи заменяется, переводы строк схлопываются', () {
    final line = imageCatalogLine(
      image(
        id: 'img3',
        caption: 'Рис. 2 | схема',
        context: 'Первая строка\nвторая строка',
      ),
    );
    expect(line, contains('Рис. 2 / схема'));
    expect(line, contains('Первая строка вторая строка'));
    expect(line.split(' | '), hasLength(4));
  });

  test('длинный окружающий текст обрезается', () {
    final line = imageCatalogLine(image(id: 'img4', context: 'а' * 400));
    expect(line.length, lessThan(260));
    expect(line, contains('…'));
  });

  test('каталог — по строке на изображение', () {
    final catalog = buildImageCatalog(<DocumentImage>[
      image(id: 'img1'),
      image(id: 'img2', caption: 'Рис. 2'),
    ]);
    expect(catalog.split('\n'), hasLength(2));
    expect(catalog, startsWith('img1 | лекция.docx'));
  });
}
