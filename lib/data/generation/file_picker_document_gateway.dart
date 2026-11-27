/// Файловый шлюз генерации через `file_picker` 13.3.3 (SPEC A6.8, A8.3).
///
/// TASK 04 (импорт файлов на Android). Проверено по исходникам плагина
/// (`android_file_picker 2.1.5`, `FileUtils.openFileStream`): выбранный файл
/// **копируется** в кэш приложения, и `PlatformFile.path` указывает на эту
/// копию, а `content://`-URI остаётся только в `identifier`. Поэтому «pdfrx
/// не умеет `content://`» само по себе PDF не ломало — но приложение обязано
/// быть устойчивым к платформам/провайдерам, которые локального пути не дают
/// (веб, оболочки, будущие версии плагина). Здесь:
///
/// * `content://` (и любой не-`file` URI) читается в байты и **материализуется
///   во временный файл** приложения (`getTemporaryDirectory()`), чтобы парсер
///   получил локальный путь (требование TASK 04, часть 2);
/// * ошибка одного файла не отменяет остальные; полный отказ доступа — явный
///   `ParserErrorCode.fileAccessDenied`, а не общее «не удалось прочитать»;
/// * временная копия удаляется после разбора (`releaseDocument`).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:cardflow/api/parsers/parser_diagnostics.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parser_exception.dart';

/// Фильтр форматов A8.3 в пикере (включая `.doc`/`.ppt`/`.xls` — для понятной
/// ошибки «формат не поддерживается», ADR-003/ADR-049) и изображения JPG/PNG.
List<String> get generationDocumentExtensions => <String>[
  for (final DocumentFormat format in DocumentFormat.values) format.extension,
  ...generationImageExtensions,
];

/// Расширения изображений, которые принимает пикер (ADR-022).
const List<String> generationImageExtensions = <String>['jpg', 'jpeg', 'png'];

/// Файл, как его отдал системный пикер (без привязки к `file_picker`).
///
/// Абстракция нужна тестам: `PlatformFile` объявлен `base class`, поэтому
/// подделать его снаружи пакета нельзя, а поведение shim'а (URI без локального
/// пути) проверить нужно.
abstract interface class PickedFileRef {
  /// Имя файла с расширением.
  String get name;

  /// URI файла (`file://`, `content://`, `blob:` …).
  Uri get uri;

  /// Размер, если платформа сообщила его без чтения.
  int? get knownSize;

  /// MIME-тип, если платформа сообщила.
  String? get mimeType;

  /// Читает содержимое файла.
  Future<Uint8List> readBytes();
}

/// Открывает системный пикер и возвращает выбранные файлы.
typedef PickFilesCallback = Future<List<PickedFileRef>> Function();

/// Каталог временных файлов приложения (production — `path_provider`).
typedef TemporaryDirectoryProvider = Future<Directory?> Function();

/// Реализация [DocumentGateway] на `file_picker` и `dart:io`.
class FilePickerDocumentGateway implements DocumentGateway {
  /// Создаёт шлюз.
  ///
  /// [maxFileBytes] — лимит размера файла (SPEC A8.3: 25 МБ); больше — ошибка
  /// до чтения в память.
  ///
  /// [pickFiles], [temporaryDirectory], [diagnostics] инжектируются в тестах;
  /// значения по умолчанию — реальный `file_picker`, `path_provider` и
  /// debug-диагностика.
  FilePickerDocumentGateway({
    this.maxFileBytes = 25 * 1024 * 1024,
    this.pickFiles,
    this.temporaryDirectory,
    this.diagnostics = const ParserDiagnostics(),
  });

  @override
  final int maxFileBytes;

  /// Открытие системного пикера (подмена в тестах).
  final PickFilesCallback? pickFiles;

  /// Каталог временных файлов приложения (подмена в тестах).
  final TemporaryDirectoryProvider? temporaryDirectory;

  /// Debug-диагностика импорта (TASK 04, часть 8).
  final ParserDiagnostics diagnostics;

  /// Сколько раз подряд могли не прочитать URI (для сообщения об ошибке).
  static const String _temporarySubdirectory = 'cardflow-import';

  @override
  Future<List<PickedDocument>> pickDocuments() async {
    final List<PickedFileRef> files = await _pick();
    final List<PickedDocument> picked = <PickedDocument>[];
    for (final PickedFileRef file in files) {
      final PickedDocument? resolved = await _resolve(file, picked.length);
      if (resolved != null) picked.add(resolved);
    }
    if (files.isNotEmpty && picked.isEmpty) {
      // Ни один файл не удалось даже прочитать: это не «пустой выбор», а
      // недоступный URI — сообщаем отдельным кодом (TASK 04).
      throw const ParserException(
        ParserErrorCode.fileAccessDenied,
        details: 'Ни один выбранный файл не читается: нет локального пути',
      );
    }
    return picked;
  }

  Future<List<PickedFileRef>> _pick() {
    final PickFilesCallback? injected = pickFiles;
    if (injected != null) return injected();
    return _pickWithFilePicker();
  }

