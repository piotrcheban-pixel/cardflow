/// Файловый шлюз генерации через `file_picker` 13.3.3 (SPEC A6.8, A8.3).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parser_exception.dart';

/// Фильтр форматов A8.3 в пикере (включая `.doc`/`.xls` — для понятной
/// ошибки «формат не поддерживается», ADR-003) и изображения JPG/PNG (7.8).
List<String> get generationDocumentExtensions => <String>[
  for (final DocumentFormat format in DocumentFormat.values) format.extension,
  ...generationImageExtensions,
];

/// Расширения изображений, которые принимает пикер (ADR-022).
const List<String> generationImageExtensions = <String>['jpg', 'jpeg', 'png'];

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
      // content:// (Android/iOS) и веб: локального пути нет. Путь синтетический
      // и уникальный (номер в списке), иначе два разных notes.txt схлопнулись
      // бы в один файл. Большой файл не читаем в память: ошибку размера
      // вернёт readDocument/парсинг.
      final Uint8List? bytes = size <= maxFileBytes
          ? await file.readAsBytes()
          : null;
      final int actualSize = bytes?.length ?? size;
      picked.add(
        PickedDocument(
          path: syntheticMemoryPath(picked.length, file.name),
          name: file.name,
          sizeBytes: actualSize,
          preloadedBytes: actualSize <= maxFileBytes ? bytes : null,
        ),
      );
    }
    return picked;
  }

  @override
  Future<Uint8List> readDocument(PickedDocument document) async {
    final Uint8List? preloaded = document.preloadedBytes;
    if (preloaded != null) {
      if (preloaded.length > maxFileBytes ||
          document.sizeBytes > maxFileBytes) {
        throw const ParserException(
          ParserErrorCode.fileTooLarge,
          details: 'Файл больше лимита 25 МБ',
        );
      }
      return preloaded;
    }
    if (document.sizeBytes > maxFileBytes) {
      throw const ParserException(
        ParserErrorCode.fileTooLarge,
        details: 'Файл больше лимита 25 МБ',
      );
    }
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

/// Синтетический уникальный путь для платформ без локального пути.
String syntheticMemoryPath(int index, String fileName) {
  return 'memory://$index/${Uri.encodeComponent(fileName)}';
}
