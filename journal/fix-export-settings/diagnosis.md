# Диагностика owner-note 1.0.1 — экспорт и сохранение настроек

**Дата:** 2026-11-25 · **Старт:** `HEAD = origin/main = 0d5446c`, ветка `main`,
`git status` — только неотслеживаемые каталоги аудита. Итерация «Фикс экспорта
и сохранения настроек», режим ИТЕРАЦИИ. Решение — ADR-047.

## 1. Экспорт: диалог открывался в корне профиля

Замер: `FilePickerGateway.saveZipFile` вызывал `FilePicker.saveFile` без
`initialDirectory` → нативный `IFileSaveDialog` открывался в профиле
пользователя (`C:\Users\piotr\`) и Windows отвечал «У вас нет разрешения на
сохранение файлов в этом месте».

Воспроизведение на живом приложении (debug, скриншот диалога до фикса:
каталог `C:\Users\piotr`) — владелец видел тот же путь.

После фикса (ADR-047 §1) живая проверка:

```
EXPORT-DIAG initialDirectory=C:\Users\piotr\Downloads
```

Скриншот `screenshots/export-dialog-downloads.png`: диалог «Save File»
открыт в **Downloads** (хлебные крошки `Downloads ›`, слева выбран
Downloads), предложенное имя файла — `Электротехника.zip`.

Первый прогон живой проверки дал другую ошибку — «В архиве не хватает
медиафайлов» (`ArchiveErrorCode.mediaMissing`): в диагностическую копию
каталога данных не был скопирован `media/`. После копирования 311 файлов
(36,1 МБ) экспорт дошёл до диалога сохранения. Это подтверждает, что
`mediaMissing` — не дефект экспорта, а следствие неполной копии данных.

## 2. Настройки: `SQLITE_READONLY`, а не JSON и не провайдер

Красная фаза: экран настроек показывал только строку ARB и проглатывал
исключение. Добавлена debug-диагностика (`SettingsDiagnostics`), прогон на
живом приложении дал точную причину:

```
Настройки не записаны: DriftRemoteException: SqliteException(8): while executing
statement, attempt to write a readonly database, attempt to write a readonly
database (code 8)
Causing statement: INSERT INTO "app_settings" ("key", "value_json") VALUES (?, ?)
ON CONFLICT("key") DO UPDATE SET "key" = ?, "value_json" = ?, parameters:
app.settings, {"version":1,"theme":"light",…,"daily_new_limit":21,…}
Стек (8): package:sqlite3/src/implementation/exception.dart 101:3 throwException |
… | package:drift/native.dart 440:7 _NativeDelegate.runInsert.<fn> | …
```

Что проверено и исключено:

| Гипотеза | Замер | Итог |
|---|---|---|
| JSON-сериализация новых полей после редизайна | `AppSettings.toJson` — плоские примитивы; в БД валидный `{"version":1,…}` | исключено |
| Потеря провайдера при рефакторинге оболочки | `app_providers.dart` в `3967d20` не менялся; в `settings_screen.dart` изменилась только панель разделов (градиент кромки) | исключено |
| Блокировка БД | в тексте ошибки `SQLITE_READONLY` (код 8), а не `SQLITE_BUSY` | не она |
| Права ОС на каталог данных | ACL `%APPDATA%\ru.example\cardflow\cardflow` — `FullControl` пользователю; сторонний процесс того же пользователя пишет в каталог успешно | причина ниже |
| Процесс приложения под ограничением записи | диагностический зонд в `main()`: `writeAsStringSync` в каталог данных → `PathAccessException: … Отказано в доступе (errno = 5)`; тот же зонд в каталоге проекта — `ok` | **внешнее ограничение среды** |

Контрольный опыт: каталог данных перенесён в рабочую папку проекта
(`CARDFLOW_DIAG_BASE`, временная правка), приложение запущено тем же
способом, настройки изменены кликом — значение `daily_new_limit`
**20 → 21** в UI и в `app_settings.value_json`, снекбара ошибки нет
(`screenshots/settings-saved-21.png`). Значит, проводка
`AppSettingsController → DriftAppSettingsStore → drift → файл` корректна, а
отказ записи в `%APPDATA%` даёт среда запуска (в этой сессии процессы
приложения не могут писать за пределы рабочего каталога).

Вывод для продукта: восстановить «сломанную запись» в коде нечего — её нет;
нужно (1) показать причину в debug-логе и (2) отличить отказ в правах от
прочих сбоев в UI, чтобы сообщение «Попробуйте ещё раз» не вводило в
заблуждение. Обе части сделаны (ADR-047 §3).

## 3. Гейты

Полный набор, `analyze`, `dart format`, покрытие и Windows-сборка — в
`journal/STATE.md` (итерация «Фикс экспорта и сохранения настроек»).
