// Открытие файловой БД приложения (ADR-005: path_provider + NativeDatabase).
//
// Данные приложения лежат в `getApplicationSupportDirectory()/cardflow/`
// (не в пользовательских «Документах»: перенос/бэкап — через `.zip`, ADR-006).
//
// Перед первой миграцией схемы файл БД копируется в `cardflow.sqlite.bak`
// (ADR-005 §5): если шаг миграции окажется дефектным, исходные данные остаются
// рядом. Копия делается только когда версия файла **старее** текущей
// (`PRAGMA user_version`), а не при каждом старте.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';

/// Имя каталога данных приложения внутри application support.
const String appDataDirectoryName = 'cardflow';

/// Имя файла SQLite-базы.
const String appDatabaseFileName = 'cardflow.sqlite';

/// Суффикс резервной копии перед миграцией (`cardflow.sqlite.bak`).
const String appDatabaseBackupSuffix = '.bak';

/// Открывает файловую БД приложения и возвращает drift-класс.
///
/// [baseDirectory] — override для тестов: тогда файл создаётся в
/// `<baseDirectory>/cardflow/cardflow.sqlite` без обращения к `path_provider`.
Future<AppDatabase> openAppDatabase({Directory? baseDirectory}) async {
  final base = baseDirectory ?? await getApplicationSupportDirectory();
  final dataDirectory = Directory(p.join(base.path, appDataDirectoryName));
  await dataDirectory.create(recursive: true);
  final file = File(p.join(dataDirectory.path, appDatabaseFileName));
  await backupBeforeMigration(file);
  return AppDatabase(NativeDatabase.createInBackground(file));
}

/// Копирует [file] в `<файл>.bak`, если версия схемы в файле старее текущей.
///
/// Вызывается **до** открытия drift: миграция 1 → 2 (ADR-051) меняет схему, и
/// копия «как было» должна существовать раньше, чем что-то записано. Отсутствие
/// файла (первый запуск) и уже актуальная версия — копия не нужна; нечитаемый
/// файл не копируется — открытие само сообщит об ошибке.
Future<void> backupBeforeMigration(File file) async {
  if (!await file.exists()) return;
  final int? userVersion = _readUserVersion(file);
  if (userVersion == null) return;
  if (userVersion >= AppDatabase.currentSchemaVersion) return;
  await file.copy('${file.path}$appDatabaseBackupSuffix');
}

/// Версия схемы из заголовка SQLite-файла; `null` — файл не читается.
int? _readUserVersion(File file) {
  Database? database;
  try {
    database = sqlite3.open(file.path);
    final ResultSet rows = database.select('PRAGMA user_version');
    if (rows.isEmpty) return null;
    final Object? value = rows.first.columnAt(0);
    return value is int ? value : null;
  } on SqliteException {
    return null;
  } finally {
    database?.close();
  }
}
