/// Причины отказа записи пользовательских настроек (ADR-047).
///
/// Контракт хранения ([AppSettingsStore.write]) бросает
/// [AppSettingsWriteException]; UI маппит [AppSettingsWriteFailure] в строку
/// ARB. Текст исключения (drift/SQLite/`dart:io`) пользователю не показывается.
library;

/// Причина отказа записи настроек.
enum AppSettingsWriteFailure {
  /// Операционная система запретила запись в каталог данных приложения:
  /// `SQLITE_READONLY` (код 8), «attempt to write a readonly database»,
  /// отказ доступа к файлу. Лечится не повтором, а правами на папку.
  writeDenied,

  /// Прочие ошибки записи (неизвестная причина) — общая строка ARB.
  unknown,
}

/// Ошибка записи настроек с машинной причиной.
class AppSettingsWriteException implements Exception {
  /// Создаёт ошибку с причиной [failure].
  const AppSettingsWriteException(this.failure, {this.details});

  /// Причина для маппинга в UI.
  final AppSettingsWriteFailure failure;

  /// Технические детали для логов/тестов (пользователю не показываются).
  final String? details;

  @override
  String toString() => 'AppSettingsWriteException(${failure.name}): $details';
}

/// Классифицирует ошибку записи настроек.
///
/// Признак отказа в правах ищется по тексту драйвера, потому что drift не
/// сохраняет исходный `SqliteException` в типизированном виде: он приходит как
/// `DriftRemoteException` с вложенным текстом (в журнале дефекта —
/// «SqliteException(8): attempt to write a readonly database»). Для прямого
/// соединения (`NativeDatabase` без изолята) приходит сам `SqliteException`, но
/// домен не должен зависеть от пакета `sqlite3`, поэтому решение принимает
/// единый разбор текста; тест `app_settings_write_error_test` проверяет на
/// настоящей readonly-БД, что текст совпадает с ожидаемым.
AppSettingsWriteFailure classifyAppSettingsWriteFailure(Object error) {
  // `toString` покрывает и `FileSystemException`, и `SqliteException`, и
  // обёртку drift: причины перечислены в нижнем регистре.
  final String text = error.toString().toLowerCase();
  for (final String marker in _writeDeniedMarkers) {
    if (text.contains(marker)) return AppSettingsWriteFailure.writeDenied;
  }
  return AppSettingsWriteFailure.unknown;
}

/// Признаки отказа ОС в записи (права на каталог/файл данных).
///
/// Блокировка БД здесь намеренно отсутствует: `database is locked` — временное
/// состояние, для него повтор действительно помогает.
const List<String> _writeDeniedMarkers = <String>[
  'readonly', // SQLite: «attempt to write a readonly database», SQLITE_READONLY
  'read-only',
  'read only',
  'access is denied', // Win32 через dart:io
  'permission denied', // POSIX через dart:io
  'отказано в доступе', // русская локаль ОС
  'errno = 5', // EACCES в тексте OSError
  'errno = 13',
];
