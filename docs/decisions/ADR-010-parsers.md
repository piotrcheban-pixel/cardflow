# ADR-010 — Парсеры документов: `ParsedDocument`, кодировки, лимиты, изоляты

**Дата:** 2026-11-13 · **Статус:** принято (итерация 3a) · **Связано:** SPEC A8.3, A8.5, A6.8; ADR-003; `docs/dependencies.md`; `journal/iteration-3a/spikes.md`

## Контекст

SPEC A8.3 требует нативного локального парсинга PDF, DOCX, XLSX, PPTX, ODT, TXT/MD, RTF в нормализованный
текст с границами разделов и метаданными; ошибки — понятные, по файлу; лимит 25 МБ; `.doc`/`.xls` — ADR-003.
Пайплайн A8.5 режет текст по границам разделов (заголовки/слайды/страницы/листы) — значит парсер обязан
отдавать эти границы, а не только плоский текст. Спайки (`journal/iteration-3a/spikes.md`) подтвердили:
`pdfrx` извлекает текстовый слой и работает в `Isolate.run`; `excel_plus` отдаёт `FormulaCellValue.cachedValue`;
`enough_convert` покрывает cp1251/KOI8-R; OOXML разбирается `archive` + `xml` (`innerText`).

## Решение

### 1. Формат результата (`lib/domain/text/`)

```dart
class ParsedDocument {
  final DocumentFormat format;
  final String fileName;
  final String text;                 // нормализованный текст, границы разделов — смещения в нём
  final List<ParsedSection> sections; // {title?, start, end} — start/end в границах text
  final ParsedDocumentMetadata metadata;
}
```

- `ParsedSection.start/end` — смещения в `text` (границы разделов для чанкинга A8.5). Пустой текст → ошибка
  `emptyText` (парсер не отдаёт пустой документ).
- `metadata`: `pageCount` (PDF), `slideCount` (PPTX), `sheetNames` (XLSX), `encoding` (TXT/MD) — nullable.
- Нормализация единая для всех парсеров (`normalizeDocumentText`): `\r\n`/`\r` → `\n`, NUL и control-символы
  кроме `\t\n` удаляются, NBSP → пробел, хвостовые пробелы строк убираются, 3+ пустых строк → 2, концы обрезаются.
  Это гарантирует одинаковый текст и одинаковые `content_hash`-пути при повторном парсинге.

### 2. Ошибки (`lib/domain/text/parser_exception.dart`)

`ParserErrorCode { unsupportedFormat, fileTooLarge, unreadableFile, scannedPdf, emptyText }`.
Парсеры бросают `ParserException(code, details)`; `details` — для логов/тестов, **никогда** не в UI.
UI-слой маппит код в ARB (`lib/ui/generation/parser_error_message.dart`): «Не удалось прочитать файл»,
«Формат не поддерживается. Сохраните файл как DOCX или XLSX и попробуйте снова», «В файле нет текстового слоя.
Похоже, это скан. Загрузите PDF с текстом», лимит размера, «В файле нет текста».

### 3. Определение формата и `.doc`/`.xls`

- Формат — по расширению имени файла (регистр не важен): `.pdf/.docx/.xlsx/.pptx/.odt/.txt/.md/.rtf/.doc/.xls`.
- Сигнатуры валидируются перед парсингом: OOXML/ODT — ZIP (`PK\x03\x04`), PDF — `%PDF-`, RTF — `{\rtf`;
  несовпадение → `unreadableFile`. TXT/MD — без сигнатур.
- `.doc`/`.xls` → сразу `unsupportedFormat` (ADR-003), файл не читается и не блокирует остальные.
- Неизвестное расширение → `unsupportedFormat`.

### 4. Лимиты

- `maxFileBytes` = 25 МБ (SPEC A8.3) — проверяется до парсинга, иначе `fileTooLarge`.
- Внутри ZIP-форматов: лимит записей (10 000), лимит размера одной записи (32 МБ) и суммарного распакованного
  объёма (120 МБ) — защита от zip-bomb; превышение → `unreadableFile`.
