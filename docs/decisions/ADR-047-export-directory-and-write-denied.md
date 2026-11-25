# ADR-047 — сохранение файла экспорта в «Загрузки» и честная ошибка прав записи

**Дата:** 2026-11-25 · **Статус:** принято. Уточняет
[ADR-006](ADR-006-deck-archive-and-file-gateway.md) (контракт `FileGateway`,
пикер `file_picker`) и [ADR-019](ADR-019-settings-statistics.md) §1
(хранение настроек в `app_settings`). Диагностика owner-note —
`journal/fix-export-settings/diagnosis.md`.

## Контекст

Владелец после установки релиза 1.0.0 сообщил о двух дефектах.

**1. Экспорт колоды.** Диалог сохранения открывался в корне профиля
пользователя (`C:\Users\piotr\`), и Windows отказывал:
«У вас нет разрешения на сохранение файлов в этом месте». Причина в коде:
`FilePickerGateway.saveZipFile` вызывал `FilePicker.saveFile` **без**
`initialDirectory`, поэтому нативный `IFileSaveDialog` стартовал в профиле
(`SHGetKnownFolderPath` не задавался), а не в пользовательском каталоге
загрузок. Параметр `initialDirectory` поддерживается `file_picker` 13.3.3 на
desktop (`windows_file_picker` 2.0.2: `SHCreateItemFromParsingName` +
`setFolder`).

**2. Сохранение настроек.** При любом изменении показывалось
«Не удалось сохранить настройки. Попробуйте ещё раз». Замер (debug-сборка,
диагностика в лог) дал точную причину:

```
DriftRemoteException: SqliteException(8): attempt to write a readonly database
Causing statement: INSERT INTO "app_settings" ... ON CONFLICT("key") DO UPDATE
```

То есть падала **запись в SQLite** (`SQLITE_READONLY`, код 8), а не
JSON-сериализация и не потеря провайдера:

* `AppSettings.toJson` — плоские примитивы (`String`/`bool`/`double`/`int`/
  `List<int>`), `jsonEncode` не может упасть; в БД лежит валидный
  `{"version":1,...}` (проверено по фактической базе приложения);
* `appSettingsProvider`/`AppSettingsController` не менялись: в редизайне
  TASK 04 (`3967d20`) в `settings_screen.dart` изменилась только панель
  разделов (градиент кромки), `_update`/`save` те же, что и в ADR-019;
* тот же код на файловой БД в доступном для записи каталоге сохраняет
  настройки: значение `daily_new_limit` 20 → 21 в UI **и** в
  `app_settings.value_json` (живая проверка, журнал).

`SQLITE_READONLY` приходит из ОС: попытка записи в каталог данных
(`%APPDATA%\ru.example\cardflow\cardflow`) отклонена процессу приложения
(`PathAccessException ... Отказано в доступе`), хотя ACL каталога даёт
пользователю `FullControl`, а сторонний процесс того же пользователя пишет
успешно. В среде агента запись за пределы рабочего каталога ограничена —
поэтому симптом воспроизводится и без дефекта в коде.

## Решение

### 1. Каталог по умолчанию для диалога сохранения — только desktop

`FilePickerGateway` получает `initialDirectory`:

1. `getDownloadsDirectory()` (`path_provider`) — пользовательские «Загрузки»;
2. если каталога нет/он `null` — `getApplicationDocumentsDirectory()`;
3. если и это недоступно (`UnsupportedError`, `MissingPlatformException`,
   любое исключение плагина) — `null`: диалог открывается там, где решит ОС
   (прежнее поведение), но это осознанный откат, а не дефолт.

На мобильных платформах `initialDirectory` **не передаётся**: на Android
`FilePicker.saveFile` пишет через SAF (`content://`), а `getDownloadsDirectory`
возвращает каталог приложения во внешнем хранилище — подставлять его в диалог
бессмысленно и потенциально ломает выбор места. Решение инжектируется
(`useInitialDirectory`/`saveDirectoryResolver`), чтобы тест проверял оба
сценария без платформенных хаков.

### 2. `ArchiveErrorCode.writeDenied` вместо системного текста Windows

`FileSystemException` (dart:io) из `saveFile` (плагин сам пишет байты после
диалога) и из `_ensureSaved` (дописывание, если плагин вернул путь без
записи) преобразуется в `ArchiveException(ArchiveErrorCode.writeDenied)`.
UI по-прежнему показывает **только** строку ARB: «Нет прав на запись в эту
папку. Выберите другую». Отмена диалога остаётся тихим no-op (ADR-006 п. 7).

Доменный код, а не `dart:io` в UI: `lib/ui/` не знает о файловых исключениях,
маппинг один — `archiveErrorCodeMessage` (switch по коду, компилятор требует
ветку для нового значения).

### 3. Настройки: причина видна в debug-логе, запись проверяется тестом

Код записи настроек не менялся — он корректен. Добавлено то, чего не хватало
для разбора:

* `SettingsDiagnostics` (`lib/ui/state/settings_diagnostics.dart`,
  по образцу ADR-024): тип исключения, текст drift/SQLite и первые 8 кадров
  стека — в `debugPrint` через `settingsDiagnosticsProvider`; в release —
  no-op. Пользователю по-прежнему только строка ARB;
* интеграционный тест на **файловой** drift-БД: изменение → `save` → закрытие
  → повторное открытие → `read` → значения совпадают (in-memory тест эту
  ошибку класса «файл/права/блокировка» не ловит).

## Последствия

* Экспорт по умолчанию предлагает «Загрузки», затем «Документы»; при отказе
  ОС пользователь видит русскую причину вместо системного текста.
* Схема БД, `schemaVersion`, `format_version` не менялись.
* `initialDirectory` на desktop поддерживается `windows_file_picker` 2.0.2;
  при обновлении `file_picker` проверить сохранение параметра (тест
  `file_picker_gateway_test` падает, если параметр перестанет доходить).
* Остаётся ограничение: если каталог данных приложения недоступен для записи
  (права ОС), настройки не сохраняются — теперь это видно в debug-логе и
  сопровождается русской строкой в UI, но самолечения нет (см.
  `journal/KNOWN_LIMITATIONS.md`).
