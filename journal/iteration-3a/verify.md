# Итерация 3a — «Парсеры». Verify (шаг 5)

**Дата:** 2026-11-13 · **Снимок:** `ecf845a` (fix-итерация после ревью; зелёная фаза — `e12d819`, красная — `6c3a019`)
**Режим:** `ИТЕРАЦИИ` · **Хост:** Windows 11, FVM 4.3.2 / Flutter 3.47.9 / Dart 3.13.7

## Команды и результаты (выполнены в этой сессии)

| # | Команда | Результат |
|---|---|---|
| V1 | `fvm flutter analyze` | **No issues found!** (0 issues) |
| V2 | `fvm dart format --output=none --set-exit-if-changed .` | **0 changed** (142 файла) |
| V3 | `fvm flutter test --exclude-tags golden` | **595 тестов, all passed** (было 484 в итерации 2 → +111 новых) |
| V4 | `fvm flutter test --exclude-tags golden --coverage` | 595 passed, lcov сгенерирован |
| V5 | `fvm dart run tool/coverage_check.dart --min=80` | **95.3% (3152/3309)**, порог 80% пройден |
| V6 | `fvm flutter build windows --release` | **√ Built build\\windows\\x64\\runner\\Release\\cardflow.exe** (51.0 s) |

**Покрытие новых файлов (V5, lcov):** `file_parsing_service` 100% (33/33), `odt_parser` 100% (20/20),
`parsed_document_builder` 100% (42/42), `xml_local_names` 100% (16/16), `parsed_document` 100% (30/30),
`document_text_normalization` 100% (12/12), `docx_parser` 98.7% (78/79), `pptx_parser` 98.2% (56/57),
`zip_xml` 96.8% (60/62), `txt_parser` 96.3% (52/54), `xlsx_parser` 94.7% (36/38), `document_format` 94.1%
(32/34), `rtf_parser` 89.0% (121/136), `pdf_parser` 85.3% (29/34), `parser_exception` 33.3% (1/3 — только
`toString` в исключениях, конструктор/поля покрыты косвенно).

**Guard-тесты** входят в V3 и зелёные: `no_webview`, `ru_strings` (ARB-ключи парсеров прошли allow-list:
PDF/DOCX/XLSX допустима латиница; «25 МБ» без латиницы), `no_secrets`, `architecture_test` (domain/text —
чистый Dart, без Flutter), `no_flutter_material` и др.

## Сверка критериев приёмки итерации (C1–C14 из `plan.md`)

| # | Критерий | Статус | Доказательство |
|---|---|---|---|
| C1 | `ParsedDocument`: текст, границы разделов, метаданные; идемпотентная нормализация | **выполнено** | `test/unit/domain/{parsed_document,document_text_normalization}_test.dart` |
| C2 | DOCX: абзацы → строки, таблицы через `\t`, заголовки → разделы | **выполнено** | `test/unit/api/parsers/docx_parser_test.dart` (6 тестов; +таб-стопы, sdt/customXml после ревью) |
| C3 | PPTX: слайды в порядке presentation.xml, fallback, разделы | **выполнено** | `pptx_parser_test.dart` (4 теста) |
| C4 | ODT: `text:h`/`text:p`, разделы; оглавление/аннотации пропускаются | **выполнено** | `odt_parser_test.dart` (5 тестов) |
| C5 | XLSX: листы → разделы, `\t`, кэш формул, даты, пустые ячейки | **выполнено** | `xlsx_parser_test.dart` (9 тестов) |
| C6 | TXT/MD: BOM/UTF-8/cp1251/KOI8-R, кодировка в metadata | **выполнено** | `txt_parser_test.dart` (9 тестов) |
| C7 | RTF: `\'hh` cp1251/KOI8-R, `\uN`+`\uc`, пропуск групп, CR/LF | **выполнено** | `rtf_parser_test.dart` (13 тестов) |
| C8 | PDF: текстовый слой, страницы-разделы, скан, битый, запароленный, многостраничный | **выполнено** | `pdf_parser_test.dart` (6 тестов; pdf_parser покрытие 85.3%) |
| C9 | `.doc`/`.xls`/неизвестное → unsupportedFormat; сигнатуры | **выполнено** | `document_format_test.dart`, `file_parsing_service_test.dart` |
| C10 | Лимит 25 МБ; ZIP-лимиты (записи/запись/объём) для всех 4 ZIP-форматов | **выполнено** | `zip_xml_test.dart` (лимиты/повреждения/BOM), `xlsx_parser_test` (>10 000 записей), service test (25 МБ) |
| C11 | Ошибка файла не блокирует остальные; порядок сохраняется | **выполнено** | `file_parsing_service_test.dart`, `test/integration/file_parsing_pipeline_test.dart` |
| C12 | Парсинг в изоляте; код ошибки из изолята сохраняется | **выполнено** | unit-тест с инжектированным runner + интеграционный тест с реальным `Isolate.run` (`unreadableFile`, `scannedPdf`) |
| C13 | ARB-сообщения, ru-локаль, guard-тесты, analyze/format/покрытие | **выполнено** | V1–V5; `parser_error_message_test.dart` (3 теста) |
| C14 | Документация: ADR-010 (+дополнения), `docs/parsers.md`, `docs/dependencies.md` §10 | **выполнено** | файлы в коммите docs |

## Независимое ревью и fix-итерация

- Ревьюер (fresh context) на снимке `e12d819`: `journal/iteration-3a/review.md` — **0 blocker / 0 critical /
  2 high / 8 medium / 9 low**; вердикт «с findings».
- Fix-итерация (коммит `ecf845a`) закрыла **H1–H2**, **M1–M8**, **L1–L3, L6, L8**:
  RTF `\*`-группы/CR-LF/`\uc`/KOI8-R; XLSX ZIP-лимиты; DOCX таб-стопы и content controls; ODT оглавление/
  аннотации; strict `ZipDecoder`; XLSX формула без кэша и дата-со-временем; тесты `zip_xml`, многостраничный
  и запароленный PDF, код ошибки из реального изолята; строгая ZIP-сигнатура; immutable-модели; PPTX slideCount;
  RTF-сигнатура с ведущими пробелами.
- Не исправлены (осознанно, в `KNOWN_LIMITATIONS`): L4 (ошибки `loadText` отдельной страницы PDF не имеют
  синтетической фикстуры — ветка покрыта кодом, но не тестом), L5 (UTF-16 нечётной длины — усечение),
  L7 (документация — сделана в этом шаге), L9 (правило `\n\n` — зафиксировано в ADR-010 §1 дополнений).

## Не проверено и почему (не считается выполненным)

| Что | Почему | Куда |
|---|---|---|
| CI-прогон итерации 3a (Linux/Windows/macOS, pdfrx native assets) | push — по команде владельца; локально проверен Windows | L26; после push |
| Реальные Word/LibreOffice/PDF-файлы | нет набора реальных файлов в окружении | L23 |
| Лимит 25 МБ / производительность / OOM на реальных файлах | нет больших файлов; лимиты покрыты unit-тестами | L25 |
| Ручной UX генерации (A6.8) | экран — итерация 3c | план |
| Golden/скриншоты | golden-тестов парсеров нет (не UI) | — |

## Вывод

Итерация 3a по критериям C1–C14 — **выполнена** (docs — этот шаг). Непроверенное вынесено в
`KNOWN_LIMITATIONS.md` (L23–L27); зелёный CI-прогон итерации 3a требуется после push (по команде владельца).
