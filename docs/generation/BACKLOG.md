# BACKLOG — генерация v3: девять срезов

**Контракт:** `docs/generation/ARCH.md` · **Решение:** `ADR-050` · **Аудит:** `AUDIT.md`.
**Правило:** один прогон = один срез. У каждого среза **ровно одна** команда
проверки DoD; полный `analyze`/`test` прогоняется в конце среза по протоколу
прогона, но DoD закрывает именно указанная команда.

**Как читать.** Срез — этап архитектуры, а не файл. Пока новый путь не покрыт
тестами и не включён флагом, старый код не удаляется (протокол §9). Флаг —
`GenerationSettings.generationV3` (по умолчанию выключен до S7; включается в S7
и S9 и только после зелёных тестов).

| # | Срез (этап) | Что появляется | Зависит от |
|---|---|---|---|
| S1 | Ingestion | `MaterialUnit` с offsets — единственный источник истины о тексте | — |
| S2 | Understanding | `KnowledgeMap`/`KMItem` — детерминированная карта утверждений | S1 |
| S3 | Allocation | `OrderBudget`: `Σ бюджетов == requested`, нехватка материала отдельно | S2 |
| S4 | Generation | `RequestLedger` на запрос: произведено / валидно / принято | S3 |
| S5 | Validation | цитата валидна по offsets; `section_id` сверяется с партией | S1, S4 |
| S6 | Dedup | вердикт `exact`/`semantic`/`distinct` вместо удаления | S4 |
| S7 | Replenish | долг `requested − принято` и план добора; флаг включён | S3, S4, S6 |
| S8 | Persistence | журнал запуска: принято/отброшено/помечено/долг; импорт идемпотентен | S4, S6 |
| S9 | Completion | `done` ⟺ `принято ≥ requested`; старый путь удаляется | S7, S8 |

---

## S1 — Ingestion: единица материала с offsets

**Цель.** Текст перестаёт быть строкой: `MaterialUnit{id, documentId, sectionId,
start, end, tokens, textHash}`. Офсеты — относительно нормализованного текста
документа; правило «текст восстанавливается по `start/end`» проверяется тестом.

**Write-scope.** `lib/domain/generation/material_unit.dart` (новый),
`lib/api/parsers/*` — только чтение offsets из `ParsedDocument` (`TextPiece.start/
end` уже есть, `content_unit.dart:110-113`), без переписывания парсеров.

**Не делать.** Не менять `GenerationPlan`/план в этом срезе; старый путь нарезки
остаётся.

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/domain/generation/material_unit_test.dart`

## S2 — Understanding: карта знаний

**Цель.** `KnowledgeMap` из `MaterialUnit`: пункты-утверждения
`KMItem{id, claim, unitId, start, end, importance}`; разбор детерминированный,
без сети и без модели. Важность — из структуры (заголовок раздела, повтор
термина, определения). Дедуп пунктов — нормализацией (не хешем карточек).

**Write-scope.** `lib/domain/generation/knowledge_map.dart` (новый) +
`test/unit/domain/generation/knowledge_map_test.dart`. Планировщик не меняется.

**Не делать.** Не подключать карту к промпту в этом срезе — только тип и правило.

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/domain/generation/knowledge_map_test.dart`

## S3 — Allocation: бюджеты как контракт заказа

**Цель.** `OrderBudget{requested, batches[], deliverable, materialLimited}`:
`Σ бюджетов партий == requested` при достаточном материале; при нехватке —
отдельный статус с числом (`материала ≈ на K из N`). `OrderBudget` строится из
`KnowledgeMap` (сколько утверждений на партию), а не из «мягкой ёмкости на глаз».
Старый `CardAllocator` подключается как источник весов, но сумма фиксируется
`OrderBudget`.

**Write-scope.** `lib/domain/generation/order_budget.dart` (новый);
`GenerationChunkPlanner` вызывает его за флагом (по умолчанию выключен).

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/domain/generation/order_budget_test.dart`

## S4 — Generation: бухгалтерия запроса

**Цель.** `RequestLedger{requestedItems, requestedCards, produced, valid,
accepted, droppedByReason}` заполняется на каждый вызов модели; причина потери —
машинный код, а не строка. Запрос несёт `unitId`/`itemId`, ответ сопоставляется с
ними (иначе — пометка, см. S5).

**Write-scope.** `lib/domain/generation/request_ledger.dart` (новый),
`CardGenerationService.generate` заполняет ledger (`lib/api/generation/
card_generation_service.dart:125`), конвейер пробрасывает его в результат.

**Не делать.** Не менять статус задания в этом срезе (`partial`/`done` — S9).

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/api/generation/request_ledger_test.dart`

**Сделано в срезе 5 TASK.txt (2026-11-27).** Generation выполняется
`CardsBatchEngine` поверх `AdapterCardsBatchPort` (существующие адаптеры) и
промпта `gen-cards-v3`; «`RequestLedger`» по смыслу — журнал
`GenerationLedger` с `attempts` (повторы и добор не живут в отдельном
recovery-бюджете), ответ привязывается к `unit_id`/`angle`, цитата —
`quote_ref`. DoD-команда закрывает 17 тестов (20/40/80 карточек, обрезка по
единицам, 429 `Retry-After`, 400/401 без повторов, отмена с сохранением
принятого, версия промпта в задании). Детали —
`journal/generation-v3/verify-s5.md`; толкования — Q12–Q14.

