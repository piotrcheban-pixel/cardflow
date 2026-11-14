/// Файловый шлюз генерации через `file_picker` 13.3.3 (SPEC A6.8, A8.3).
library;

import 'dart:typed_data';

import 'package:cardflow/domain/generation/document_gateway.dart';

/// Реализация [DocumentGateway] на `file_picker` и `dart:io`.
class FilePickerDocumentGateway implements DocumentGateway {
  /// Создаёт шлюз.
  const FilePickerDocumentGateway();

  @override
  int get maxFileBytes => 25 * 1024 * 1024;

  @override
  Future<List<PickedDocument>> pickDocuments() {
    throw UnimplementedError('FilePickerDocumentGateway.pickDocuments');
  }

  @override
  Future<Uint8List> readDocument(PickedDocument document) {
    throw UnimplementedError('FilePickerDocumentGateway.readDocument');
  }
}
