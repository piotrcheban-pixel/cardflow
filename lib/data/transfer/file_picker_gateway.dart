import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';

/// Поддерживает ли платформа стартовый каталог в диалоге сохранения (ADR-047).
///
/// Desktop-реализации `file_picker` принимают обычный путь; Android/iOS пишут
/// через SAF (`content://`), где каталог платформы не имеет смысла.
bool get _desktopSupportsInitialDirectory =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

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
/// По умолчанию нативный диалог открывается в профиле пользователя
/// (`C:\Users\<имя>`), и Windows отвечает «У вас нет разрешения на сохранение
/// файлов в этом месте». Порядок выбора: «Загрузки», затем «Документы»; если
/// платформа не даёт ни одного существующего каталога — `null`, и место
/// выбирает ОС (прежнее поведение).
///
/// [downloads]/[documents] — точки подмены для тестов; по умолчанию
/// `path_provider`.
Future<String?> resolveDefaultSaveDirectory({
  Future<Directory?> Function()? downloads,
  Future<Directory?> Function()? documents,
}) async {
  final List<Future<Directory?> Function()> sources =
      <Future<Directory?> Function()>[
        downloads ?? getDownloadsDirectory,
        documents ?? getApplicationDocumentsDirectory,
      ];
  for (final Future<Directory?> Function() source in sources) {
    try {
      final Directory? directory = await source();
      if (directory == null) continue;
      final String path = directory.path.trim();
      // Каталог должен существовать: диалог с несуществующим путём снова
      // открылся бы не там (или не открылся вовсе).
      if (path.isEmpty || !await directory.exists()) continue;
      return path;
    } on Object {
      // `UnsupportedError` на платформах без «Загрузок», отсутствующий плагин
      // (`MissingPluginException`) или ошибка ОС — просто пробуем следующий
      // каталог: диалог сохранения не должен падать из-за подсказки места.
      continue;
    }
  }
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
  }) : useInitialDirectory =
           useInitialDirectory ?? _desktopSupportsInitialDirectory,
       _saveDirectoryResolver =
           saveDirectoryResolver ?? resolveDefaultSaveDirectory;

  /// Максимальный размер файла, который разрешено читать в память.
  final int maxFileBytes;

  /// Передавать ли диалогу стартовый каталог.
  ///
  /// Только desktop: на Android `saveFile` пишет через SAF (`content://`), а
  /// `getDownloadsDirectory` возвращает каталог приложения во внешнем
  /// хранилище — подставлять его в системный диалог нельзя (ADR-047).
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
    String? dialogTitle,
  }) async {
    try {
      final uri = await FilePicker.saveFile(
        fileName: ensureZipExtension(suggestedFileName),
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: dialogTitle,
        initialDirectory: await _initialDirectory(),
      );
      if (uri == null) {
        // Пользователь отменил диалог сохранения — тихий no-op (ADR-006 п.7).
        return false;
      }
      return await _ensureSaved(uri, bytes);
    } on FileSystemException catch (error) {
      // ADR-047: системный текст Windows («У вас нет разрешения на сохранение
      // файлов в этом месте») пользователю не показывается — только строка ARB
      // по коду writeDenied.
      throw ArchiveException(
        ArchiveErrorCode.writeDenied,
        details: 'saveZipFile: ${error.message} (${error.path})',
      );
    }
  }

  /// Стартовый каталог диалога сохранения или `null`.
  ///
  /// Подсказка места не должна ломать экспорт: любая ошибка резолвера — `null`.
  Future<String?> _initialDirectory() async {
    if (!useInitialDirectory) return null;
    try {
      return await _saveDirectoryResolver();
    } on Object {
      // Подсказка места не должна ломать экспорт.
      return null;
    }
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
