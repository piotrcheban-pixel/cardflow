// Открытие файловой БД приложения (ADR-005: path_provider + NativeDatabase).
//
// Данные приложения лежат в `getApplicationSupportDirectory()/cardflow/`
// (не в пользовательских «Документах»: перенос/бэкап — через `.zip`, ADR-006).
//
// Перед первой миграцией схемы файл БД копируется в `cardflow.sqlite.bak`
// (ADR-005 §5): если шаг миграции окажется дефектным, исходные данные остаются
// рядом. Копия делается только когда версия файла **старее** текущей
// (`PRAGMA user_version`), а не при каждом старте.
//
// Устойчивость старта (ADR-057):
//  - бэкап — страховка, а не условие открытия: сбой копирования (нет прав на
//    каталог, занятый путь `.bak`, нехватка места) больше не «кирпичит» запуск;
//  - файл, который SQLite не может прочитать/мигрировать (NOTADB/CORRUPT),
//    переименовывается в `cardflow.sqlite.corrupted_<дата>`, а на его месте
//    создаётся новая пустая БД: старое содержимое не удаляется, приложение
//    запускается;
//  - миграции применяются **до** возврата из `openAppDatabase`, поэтому сбой
//    файла виден на старте (экран ошибки), а не в случайном виджете позже.
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

/// Суффикс отложенного повреждённого файла:
/// `cardflow.sqlite.corrupted_<yyyyMMdd_HHmmss>` (ADR-057).
const String appDatabaseCorruptedSuffix = '.corrupted_';

/// Файлы-спутники SQLite, которые переезжают вместе с повреждённой БД.
const List<String> sqliteSidecarSuffixes = <String>['-journal', '-wal', '-shm'];

/// Результат открытия БД приложения.
class OpenedDatabase {
  /// Создаёт результат открытия.
  const OpenedDatabase({required this.database, this.corruptedFile});

  /// Открытая (и уже мигрированная) база данных.
  final AppDatabase database;

  /// Файл повреждённой БД после переименования (ADR-057); `null`, если
  /// аварийное восстановление не понадобилось.
  final File? corruptedFile;
}

/// Открывает файловую БД приложения и возвращает drift-класс.
///
/// [baseDirectory] — override для тестов: тогда файл создаётся в
/// `<baseDirectory>/cardflow/cardflow.sqlite` без обращения к `path_provider`.
///
/// Если файл БД повреждён и не мигрирует, он сохраняется рядом как
/// `cardflow.sqlite.corrupted_<дата>`, а приложение получает новую пустую БД
/// (ADR-057). Версия новее приложения и недоступный каталог — по-прежнему
/// ошибка открытия: данные не пересоздаются молча.
Future<AppDatabase> openAppDatabase({Directory? baseDirectory}) async {
  final OpenedDatabase opened = await openAppDatabaseWithRecovery(
    baseDirectory: baseDirectory,
  );
  return opened.database;
}

/// Открывает БД и сообщает, был ли повреждённый файл отложен в сторону.
Future<OpenedDatabase> openAppDatabaseWithRecovery({
  Directory? baseDirectory,
  DateTime Function()? clock,
}) async {
  final Directory base =
      baseDirectory ?? await getApplicationSupportDirectory();
  final Directory dataDirectory = Directory(
    p.join(base.path, appDataDirectoryName),
  );
  await dataDirectory.create(recursive: true);
  final File file = File(p.join(dataDirectory.path, appDatabaseFileName));
  await backupBeforeMigration(file);
  try {
    return OpenedDatabase(database: await _openMigrated(file));
  } on Object catch (error, stack) {
    // Диагноз ставится прямым чтением файла `sqlite3` (тот же изолят): drift
    // в фоновом изоляте оборачивает исключение SQLite в `DriftRemoteException`,
    // и без пробы причину не отличить от ошибки версии.
    final _ProbeResult probe = _probeDatabaseFile(file);
    final Object? cause = probe.error;
    if (cause != null && isCorruptedDatabaseError(cause)) {
      final File corrupted = await quarantineCorruptedDatabase(
        file,
        clock: clock,
      );
      return OpenedDatabase(
        database: await _openMigrated(file),
        corruptedFile: corrupted,
      );
    }
    if (cause != null && isDatabaseAccessFailure(cause)) {
      // Нет прав на файл/каталог: восстановление пересоздало бы пустую БД в
      // недоступном каталоге. Сообщаем ошибку доступа — экран подскажет причину.
      Error.throwWithStackTrace(cause, probe.stackTrace ?? stack);
    }
    // Не повреждение файла: понижение версии, занятый файл, сбой миграции —
    // политика ADR-005 остаётся fail-fast, данные не трогаем.
    Error.throwWithStackTrace(error, stack);
  }
}

/// Копирует [file] в `<файл>.bak`, если версия схемы в файле старее текущей.
///
/// Вызывается **до** открытия drift: миграция 1 → 2 (ADR-051) меняет схему, и
/// копия «как было» должна существовать раньше, чем что-то записано. Отсутствие
/// файла (первый запуск) и уже актуальная версия — копия не нужна; нечитаемый
/// файл не копируется — открытие само сообщит об ошибке.
///
/// Возвращает `true`, если копия создана. Сбой копирования (нет прав, занятый
/// путь `.bak`, нехватка места) **не** выбрасывается наружу (ADR-057): бэкап —
/// страховка, а не условие открытия БД.
Future<bool> backupBeforeMigration(File file) async {
  try {
    if (!await file.exists()) return false;
    final int? userVersion = _readUserVersion(file);
    if (userVersion == null) return false;
    if (userVersion >= AppDatabase.currentSchemaVersion) return false;
    await file.copy('${file.path}$appDatabaseBackupSuffix');
    return true;
  } on Object {
    return false;
  }
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
  } on FileSystemException {
    return null;
  } finally {
    database?.close();
  }
}

