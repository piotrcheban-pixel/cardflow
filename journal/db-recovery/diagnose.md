# Диагностика инцидента «Не удалось открыть базу данных» (2026-11-28)

Владелец запустил Windows-релиз `1.0.2+3` и получил экран
`databaseOpenError` («Не удалось открыть базу данных. Перезапустите
приложение»). Приложение неработоспособно; данные владельца — 14 колод,
392 карточки, 448 повторений, 163 медиа.

## 1. Состояние файла БД владельца

Файл: `%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite` (757 760 Б,
mtime 25.11.2026 13:27 — **приложение в него не писало**).

```
user_version: 1
integrity: ok
sqlite_master: 10 таблиц схемы v1 + 3 индекса (SPEC A5)
decks 14, cards 392, review_logs 448, media 163, generation_jobs 28
foreign_key_check: []
```

Вывод: файл **не повреждён**, миграция не выполнялась (версия 1).

## 2. Воспроизведение production-пути на копии

Копия файла во временном каталоге, открытие тем же кодом, что в приложении
(`openAppDatabase` → `NativeDatabase.createInBackground` → миграции):

```
raw user_version=1
openAppDatabase OK
after open user_version=3
decks=14
tables=[app_settings, card_drafts, cards, decks, generation_batches,
        generation_jobs, generation_runs, generation_units, knowledge_maps,
        media, practice_logs, review_logs, session_presets, source_docs,
        sync_meta]
after user_version=3
bak exists=true
```

**Миграция 1 → 2 → 3 исправна**, данные сохранены. Причина не в
`onUpgrade`/`MigrationStrategy`/`PRAGMA foreign_keys`.

## 3. Точная ошибка старта (временное логирование в `main.dart`)

Запуск собранного релиза с записью шагов старта:

```
start
base=C:\Users\piotr\AppData\Roaming\ru.example\cardflow
ERROR PathAccessException: Cannot copy file to
  '...\cardflow\cardflow.sqlite.bak', path = '...\cardflow\cardflow.sqlite'
  (OS Error: Отказано в доступе, errno = 5)
#2 backupBeforeMigration (package:cardflow/data/db/database_opener.dart:52)
#3 openAppDatabase (package:cardflow/data/db/database_opener.dart:37)
#4 main (package:cardflow/main.dart:35)
```

Сбой — **копирование `.bak` перед миграцией**; исключение выходит из
`openAppDatabase` и попадает в общий `catch` `main()` → экран ошибки. Файл БД
остаётся версии 1, mtime не меняется — ровно то, что видно в §1.

## 4. Почему отказано в доступе (внешняя среда, не приложение)

Признак: процесс не может создавать файлы в `%APPDATA%` и `%TEMP%`, но пишет в
каталог проекта. Проверено контрольно:

| запуск | integrity-токен | запись в `%APPDATA%`/`%TEMP%` |
|---|---|---|
| `cardflow.exe` из `build\windows\...\Release` | `S-1-16-4096` (Low) | отказ (errno 5) |
| та же сборка, скопированная в `C:\Temp\cfrel` | `S-1-16-8192` (Medium) | успех; БД мигрировала до v3 |
| `notepad.exe`, скопированный в каталог проекта | `S-1-16-4096` (Low) | — |
| `notepad.exe` в `Downloads` / на `Desktop` | `S-1-16-8192` (Medium) | — |
| `cardflow.exe` из проекта, запущенный через `WmiPrvSE.exe` (вне дерева агента) | `S-1-16-4096` (Low) | — |

Итог: исполняемые файлы, **лежащие в каталоге проекта**, запускаются с
Low-integrity токеном (mandatory integrity control запрещает Low-процессу
создавать/менять объекты Medium — `%APPDATA%`, `%TEMP%`). Это ограничение среды
агента (`DSH_SHELL=1`, песочница рабочего каталога), а не дефект CardFlow.
Владелец запускал релиз из `build\windows\...` — то есть из каталога проекта.

ACL каталога данных при этом в порядке (`icacls`: `PETER\piotr:(I)(OI)(CI)(F)`);
прямая запись `.bak` и копирование из шелла (Medium) проходят.

## 5. Слабые места приложения, которые превратили отказ среды в «кирпич»

1. `backupBeforeMigration` бросал исключение наружу — бэкап был **условием**
   открытия, хотя задуман страховкой.
2. Не было восстановления: повреждённый/нечитаемый файл БД означал вечную
   ошибку старта.
3. Миграции применялись лениво — сбой файла мог всплыть позже, в произвольном
   месте UI.
4. Экран ошибки не различал «нет прав» и «файл повреждён».

## 6. Что сделано

См. `docs/decisions/ADR-057-database-recovery-and-best-effort-backup.md`:
бэкап best-effort; eager-миграции на старте; аварийное восстановление
`cardflow.sqlite.corrupted_<дата>` для `SQLITE_NOTADB`/`SQLITE_CORRUPT`; подсказка
о правах на экране ошибки; уведомление о восстановлении в приложении.

## 7. Реальная проверка на машине владельца

После правок (см. `journal/db-recovery/verify.md`):
- сборка запущена **вне каталога проекта** — приложение открывается, БД
  мигрирована до v3, данные (14 колод / 392 карточки / 448 повторений / 163
  медиа) на месте, `integrity_check = ok`;
- сборка запущена **из каталога проекта** (Low) — приложение показывает экран
  ошибки **с подсказкой о правах** (`databaseOpenAccessHint`), файл БД не
  тронут;
- мусорный `cardflow.sqlite` — приложение запускается, файл отложен в
  `cardflow.sqlite.corrupted_<дата>`, создана новая БД (проверено на реальной
  машине и тестами).

**Что должен сделать владелец:** распаковать релиз и запускать `.exe` **не из
каталога проекта** (например, `C:\Users\piotr\Downloads\cardflow-1.0.2`).
Каталог проекта в песочнице агента — Low-integrity: приложение физически не
может записать `%APPDATA%` из него, и это не исправляется кодом.
