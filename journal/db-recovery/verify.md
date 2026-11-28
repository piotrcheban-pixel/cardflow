# Итоги итерации «Починка базы данных и миграции» (2026-11-28)

**Задача:** owner-note — Windows-релиз показывает «Не удалось открыть базу
данных. Перезапустите приложение»; приложение неработоспособно. Диагностика,
исправление, тесты, проверка на Windows.

**Факты старта:** ветка `main`, `HEAD = a5f3986` (док среза 18); baseline —
3310 passed + 21 skipped, покрытие 90,9 %, `schemaVersion = 3`, релиз `1.0.2+3`;
БД владельца — схема v1 (14 колод, 392 карточки, 448 повторений, 163 медиа).

## 1. Причина (подробно — `diagnose.md`)

- Файл БД владельца цел (`integrity_check = ok`, `user_version = 1`), миграция
  1 → 2 → 3 на копии проходит, данные сохраняются. **Миграция не была
  сломана.**
- Реальный сбой — `backupBeforeMigration`: копирование `cardflow.sqlite` →
  `cardflow.sqlite.bak` падало с `PathAccessException ... errno = 5`, и
  исключение выходило из `openAppDatabase`, минуя любую обработку.
- Причина отказа в доступе — среда: процессы из каталога проекта запускаются с
  Low-integrity токеном (`S-1-16-4096`), запись в `%APPDATA%`/`%TEMP%` запрещена
  mandatory integrity control. Та же сборка вне каталога проекта
  (`C:\Temp\...`) открывает БД и мигрирует её; `notepad.exe` в каталоге проекта
  тоже Low. Владелец запускал exe из `build\windows\...` — то есть из проекта.

## 2. Что исправлено

| Файл | Изменение |
|---|---|
| `lib/data/db/database_opener.dart` | бэкап best-effort (сбой копии не блокирует старт); eager-миграции при открытии; `openAppDatabaseWithRecovery` → `OpenedDatabase`; аварийное восстановление `cardflow.sqlite.corrupted_<yyyyMMdd_HHmmss>` для `SQLITE_NOTADB`/`SQLITE_CORRUPT` (проба файла `sqlite3`, вместе с `-journal`/`-wal`/`-shm`); классификаторы `isCorruptedDatabaseError`/`isDatabaseAccessFailure` |
| `lib/main.dart` | открытие через `openAppDatabaseWithRecovery`; экран ошибки получает признак «нет доступа»; в release логируется только тип сбоя, в debug — текст/стек; уведомление о восстановлении |
| `lib/ui/app.dart` | `StartupErrorApp(accessDenied)` — подсказка о правах; `CardFlowApp(recoveredDatabaseFileName)` — SnackBar о восстановлении после первого кадра |
| `lib/l10n/app_ru.arb` (+ сгенерированные) | `databaseOpenAccessHint`, `databaseRecoveredNotice` |
| `pubspec.yaml`, `about_links.dart` | версия `1.0.3+4` / `appVersion 1.0.3` |

Решения — `docs/decisions/ADR-057-database-recovery-and-best-effort-backup.md`;
политика ADR-005 §5 сохраняется для понижения версии и неизвестных апгрейдов.

## 3. Тесты

Красная фаза (до правок, assertion-level):

```
файл-мусор вместо БД [E] SqliteException(26): ... file is not a database
сбой копии .bak [E] PathExistsException: Cannot copy file to '...cardflow.sqlite.bak'
```

Добавлено/расширено (12 тестов):

- `test/unit/data/db/schema_test.dart`: мусорный файл → открывается пустая БД,
  файл сохранён как `.corrupted_*`; занятый путь `.bak` (каталог) → БД
  открывается, данные v1 на месте.
- `test/unit/data/db/database_recovery_test.dart` (новый): БД v1 **полной схемы
  SPEC A5** на реальном файле мигрирует до v3 (`user_version = 3`,
  `PRAGMA foreign_keys = 1`, колоды/карточки/повторения/медиа сохранены,
  таблицы v2/v3 и колонки Dedup созданы, `.bak` версии 1 рядом); мусорный файл →
  имя `cardflow.sqlite.corrupted_20261128_204005` при подставленных часах,
  новая БД переживает переоткрытие; повторное восстановление не перетирает
  прошлую копию (два файла с разным содержимым); понижение версии (99) —
  fail-fast, файл не переименован; классификация `SQLITE_CORRUPT/NOTADB` и
  `PERM/READONLY/CANTOPEN/AUTH` vs `BUSY`/`StateError`.
- `test/widget/app_test.dart`: подсказка о правах на экране ошибки (и её
  отсутствие без признака), уведомление о восстановлении показывается один раз
  и не появляется при обычном старте.

Итог: см. §4.

## 4. Гейты

- `fvm dart format lib test tool` → **0 changed** (755 файлов);
  `--set-exit-if-changed` → exit 0.
- `fvm flutter analyze --no-pub lib test tool` → **No issues found!**
- `fvm flutter test --no-pub --coverage --exclude-tags golden` →
  **3322 passed + 21 skipped, exit 0** (+12 к baseline), лог —
  `green-full-final.txt`.
- Покрытие рукописного кода — **90,9 % (27613/30386)**, порог 80 % пройден,
  `coverage-final.txt` (baseline — 90,9 %, 27544/30314).
- CI — run (см. STATE.md).

## 5. Проверка на Windows (реальная машина)

- `fvm flutter build windows --release` → `cardflow.exe` (версия `1.0.3+4`).
- Запуск **вне каталога проекта** (копия `C:\Temp\cardflow-1.0.3`):
  окно открывается, экран «Колоды», БД мигрирована до v3, `integrity_check =
  ok`, 14 колод / 392 карточки / 448 повторений / 163 медиа; `cardflow.sqlite.bak`
  версии 1 рядом.
- Запуск **из каталога проекта** (Low-integrity песочница агента): экран ошибки
  с подсказкой `databaseOpenAccessHint`, файл БД не тронут (mtime/версия те же).
- Мусорный `cardflow.sqlite` в реальном каталоге данных: приложение запускается,
  файл отложен как `cardflow.sqlite.corrupted_<дата>`, создана новая БД,
  уведомление показано; после проверки исходная БД возвращена.
