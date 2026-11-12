// Открытие файловой БД приложения (ADR-005: path_provider + NativeDatabase).
//
// Данные приложения лежат в `getApplicationSupportDirectory()/cardflow/`
// (не в пользовательских «Документах»: перенос/бэкап — через `.zip`, ADR-006).
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// Имя каталога данных приложения внутри application support.
const String appDataDirectoryName = 'cardflow';

/// Имя файла SQLite-базы.
const String appDatabaseFileName = 'cardflow.sqlite';

/// Открывает файловую БД приложения и возвращает drift-класс.
///
/// [baseDirectory] — override для тестов: тогда файл создаётся в
/// `<baseDirectory>/cardflow/cardflow.sqlite` без обращения к `path_provider`.
Future<AppDatabase> openAppDatabase({Directory? baseDirectory}) async {
  final base = baseDirectory ?? await getApplicationSupportDirectory();
  final dataDirectory = Directory(p.join(base.path, appDataDirectoryName));
  await dataDirectory.create(recursive: true);
  final file = File(p.join(dataDirectory.path, appDatabaseFileName));
  return AppDatabase(NativeDatabase.createInBackground(file));
}
