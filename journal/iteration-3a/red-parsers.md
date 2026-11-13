# Итерация 3a — красная фаза (парсеры)

**Дата:** 2026-11-13 · **Тесты:** новые 13 файлов (82 теста: 70 падений, 12 проходят — только тривиальные геттеры форматов/дефолты сервиса) · **Команда:** `fvm flutter test <13 новых файлов>`

## Что создано в красной фазе

- **Скелеты production-кода** (без поведения, `UnimplementedError` там, где нужна логика):
  `lib/domain/text/{document_format,parser_exception,parsed_document,document_text_normalization}.dart`,
  `lib/api/parsers/{document_parser,zip_xml,docx_parser,pptx_parser,odt_parser,xlsx_parser,txt_parser,rtf_parser,pdf_parser,file_parsing_service}.dart`,
  `lib/ui/generation/parser_error_message.dart`.
- **ARB-ключи** (5): `parserErrorUnreadableFile`, `parserErrorUnsupportedFormat`, `parserErrorScannedPdf`,
  `parserErrorFileTooLarge`, `parserErrorEmptyText` + `fvm flutter gen-l10n`.
- **Фикстуры** `test/unit/api/parsers/fixtures/document_fixtures.dart`: программные сборщики DOCX/PPTX/ODT/XLSX/PDF
  (с/без текстового слоя), RTF (cp1251 `\'hh`, `\uN`), тексты в UTF-8/UTF-8-BOM/UTF-16LE/UTF-16BE/cp1251/KOI8-R.
- **Тесты**: домен (`document_format_test`, `parsed_document_test`, `document_text_normalization_test`),
  парсеры (docx/pptx/odt/xlsx/txt/rtf/pdf), сервис (`file_parsing_service_test`), маппинг ошибок
  (`parser_error_message_test`), интеграционный срез (`test/integration/file_parsing_pipeline_test.dart`).

## Фрагменты вывода (ожидаемое vs получено)

```
00:02 +12 -70: Some tests failed.
```

- `normalizeDocumentText`: падает `UnimplementedError: normalizeDocumentText` (реализации нет).
- `ParsedDocument`: ожидалось `throws <Instance of 'ArgumentError'>` → `Actual: <Closure: () => ParsedDocument>`
  (инварианты пустого текста, пустых разделов, границ и пересечений ещё не проверяются).
- `verifyDocumentSignature`: `Expected: return normally` → `Which: threw UnimplementedError`.
  Для «чужих» сигнатур: `Expected: throws ParserException ... code unreadableFile` → `threw UnimplementedError`.
- `DocxParser.parse` / `PptxParser.parse` / `OdtParser.parse` / `XlsxParser.parse` / `TxtParser.parse` /
  `RtfParser.parse` / `PdfParser.parse`: `UnimplementedError: <Parser>.parse` (поведения нет).
- `FileParsingService.parseFile/parseAll`: `UnimplementedError: FileParsingService.parseAll` (сервиса нет).
- `parserErrorCodeMessage` / `parserErrorMessage`: `UnimplementedError` (маппинга нет).
- Тривиально проходят: `parser.format == ...` (данные enum), дефолты `FileParsingService()`,
  «фикстуры непустые» — поведение не проверяют, оставлены как страховка фикстур.

## Проверки красной фазы

- `fvm flutter analyze` → **No issues found!** (скелеты и тесты компилируются, падения — поведенческие, не компиляционные).
- PDF-тесты стартуют: `setUpAll(pdfrxInitialize)` выполняется (спайк S-PDF подтверждён в тестовой среде).

## Ожидаемо зеленеет в зелёной фазе

Домен (T1–T4) → zip/XML-хелпер + OOXML-парсеры (T6–T9) → XLSX/TXT/RTF/PDF (T10–T13) →
сервис (T14) → ARB-маппинг (T15) → интеграция (T18). После каждого слоя — прогон тестов + `analyze`/`format`.
