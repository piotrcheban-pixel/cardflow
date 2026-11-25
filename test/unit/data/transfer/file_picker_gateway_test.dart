import 'dart:io';
import 'dart:typed_data';

import 'package:cardflow/data/transfer/file_picker_gateway.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Фальшивый `PlatformFile` платформенного пикера.
///
/// Нужны только `name`/`uri`/`path`; реальные методы чтения в тестах
/// не вызываются, поэтому они бросают `UnimplementedError` (тип `Never`
/// корректно сужает возвращаемые типы).
base class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(this._uri);

  final Uri _uri;

  @override
  String get name => p.basename(_uri.toFilePath());

  @override
  Uri get uri => _uri;

  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => throw UnimplementedError();

  @override
  Future<int?> length() => throw UnimplementedError();

  @override
  Future<Uint8List> readAsBytes() => throw UnimplementedError();

  @override
  Stream<Uint8List> readAsByteStream() => throw UnimplementedError();
}

/// Фальшивая реализация платформенного интерфейса `file_picker` 13.3.3.
class _FakePickerPlatform extends FilePickerPlatform {
  /// Путь, который «выбирает» пользователь в диалоге импорта (null — отмена).
  String? pickedImportPath;

  /// URI, который «возвращает» диалог сохранения (null — отмена).
  Uri? savedUri;

  /// Если `true` — имитируем desktop-плагин, который сам пишет байты.
  bool writeSavedFile = false;

  /// Исключение, которое «нативный диалог» бросает вместо возврата пути
  /// (Windows: нет прав на запись в выбранную папку).
  Object? throwOnSave;

  FileType? pickedType;
  List<String>? pickedExtensions;
  String? savedFileName;
  String? savedMimeType;
  Uint8List? savedBytes;

  /// Каталог, который плагин получил для старта диалога (ADR-047).
  String? savedInitialDirectory;

  /// Заголовок диалога сохранения (находка F12/ADR-047).
  String? savedDialogTitle;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickedType = type;
    pickedExtensions = allowedExtensions;
    final path = pickedImportPath;
    if (path == null) {
      return null;
    }
    return _FakePlatformFile(Uri.file(path));
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedFileName = fileName;
    savedMimeType = mimeType;
    savedBytes = bytes;
    savedInitialDirectory = initialDirectory;
    savedDialogTitle = dialogTitle;
    final Object? failure = throwOnSave;
    if (failure != null) {
      throw failure;
    }
    final uri = savedUri;
    if (uri != null && writeSavedFile && uri.scheme == 'file') {
      await File(uri.toFilePath()).writeAsBytes(bytes, flush: true);
    }
    return uri;
  }
}

