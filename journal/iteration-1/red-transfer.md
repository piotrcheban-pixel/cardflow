# Красная фаза TDD — ZIP-кодек, MediaStore, FileGateway (task-2, фаза 1)

**Дата:** 2026-11-12 · **Автор:** archive-zip · **Задача:** task-2 (фаза 1) · **Ветка:** `main` (git не трогал, коммиты — Lead)
**Область:** `lib/data/transfer/{zip_deck_archive_codec,media_store,file_picker_gateway}.dart`, `test/unit/data/transfer/**`
**Контракт:** `docs/archive-format.md`, ADR-006, SPEC 0.4 п.4, A6.9, A5.

## 1. Окружение и проверка API

- Windows 11, Flutter 3.47.9 / Dart 3.13.7 через FVM (`fvm flutter test`, `fvm dart format`, `fvm dart analyze`).
- API `package:archive 4.6.0` проверен по исходникам pub-кэша
  (`.../pub.dev/archive-4.6.0/lib/src/...`): `ZipEncoder().encodeBytes(Archive, {modified})`,
  `ZipDecoder().decodeBytes(bytes, {verify, throwOnError})`, `ArchiveFile.bytes/string`,
  `ArchiveFile.readBytes()`, `Archive.find(name)`; `ArchiveException` пакета скрыт (`hide`),
  чтобы не конфликтовать с доменным `ArchiveException`.
- `file_picker 13.3.3` — новая модульная раскладка: `FilePicker.pickFile(...)` →
  `PlatformFile?` (с `path`/`uri`), `FilePicker.saveFile(...)` **пишет байты сам** и
  возвращает `Uri?`; `FilePickerPlatform.instance` подменяется в тестах.

## 2. Порядок TDD

1. Написаны тесты (до реализации):
   - `test/unit/data/transfer/zip_deck_archive_codec_test.dart` — 65 кейсов: публичный формат
     (порядок записей, поля `meta.json`/`cards.json`, epoch ms), roundtrip без потерь,
     ошибки `corruptZip`/`missingEntry`/`unsupportedVersion`/`invalidMeta`/`invalidCards`/
     `invalidEntryName`/`tooLarge`/`mediaMissing`, zip-slip, лимиты (инжектируемые),
     пустая колода, пустой медиафайл;
   - `test/unit/data/transfer/media_store_test.dart` — 31 кейс: запись/чтение/удаление,
     вложенные каталоги, пустой файл, перезапись, отсутствие временных файлов,
     path traversal (`..`, `..\\`, абсолютные пути, другой диск), отсутствующие файлы;
   - `test/unit/data/transfer/file_picker_gateway_test.dart` — 17 кейсов: `ensureZipExtension`,
     `saveFilePathFromUri`, пикеры через фейковый `FilePickerPlatform.instance`, `readFile`/`writeFile`.
2. Красная фаза (ниже).
3. Реализация.
4. Зелёный прогон: `fvm flutter test test/unit/data/transfer` → **113 tests, All tests passed**.

## 3. Red #1 — прогон тестов против заглушек Lead

`fvm flutter test test/unit/data/transfer` (заглушки `UnimplementedError`, кодек без
инжектируемых лимитов, нет чистых функций шлюза) → **ошибка компиляции тестов**, не
assertion-level. Фрагмент вывода:

```text
test/unit/data/transfer/file_picker_gateway_test.dart:121:14: Error: Method not found: 'ensureZipExtension'.
      expect(ensureZipExtension('Колода'), 'Колода.zip');
test/unit/data/transfer/file_picker_gateway_test.dart:141:14: Error: Method not found: 'saveFilePathFromUri'.
...
Error: The Dart compiler exited unexpectedly.
```

Вывод: этот прогон доказывает только наличие тестов, а не их проверяющую силу. Поэтому
красная фаза продолжена с минимальными фейковыми реализациями (возвращают пустые/неверные
значения, без реальной логики), чтобы получить **assertion-level** доказательства
«ожидалось / получено».

## 4. Red #2 — assertion-level: минимальные фейковые реализации

