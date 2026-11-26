/// Классификация сбоев локального хранилища по тексту исключения.
///
/// Drift/SQLite и `dart:io` не приводятся к общему типу в слоях генерации:
/// репозитории drift оборачивают свои ошибки сами, но неожиданный сбой всё
/// равно может прийти сырым. Классификация по маркерам (те же, что у настроек,
/// ADR-047) позволяет показать пользователю причину «хранилище недоступно», а
/// не общую строку, и сохранить причину в `generation_jobs`/логе.
library;

/// Признаки сбоя записи/чтения локального хранилища.
///
/// Блокировка БД (`database is locked`) включена: сообщение конкретнее общей
/// строки, а повтор пользователь выполняет сам. Сырой текст в UI не попадает —
/// только строка ARB.
const List<String> storageFailureMarkers = <String>[
  'readonly', // SQLITE_READONLY: attempt to write a readonly database
  'read-only',
  'read only',
  'access is denied', // Win32 через dart:io
  'permission denied', // POSIX через dart:io
  'отказано в доступе', // русская локаль ОС
  'errno = 5', // EACCES в тексте OSError
  'errno = 13',
  'errno = 28', // ENOSPC: нет места на диске
  'database is locked',
  'sqliteexception',
  'driftremoteexception',
  'disk is full',
  'database is closed',
];

/// Похоже ли исключение на сбой локального хранилища/БД.
///
/// [error] — любое исключение; проверяется только текст, без сети и секретов.
bool isStorageFailure(Object error) {
  final String text = error.toString().toLowerCase();
  return storageFailureMarkers.any(text.contains);
}