- Объём извлечённого текста не ограничивается на этапе парсинга (бюджет модели и чанкинг — итерация 3c).

### 5. Парсеры (`lib/api/parsers/`)

| Формат | Реализация | Разделы |
|---|---|---|
| DOCX | `archive` + `xml`: `word/document.xml`, `w:p`/`w:t`, `w:tab`, `w:br`; таблицы `w:tbl`/`w:tr`/`w:tc` → строки через табуляцию | по заголовкам `w:pStyle` = `Heading*`/`Title`; текст до первого заголовка — раздел без title |
| PPTX | `archive` + `xml`: порядок из `ppt/presentation.xml` + `ppt/_rels/presentation.xml.rels`; fallback — числовой порядок `slideN.xml`; текст `a:t` | по слайдам (title null) |
| ODT | `archive` + `xml`: `content.xml`, `text:h` — заголовки разделов, `text:p` — абзацы | по `text:h` (title = текст заголовка) |
| XLSX | `excel_plus`: листы → разделы (title = имя листа); строки → строки, ячейки через `\t`; `FormulaCellValue` → `cachedValue` (SPEC), `DateCellValue` → `yyyy-MM-dd`, пустые хвостовые ячейки обрезаются | по листам |
| TXT/MD | байты → текст с явным определением кодировки (см. п. 6); MD — без разметки (текст как есть) | один раздел |
| RTF | собственный минимальный конвертер (см. п. 7) | один раздел |
| PDF | `pdfrx`: `PdfDocument.openData` + `page.loadText()`; пустой текст по всем страницам → `scannedPdf`; битый/запароленный PDF → `unreadableFile` | по страницам (title null) |

### 6. Определение кодировки TXT/MD (порядок)

1. BOM UTF-8 (`EF BB BF`) → UTF-8 без BOM.
2. BOM UTF-16 LE/BE (`FF FE`/`FE FF`) → UTF-16.
3. Строгий `utf8.decode(allowMalformed: false)` — успех → UTF-8.
4. Иначе декодируем `Windows1251Codec` и `Koi8rCodec`; выбираем вариант с большей долей кириллических букв
   среди букв (равенство — cp1251, как более частый для русских документов). Кодировка пишется в `metadata.encoding`
   (`utf-8`, `utf-8-bom`, `utf-16le`, `utf-16be`, `windows-1251`, `koi8-r`).

### 7. RTF-конвертер (минимальный, без внешних пакетов — так требует SPEC)

- Разбор по байтам (latin1), состояния: глубина группы, режим «пропустить группу», `\ucN` (по умолчанию 1),
  `\ansicpgN` (кодовая страница; при отсутствии — cp1251), счётчик пропуска после `\uN`.
- Пропуск групп: `fonttbl`, `colortbl`, `stylesheet`, `pict`, `info` (+ `header`, `footer`, `object`, `themedata`);
  управления `\*` — пропуск группы.
- Текст: `\'hh` — байт в текущей кодовой странице (cp1251/cp1252/KOI8-R через `enough_convert`),
  `\uN` (signed 16-bit) → code point + пропуск `\ucN` символов; `\par`/`\line` → `\n`, `\tab` → `\t`;
  `\\`, `\{`, `\}` — литералы; прочие control words игнорируются.
- Не-RTF вход (нет `{\rtf`) → `unreadableFile`.

### 8. Изоляты и сервис (`lib/api/parsers/file_parsing_service.dart`)

- `DocumentParser.parse` — асинхронный; каждый файл парсится отдельно.
- `FileParsingService` инжектит `IsolateRunner` (по умолчанию `Isolate.run`), чтобы в unit-тестах подменять
  прогон парсера и проверять, что изолят используется; интеграционный тест идёт реальным изолятом.