/// Открывает drift поверх [file] и применяет миграции до возврата.
Future<AppDatabase> _openMigrated(File file) async {
  final AppDatabase database = AppDatabase(
    NativeDatabase.createInBackground(file),
  );
  try {
    // Любой запрос запускает `beforeOpen` и `onUpgrade`; ждём их здесь, чтобы
    // сбой файла стал ошибкой старта, а не поздним исключением в UI.
    await database.customSelect('PRAGMA user_version').getSingle();
    return database;
  } on Object {
    await _closeQuietly(database);
    rethrow;
  }
}

/// Переименовывает повреждённый файл (и его `-journal`/`-wal`/`-shm`) в
/// `cardflow.sqlite.corrupted_<yyyyMMdd_HHmmss>`; возвращает новый файл.
Future<File> quarantineCorruptedDatabase(
  File file, {
  DateTime Function()? clock,
}) async {
  final DateTime now = (clock ?? DateTime.now)();
  final String stamp = _fileStamp(now);
  File target = File('${file.path}$appDatabaseCorruptedSuffix$stamp');
  int attempt = 1;
  while (await target.exists()) {
    target = File(
      '${file.path}$appDatabaseCorruptedSuffix${stamp}_${attempt++}',
    );
  }
  final File renamed = await file.rename(target.path);
  for (final String suffix in sqliteSidecarSuffixes) {
    final File sidecar = File('${file.path}$suffix');
    if (await sidecar.exists()) {
      await sidecar.rename('${renamed.path}$suffix');
    }
  }
  return renamed;
}

/// Результат прямой пробы файла БД (`sqlite3`, тот же изолят).
class _ProbeResult {
  const _ProbeResult({this.error, this.stackTrace});

  /// Исключение пробы; `null` — файл читается и доступен для записи.
  final Object? error;

  /// Стек пробы (для диагностики исходной причины).
  final StackTrace? stackTrace;
}

/// Читает файл БД напрямую, чтобы назвать причину сбоя drift-открытия.
///
/// Проба идёт только после неудачного открытия (в успешном старте её нет):
///  - чтение `PRAGMA user_version` — мусорный файл отдаёт `SQLITE_NOTADB` (26),
///    повреждённый — `SQLITE_CORRUPT` (11);
///  - запись той же версии обратно — проверка прав на запись: каталог только для
///    чтения отдаёт `SQLITE_READONLY`/`SQLITE_CANTOPEN` (значение не меняется).
_ProbeResult _probeDatabaseFile(File file) {
  if (!file.existsSync()) return const _ProbeResult();
  Database? database;
  try {
    database = sqlite3.open(file.path);
    final ResultSet rows = database.select('PRAGMA user_version');
    final Object? value = rows.isEmpty ? null : rows.first.columnAt(0);
    if (value is int) {
      database.execute('PRAGMA user_version = $value');
    }
    return const _ProbeResult();
  } on Object catch (error, stackTrace) {
    return _ProbeResult(error: error, stackTrace: stackTrace);
  } finally {
    database?.close();
  }
}

/// Причина сбоя — повреждённый/нечитаемый файл БД (а не версия и не права)?
///
/// Восстановление (ADR-057) включается только для `SQLITE_CORRUPT` (11) и
/// `SQLITE_NOTADB` (26): остальные причины не дают права пересоздавать файл,
/// в котором могут быть данные пользователя.
bool isCorruptedDatabaseError(Object error) {
  if (error is! SqliteException) return false;
  final int code = error.resultCode;
  return code == SqlError.SQLITE_CORRUPT || code == SqlError.SQLITE_NOTADB;
}

/// Причина сбоя — нет доступа к файлу/каталогу данных (а не повреждение)?
///
/// Нужно экрану ошибки старта: «нет прав» и «файл повреждён» требуют разных
/// действий от пользователя, а сырые исключения в UI не показываются.
bool isDatabaseAccessFailure(Object error) {
  if (error is FileSystemException) return true;
  if (error is! SqliteException) return false;
  const Set<int> accessCodes = <int>{
    SqlError.SQLITE_PERM,
    SqlError.SQLITE_READONLY,
    SqlError.SQLITE_CANTOPEN,
    SqlError.SQLITE_AUTH,
  };
  return accessCodes.contains(error.resultCode);
}

/// `yyyyMMdd_HHmmss` в локальном времени — суффикс отложенного файла.
String _fileStamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year.toString().padLeft(4, '0')}'
      '${two(time.month)}${two(time.day)}'
      '_${two(time.hour)}${two(time.minute)}${two(time.second)}';
}

/// Закрывает БД, не заслоняя исходную ошибку открытия.
Future<void> _closeQuietly(AppDatabase database) async {
  try {
    await database.close();
  } on Object {
    // Соединение уже разорвано сбоем — важен исходный диагноз.
  }
}
