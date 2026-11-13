# Итерация 3a — «Парсеры». План (шаг 1)

**Дата:** 2026-11-13 · **Режим:** `ИТЕРАЦИИ` · **Ветка:** `main` (рабочее дерево clean, HEAD `e7efc19`; CI зелёный — `43468349877`)
**Цель SPEC B2:** нативный локальный парсинг A8.3 без WebView: PDF, DOCX, XLSX, PPTX, ODT, TXT/MD, RTF →
`ParsedDocument` (текст с границами разделов + метаданные); кодировки; сканы; понятные ошибки по файлу; лимиты;
`.doc`/`.xls` — ADR-003. Спайки выполнены: `journal/iteration-3a/spikes.md`; решение — **ADR-010**.

## Критерии приёмки итерации (SPEC)

| # | Критерий | Источник | Проверка |
|---|---|---|---|
| C1 | `ParsedDocument`: нормализованный текст, границы разделов (`start/end` в тексте), метаданные; итоговый текст одинаков при повторном парсинге | A8.3, A8.5 | unit-тесты `ParsedDocument`/нормализации |
| C2 | DOCX: абзацы → строки, таблицы → строки через табуляцию, заголовки → разделы, текст до заголовка — раздел без title | A8.3 | unit-тест `DocxParser` на программной фикстуре |
| C3 | PPTX: слайды в порядке `presentation.xml` (rel → slideN.xml), текст `a:t`; разделы — слайды | A8.3 | unit-тест `PptxParser` (порядок, fallback) |
| C4 | ODT: `content.xml`, `text:h` — разделы (title), `text:p` — абзацы | A8.3 | unit-тест `OdtParser` |
| C5 | XLSX: листы → разделы (title = имя листа), строки → `\t`, **формулы по кэшированному значению**, даты `yyyy-MM-dd`, пустые хвостовые ячейки убираются | A8.3 | unit-тест `XlsxParser` |
| C6 | TXT/MD: BOM (UTF-8/UTF-16) → UTF-8 → cp1251/KOI8-R; кодировка явно в metadata; детерминированный выбор при равенстве | A8.3 | unit-тесты на фикстурах в 5 кодировках |
| C7 | RTF: `\'hh` с `\ansicpg` (для русского cp1251), `\uN` с `\uc`, пропуск `fonttbl`/`colortbl`/`stylesheet`/`pict`/`info`/`\*`-групп, `\par`/`\line`/`\tab` | A8.3 | unit-тесты `RtfParser` (русский cp1251, `\uN`, пропуск групп) |
| C8 | PDF: текстовый слой через pdfrx, страницы → разделы; скан без слоя → `scannedPdf`; битый/запароленный → `unreadableFile` | A8.3 | unit-тесты `PdfParser` (текст, скан, битый) |
| C9 | `.doc`/`.xls` и неизвестное расширение → `unsupportedFormat` без чтения; сообщение из ARB; сигнатуры PDF/ZIP/RTF проверяются | ADR-003, A8.3 | unit-тест детекции + маппинга |
| C10 | Лимит 25 МБ на файл → `fileTooLarge` до парсинга; ZIP-лимиты (записи/размер записи/распакованный объём) | A8.3 | unit-тесты сервиса и zip-хелпера |
| C11 | Ошибка одного файла не блокирует остальные; `parseAll` сохраняет порядок и отдаёт результат по каждому файлу | A8.3 | unit-тест сервиса + интеграционный |
| C12 | Тяжёлый парсинг — в отдельном изоляте; сырые исключения наружу не утекают | A8.3 | unit-тест (инжектированный `IsolateRunner`) + интеграционный на real изоляте |
| C13 | Сообщения только из ARB (ru), локаль ru; guard-тесты зелёные; `analyze` 0 issues; `format`; покрытие ≥80% | 3.1, B6 | guard-тесты, `fvm flutter test --coverage` |
| C14 | Документация: ADR-010, `docs/parsers.md`, `docs/dependencies.md` (enough_convert), журнал итерации | A8.3, агент-промпт §11 | ревью файлов |