  /// Один выбранный файл → [PickedDocument]; `null` — файл пропущен.
  Future<PickedDocument?> _resolve(PickedFileRef file, int index) async {
    final String? localPath = file.uri.scheme == 'file'
        ? file.uri.toFilePath()
        : null;
    final int size = file.knownSize ?? 0;
    if (localPath != null) {
      diagnostics.picked(
        fileName: file.name,
        source: 'file',
        sizeBytes: size,
        mimeType: file.mimeType,
      );
      return PickedDocument(
        path: localPath,
        name: file.name,
        sizeBytes: size,
        mimeType: file.mimeType,
        sourceScheme: file.uri.scheme,
      );
    }
    // Платформа без локального пути: читаем байты сами. Большой файл в
    // память не тянем — ошибку размера вернёт readDocument/парсинг.
    Uint8List? bytes;
    if (size <= maxFileBytes) {
      try {
        bytes = await file.readBytes();
      } on Object catch (error) {
        diagnostics.unavailable(
          fileName: file.name,
          reason:
              '${file.uri.scheme}-URI не читается '
              '(${error.runtimeType})',
        );
        return null;
      }
    }
    final int actualSize = bytes?.length ?? size;
    final String? temporaryPath = bytes == null
        ? null
        : await _materialize(file.name, bytes, index);
    diagnostics.picked(
      fileName: file.name,
      source: temporaryPath == null ? 'memory' : 'content',
      sizeBytes: actualSize,
      mimeType: file.mimeType,
    );
    return PickedDocument(
      path: temporaryPath ?? syntheticMemoryPath(index, file.name),
      name: file.name,
      sizeBytes: actualSize,
      preloadedBytes: actualSize <= maxFileBytes ? bytes : null,
      temporaryPath: temporaryPath,
      mimeType: file.mimeType,
      sourceScheme: file.uri.scheme,
    );
  }

  /// Копирует байты URI во временный файл приложения (TASK 04, часть 2).
  ///
  /// `null` — каталог недоступен: работаем из памяти (байты уже прочитаны).
  Future<String?> _materialize(String name, Uint8List bytes, int index) async {
    final Directory? directory = await _temporaryDirectory();
    if (directory == null) return null;
    try {
      final Directory target = Directory(
        p.join(directory.path, _temporarySubdirectory),
      );
      await target.create(recursive: true);
      final String base = p.basename(name).isEmpty
          ? 'document'
          : p.basename(name);
      final String path = p.join(target.path, '${index}_$base');
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } on Object catch (error) {
      diagnostics.unavailable(
        fileName: name,
        reason: 'временная копия не создалась (${error.runtimeType})',
      );
      return null;
    }
  }

  Future<Directory?> _temporaryDirectory() async {
    final TemporaryDirectoryProvider? injected = temporaryDirectory;
    try {
      if (injected != null) return await injected();
      return await getTemporaryDirectory();
    } on Object {
      return null;
    }
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
    final String? temporary = document.temporaryPath;
    if (temporary != null) {
      try {
        return await File(temporary).readAsBytes();
      } on Object catch (error) {
        diagnostics.unavailable(
          fileName: document.name,
          reason: 'временная копия недоступна (${error.runtimeType})',
        );
        throw const ParserException(
          ParserErrorCode.fileAccessDenied,
          details: 'Временная копия файла недоступна',
        );
      }
    }
    if (!document.path.startsWith('memory://')) {
      final File file = File(document.path);
      final int length;
      try {
        length = await file.length();
      } on Object {
        throw const ParserException(
          ParserErrorCode.fileAccessDenied,
          details: 'Нет доступа к выбранному файлу',
        );
      }
      if (length > maxFileBytes) {
        throw const ParserException(
          ParserErrorCode.fileTooLarge,
          details: 'Файл больше лимита 25 МБ',
        );
      }
      return file.readAsBytes();
    }
    throw const ParserException(
      ParserErrorCode.fileAccessDenied,
      details: 'Нет локального пути и байтов файла',
    );
  }

  @override
  Future<void> releaseDocument(PickedDocument document) async {
    final String? temporary = document.temporaryPath;
    if (temporary == null) return;
    try {
      final File file = File(temporary);
      if (await file.exists()) await file.delete();
    } on Object {
      // Временный каталог чистится ОС: ошибка удаления не влияет на импорт.
    }
  }
}

/// Синтетический уникальный путь для платформ без локального пути.
String syntheticMemoryPath(int index, String fileName) {
  return 'memory://$index/${Uri.encodeComponent(fileName)}';
}

/// Открывает системный пикер `file_picker` 13.3.3.
///
/// На мобильных используется `FileType.any`: фильтр по расширениям превращается
/// в список MIME (`MimeTypeMap`), а у `.md`/`.rtf`/`.ppt` его может не быть —
/// Android тогда **не показывает** файл в диалоге (TASK 04: обычный документ
/// должен выбираться). Расширение проверяет парсинг и даёт строку ARB. На
/// десктопе фильтр остаётся: там расширения работают как ожидается.
Future<List<PickedFileRef>> _pickWithFilePicker() async {
  final bool mobileFilterUnreliable = Platform.isAndroid || Platform.isIOS;
  final List<PlatformFile> files = await FilePicker.pickFiles(
    type: mobileFilterUnreliable ? FileType.any : FileType.custom,
    allowedExtensions: mobileFilterUnreliable
        ? null
        : generationDocumentExtensions,
  );
  return <PickedFileRef>[
    for (final PlatformFile file in files) _PlatformFileRef(file),
  ];
}

/// `PlatformFile` → [PickedFileRef] (единственная точка связи с плагином).
class _PlatformFileRef implements PickedFileRef {
  _PlatformFileRef(this.file);

  final PlatformFile file;

  @override
  String get name => file.name;

  @override
  Uri get uri => file.uri;

  @override
  int? get knownSize => file.lengthSync();

  @override
  String? get mimeType => null;

  @override
  Future<Uint8List> readBytes() => file.readAsBytes();
}
