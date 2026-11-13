# Парсеры документов CardFlow (SPEC A8.3)

**Итерация:** 3a «Парсеры» · **Дата:** 2026-11-13 · **Решение:** ADR-010 · **План:** `journal/iteration-3a/plan.md`
**Статус:** реализовано и покрыто тестами; живой прогон на реальных Word/LibreOffice/PDF-файлах не выполнялся (см. раздел «Ограничения»).

## Назначение

Пользователь прикрепляет файлы к экрану генерации (A6.8). Каждый файл **локально** разбирается в
нормализованный текст с границами разделов, который затем режется на фрагменты по бюджету модели (A8.5,
итерация 3c). Сеть не участвует; WebView не используется (SPEC 3.3).

## Архитектура

| Слой | Файлы | Что делает |
|---|---|---|
| Домен | `lib/domain/text/document_format.dart` | `DocumentFormat`, определение по расширению, проверка сигнатур |
| Домен | `lib/domain/text/parsed_document.dart` | `ParsedDocument`, `ParsedSection` (`start/end/title`), `ParsedDocumentMetadata`; инварианты и immutable-списки |
| Домен | `lib/domain/text/parser_exception.dart` | `ParserErrorCode` (5 кодов) и `ParserException` (`details` — не в UI) |
| Домен | `lib/domain/text/document_text_normalization.dart` | Единый нормализатор извлечённого текста |
| API | `lib/api/parsers/*_parser.dart` | Нативные парсеры форматов; один общий интерфейс `DocumentParser` |
| API | `lib/api/parsers/zip_xml.dart` | `SecureZip` + лимиты ZIP-контейнеров, декодирование XML (BOM/UTF-16) |
| API | `lib/api/parsers/parsed_document_builder.dart` | Сборка текста и границ разделов из логических секций |
| API | `lib/api/parsers/file_parsing_service.dart` | Оркестрация: лимит 25 МБ, формат → парсер, `Isolate.run`, результат по каждому файлу |
| UI | `lib/ui/generation/parser_error_message.dart` | `ParserErrorCode` → строка ARB (никаких сырых ошибок) |

## Поддерживаемые форматы

| Формат | Библиотека | Разделы | Особенности |
|---|---|---|---|
| PDF | `pdfrx` (PDFium, MIT) в изоляте | страницы | Только текстовый слой; скан без слоя → `scannedPdf`; запароленный/битый → `unreadableFile`; `metadata.pageCount` |
| DOCX | `archive` + `xml` | заголовки `Heading*`/`Title` | абзацы → строки; таблицы → строки через `\t`; `w:tab`/`w:br`; content controls `w:sdt` и `w:customXml` разворачиваются; таб-стопы `w:pPr` игнорируются; текст до первого заголовка — раздел без title |
| PPTX | `archive` + `xml` | слайды | порядок из `ppt/presentation.xml` + rels; fallback — номер файла `slideN.xml`; `metadata.slideCount` |
| ODT | `archive` + `xml` | `text:h` | `text:p` — абзацы; оглавление (`index-body`/`table-of-content`), `office:annotation`, `tracked-changes` пропускаются |
| XLSX | `excel_plus` | листы (title = имя листа) | ячейки через `\t`, хвостовые пустые ячейки убираются; формулы — `FormulaCellValue.cachedValue` (без кэша — `=формула`, без тихой потери); даты — `yyyy-MM-dd`; `metadata.sheetNames`; ZIP-лимиты через `SecureZip` |
| TXT / MD | `enough_convert` | один раздел | определение кодировки: BOM UTF-8/UTF-16 → строгий UTF-8 → cp1251/KOI8-R по частотной оценке; кодировка в `metadata.encoding` |
| RTF | собственный минимальный конвертер | один раздел | `\'hh` с `\ansicpg` (1251 по умолчанию, 1252, 20866 KOI8-R, 21866 KOI8-U, UTF-8), `\uN` + `\ucN` (в границах группы), `\par`/`\line`/`\tab`, экранирование, `\~`/`\_`/`\-`, пропуск `fonttbl`/`colortbl`/`stylesheet`/`pict`/`info` и `\*`-групп |
| `.doc` / `.xls` | — | — | Не поддерживаются (ADR-003): сообщение «Формат не поддерживается. Сохраните файл как DOCX или XLSX и попробуйте снова», файл не читается |

## Ошибки и сообщения

| Код | Когда | Строка ARB |
|---|---|---|
| `unsupportedFormat` | `.doc`, `.xls`, неизвестное расширение, нет парсера | «Формат не поддерживается. Сохраните файл как DOCX или XLSX и попробуйте снова» |
| `fileTooLarge` | размер > 25 МБ (до парсинга) | «Файл больше 25 МБ. Уменьшите файл и попробуйте снова» |
| `unreadableFile` | битый/не тот формат, запароленный PDF, нарушены ZIP-лимиты, неизвестное исключение | «Не удалось прочитать файл» |
| `scannedPdf` | PDF без текстового слоя | «В файле нет текстового слоя. Похоже, это скан. Загрузите PDF с текстом» |
| `emptyText` | после извлечения/нормализации текста нет | «В файле нет текста» |