## Задачи (TDD: red → green на каждую)

### Домен (`lib/domain/text/`, без Flutter)
- **T1. `DocumentFormat` + детекция** (`document_format.dart`): enum `pdf/docx/xlsx/pptx/odt/txt/md/rtf/doc/xls`;
  `detectDocumentFormat({fileName, bytes})` → формат по расширению + сигнатуры (`PK`, `%PDF-`, `{\rtf`);
  `.doc`/`.xls` → возвращаются как формат (сервис даёт `unsupportedFormat`); неизвестное — `null`.
  Тест: `test/unit/domain/document_format_test.dart`.
- **T2. `ParsedDocument`/`ParsedSection`/`ParsedDocumentMetadata`** (`parsed_document.dart`): инварианты
  (разделы в границах текста, непустой текст, start<end), `sections` отсортированы. Тест: `parsed_document_test.dart`.
- **T3. `ParserException` + `ParserErrorCode`** (`parser_exception.dart`): 5 кодов, `details` не в UI.
- **T4. `normalizeDocumentText`** (`document_text_normalization.dart`): CRLF/CR → LF, NUL/control → удаление (кроме `\t\n`),
  NBSP → пробел, хвостовые пробелы, 3+ пустых строк → 2, trim. Тест: `document_text_normalization_test.dart`.

### API-слой парсеров (`lib/api/parsers/`)
- **T5. `DocumentParser`** (`document_parser.dart`): `DocumentFormat get format; Future<ParsedDocument> parse(Uint8List bytes, {required String fileName})`.
- **T6. ZIP/XML-хелпер** (`zip_xml.dart`): декод zip с лимитами (записи, размер записи, суммарный распакованный объём),
  чтение записи по имени, парсинг XML; ошибки → `ParserException(unreadableFile)`.
- **T7. `DocxParser`** (`docx_parser.dart`).
- **T8. `PptxParser`** (`pptx_parser.dart`).
- **T9. `OdtParser`** (`odt_parser.dart`).
- **T10. `XlsxParser`** (`xlsx_parser.dart`): `excel_plus`; `FormulaCellValue.cachedValue`, `DateCellValue` → `yyyy-MM-dd`.
- **T11. `TxtParser`** (`txt_parser.dart`): определение кодировки (ADR-010 п.6), MD = тот же декод.
- **T12. `RtfParser`** (`rtf_parser.dart`): минимальный конвертер (ADR-010 п.7).
- **T13. `PdfParser`** (`pdf_parser.dart`): `pdfrxInitialize()` + `PdfDocument.openData(passwordProvider: () => null)`,
  `pages → loadText()`, скан/битый/запароленный; разделы по страницам.
- **T14. `FileParsingService`** (`file_parsing_service.dart`): реестр парсеров, лимит 25 МБ, `parseAll`/`parseFile`,
  `IsolateRunner` (по умолчанию `Isolate.run`), порядок и результаты по файлам, ошибка файла не блокирует остальные.

### UI/локализация
- **T15. Маппинг ошибок** (`lib/ui/generation/parser_error_message.dart`): `ParserErrorCode → String` из ARB,
  `parserErrorMessage(l10n, Object)` без сырых исключений; ключи ARB + `fvm flutter gen-l10n`.
  Тест: `test/unit/ui/parser_error_message_test.dart` (по образцу `archive_error_message_test.dart`).

### Тесты, фикстуры, интеграция
- **T16. Фикстуры** (`test/unit/api/parsers/fixtures/document_fixtures.dart`): программные сборщики PDF/DOCX/PPTX/ODT/XLSX/RTF
  и текстов в 5 кодировках (бинарные файлы не коммитим; PDF — минимальный с xref, как в спайке).
