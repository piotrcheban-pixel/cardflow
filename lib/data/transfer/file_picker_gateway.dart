import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';

/// Добавляет расширение `.zip`, если его ещё нет (сравнение без учёта
/// регистра), и обрезает пробелы вокруг имени.
///
/// Для пустого имени возвращается запасное `cardflow.zip` (ADR-006 п.8:
/// имя файла экспорта выводится из имени колоды).
String ensureZipExtension(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) {
    return 'cardflow.zip';
  }
  if (trimmed.toLowerCase().endsWith('.zip')) {
    return trimmed;
  }
  return '$trimmed.zip';
}

/// Возвращает каталог, который предлагается в диалоге сохранения (ADR-047).
typedef SaveDirectoryResolver = Future<String?> Function();

/// Каталог по умолчанию для диалога сохранения (ADR-047).
///
/// [downloads]/[documents] — точки подмены для тестов; по умолчанию
/// `path_provider`.
Future<String?> resolveDefaultSaveDirectory({
  Future<Directory?> Function()? downloads,
  Future<Directory?> Function()? documents,
}) async {
  return null;
}

/// Файловый шлюз через `file_picker` 13.3.3 + `dart:io` (SPEC A6.9).
///
/// Контракт сохранения объединён в [saveZipFile]: в `file_picker` 13.3.3
/// `saveFile` сам записывает байты и возвращает URI (на мобильных —
/// `content://`, на desktop — `file://`), отдельного «выбора пути без записи»
/// в API нет.
class FilePickerGateway implements FileGateway {
  /// Создаёт шлюз.
  ///
  /// [maxFileBytes] — предел размера читаемого файла (по умолчанию
  /// [DeckArchiveLimits.maxImportBytes]); больше — `tooLarge` до чтения.
  ///
  /// [useInitialDirectory] — передавать ли диалогу сохранения стартовый
  /// каталог (ADR-047); `null` — автоопределение по платформе.
  /// [saveDirectoryResolver] — источник каталога (по умолчанию «Загрузки» →
  /// «Документы», см. [resolveDefaultSaveDirectory]).
  FilePickerGateway({
    this.maxFileBytes = DeckArchiveLimits.maxImportBytes,
    bool? useInitialDirectory,
    SaveDirectoryResolver? saveDirectoryResolver,
  }) : useInitialDirectory = useInitialDirectory ?? false,
       _saveDirectoryResolver =
           saveDirectoryResolver ?? resolveDefaultSaveDirectory;

  /// Максимальный размер файла, который разрешено читать в память.
  final int maxFileBytes;

  /// Передавать ли диалогу стартовый каталог.
  final bool useInitialDirectory;

  /// Источник стартового каталога диалога сохранения.
  final SaveDirectoryResolver _saveDirectoryResolver;

  @override
  Future<String?> pickZipToImport({String? dialogTitle}) async {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    return file?.path;
  }

  @override
  Future<bool> saveZipFile({
    required String suggestedFileName,
    required Uint8List bytes,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: ensureZipExtension(suggestedFileName),
      bytes: bytes,
      mimeType: 'application/zip',
    );
    if (uri == null) {
      // Пользователь отменил диалог сохранения — тихий no-op (ADR-006 п.7).
      return false;
    }
    return _ensureSaved(uri, bytes);
  }

  @override
  Future<Uint8List> readFile(String path) async {
    final file = File(path);
    // Размер проверяется ДО чтения в память (контракт FileGateway, H1):
    // большой .zip не должен приводить к OOM.
    final length = await file.length();
    if (length > maxFileBytes) {
      throw ArchiveException(
        ArchiveErrorCode.tooLarge,
        details: 'readFile: $path размером $length > $maxFileBytes байт',
      );
    }
    return file.readAsBytes();
  }

  /// Гарантирует, что байты оказались в файле.
  ///
  /// Desktop-реализации `file_picker` пишут файл сами, но контракт гейтвея не
  /// должен от этого зависеть: если вернулся файловый URI и размер не совпал
  /// с [bytes] (файл не записан или записан неполностью) — дописываем через
  /// `dart:io`. Не-файловые URI (`content://` на мобильных) записывает плагин,
  /// `dart:io` с ними не работает.
  Future<bool> _ensureSaved(Uri uri, Uint8List bytes) async {
    if (uri.scheme != 'file') {
      return true;
    }
    final file = File(uri.toFilePath());
    if (await file.exists() && await file.length() == bytes.length) {
      return true;
    }
    await file.writeAsBytes(bytes, flush: true);
    return true;
  }
}