## S5 — Validation: цитата по offsets

**Цель.** `CardCandidate` хранит `unitId + start/end`; проверка — границы +
равенство нормализованного текста, а не `contains` по всей партии
(сейчас `card_content_validator.dart:232-236`). `section_id` модели сверяется с
разделами партии: не из партии → пометка `sectionUnknown`, значение не
принимается как факт. Карточка не отбрасывается — пометка видна в предпросмотре.

**Write-scope.** `lib/api/generation/quote_offsets.dart` (новый) + подключение в
`CardContentValidator` за флагом; `CardIssueCode` — новые коды.

**Не делать.** Не удалять проверку `contains` — она остаётся fallback для
prompt-only и старых записей.

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/api/generation/quote_offsets_test.dart`

## S6 — Dedup: вердикт вместо удаления

**Цель.** `DedupVerdict.exact` (отбросить — не потеря), `.semantic` (**пометить,
оставить**), `.distinct`. Смысловое сравнение — по `front`+`back` и по пункту
карты (`KMItem.id`), не только по `front`. Против колоды — тот же вердикт, не
только хеш.

**Write-scope.** `lib/domain/cards/dedup_verdict.dart` (новый); `_acceptCard`
(`generation_pipeline.dart:1933`) перевод на вердикт за флагом; тест
`test/unit/api/generation/generation_pipeline_v8_test.dart:250` меняет ожидание
(«удалён» → «помечен и оставлен») с комментарием ADR-050.

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/domain/cards/dedup_verdict_test.dart`

## S7 — Replenish: долг и добор как этап

**Цель.** `ReplenishPlanner.plan(debt, map, exhausted)` → новый `OrderBudget` на
добор или `exhausted(reason)` с числом. Долг считается из ledger'ов, а не из
локальной переменной прогона (`generation_pipeline.dart:727`). Перезапуск добора
после «Повторить неудавшиеся» возможен при долге без ошибок. Раунды остаются
предохранителем (`maxTopUpRounds`, `:127`), но не единственным способом добрать.

**Write-scope.** `lib/domain/generation/replenish_planner.dart` (новый); включение
`generationV3` для S1–S7; конвейер: долг вместо `shortfall`.

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/domain/generation/replenish_planner_test.dart`

## S8 — Persistence: журнал принятого

**Цель.** Журнал запуска пишется по ходу: принятые карточки, решения дедупа,
пометки валидации, долг. Хранение — JSON в `generation_jobs` (схема БД не
меняется); staging-таблица — только отдельным ADR. Импорт идемпотентен:
повторный импорт того же журнала не создаёт дублей и не «съедает» карточки
молча — скип попадает в журнал с причиной.

**Write-scope.** `lib/data/generation/generation_ledger_store.dart` (новый),
`GenerationJobRepository`/`drift_generation_card_store.dart` — чтение/запись
журнала; `generation_jobs.*_json` через `files_json`-совместимый pattern.

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/data/generation/generation_ledger_store_test.dart`

## S9 — Completion: ложный успех запрещён

**Цель.** `CompletionVerdict` считается только по журналу: `done` ⟺
`принято ≥ requested`; иначе `partial` + число + причина. В «авто»-режиме
(заказ не задан) `done` требует отсутствия долга — закрывает
`generation_pipeline.dart:1176`. После зелёных S7–S9 и включённого флага старый
путь (`shortfall`/`trimmed`/`retryFailed`-логика) удаляется одним коммитом.

**Write-scope.** `lib/domain/generation/completion_verdict.dart` (новый),
`generation_pipeline.dart` (статус, удаление старой ветки), UI: строка причины в
предпросмотре.

**DoD-команда (одна):**
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/integration/generation_completion_verdict_test.dart`

---

## Что уже сделано до S1 (не переделывать)

- ADR-043 (`Σ planned == requested`, партии до вместимости) — **используется**
  как вход S3, не переписывается.
- ADR-049 (оборванный ответ: `salvageCards` + `truncated`) — вход S4; `RequestLedger`
  обязан различать «произведено» и «спасено».
- ADR-024/028 (prompt-only, исчерпание разделов) — режимы, которые S7 обязан не
  сломать: prompt-only не имеет карты знаний, долг считается по ledger'ам.

## Известные долги, выносимые вне девяти срезов

- Журнал в `generation_jobs` — временное решение до отдельного ADR о staging-таблице.
- Смысловой дедуп против уже существующей колоды требует индекса (S6 даёт
  вердикт по хешу и нормализации; векторный поиск — отдельное решение).
- Живые прогоны (тег `live`, `CARDFLOW_LIVE_TESTS=1`) для проверки «300 карточек
  действительно получены» — после S9, отдельным прогоном с бюджетом.