Заглушки заменены на фейковые: кодек `encode → Uint8List(0)`, `decode → пустой DeckArchive`;
`MediaStore` ничего не пишет и возвращает `null`; шлюз возвращает `null` из пикеров,
`ensureZipExtension` не добавляет расширение. Прогон:

```text
fvm flutter test test/unit/data/transfer
00:00 +11 -38: Some tests failed.
```

36 пар `Expected/Actual`, например:

```text
[E] FilePickerGateway: импорт возвращает путь выбранного файла и фильтр .zip
  Expected: 'C:\\Users\\...\\Temp\\...\\deck.zip'
    Actual: <null>

[E] ensureZipExtension добавляет .zip, если расширения нет
  Expected: 'Колода.zip'
    Actual: 'Колода'

[E] ensureZipExtension обрезает пробелы вокруг имени
  Expected: 'deck.zip'
    Actual: '  deck  '

[E] MediaStore: запись и чтение writeMedia создаёт файл в корневом каталоге и читается обратно
  Expected: true
    Actual: <false>

[E] MediaStore: запись и чтение пустой файл допустим
  Expected: empty
    Actual: <null>

[E] FilePickerGateway: экспорт не-file URI → UnsupportedError
  Expected: throws <Instance of 'UnsupportedError'>
    Actual: <Closure: () => Future<String?>>
```

Пройдено 11 — это кейсы, которые фейк случайно удовлетворял (например, «чтение
отсутствующего файла → null»), что нормально для красной фазы: проверяется, что зелёный
прогон будет осмысленным, а не пустым.

## 5. Red для кодека — контрольный mutation-прогон

Первый заход Red #2 для кодека не дошёл до assert'ов: в самом тест-файле был
не-const default-параметр (`Map<String, Object?> settings = _settings`), тест не
компилировался. Ошибка исправлена (`settings ?? _settings`). Чтобы честно подтвердить,
что кейсы кодека — assertion-level, а не «зелёные по факту компиляции», после фиксации
тестов выполнен **контрольный mutation-прогон**: реализация временно заменена фейковым
кодеком (пустые данные), `zip_deck_archive_codec_test.dart` прогнан, затем реализация
восстановлена из бэкапа (SHA-256 до/после совпал):

```text
fvm flutter test test/unit/data/transfer/zip_deck_archive_codec_test.dart
00:00 +1 -64: Some tests failed.
```

61 пара `Expected/Actual`, например:

```text
[E] encode — публичный формат v1 пишет meta.json, cards.json и media/<id> ...
  Expected: ['meta.json', 'cards.json', 'media/media-1', 'media/media-2']
    Actual: []

[E] encode — архив с архивной колодой сохраняет archived_at
  Expected: DateTime:<2026-11-11 23:59:59.000Z>
    Actual: <null>

[E] encode — неизвестная версия формата при encode → unsupportedVersion
  Expected: throws <Instance of 'ArchiveException'> with `code`:
            ArchiveErrorCode:<ArchiveErrorCode.unsupportedVersion>
    Actual: <Closure: () => Uint8List>

[E] roundtrip без потерь encode→decode ...
  Expected: DateTime:<2026-11-12 10:30:05.123Z>
    Actual: DateTime:<1970-01-01 00:00:00.000Z>
```

## 6. Зелёный прогон и проверки

```text
fvm flutter test test/unit/data/transfer
00:00 +113: All tests passed!

fvm dart format lib/data/transfer test/unit/data/transfer
Formatted 7 files

fvm dart analyze lib/data/transfer test/unit/data/transfer
No issues found!
```

Общий `fvm flutter analyze` по репозиторию на момент отчёта содержит ошибки **вне scope**
этого агента (параллельные правки `lib/ui/state/**`, `lib/l10n/**`, `test/helpers/**`,
`test/widget/**` — 22 issues); в `lib/data/transfer/**` и `test/unit/data/transfer/**`
issues нет.

## 7. Решения по валидации (соответствие `docs/archive-format.md`)

- `app` обязан быть строкой `"CardFlow"` (invalidMeta иначе), `exported_at` — ISO-8601;
  `cards_count`/`media_count` сверяются с содержимым архива (расхождение → invalidMeta);
