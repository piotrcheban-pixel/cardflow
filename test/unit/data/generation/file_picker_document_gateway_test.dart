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

  test('фильтр пикера содержит изображения JPG/JPEG/PNG (итерация 7.8)', () {
    expect(
      generationDocumentExtensions,
      containsAll(<String>['jpg', 'jpeg', 'png']),
    );
  });

  test('readDocument читает локальный файл', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'cardflow_doc_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final File file = File('${directory.path}/lecture.txt')
      ..writeAsStringSync('Материал');
    final gateway = FilePickerDocumentGateway();

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
    final gateway = FilePickerDocumentGateway(maxFileBytes: 10);
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

  test(
    'readDocument без локального пути и байтов — fileAccessDenied',
    () async {
      final gateway = FilePickerDocumentGateway();
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
            ParserErrorCode.fileAccessDenied,
          ),
        ),
      );
    },
  );

  test('preloadedBytes возвращаются без обращения к диску', () async {
    final gateway = FilePickerDocumentGateway();
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

  test('preloadedBytes больше лимита отклоняются до парсинга', () async {
    final gateway = FilePickerDocumentGateway(maxFileBytes: 2);
    await expectLater(
      gateway.readDocument(
        PickedDocument(
          path: 'memory://большой.txt',
          name: 'большой.txt',
          sizeBytes: 3,
          preloadedBytes: Uint8List.fromList(<int>[1, 2, 3]),
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

  test('синтетические пути платформы без локального пути уникальны', () {
    expect(
      syntheticMemoryPath(0, 'notes.txt'),
      isNot(syntheticMemoryPath(1, 'notes.txt')),
    );
    expect(syntheticMemoryPath(0, 'notes.txt'), contains('notes.txt'));
  });

  group('TASK 04: content:// (Android) → временный файл приложения', () {
    late Directory temp;
    late Directory appTemp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('cardflow_gw_');
      appTemp = Directory.systemTemp.createTempSync('cardflow_apptmp_');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
        if (appTemp.existsSync()) appTemp.deleteSync(recursive: true);
      });
    });

    test(
      'байты content:// материализуются в локальный файл, копия удаляется',
      () async {
        final bytes = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x2D]);
        final gateway = FilePickerDocumentGateway(
          pickFiles: () async => <PickedFileRef>[
            _FakeRef(
              name: 'лекция.pdf',
              uri: Uri.parse('content://com.android.providers/document/1'),
              bytes: bytes,
            ),
          ],
          temporaryDirectory: () async => appTemp,
        );

        final List<PickedDocument> picked = await gateway.pickDocuments();
        expect(picked, hasLength(1));
        final PickedDocument document = picked.single;
        expect(document.isTemporaryCopy, isTrue);
        expect(document.temporaryPath, isNotNull);
        expect(File(document.temporaryPath!).existsSync(), isTrue);
        expect(document.sourceScheme, 'content');

        final Uint8List read = await gateway.readDocument(document);
        expect(read, bytes);

        await gateway.releaseDocument(document);
        expect(File(document.temporaryPath!).existsSync(), isFalse);
      },
    );

    test('файл без локального пути и без каталога — байты из памяти', () async {
      final gateway = FilePickerDocumentGateway(
        pickFiles: () async => <PickedFileRef>[
          _FakeRef(
            name: 'заметки.md',
            uri: Uri.parse('content://provider/2'),
            bytes: Uint8List.fromList(<int>[0x23, 0x20]),
          ),
        ],
        temporaryDirectory: () async => null,
      );

      final PickedDocument document = (await gateway.pickDocuments()).single;
      expect(document.isTemporaryCopy, isFalse);
      expect(document.path, startsWith('memory://'));
      expect(await gateway.readDocument(document), <int>[0x23, 0x20]);
    });

    test(
      'нечитаемый URI одного файла не отменяет остальные (TASK 04)',
      () async {
        final File valid = File('${temp.path}/конспект.txt')
          ..writeAsStringSync('Текст');
        final gateway = FilePickerDocumentGateway(
          pickFiles: () async => <PickedFileRef>[
            _FakeRef(
              name: 'закрыт.pdf',
              uri: Uri.parse('content://provider/3'),
              throwOnRead: true,
            ),
            _FakeRef(name: 'конспект.txt', uri: valid.uri),
          ],
          temporaryDirectory: () async => appTemp,
        );

        final List<PickedDocument> picked = await gateway.pickDocuments();
        expect(picked, hasLength(1));
        expect(picked.single.name, 'конспект.txt');
        expect(await gateway.readDocument(picked.single), isNotEmpty);
      },
    );

    test(
      'если не читается ни один — fileAccessDenied, а не пустой выбор',
      () async {
        final gateway = FilePickerDocumentGateway(
          pickFiles: () async => <PickedFileRef>[
            _FakeRef(
              name: 'закрыт.pdf',
              uri: Uri.parse('content://provider/4'),
              throwOnRead: true,
            ),
          ],
        );

        await expectLater(
          gateway.pickDocuments(),
          throwsA(
            isA<ParserException>().having(
              (error) => error.code,
              'code',
              ParserErrorCode.fileAccessDenied,
            ),
          ),
        );
      },
    );

    test(
      'большой content:// не читается в память до проверки лимита',
      () async {
        final ref = _FakeRef(
          name: 'огромный.pdf',
          uri: Uri.parse('content://provider/5'),
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          knownSize: 11,
        );
        final gateway = FilePickerDocumentGateway(
          maxFileBytes: 10,
          pickFiles: () async => <PickedFileRef>[ref],
          temporaryDirectory: () async => appTemp,
        );

        final PickedDocument document = (await gateway.pickDocuments()).single;
        expect(ref.reads, 0, reason: 'Файл сверх лимита не читается в память');
        await expectLater(
          gateway.readDocument(document),
          throwsA(
            isA<ParserException>().having(
              (error) => error.code,
              'code',
              ParserErrorCode.fileTooLarge,
            ),
          ),
        );
      },
    );

    test(
      'пикер с .ppt/.doc попадает в ошибки парсинга, а не в молчание',
      () async {
        expect(
          generationDocumentExtensions,
          containsAll(<String>['ppt', 'doc']),
        );
        expect(
          generationDocumentExtensions,
          containsAll(<String>['pptx', 'docx']),
        );
      },
    );
  });
}

/// Поддельный выбранный файл: URI, байты и журнал чтений.
class _FakeRef implements PickedFileRef {
  _FakeRef({
    required this.name,
    required this.uri,
    this.bytes,
    this.knownSize,
    this.throwOnRead = false,
  });

  @override
  final String name;

  @override
  final Uri uri;

  final Uint8List? bytes;

  @override
  final int? knownSize;

  final bool throwOnRead;

  /// Сколько раз реально читали байты.
  int reads = 0;

  @override
  String? get mimeType => null;

  @override
  Future<Uint8List> readBytes() async {
    reads++;
    if (throwOnRead) throw StateError('content:// недоступен');
    return bytes ?? Uint8List(0);
  }
}