Ошибка одного файла **не блокирует остальные**: `FileParsingService.parseAll` возвращает
`ParsedFileSuccess`/`ParsedFileFailure` в порядке входа (SPEC A8.3). `ParserException.details` и сырые
исключения в UI не попадают.

## Нормализация и границы разделов

`normalizeDocumentText`: `\r\n`/`\r` → `\n`; NUL/control-символы (кроме `\t\n`) удаляются; NBSP → пробел;
хвостовые пробелы строк убираются; 3+ пустых строк → 2; текст обрезается по краям. Разделы нормализуются
по отдельности, между разделами — ровно пустая строка; `ParsedSection.start/end` — смещения в итоговом
тексте (используются чанкингом A8.5 в итерации 3c).

## Лимиты и изоляты

- Максимальный размер файла — **25 МБ** (SPEC A8.3), проверяется до парсинга.
- ZIP-контейнеры (DOCX/PPTX/ODT/XLSX) — `SecureZip`: ≤10 000 записей, ≤32 МБ одна запись, ≤120 МБ
  суммарный распакованный объём (ADR-010); повреждённый архив → `unreadableFile`.
- Парсинг каждого файла выполняется в отдельном изоляте (`Isolate.run`); `FileParsingService` позволяет
  инжектировать `IsolateRunner` для тестов. PDF-парсер инициализирует PDFium внутри изолята
  (`pdfrxInitialize`), без Flutter-виджетов.
- Файлы парсятся последовательно (без параллельных изолятов) — предсказуемая память.

## Пример использования (для итерации 3c)

```dart
final service = FileParsingService(); // все парсеры A8.3 + Isolate.run
final outcomes = await service.parseAll(<FileParsingInput>[
  FileParsingInput(fileName: 'лекция.docx', bytes: bytes),
  FileParsingInput(fileName: 'скан.pdf', bytes: scanBytes),
]);

for (final outcome in outcomes) {
  switch (outcome) {
    case ParsedFileSuccess(:final document):
      // document.text, document.sections, document.metadata
    case ParsedFileFailure(:final fileName, :final code):
      // parserErrorCodeMessage(l10n, code) — сообщение из ARB
  }
}
```

## Тесты и фикстуры

- Фикстуры **программные** (`test/unit/api/parsers/fixtures/document_fixtures.dart`): DOCX/PPTX/ODT/XLSX/PDF
  (включая скан и запароленный PDF V1/R2 RC4 40-bit), RTF (cp1251/KOI8-R/`\uN`), тексты в
  UTF-8/BOM/UTF-16LE/BE/cp1251/KOI8-R. Бинарные файлы в репозиторий не коммитятся.
- Unit-тесты: домен, каждый парсер, `SecureZip` (лимиты/повреждения/кодировки XML), сервис, маппинг ARB.
- Интеграционный срез: производственный сервис с реальным `Isolate.run` — все форматы, ошибки по файлам,
  сохранение кода `ParserException` из изолята.

### PDF в CI (L26)

PDF-тесты реально выполняются на всех трёх ОС (ubuntu/windows/macos), без skip и тегов. В `flutter test`
PDFium не находится сам (native assets не дают `libpdfium` на Linux/macOS, на macOS Dart-загрузчик
`pdfium_dart` не поддерживает платформу), поэтому job `test` скачивает pinned релиз
`bblanchon/pdfium-binaries` `chromium/8125` (тот же, что build-hook `pdfium_dart` 0.4.1), сверяет sha256 и
экспортирует `PDFIUM_PATH`; `pdfrxInitialize()` грузит модуль по явному пути (ADR-010 §9, §11).
Инварианты (матрица ОС, команда тестов, отсутствие skip/тегов, шаг с sha256 до тестов, `.gitattributes`
eol=lf) защищает guard `test/guards/ci_pdfium_test.dart`. Остаточные риски — сеть до GitHub releases,
только arm64 на macOS, нет iOS-тестов — зафиксированы в `journal/KNOWN_LIMITATIONS.md` L26.

## Ограничения

Реальные файлы Word/LibreOffice/PDF с устройства не проверялись (фикстуры программные); вложенные таблицы
DOCX уплощаются в текст ячейки; нумерация списков DOCX не извлекается; объём 25 МБ и производительность/OOM
не проверялись; PDF-тесты в CI идут на всех трёх ОС через pinned PDFium (L26, ADR-010 §11). Подробно —
`journal/KNOWN_LIMITATIONS.md` L7, L23–L27.
