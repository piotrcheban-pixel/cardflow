/// Файловый шлюз генерации через `file_picker` 13.3.3 (SPEC A6.8, A8.3).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parser_exception.dart';

/// Фильтр форматов A8.3 в пикере (включая `.doc`/`.xls` — для понятной
/// ошибки «формат не поддерживается», ADR-003).
List<String> get generationDocumentExtensions => <String>[
  for (final DocumentFormat format in DocumentFormat.values) format.extension,
];

/// Реализация [DocumentGateway] на `file_picker` и `dart:io`.
class FilePickerDocumentGateway implements DocumentGateway {
  /// Создаёт шлюз.
  ///
  /// [maxFileBytes] — лимит размера файла (SPEC A8.3: 25 МБ); больше — ошибка
  /// до чтения в память.
  const FilePickerDocumentGateway({this.maxFileBytes = 25 * 1024 * 1024});

  @override
  final int maxFileBytes;

  @override
  Future<List<PickedDocument>> pickDocuments() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: generationDocumentExtensions,
    );
    final List<PickedDocument> picked = <PickedDocument>[];
    for (final PlatformFile file in files) {
      final int? knownLength = file.lengthSync() ?? await file.length();
      final int size = knownLength ?? 0;
      final String? path = file.path;
      if (path != null) {
        picked.add(
          PickedDocument(path: path, name: file.name, sizeBytes: size),
        );
        continue;
      }
      // content:// (Android/iOS) и веб: локального пути нет. Большой файл не
      // читаем в память — ошибку размера вернёт readDocument/парсинг.
      final Uint8List? bytes = size <= maxFileBytes
          ? await file.readAsBytes()
          : null;
      picked.add(
        PickedDocument(
          path: 'memory://${file.name}',
          name: file.name,
          sizeBytes: size,
          preloadedBytes: bytes,
        ),
      );
    }
    return picked;
  }

  @override
  Future<Uint8List> readDocument(PickedDocument document) async {
    if (document.sizeBytes > maxFileBytes) {
      throw const ParserException(
        ParserErrorCode.fileTooLarge,
        details: 'Файл больше лимита 25 МБ',
      );
    }
    final Uint8List? preloaded = document.preloadedBytes;
    if (preloaded != null) return preloaded;
    if (!document.path.startsWith('memory://')) {
      final File file = File(document.path);
      final int length = await file.length();
      if (length > maxFileBytes) {
        throw const ParserException(
          ParserErrorCode.fileTooLarge,
          details: 'Файл больше лимита 25 МБ',
        );
      }
      return file.readAsBytes();
    }
    throw const ParserException(
      ParserErrorCode.unreadableFile,
      details: 'Нет локального пути и байтов файла',
    );
  }
}
