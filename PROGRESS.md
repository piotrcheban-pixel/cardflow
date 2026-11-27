# PROGRESS — CardFlow: генерация v3 (внешняя память прогонов)

## Сделано

**Срез 2 (2026-11-27) — журнал прогона, стейт-машина этапов, порты.**
- `lib/domain/generation/generation_ledger.dart`: `GenerationLedger` (суммарно)
  и `GenerationBatchLedger` (по партиям) — `requested`, `generated`, `invalid`,
  `duplicates`, `accepted`, `remaining`; неизменяемые значения, события через
  `record`/`withCause`/`markCause`; `requested` = **сумма бюджетов**
  (`fromBudgets`, `fromPlan`), партии нумеруются подряд с 0. `ShortfallKind` —
  wire-коды TASK (`exhausted_material`, `provider_error`, `truncated`,
  `validation_rejects`, `cancelled`), приоритет прогона — Q7; дубли —
  отдельный счётчик, класс — `validation_rejects` (Q5); у партии без событий
  `shortfall == null`.
- `lib/domain/generation/generation_run.dart`: стейт-машина прогона —
  `GenerationStage` (`planned → understanding → generating → validating →
  dedup → replenishing → ready | partial | failed | cancelled`),
  `GenerationRunState.advanceTo` (недопустимый переход —
  `InvalidGenerationStageTransition`), `GenerationStage.jobStatus` для
  `generation_jobs.status` (SPEC A5). `ready`/`partial` — только из
  `replenishing`, `failed`/`cancelled` — с любого незавершённого этапа.
- `lib/domain/generation/ports.dart`: `LlmPort` (один вызов на партию,
  `batchIndex`), `CardSink` (принятое пишется по ходу), `ProgressSink` (этап +
  журнал), `Clock`, `KnowledgeMapCache<M>` (ключ — документ + хеш; тип карты —
  параметр, Q6). Этапы зависят только от портов.
- Guard `test/guards/architecture_test.dart` расширен: `lib/domain/` не
  импортирует `package:dio/` и `package:drift/` (ADR-050), +1 self-test.
- Старый конвейер, UI, схема БД и публичные типы провайдеров не менялись.
- Тесты (+38): `test/unit/domain/generation/generation_ledger_test.dart` (21),
  `generation_stage_test.dart` (11), `ports_test.dart` (5), guard (+1).

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

**Срез 2.** Красная фаза — `journal/generation-v3/red-s2.txt`: 28 падений
assertion-level (`Expected: <211> Actual: <0>`, `Expected: throws
<Instance of 'AssertionError'>`, `Expected: contains 'принято 3/8'`), а не
только ошибки компиляции. Гейты: `.\.fvm\versions\3.47.9\bin\flutter.bat
analyze --no-pub lib test` → **No issues found!**;
`.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` →
**628 files, 0 changed**; `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub
--coverage --exclude-tags golden` → **2863 passed + 17 skipped**, `exit 0`
(baseline 2825 + 17 + 38 новых); покрытие рукописного кода **90.8 %
(23860/26277)** при пороге 80 %; `generation_ledger.dart` — **100 % (99/99)**;
`generation_run.dart` — 94.7 % (36/38; непокрыты прежние `planWarnings`).
DoD-тесты: property «Σ бюджетов == requested» на 200 случайных планах,
`generating → ready` невозможно (полная матрица 10×10), после сбоя батча
принятое сохраняется. Итоги — `journal/generation-v3/verify-s2.md`.

**Срез 1.** Красная фаза — `journal/generation-v3/red-s1.txt` (assertion-level
падения, не только ошибка компиляции).
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
- **Const-контекст в тесте не даёт покрытия строке конструктора.** Тест с
  `const GenerationRunState.planned()` вычисляется при компиляции, и lcov не
  считает строку инициализатора исполненной (`generation_run.dart:482` = 0).
  Для покрытия константного конструктора вызывать его без `const`.
- **Проверять арифметику негативного assert-теста.** Тест «validation +
  duplicates > generated» в красной фазе взял `generated: 2, invalid: 1,
  duplicates: 1` — сумма ровно 2, `AssertionError` не бросается. Для нарушения
  нужно `generated: 1`.
- **`GenerationLedger.requested` — только Σ бюджетов партий.** Не выводить
  «цель» из `GenerationPlan.requestedCards`: план может не покрывать заказ
  (`requestedAboveAchievable`), и журнал занизил бы долг; нехватку материала
  показывает план, а не журнал.
- **`ready`/`partial` в стейт-машине — только из `replenishing`.** Это
  дословная цепочка TASK.txt (`dedup → replenishing → ready|partial`);
  `failed`/`cancelled` разрешены с любого незавершённого этапа.
- **`ports.dart` не попадает в lcov** (только объявления портов, 0 исполняемых
  строк) — ожидаемо, прецедент `api_key_store.dart` и репозитории портов.
  Не «чинить» это пустыми реализациями ради процента.

## СЛЕДУЮЩЕЕ ДЕЙСТВИЕ

Срез 3 — ждать обновлённый `TASK.txt` владельца: `read TASK.txt` → верхний
блок `journal/STATE.md` («Генерация v3 — срез 2») → `docs/generation/BACKLOG.md`.
Если в TASK.txt снова «Срез 2»/пусто — брать S2 из BACKLOG (`KnowledgeMap`):
red-тест `test/unit/domain/generation/knowledge_map_test.dart`, команда
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/domain/generation/knowledge_map_test.dart`.

---

**Архив прежнего (незавершённого, другой заход) прогона:**
`PROGRESS_slow_20261122.md` (120 КБ) — читать целиком не нужно, к срезам 0–1
отношения не имеет.
