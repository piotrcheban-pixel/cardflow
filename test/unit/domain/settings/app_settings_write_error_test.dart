import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cardflow/domain/settings/app_settings_write_error.dart';

/// Owner-note 1.0.1 (ADR-047): причину отказа записи настроек нужно отличать
/// от прочих ошибок, чтобы UI показал «нет прав на папку данных», а не
/// бессмысленное «попробуйте ещё раз».
void main() {
  group('classifyAppSettingsWriteFailure: права на папку данных', () {
    test('SQLITE_READONLY из drift (текст sqlite3) → writeDenied', () {
      // Реальный текст из debug-лога приложения:
      // DriftRemoteException: SqliteException(8): attempt to write a readonly
      // database ... Causing statement: INSERT INTO "app_settings" ...
      final Object error =StateError(
        'DriftRemoteException: SqliteException(8): while executing statement, '
        'attempt to write a readonly database (code 8) '
        'Causing statement: INSERT INTO "app_settings" ("key", "value_json") '
        'VALUES (?, ?) ON CONFLICT("key") DO UPDATE SET "key" = ?, '
        '"value_json" = ?, parameters: app.settings, {…}',
      );

      expect(
        classifyAppSettingsWriteFailure(error),
        AppSettingsWriteFailure.writeDenied,
      );
    });

    test('«read-only» и «read only» тоже распознаются', () {
      for (final String text in <String>[
        'SQLITE_READONLY',
        'attempt to write a read-only database',
        'database is read only',
      ]) {
        expect(
          classifyAppSettingsWriteFailure(StateError(text)),
          AppSettingsWriteFailure.writeDenied,
          reason: 'Не распознан текст: $text',
        );
      }
    });

    test('FileSystemException с отказом доступа → writeDenied', () {
      expect(
        classifyAppSettingsWriteFailure(
          const FileSystemException(
            'Cannot open file',
            r'C:\Users\user\AppData\Roaming\cardflow\cardflow.sqlite',
            OSError('Отказано в доступе', 5),
          ),
        ),
        AppSettingsWriteFailure.writeDenied,
      );
    });

    test('обычная ошибка БД → unknown (общая строка ARB)', () {
      expect(
        classifyAppSettingsWriteFailure(
          StateError('no such table: app_settings'),
        ),
        AppSettingsWriteFailure.unknown,
      );
      expect(
        classifyAppSettingsWriteFailure(Exception('disk I/O error')),
        AppSettingsWriteFailure.unknown,
      );
    });

    test('AppSettingsWriteException сохраняет код и детали для логов', () {
      const AppSettingsWriteException error = AppSettingsWriteException(
        AppSettingsWriteFailure.writeDenied,
        details: 'SQLITE_READONLY',
      );

      expect(error.failure, AppSettingsWriteFailure.writeDenied);
      expect(error.details, contains('SQLITE_READONLY'));
      expect(error.toString(), contains('writeDenied'));
    });
  });

  group('classifyAppSettingsWriteFailure: настоящий readonly SQLite', () {
    late Directory tempDir;
    late String path;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cardflow_rw_classify_');
      path = '${tempDir.path}${Platform.pathSeparator}readonly.sqlite';
      // Создаём валидную БД и закрываем её, чтобы файл существовал.
      final Database seed = sqlite3.open(path);
      seed.execute('CREATE TABLE probe (x INTEGER)');
      seed.dispose();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('SqliteException из драйвера классифицируется как writeDenied', () {
      final Database readOnly = sqlite3.open(path, mode: OpenMode.readOnly);
      addTearDown(readOnly.dispose);
      SqliteException? failure;
      try {
        readOnly.execute('INSERT INTO probe (x) VALUES (1)');
      } on SqliteException catch (error) {
        failure = error;
      }

      expect(failure, isNotNull, reason: 'Запись в readonly-БД обязана падать');
      expect(failure!.extendedResultCode & 0xFF, 8, reason: 'SQLITE_READONLY');
      expect(
        classifyAppSettingsWriteFailure(failure),
        AppSettingsWriteFailure.writeDenied,
      );
    });
  });
}
