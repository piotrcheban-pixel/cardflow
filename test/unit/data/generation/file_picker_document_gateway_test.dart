import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/generation/file_picker_document_gateway.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parser_exception.dart';

/// Файловый шлюз генерации: фильтр форматов и лимит 25 МБ до чтения.
void main() {
  test('фильтр пикера содержит все форматы A8.3, включая .doc/.xls', () {
    final extensions = generationDocumentExtensions;
    for (final DocumentFormat format in DocumentFormat.values) {
      expect(extensions, contains(format.extension));
    }
  });

  test('readDocument читает локальный файл', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'cardflow_doc_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final File file = File('${directory.path}/lecture.txt')
      ..writeAsStringSync('Материал');
    const gateway = FilePickerDocumentGateway();

    final bytes = await gateway.readDocument(
      PickedDocument(
        path: file.path,
        name: 'lecture.txt',
        sizeBytes: file.lengthSync(),
      ),
    );

    expect(bytes, isNotEmpty);
  });

  test('readDocument отклоняет файл больше лимита без чтения', () async {
    const gateway = FilePickerDocumentGateway(maxFileBytes: 10);
    await expectLater(
      gateway.readDocument(
        const PickedDocument(
          path: '/tmp/too-big.txt',
          name: 'too-big.txt',
          sizeBytes: 11,
        ),
      ),
      throwsA(
        isA<ParserException>().having(
          (error) => error.code,
          'code',
          ParserErrorCode.fileTooLarge,
        ),
      ),
    );
  });

  test('readDocument без локального пути и байтов — unreadableFile', () async {
    const gateway = FilePickerDocumentGateway();
    await expectLater(
      gateway.readDocument(
        const PickedDocument(
          path: 'memory://нет',
          name: 'нет.txt',
          sizeBytes: 1,
        ),
      ),
      throwsA(
        isA<ParserException>().having(
          (error) => error.code,
          'code',
          ParserErrorCode.unreadableFile,
        ),
      ),
    );
  });

  test('preloadedBytes возвращаются без обращения к диску', () async {
    const gateway = FilePickerDocumentGateway();
    final bytes = await gateway.readDocument(
      PickedDocument(
        path: 'memory://из-пикера.txt',
        name: 'из-пикера.txt',
        sizeBytes: 3,
        preloadedBytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );
    expect(bytes, <int>[1, 2, 3]);
  });
}
