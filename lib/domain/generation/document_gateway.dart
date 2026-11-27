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
    this.temporaryPath,
    this.mimeType,
    this.sourceScheme,
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

  /// Локальная временная копия файла, созданная из URI провайдера (TASK 04).
  ///
  /// Android отдаёт `content://`-URI; парсеру (и PDFium) нужен локальный
  /// файл, поэтому байты копируются в каталог приложения
  /// (`getTemporaryDirectory()`), а копия удаляется после разбора
  /// ([DocumentGateway.releaseDocument]).
  final String? temporaryPath;

  /// MIME-тип, который сообщила платформа/провайдер (для диагностики).
  final String? mimeType;

  /// Схема исходного URI (`file`, `content`, `blob`, …) — для диагностики.
  final String? sourceScheme;

  /// Временная копия файла во временном каталоге приложения.
  bool get isTemporaryCopy => temporaryPath != null;
}

/// Контракт файлового шлюза генерации.
abstract interface class DocumentGateway {
  /// Максимальный размер читаемого файла в байтах (SPEC A8.3: 25 МБ).
  int get maxFileBytes;

  /// Открывает системный пикер с множественным выбором; пустой список — отмена.
  Future<List<PickedDocument>> pickDocuments();

  /// Читает файл в память с проверкой [maxFileBytes] до чтения.
  Future<Uint8List> readDocument(PickedDocument document);

  /// Освобождает ресурсы выбранного файла (временная копия URI).
  ///
  /// Ошибки удаления не пробрасываются: импорт уже завершён, а временный
  /// каталог чистится ОС.
  Future<void> releaseDocument(PickedDocument document);
}