- обязательные nullable-поля карточки/колоды должны присутствовать в JSON (значение `null`
  допустимо); отсутствие ключа → invalidCards/invalidMeta;
- `front` не пустой, тегов не больше 3 → invalidCards (как в `docs/archive-format.md`);
- медиа-запись в архиве без владельца (карточка не ссылается) → invalidEntryName;
  ссылка карточки на отсутствующую `media/<id>` → mediaMissing;
- лимиты инжектируются в конструктор кодека (по умолчанию — `DeckArchiveLimits`), это
  позволяет тестировать `tooLarge` без гигантских файлов;
- `encode` детерминирован (порядок записей и штамп `modified = exportedAt`), повторный
  encode одного объекта даёт идентичные байты; пункт «JSON без лишних полей» проверен
  точным набором ключей в тесте.

## 8. Что не проверено в красной/зелёной фазе

- `FilePickerGateway.readFile/writeFile` — покрыты на реальной ФС; пикеры — через
  подмену `FilePickerPlatform.instance` (плагин в unit-тестах не поднимается).
- `saveFile` на desktop создаёт пустой файл при выборе локации (API 13.3.3 пишет байты
  сам) — реальный диалог в тестах недоступен; поведение зафиксировано в отчёте Lead.
- zip-bomb на реальных больших архивах не проверялся — лимиты проверены на инжектируемых
  маленьких значениях.

---

# ФАЗА 2 — `DriftDeckTransferService` + новый контракт `FileGateway`

**Дата:** 2026-11-12 (продолжение) · **Основание:** сообщение Lead от 2026-11-12
(контрактное изменение `FileGateway`, допуск `media/`, старт фазы 2).

## 9. Контрактное изменение `FileGateway` (Lead)

`lib/domain/transfer/file_gateway.dart` изменён Lead'ом: вместо
`pickZipSaveLocation` + `writeFile` — один метод
`Future<bool> saveZipFile({required String suggestedFileName, required Uint8List bytes})`.
Причина: в `file_picker` 13.3.3 `saveFile` сам записывает байты и возвращает URI
(на mobile — `content://`, с которым `dart:io` не работает), отдельного «выбрать путь
без записи» API нет. Канонический fallback имени — `cardflow.zip` (ADR-006 п.8).

TDD фазы 2:

- **Red #1:** тесты переписаны под новый контракт, реализация ещё старая →
  ошибка компиляции `Missing concrete implementation of 'FileGateway.saveZipFile'`
  (и `CardRow.mediaIds` в моём тест-хелпере, исправлено до красного прогона).
- **Red #2:** фейковые реализации (гейтвей: пикеры «отменяются»/ничего не пишет;
  сервис: возвращает пустые `Uint8List`/`ImportPreview`/`ImportResult`):

```text
fvm flutter test test/unit/data/transfer/{file_picker_gateway,deck_transfer_service}_test.dart
00:00 +4 -32: Some tests failed.
```

25 пар `Expected/Actual`, например:

```text
[E] FilePickerGateway: saveZipFile desktop: файл дописывается, если плагин вернул URI без записи
  Expected: true
    Actual: <false>

[E] FilePickerGateway: импорт возвращает путь выбранного файла и фильтр .zip
  Expected: 'C:\\Users\\...\\Temp\\...\\deck.zip'
    Actual: <null>

[E] ensureZipExtension пустое имя заменяет запасным (ADR-006 п. 8)
  Expected: 'cardflow.zip'
    Actual: '   '

[E] DriftDeckTransferService: exportDeckZip отсутствующая колода → deckNotFound
  ... (ожидалось ArchiveException(deckNotFound), получено исключение отсутствия кода)

[E] DriftDeckTransferService: previewImport показывает имя, версию, карточки и медиа; БД не меняет
  Expected: 'Испанский: базовые глаголы'
    Actual: ''
```

- Реализация: `FilePicker.saveFile(fileName: ensureZipExtension(name), bytes: bytes,
  mimeType: 'application/zip')`; `null` → `false`; файловый URI — проверка размера и
  дописывание через `dart:io`, если плагин файл не записал/записал неполностью;
  `content://` → `true` (плагин записал сам). Параметры `type`/`allowedExtensions` у
  `saveFile` в 13.3.3 помечены `@Deprecated` и ни на что не влияют — не передаются
  (иначе `flutter analyze` не 0 issues); фильтр `.zip` реализован для пикера импорта
  (`pickFile(type: custom, allowedExtensions: ['zip'])`).
