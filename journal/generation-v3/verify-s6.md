# Срез 6 — Validation и каскад дедупликации: проверка

**Дата:** 2026-11-27 · **Ветка:** `main` · **TASK:** «Срез 6. Validation и каскад
дедупликации» · **План:** `docs/generation/ARCH.md` (§Validation, §Dedup),
`docs/generation/BACKLOG.md` (S5/S6), ADR-050 · **Толкования:** Q15–Q16
(`journal/QUESTIONS.md`).

**Факты старта.** `HEAD = d413247` (docs среза 5), `git status` — только прежние
неотслеживаемые каталоги аудита. Baseline: `flutter test --no-pub
--exclude-tags golden` → **2992 passed + 17 skipped**, `exit 0`
(`.dsh-s6-baseline.log`).

## Что сделано

| Файл | Роль |
|---|---|
| `lib/api/generation/validation/card_validator.dart` (новый) | A8.4 + семантические эвристики с кодом причины; вердикт `accepted/warning/rejected`; цитата по offsets `ContentModel`; отброшенное сохраняется (`RejectedCard.raw`) |
| `lib/domain/generation/validation/semantic_matcher.dart` (новый) | каскад: точный ключ → нормализованный ключ → символьные шинглы + Жаккар → эмбеддинги за `TextEmbeddingProvider`; пары + `DedupReport` |
| `lib/domain/generation/dedup_report.dart` (новый) | `DedupLevel` (wire-коды), `DedupPair`, `DedupReport` (пары, счётчики по уровням, сильнейший уровень карточки) |
| `lib/domain/generation/generation_ledger.dart` | `dedup`/`withDedup` у журнала; отчёт переживает `record`/`attempt`/`markCause`/`replace`; арифметика заказа не менялась |
| `test/unit/api/generation/card_validator_test.dart` (новый) | 24 теста: каждая проверка + ложные срабатывания |
| `test/unit/api/generation/quote_offsets_test.dart` (новый) | 7 тестов: DoD-команда S5 BACKLOG — offsets, почти-цитата, границы блоков, мусорный блок |
| `test/unit/domain/generation/semantic_matcher_test.dart` (новый) | 14 тестов: уровни каскада, колода, эмбеддинги, метрики, фикстура |
| `test/unit/domain/generation/dedup_report_test.dart` (новый) | 6 тестов: счётчики, сильнейший уровень, ledger |
| `test/fixtures/validation/duplicate_pairs.json` | 8 карточек: exact/normalized/semantic пары + 2 «ловушки» ложных срабатываний |

**Проверки (коды причин `CardReasonCode`).** Структурные: `missingRequiredField`,
`unknownCardType`, `emptyFront` (только они отбрасывают), `frontTooLong`,
`backTooLong`, `clozeMissing`, `tagsAdjusted`, `latexBroken` (пометки A8.4).
Семантические: `answerInQuestion`, `questionNotSelfContained` (этот/выше/см.
рис.), `notAtomic` (перечисление > 3), `clozeMeaningless`, `languageNotRussian`,
`quoteNotLiteral`, `quoteOutOfRange`, `sectionUnknown`, `unitUnknown`.

**Старый путь не тронут.** `card_content_validator.dart`, конвейер, UI, адаптеры,
схема БД не менялись: валидатор и дедуп нового пути не подключены к
production (флаг `GenerationSettings.generationV3` — S7 по BACKLOG, протокол §9).

## Гейты

| Команда | Результат |
|---|---|
| `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/api/generation/card_validator_test.dart test/unit/api/generation/quote_offsets_test.dart test/unit/domain/generation/semantic_matcher_test.dart test/unit/domain/generation/dedup_report_test.dart` (красная фаза) | **6 passed / 45 failed**, все падения assertion-level — `journal/generation-v3/red-s6.txt` |
| то же после реализации | **51 passed**, `exit 0` |
| `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` | **No issues found!** |
| `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` | **660 files, 0 changed** |
| `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage --exclude-tags golden` | **3043 passed + 17 skipped**, `exit 0` (baseline 2992 + 17 + 51) — `journal/generation-v3/green-s6-full.txt` |
| `.\.fvm\versions\3.47.9\bin\dart.bat run tool\coverage_check.dart --min=80` | покрытие рукописного кода **90.8 % (24989/27535)**, порог 80 % пройден — `journal/generation-v3/coverage-s6.txt` |

**Покрытие новых файлов:** `card_validator.dart` — 87.7 % (214/244),
`semantic_matcher.dart` — 96.4 % (81/84), `generation_ledger.dart` — 99.2 %
(120/121), `dedup_report.dart` — 70.8 % (34/48; непокрыты `DedupLevel.fromWire`,
`DedupPair.==`/`hashCode`/`toString`, `DedupReport.toString` — тривиальные
аксессоры, а не правила).

**DoD среза:** тест на каждую проверку (24 в `card_validator_test`), включая
ложные срабатывания на корректных карточках (`самостоятельный вопрос без
ложных срабатываний`, `ответ не в вопросе у корректной`, `теги без пометки`,
`осмысленный cloze проходит`); фикстура с известными парами — все три пары
найдены на своих уровнях, «ловушки» `trap-1`/`trap-2` не помечены; отчёт по
уровням — `GenerationLedger.dedup` (`dedup_report_test`).

## Ограничения и толкования

1. **Не подключено к конвейеру и UI.** Новый валидатор и матчер — отдельные
   этапы, как Allocation/Generation предыдущих срезов: подключение — S7
   (`replenishing`/добор) и S9 (предпросмотр «показать отброшенные»), за флагом
   `generationV3`. Данные для UI уже есть: `CardValidationReport.rejected`
   хранит исходный JSON, `CardCandidate.verdict/reasons` — пометки.
2. **Старый валидатор живёт рядом.** `CardContentValidator` обслуживает
   production `gen-ru-v9` (включая `source_excerpt` по `contains`); новый
   валидатор эти правила не дублирует. BACKLOG S5 говорит «не удалять проверку
   `contains` — она остаётся fallback для prompt-only и старых записей»: она и
   не удалена.
3. **Буквальность цитаты.** Регистр/«ё»/тире/пробелы — не буквальное
   совпадение: `quoteNotLiteral`, offsets не пишутся (нормализация меняет
   длину строки). Цитата через границу блоков не принимается (якоря единиц
   лежат внутри одного блока — Q13): `quoteOutOfRange`. Ищутся только
   `contentBlocks` (подпись рисунка — мусор).
4. **Символьные шинглы, а не словесные** (Q16): на словесных 3-шинглах одна
   вставка слова роняет Жаккара до ≈0,55 при пороге 0,7, и почти-дубль не
   ловится. Эмбеддинги не используются в production (интерфейс есть, провайдера
   нет — TASK запрещает тянуть ML-зависимости).
5. **`sectionUnknown`/`unitUnknown` — только при переданных наборах id**
   (в prompt-only сверять не с чем). Значение id не принимается как факт: это
   подсказка модели (ARCH §4).
6. **Сравнение O(n²)** по парам карточек: для партии (≤ `maxCardsPerBatch`
   профиля) дёшево; расширение на всю колоду с индексом — вне среза
   (BACKLOG «известные долги»).
7. **`CardReasonCode.isRejecting`** — единственное место, где живёт деление
   «отбросить/пометить»: если владелец захочет отбрасывать, например, пустой
   `back`, меняется одно перечисление, а не проверки.