- `parseAll` сохраняет порядок файлов и возвращает результат по каждому: success(ParsedDocument) | failure(fileName, code).
  Ошибка одного файла не прерывает остальные (SPEC A8.3), неожиданное исключение парсера → `unreadableFile`
  (сырой текст исключения наружу не выходит).

### 9. PDF и pdfrx

- Используется `pdfrx` 2.12.0 (MIT) — виджеты не используются; в изоляте вызывается `pdfrxInitialize()`
  (Dart-инициализация); `pdfrxFlutterInitialize()` не нужен.
- **Откуда PDFium:** в приложении — native assets (`pdfium_dart`, Windows/Linux/Android) или XCFramework
  (iOS/macOS, через `pdfium_flutter`); в **`flutter test`** native assets PDFium не дают (L26), поэтому CI
  job `test` скачивает pinned релиз `bblanchon/pdfium-binaries` `chromium/8125` (тот же, что в build-hook
  `pdfium_dart` 0.4.1), проверяет sha256 и экспортирует `PDFIUM_PATH`; `pdfrxInitialize()` читает переменную
  и грузит модуль по явному пути.
- `passwordProvider: () => null` → запароленный PDF → `unreadableFile`; `PdfException` → `unreadableFile`.

### 10. Итерационные границы

- В итерации 3a **нет UI-экрана**: парсеры + сервис + ARB-сообщения + маппинг ошибок; экран A6.8, drag-n-drop
  и прогресс — итерация 3c. Мёртвых кнопок не добавляем.

### 11. Политика покрытия PDF в CI (L26)

- **PDF-тесты не скипаются и не тегируются.** Ситуация «PDFium недоступен» — это красный job, который чинится
  инфраструктурой CI, а не тихое отключение покрытия. Политику защищает guard `test/guards/ci_pdfium_test.dart`:
  матрица ОС (`ubuntu/windows/macos`), команда тестов (`--exclude-tags golden` без дополнительных фильтров),
  отсутствие `skip`/тегов/`testOn` в PDF-тестах, наличие PDFium-бутстрапа с sha256 до шага тестов.
- PDFium в CI — **pinned** `bblanchon/pdfium-binaries` `chromium/8125`: тот же релиз скачивает build-hook
  `pdfium_dart` 0.4.1. При обновлении `pdfium_dart`/`pdfrx` обновлять пин в `.github/workflows/ci.yml`
  (URL, имена ассетов и три sha256) в том же коммите; иначе PDF-тесты могут грузить несовместимый API.
- **Остаточные риски (осознанно):** сеть до GitHub releases (сбой → красный job, не skip); macOS-ассет только
  arm64 (`macos-latest`); iOS-тестов PDF нет (iOS покрыт сборкой); реальные PDF-файлы и лимиты 25 МБ — L23/L25.
- `.gitattributes` (`* text=auto eol=lf`) — общий инвариант: guard-тесты читают файлы и сверяют точные
  маркеры; CRLF из checkout-а на Windows ломал L26-guard (ревью B1).

## Последствия

**Плюсы:** единый нормализованный текст и границы разделов для чанкинга 3c; понятные ошибки по файлу;
лимиты защищают от OOM/zip-bomb; PDF-текст без платных лицензий (pdfrx/MIT); тесты на всех форматах
воспроизводимы (фикстуры генерируются кодом).

**Минусы/риски:** RTF-конвертер — минимальный (не полный RTF); `.doc`/`.xls` не поддерживаются (ADR-003);
pdfrx тянет нативные PDFium (сборка/pdfium в тестах на 3 ОС CI — проверяется); XLSX-даты нормализуются к
`yyyy-MM-dd` (не локальный формат) — осознанно для детерминизма.

**Обязательства:** сообщения — только из ARB (guard `ru_strings`); ошибка файла не блокирует остальные;
один нормализатор текста на весь проект; при изменении поведения — новый ADR, а не тихая правка.