- Итог: `file_picker_gateway_test.dart` — 16 тестов зелёные; widget-тесты UI-агента,
  использующие новый контракт, разблокированы.

## 10. `DriftDeckTransferService` — красная фаза и реализация

Тесты (`test/unit/data/transfer/deck_transfer_service_test.dart`, 20 кейсов; реальные
`AppDatabase.inMemory()` + `NativeDatabase`, временный каталог `MediaStore`):

- экспорт: колода/карточки/медиа без потерь, архивная колода, `deckNotFound`,
  отсутствующий файл медиа → `mediaMissing`, пустая колода;
- предпросмотр: счётчики, дубликаты по `content_hash` (в архиве и по вычисленному
  для `null`), `mediaCount` только импортируемых карточек, отсутствие записи в БД,
  `corruptZip`;
- импорт: export→import→export без потери контента (все поля карточек, настройки/время
  колоды, медиа-байты, `sibling_id` пары `basic_reversed` переназначены взаимно),
  новые uuid v4 для колоды/карточек/медиа, пустая колода, дедупликация, вычисление
  `content_hash`, `deckName`-override, сохранение `archived_at`, запись файлов в
  `MediaStore` + строк `media`; откат транзакции и best-effort удаление файлов при
  сбое записи медиа; битый архив не меняет БД.

Реализация: одна `appDatabase.transaction`; новые id (uuid v4); дедупликация по
`content_hash` (первая карточка выигрывает, `null` → `contentHashOf`); медиа — новые
`media/<uuid><ext>` в `MediaStore` + строки `media`; при исключении — откат и
best-effort удаление записанных файлов; `deckNotFound`/`mediaMissing` — машинные коды.

## 11. Толерантность `media/` (уточнение Lead по ADR-006)

- zip-запись-каталог `media/` (0 байт, имя оканчивается на `/`) — **игнорируется**
  как directory-entry (так делают darwin/сторонние архиваторы), не `invalidEntryName`;
- прочие каталоги/файлы вне `{meta.json, cards.json, media/<id>}` — по-прежнему
  `invalidEntryName`; медиа без владельца — `invalidEntryName` (строго, подтверждено Lead);
- тесты: «запись-каталог media/ игнорируется», `extra/` → `invalidEntryName`,
  `media/` убран из списка недопустимых имён.

## 12. Итоговый зелёный прогон фазы 2

```text
fvm flutter test test/unit/data/transfer
00:00 +133: All tests passed!
  (кодек 66, MediaStore 31, FileGateway 16, DriftDeckTransferService 20)

fvm dart format lib/data/transfer test/unit/data/transfer
Formatted 8 files (0 changed)

fvm dart analyze lib/data/transfer test/unit/data/transfer
No issues found!

fvm flutter analyze
No issues found! (10.8s)
```

Не проверено на реальных устройствах: фактический системный диалог `file_picker` и
запись `content://` на mobile (только фейковый `FilePickerPlatform`); Android/iOS-сборки
локально недоступны (известное ограничение хоста).

---

# Fix-итерация по ревью (task-5): H1 / M8 / M9 / M10

**Дата:** 2026-11-12 · **Основание:** независимое ревью итерации 1 (findings H1, M8, M9,
M10), `journal/iteration-1/review.md` (полная версия появится у Lead). Контракт домена
уже поправлен Lead'ом: `DeckArchiveLimits.maxEntries = 10000`, dartdoc
`FileGateway.readFile` требует проверку размера до чтения. Домен не менялся.

## 13. Что исправлено