- **T17. Unit-тесты** по T1–T15 (см. таблицу C1–C12).
- **T18. Интеграционный срез** (`test/integration/file_parsing_pipeline_test.dart`): production-сервис (все 7 парсеров,
  реальный `Isolate.run`), файлы всех форматов + `.doc`/`.xls` + битый файл: порядок, тексты, ошибки по файлам,
  ошибка не блокирует остальные. Закрывает урок H1 (стык: байты файла → парсер → `ParsedDocument` → нормализованный текст).

### Ревью, проверка, память
- **T19. Ревью** независимым reviewer на снимке после коммита зелёной фазы: `journal/iteration-3a/review.md`;
  fix-итерация findings до verify.
- **T20. Verify:** полный `fvm flutter test --coverage`, `analyze`, `format`, покрытие ≥80% (рукописный код),
  `fvm flutter build windows --release`; сверка C1–C14 → `journal/iteration-3a/verify.md`.
- **T21. Память/улучшение:** `docs/parsers.md`, `journal/iteration-3a/summary.md`, `STATE.md`, `AGENTS.md`
  (устойчивые факты), ретроспектива шага 7.

## Вне объёма итерации 3a (осознанно)

- Экран «Генерация карточек» A6.8: drag-n-drop, список файлов, прогресс, предпросмотр — **итерация 3c**;
  в 3a нет UI-экрана и мёртвых кнопок.
- Чанкинг по бюджету модели, оценка токенов, дедупликация — итерация 3c (A8.5 шаги 4–9); 3a отдаёт границы разделов.
- `.doc`/`.xls` — ADR-003 (сообщение); собственный CFB-парсер — отдельная задача владельца.
- OCR сканов — не в MVP: скан без текстового слоя → ошибка `scannedPdf` (SPEC A8.3).
- Парсеры видео/изображений — нет в SPEC.

## Риски

| Риск | Митигация |
|---|---|
| pdfrx/PDFium в `flutter test` на Linux/macOS CI (native assets) | локальный спайк на Windows зелёный; при падении на ОС — платформенный skip с `KNOWN_LIMITATIONS`, но цель — зелёные тесты на всех 3 ОС |
| Программные фикстуры XLSX/DOCX могут быть «слишком минимальны» для реальных файлов | парсеры читают по спецификации OOXML; фикстуры покрывают реальные структуры (rels, таблицы, стили заголовков, формулы, даты) |
| RTF-конвертер неполон | минимальный набор по SPEC; известные ограничения — `KNOWN_LIMITATIONS`, тесты на cp1251/`\uN`/пропуск групп |
| Изолят + pdfrx: инициализация PDFium в каждом изоляте (память/время) | спайк показал рабочий путь; сервис парсит файлы последовательно (без параллельных изолятов) |
| Смена поведения существующих guard-тестов (domain без Flutter и т.п.) | новые файлы domain — чистый Dart; api/ui-импорты не протекают в domain |

## ADR итерации

- **ADR-010** — формат `ParsedDocument`, единая нормализация, коды ошибок, детекция форматов, лимиты,
  определение кодировок TXT/MD, RTF-конвертер, PDF через pdfrx в изоляте, изоляция ошибок по файлам.

## Порядок работы

1. Спайки (выполнены) + план + ADR-010 + `docs/dependencies.md` (enough_convert) → коммит `docs:`.
2. Красная фаза: фикстуры T16, тесты T1–T15/T18, скелеты типов/парсеров (`UnimplementedError`) → прогон,
   фрагменты `ожидалось/получено` в `journal/iteration-3a/red-parsers.md` → коммит `test:`.
3. Зелёная фаза по слоям: домен (T1–T4) → zip-хелпер + OOXML-парсеры (T6–T9) → XLSX/TXT/RTF/PDF (T10–T13) →
   сервис (T14) → ARB/маппинг (T15) → интеграция (T18); после каждого слоя тесты + `analyze`/`format` → коммиты `feat:`.
4. Ревью T19 (независимый reviewer, снимок после зелёного коммита); fix-итерация отдельным коммитом.
5. Verify T20; docs/STATE/AGENTS/summary T21; ретроспектива.
