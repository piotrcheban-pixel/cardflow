import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Хранилище медиафайлов приложения (каталог `media/`).
///
/// Контракт конструктора: `MediaStore(Directory rootDirectory)`. Публичные
/// методы принимают **относительный** путь внутри корневого каталога
/// (например `media/<id>` или `<deckId>/<id>`). Любая попытка выйти за корень
/// (`..`, абсолютный путь, другой диск) отклоняется `ArgumentError`.
///
/// Запись атомарна: байты пишутся во временный файл в том же каталоге и затем
/// переименовываются на место, поэтому при сбое не остаётся частичного файла.
class MediaStore {
  /// Создаёт хранилище с корневым каталогом.
  MediaStore(this.rootDirectory);

  /// Корневой каталог медиа (создаётся при записи).
  final Directory rootDirectory;

  static final RegExp _windowsDrive = RegExp(r'^[A-Za-z]:');
  static int _tempSequence = 0;

  /// Читает медиа по относительному пути; `null`, если файла нет.
  Future<Uint8List?> readMedia(String relativePath) async {
    final file = _fileFor(relativePath);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  /// Записывает медиа по относительному пути (создаёт каталоги).
  Future<void> writeMedia({
    required String relativePath,
    required Uint8List bytes,
  }) async {
    final file = _fileFor(relativePath);
    await file.parent.create(recursive: true);
    final temp = File(
      p.join(file.parent.path, '${_tempPrefix()}${_nextSequence()}'),
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  /// Удаляет медиа по относительному пути (нет файла — не ошибка).
  Future<void> deleteMedia(String relativePath) async {
    final file = _fileFor(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Временный префикс имени файла (не совпадает с basename реального файла).
  String _tempPrefix() => '.cardflow-tmp-';

  /// Уникальный номер временного файла в рамках процесса.
  int _nextSequence() {
    _tempSequence = (_tempSequence + 1) & 0x7fffffff;
    return _tempSequence;
  }

  /// Проверяет относительный путь и возвращает файл внутри корня.
  File _fileFor(String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    final rootPath = p.normalize(rootDirectory.absolute.path);
    final target = p.normalize(p.join(rootPath, normalized));
    final rootPrefix = rootPath.endsWith(p.separator)
        ? rootPath
        : '$rootPath${p.separator}';
    if (!target.startsWith(rootPrefix)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Путь выходит за корневой каталог медиа',
      );
    }
    return File(target);
  }

  /// Нормализует относительный путь и отклоняет выход за корень.
  String _normalizeRelativePath(String relativePath) {
    // Оба вида слэшей считаем разделителем: так медиа-пути, созданные на
    // Windows, остаются безопасными и на других платформах.
    final normalized = p.posix.normalize(relativePath.replaceAll('\\', '/'));
    final invalid =
        normalized.isEmpty ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        p.posix.isAbsolute(normalized) ||
        _windowsDrive.hasMatch(normalized);
    if (invalid) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Недопустимый относительный путь медиа',
      );
    }
    return normalized;
  }
}
