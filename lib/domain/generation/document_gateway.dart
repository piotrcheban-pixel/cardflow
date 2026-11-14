/// Шлюз прикрепления и чтения документов (SPEC A6.8, A8.3).
///
/// Домен не зависит от Flutter и file_picker: реализация — в `lib/data/`.
library;

import 'dart:typed_data';

/// Файл, выбранный пользователем (или перетащенный на ПК).
class PickedDocument {
  /// Создаёт описание файла.
  const PickedDocument({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.preloadedBytes,
  });

  /// Путь к файлу на диске (для `content://`/веба — синтетический `memory://`).
  final String path;

  /// Имя файла с расширением.
  final String name;

  /// Размер файла в байтах.
  final int sizeBytes;

  /// Байты, уже прочитанные пикером (платформы без локального пути).
  ///
  /// `null` — читать по [path] через [DocumentGateway.readDocument].
  final Uint8List? preloadedBytes;
}

/// Контракт файлового шлюза генерации.
abstract interface class DocumentGateway {
  /// Максимальный размер читаемого файла в байтах (SPEC A8.3: 25 МБ).
  int get maxFileBytes;

  /// Открывает системный пикер с множественным выбором; пустой список — отмена.
  Future<List<PickedDocument>> pickDocuments();

  /// Читает файл в память с проверкой [maxFileBytes] до чтения.
  Future<Uint8List> readDocument(PickedDocument document);
}