void main() {
  late Directory tempDir;
  late FilePickerPlatform originalPlatform;
  late _FakePickerPlatform fake;
  late FilePickerGateway gateway;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cardflow_gateway_test_');
    originalPlatform = FilePickerPlatform.instance;
    fake = _FakePickerPlatform();
    FilePickerPlatform.instance = fake;
    gateway = FilePickerGateway();
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPlatform;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ensureZipExtension', () {
    test('добавляет .zip, если расширения нет', () {
      expect(ensureZipExtension('Колода'), 'Колода.zip');
    });

    test('не меняет уже корректное имя', () {
      expect(ensureZipExtension('deck.zip'), 'deck.zip');
      expect(ensureZipExtension('DECK.ZIP'), 'DECK.ZIP');
      expect(ensureZipExtension('deck.tar.zip'), 'deck.tar.zip');
    });

    test('обрезает пробелы вокруг имени', () {
      expect(ensureZipExtension('  deck  '), 'deck.zip');
    });

    test('пустое имя заменяет запасным (ADR-006 п. 8)', () {
      expect(ensureZipExtension('   '), 'cardflow.zip');
    });
  });

  group('FilePickerGateway: импорт', () {
    test('возвращает путь выбранного файла и фильтр .zip', () async {
      final path = p.join(tempDir.path, 'deck.zip');
      fake.pickedImportPath = path;

      expect(await gateway.pickZipToImport(), path);
      expect(fake.pickedType, FileType.custom);
      expect(fake.pickedExtensions, <String>['zip']);
    });

    test('отмена выбора → null', () async {
      fake.pickedImportPath = null;

      expect(await gateway.pickZipToImport(), isNull);
    });
  });

  group('FilePickerGateway: saveZipFile', () {
    final Uint8List bytes = Uint8List.fromList(<int>[80, 75, 3, 4, 0, 255]);

    test('отмена сохранения → false', () async {
      fake.savedUri = null;

      expect(
        await gateway.saveZipFile(suggestedFileName: 'deck', bytes: bytes),
        isFalse,
      );
    });

    test(
      'desktop: файл дописывается, если плагин вернул URI без записи',
      () async {
        final path = p.join(tempDir.path, 'deck.zip');
        fake.savedUri = Uri.file(path);

        final saved = await gateway.saveZipFile(
          suggestedFileName: 'deck',
          bytes: bytes,
        );

        expect(saved, isTrue);
        expect(File(path).existsSync(), isTrue);
        expect(await File(path).readAsBytes(), bytes);
      },
    );

    test('desktop: плагин записал файл сам — содержимое не портится', () async {
      final path = p.join(tempDir.path, 'deck.zip');
      fake.savedUri = Uri.file(path);
      fake.writeSavedFile = true;

      final saved = await gateway.saveZipFile(
        suggestedFileName: 'deck.zip',
        bytes: bytes,
      );

      expect(saved, isTrue);
      expect(await File(path).readAsBytes(), bytes);
    });

    test('desktop: недописанный файл перезаписывается целиком', () async {
      final path = p.join(tempDir.path, 'deck.zip');
      await File(path).writeAsBytes(<int>[1, 2]);
      fake.savedUri = Uri.file(path);

      expect(
        await gateway.saveZipFile(suggestedFileName: 'deck', bytes: bytes),
        isTrue,
      );
      expect(await File(path).readAsBytes(), bytes);
    });

    test('mobile: content:// URI считается успешным сохранением', () async {
      fake.savedUri = Uri.parse('content://media/deck.zip');

      expect(
        await gateway.saveZipFile(suggestedFileName: 'deck', bytes: bytes),
        isTrue,
      );
    });

    test('подставляет расширение .zip и MIME image/zip-тип', () async {
      fake.savedUri = Uri.file(p.join(tempDir.path, 'deck.zip'));

      await gateway.saveZipFile(suggestedFileName: 'Моя колода', bytes: bytes);

      expect(fake.savedFileName, 'Моя колода.zip');
      expect(fake.savedMimeType, 'application/zip');
      expect(fake.savedBytes, bytes);
    });

    // Находка F12/ADR-047: диалог сохранения показывал английский «Save File».
    test('передаёт локализованный заголовок диалога', () async {
      fake.savedUri = Uri.file(p.join(tempDir.path, 'deck.zip'));

      await gateway.saveZipFile(
        suggestedFileName: 'deck',
        bytes: bytes,
        dialogTitle: 'Сохранить ZIP-архив колоды',
      );

      expect(fake.savedDialogTitle, 'Сохранить ZIP-архив колоды');
    });

    test('пустое suggested-имя → cardflow.zip', () async {
      fake.savedUri = Uri.file(p.join(tempDir.path, 'cardflow.zip'));

      await gateway.saveZipFile(suggestedFileName: '   ', bytes: bytes);

      expect(fake.savedFileName, 'cardflow.zip');
    });
  });

  // Owner-note 1.0.1 (ADR-047): Windows открывал диалог в корне профиля
  // (`C:\Users\<имя>`) и отказывал «нет разрешения на сохранение».
  group('ADR-047: каталог по умолчанию в диалоге сохранения', () {
    final Uint8List bytes = Uint8List.fromList(<int>[80, 75, 3, 4]);

    test('desktop: диалог открывается в предложенном каталоге', () async {
      final custom = FilePickerGateway(
        useInitialDirectory: true,
        saveDirectoryResolver: () async => r'C:\Users\user\Downloads',
      );
      fake.savedUri = Uri.file(p.join(tempDir.path, 'deck.zip'));

      await custom.saveZipFile(suggestedFileName: 'deck', bytes: bytes);

      expect(
        fake.savedInitialDirectory,
        r'C:\Users\user\Downloads',
        reason: 'initialDirectory должен доходить до нативного диалога',
      );
    });

    test('mobile: initialDirectory не передаётся (SAF, content://)', () async {
      final mobile = FilePickerGateway(useInitialDirectory: false);
      fake.savedUri = Uri.parse('content://media/deck.zip');

      await mobile.saveZipFile(suggestedFileName: 'deck', bytes: bytes);

      expect(fake.savedInitialDirectory, isNull);
    });

    test('разрешение каталога упало — сохранение всё равно работает', () async {
      final flaky = FilePickerGateway(
        useInitialDirectory: true,
        saveDirectoryResolver: () async =>
            throw UnsupportedError('нет каталога'),
      );
      fake.savedUri = Uri.file(p.join(tempDir.path, 'deck.zip'));

      expect(
        await flaky.saveZipFile(suggestedFileName: 'deck', bytes: bytes),
        isTrue,
      );
      expect(fake.savedInitialDirectory, isNull);
    });

    group('resolveDefaultSaveDirectory', () {
      test('берёт «Загрузки», если каталог существует', () async {
        final downloads = Directory(p.join(tempDir.path, 'Downloads'))
          ..createSync();
        Directory(p.join(tempDir.path, 'Documents')).createSync();

        expect(
          await resolveDefaultSaveDirectory(
            downloads: () async => downloads,
            documents: () async => Directory(p.join(tempDir.path, 'Documents')),
          ),
          downloads.path,
        );
      });

      test('«Загрузки» недоступны → «Документы»', () async {
        final documents = Directory(p.join(tempDir.path, 'Documents'))
          ..createSync();

        expect(
          await resolveDefaultSaveDirectory(
            downloads: () async => null,
            documents: () async => documents,
          ),
          documents.path,
        );
      });

      test('нет ни одного каталога → null (решение системы)', () async {
        expect(
          await resolveDefaultSaveDirectory(
            downloads: () async => null,
            documents: () async => null,
          ),
          isNull,
        );
      });

      test('исключение плагина не выходит наружу → null', () async {
        expect(
          await resolveDefaultSaveDirectory(
            downloads: () async => throw UnsupportedError('нет платформы'),
            documents: () async => throw MissingPluginException('нет плагина'),
          ),
          isNull,
        );
      });

      test('несуществующий каталог пропускается', () async {
        final documents = Directory(p.join(tempDir.path, 'Documents'))
          ..createSync();

        expect(
          await resolveDefaultSaveDirectory(
            // path_provider может вернуть путь, которого ещё нет.
            downloads: () async =>
                Directory(p.join(tempDir.path, 'Нет такого каталога')),
            documents: () async => documents,
          ),
          documents.path,
        );
      });
    });
  });

  // Owner-note 1.0.1, шаг 1: системный текст Windows не должен доходить до UI.
  group('ADR-047: нет прав на запись в выбранную папку', () {
    final Uint8List bytes = Uint8List.fromList(<int>[80, 75, 3, 4]);

    test(
      'FileSystemException диалога → ArchiveException, не системный текст',
      () async {
        fake.throwOnSave = const FileSystemException(
          'Access is denied',
          r'C:\Users\user\file.zip',
        );

        await expectLater(
          gateway.saveZipFile(suggestedFileName: 'deck', bytes: bytes),
          throwsA(
            isA<ArchiveException>().having(
              (ArchiveException error) => error.code,
              'code',
              ArchiveErrorCode.writeDenied,
            ),
          ),
        );
      },
    );

    test('плагин вернул путь, но запись запрещена → ArchiveException', () async {
      // Каталог вместо файла: запись `dart:io` завершится FileSystemException.
      fake.savedUri = Uri.directory(tempDir.path);
      fake.writeSavedFile = true;

      await expectLater(
        gateway.saveZipFile(suggestedFileName: 'deck', bytes: bytes),
        throwsA(
          isA<ArchiveException>().having(
            (ArchiveException error) => error.code,
            'code',
            ArchiveErrorCode.writeDenied,
          ),
        ),
      );
    });

    test('отмена диалога остаётся тихим no-op (ADR-006 п. 7)', () async {
      fake.savedUri = null;

      expect(
        await gateway.saveZipFile(suggestedFileName: 'deck', bytes: bytes),
        isFalse,
      );
    });
  });

  group('FilePickerGateway: readFile', () {
    test('читает записанный файл целиком', () async {
      final path = p.join(tempDir.path, 'данные.bin');
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 255, 0]);
      await File(path).writeAsBytes(bytes);

      expect(await gateway.readFile(path), bytes);
    });

    test('файл больше лимита → tooLarge до чтения в память (H1)', () async {
      final path = p.join(tempDir.path, 'большой.zip');
      await File(path).writeAsBytes(Uint8List(8));
      final limited = FilePickerGateway(maxFileBytes: 4);

      expect(
        () => limited.readFile(path),
        throwsA(
          isA<ArchiveException>().having(
            (ArchiveException error) => error.code,
            'code',
            ArchiveErrorCode.tooLarge,
          ),
        ),
      );
    });

    test('файл ровно в лимите читается (H1)', () async {
      final path = p.join(tempDir.path, 'ровно.bin');
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      await File(path).writeAsBytes(bytes);
      final limited = FilePickerGateway(maxFileBytes: 4);

      expect(await limited.readFile(path), bytes);
    });

    test('отсутствующий файл → FileSystemException', () {
      expect(
        () => gateway.readFile(p.join(tempDir.path, 'нет.bin')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('шлюз реализует контракт FileGateway', () {
      expect(gateway, isA<FileGateway>());
    });
  });
}