| Finding | Исправление | Файл |
|---|---|---|
| **H1** (OOM на больших архивах) | `FilePickerGateway.readFile`: `File(path).length()` до `readAsBytes`; `length > maxFileBytes` → `ArchiveException(tooLarge)`. Лимит инжектируемый: `FilePickerGateway({maxFileBytes = DeckArchiveLimits.maxImportBytes})`. | `file_picker_gateway.dart` |
| **M8** (нет лимита на число записей) | `ZipDeckArchiveCodec.decode`: после безопасного чтения zip и **до** валидации имён/содержимого — `archive.files.length > maxEntries` → `tooLarge`. Параметр `maxEntries` инжектируемый (default `DeckArchiveLimits.maxEntries`). | `zip_deck_archive_codec.dart` |
| **M9** (доверие `content_hash` из архива) | `DriftDeckTransferService`: `content_hash` **всегда пересчитывается** `contentHashOf(front, back)`; по нему же дедупликация и запись в БД. `previewImport` использует тот же пересчёт (одинаково с `importZip`). | `drift_deck_transfer_service.dart` |
| **M10** (пустое имя колоды) | decode: `deck.name.trim().isEmpty` → `invalidMeta`; `importZip` `deckName` уже триммится, пустой после trim = нет override (добавлен тест). | `zip_deck_archive_codec.dart`, `drift_deck_transfer_service.dart` |

Добавлены тесты: H1 — 2 шт. (файл больше лимита → `tooLarge`; файл ровно в лимите
читается); M8 — 2 шт. (N+1 записей → `tooLarge`; проверка раньше имён записей);
M9 — 2 шт. (подменённый хеш пересчитывается; дубликаты по пересчитанному хешу);
M10 — 3 шт. (пустое/пробельное имя в meta → `invalidMeta`; `deckName` из пробелов =
нет override). Все ранее зелёные тесты сохранены.

## 14. Красная фаза fix-итерации (assertion-level)

После добавления тестов + только сигнатур инжектируемых параметров (поведение ещё
не реализовано) — 7 новых тестов красные, фрагменты:

```text
fvm flutter test test/unit/data/transfer
00:01 +135 -7: Some tests failed.

[E] FilePickerGateway: readFile файл больше лимита → tooLarge до чтения в память (H1)
  Expected: throws <Instance of 'ArchiveException'> with `code`:
            ArchiveErrorCode:<ArchiveErrorCode.tooLarge>
    Actual: <Closure: () => Future<Uint8List>>

[E] importZip подменённый content_hash из архива пересчитывается (M9)
  Expected: '3f76c91c9b90b2a5e2765e8c6bd447517ab5613ac34a0c0b6eb374d50b3a893f'
    Actual: 'подменённый-хеш'

[E] importZip дубликаты определяются по пересчитанному хешу (M9)
  Expected: <1>
    Actual: <2>

[E] decode — meta.json пустое имя колоды → invalidMeta (M10)
  Expected: throws <Instance of 'ArchiveException'> with `code`:
            ArchiveErrorCode:<ArchiveErrorCode.invalidMeta>
    Actual: <Closure: () => DeckArchive>

[E] decode — число zip-записей больше maxEntries → tooLarge (M8)
  Expected: throws <Instance of 'ArchiveException'> with `code`:
            ArchiveErrorCode:<ArchiveErrorCode.tooLarge>
    Actual: <Closure: () => DeckArchive>
```

Затем реализованы проверки → зелёный.

## 15. Зелёный прогон после fix-итерации

```text
fvm flutter test test/unit/data/transfer
00:00 +142: All tests passed!
  (кодек 70, MediaStore 31, FileGateway 18, DriftDeckTransferService 23)

fvm dart format lib/data/transfer test/unit/data/transfer
Formatted 8 files (0 changed)

fvm dart analyze lib/data/transfer test/unit/data/transfer
No issues found!

fvm flutter test test/guards
00:00 +35: All tests passed!

fvm flutter analyze
No issues found! (4.8s)
```

Промежуточный прогон общего analyze показал 2 чужих issue вне scope
(`lib/data/decks/drift_deck_repository.dart` — параллельные правки Lead/data-drift);
на финальном прогоне они устранены, общий analyze — 0 issues.

Замечание по семантике: decode проверяет `deck.name.trim().isNotEmpty`, но сохраняет
имя как есть (без обрезки) — lossless; тримминг применяется только к `deckName`-override
при импорте.