## Дополнения fix-итерации (2026-11-13, по итогам независимого ревью)

Ревью (`journal/iteration-3a/review.md`) выявило расхождения с §1, §3, §4, §5, §7; решения уточняются ниже.

1. **§1 — разделитель разделов.** Текст собирается из нормализованных разделов, между разделами — ровно
   пустая строка (`\n\n`); смещения `start/end` считаются по итоговому тексту. Модели immutable:
   `ParsedDocument.sections` и `ParsedDocumentMetadata.sheetNames` — `List.unmodifiable`.
2. **§3 — сигнатуры строгие.** OOXML/ODF-контейнер обязан начинаться с `PK\x03\x04` (пустой ZIP `PK\x05\x06`
   документом не считается); RTF-сигнатура `{\rtf` допускает ведущие пробельные байты (и парсер, и сервис).
3. **§4 — ZIP-лимиты для всех четырёх контейнеров.** XLSX тоже проходит `SecureZip` (записи/размер записи/
   суммарный объём) **до** `excel_plus`; иначе 25-МБ `.xlsx` мог развернуться в гигабайты в изоляте (OOM).
   `SecureZip` декодирует архив в строгом режиме (`verify: true, throwOnError: true`): повреждённая
   структура → `unreadableFile`, а не пустой/частичный архив.
4. **§5 — DOCX.** Поддерево `w:pPr` (таб-стопы `w:tabs/w:tab`, рамки) — разметка, а не текст абзаца:
   пропускается. Блочные контейнеры `w:sdt` → `w:sdtContent` и `w:customXml` разворачиваются (текст
   content controls не теряется). Вложенные таблицы по-прежнему уплощаются в текст ячейки.
5. **§5 — ODT.** Пропускаются служебные поддеревья: `text:index-body`/`text:table-of-content` (оглавление),
   `office:annotation` (примечания рецензентов), `text:tracked-changes` — иначе оглавление дублирует текст.
6. **§5 — XLSX.** `DateTimeCellValue` нормализуется к `yyyy-MM-dd` (как и `DateCellValue`); формула без
   кэшированного `<v>` не теряется: выводится исходная формула с `=` (данные из не-Excel инструментов
   не исчезают молча). Числовые/текстовые/датовые значения — `toString`/`yyyy-MM-dd`.
7. **§6 — TXT/MD без изменений** (BOM → строгий UTF-8 → cp1251/KOI8-R по частотной оценке; равенство — cp1251).
8. **§7 — RTF.** `\*` пропускает **текущую** группу (в которой стоит `\*`), а не следующую; сырые `\r`/`\n`
   RTF-потока игнорируются (это форматирование файла); `\ucN` ограничен группой (восстанавливается на `}`);
   `\ansicpg` поддерживает 1251 (по умолчанию), 1252, 20866 (KOI8-R), 21866 (KOI8-U), 65001 (UTF-8);
   control symbols `\~` → пробел, `\_` → дефис, `\-` → пусто.
9. **§8 — сервис без изменений**, добавлено: код `ParserException`, брошенный внутри `Isolate.run`,
   сохраняется (интеграционный тест), а не подменяется `unreadableFile`.
10. **§9 — PDF.** Если ни одна страница не дала текста, но были ошибки `loadText()` — `unreadableFile`;
    если ошибок не было и текста нет — `scannedPdf`; запароленный PDF (стандартный security handler)
    → `unreadableFile` (тест с программной зашифрованной фикстурой V1/R2 RC4 40-bit).

## Известные ограничения парсеров (см. `journal/KNOWN_LIMITATIONS.md` L23–L27)

Реальные файлы Word/LibreOffice/PDF не проверялись живьём (фикстуры программные); вложенные таблицы DOCX
уплощаются; нумерация списков не извлекается; 25 МБ и производительность/OOM не тестировались;
pdfrx/PDFium в тестах на Linux/macOS CI проверяется прогоном итерации 3a.

