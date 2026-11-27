# PROGRESS — CardFlow: генерация v3 (внешняя память прогонов)

## Сделано

**Срез 1 (2026-11-27) — ContentModel: Document → Section → Block с якорями.**
- `lib/api/generation/content_model.dart`: `Document`, `Section`, `Block`,
  `NoiseKind`. Инварианты проверяются в конструкторе `Document` (offsets точные
  `text.substring(start, end) == text`, блоки не пересекаются, каждый блок
  целиком в одном разделе, разделы не пересекаются, иерархия замкнута).
  `block(id)`/`section(id)` — индексные карты (**O(1)**), `blockAt(offset)` —
  двоичный поиск, `blocksOfSection`, `childrenOf`, `contentBlocks`/
  `noiseBlocks`, `contentLength`, `Document.empty`.
- `lib/api/generation/content_normalizer.dart`: `ContentNormalizer` — пробелы
  (включая NBSP, типографские и нулевой ширины), `ё→е`, кавычки, тире/дефисы и
  мягкий перенос. Нормализация **не** меняет offsets: `Block.text` — текст
  источника, сравнивается `Block.normalizedText`.
- `lib/api/generation/content_model_builder.dart`: `ContentModelBuilder`
  (`ParsedDocument → Document`; `buildFromOutcome` — ошибка файла даёт пустую
  модель без исключения) и `ContentNoiseDetector` (номер страницы, подпись
  «Рис./Fig. N», оглавление по заголовку раздела и по отточию с номером,
  колонтитул — строка, повторяющаяся в ≥2 разделах первой или последней).
  Блок = строка источника; границы разделов расширены до границ блоков —
  поэтому раздел не рвёт абзац. Иерархия — по нумерации заголовков (`1.` → 0,
  `1.1` → 1), скачок уровня сглаживается, разрыв нумерации делает раздел
  корневым.
- Парсеры и их публичные типы **не менялись**, генерация и LLM не тронуты.
- Тесты (+24): `test/unit/api/generation/content_model_test.dart` (13),
  `content_normalizer_test.dart` (6), `content_model_parsers_test.dart` (5 фикстур:
  PDF, DOCX, PPTX, MD, скан без текстового слоя).

## Проверено

- Красная фаза — `journal/generation-v3/red-s1.txt` (assertion-level падения,
  не только ошибка компиляции).
- `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` →
  **No issues found!** (0 issues).
- `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` →
  **623 files, 0 changed**.
- `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --exclude-tags golden` →
  **2825 passed + 17 skipped**, `exit 0` (baseline 2801 + 17; +24 новых).
- Пять фикстур DoD: offsets точные, блок восстанавливается по id (`same(...)`),
  раздел не рвёт абзац (блоки в границах своего раздела), скан даёт пустую
  модель без исключения. Итоги — `journal/generation-v3/verify-s1.md`.

## НЕ ПОВТОРЯТЬ

- **Не использовать `\b` в регулярках после кириллицы.** В ECMAScript-регулярках
  (Dart `RegExp`) граница слова считается по ASCII: `^\s*(?:рис)\b\.` **не
  ловит** «Рис. 4» — на этом упал первый зелёный прогон. Подпись рисунка
  детектируется без `\b` (`_figureCaption` в `content_model_builder.dart`).
- **PDF-фикстуры — только латиница.** `document_fixtures.dart` собирает PDF в
  latin1 (`_pdfEscape` + `latin1.encode`), кириллица падает с
  `Invalid argument (string): Contains invalid characters`. Русский текст — в
  DOCX/PPTX/MD-фикстурах, PDF-сценарий берёт латинские строки.
- **Многострочная страница PDF — только `buildPdfFromFixturePages`.**
  `buildPdfPages` пишет текст страницы одной `Tj`-строкой (переводы строк в
  литерал не вставляются); `PdfFixturePage(text: 'line1\nline2')` пишет каждую
  строку отдельной `Tj`, и pdfrx отдаёт их через `\n` (проверено пробой).
- **Не проверять «раздел не рвёт абзац» через `ParsedDocumentBuilder`:**
  он всегда разделяет разделы `\n\n`, граница внутри строки не возникнет.
  Такой случай задаётся вручную `ParsedSection(start: 20, end: 43)` — см.
  тест «граница раздела внутри строки не рвёт абзац».
- **Не считать падение `settings_persistence_file_db_test.dart` регрессией.**
  На полном прогоне под нагрузкой он падает `TimeoutException 30s` (файловая
  drift-БД в OneDrive); отдельно и на повторном полном прогоне — зелёный.
- **Не читать `journal/STATE.md` целиком** и не искать «9 срезов» в TASK.txt
  (Q1 в `journal/QUESTIONS.md`): срез 1 = `ContentModel`, а не `MaterialUnit`
  из `BACKLOG.md` (Q3).

## СЛЕДУЮЩЕЕ ДЕЙСТВИЕ

Срез 2 — новое задание владельца: `read TASK.txt` (файл обновляется под каждый
срез) → верхний блок `journal/STATE.md` («Генерация v3») →
`docs/generation/BACKLOG.md` S2 (`KnowledgeMap`). Если в TASK.txt снова
«Срез 1»/пусто — брать S2 из BACKLOG: red-тест
`test/unit/domain/generation/knowledge_map_test.dart`, команда
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/domain/generation/knowledge_map_test.dart`.

---

**Архив прежнего (незавершённого, другой заход) прогона:**
`PROGRESS_slow_20261122.md` (120 КБ) — читать целиком не нужно, к срезам 0–1
отношения не имеет.
