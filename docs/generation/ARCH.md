# ARCH — архитектура генерации карточек (контракт этапов)

**Статус:** срез 0 (2026-11-27), целевая архитектура принята ADR-050.
**Границы:** только путь «материалы → карточки в колоде» (SPEC A8.5). Парсеры (A8.3)
и UI предпросмотра (A6.8) описаны как соседи. Код здесь не обсуждается: документ
читается без него. Аудит текущего кода и план работ — `BACKLOG.md`.

## 1. Зачем новая схема

Сегодня конвейер — один длинный проход «нарезали → попросили → приняли». Цель
(«сколько карточек нужно») живёт в плане, но не в исполнении: факт недобора
считается после ответа, а не ведётся как долг; понимание материала отсутствует
(модель сразу отвечает карточками); потеря карточки на любом шаге (дубль,
валидация, импорт) не восполняется. Отсюда «тихий недобор» и просьбы владельца
«сделай, чтобы 20/40/80/150/300 действительно получались».

Далее — девять этапов. У каждого один владелец слоя: **домен** (чистые правила,
без Flutter и сети), **API** (HTTP, промпты, разбор ответа), **данные** (drift,
транзакции, журнал) или **UI** (экран и предпросмотр).

## 2. Этапы

| # | Этап | Вход | Выход | Владелец | Тесты |
|---|---|---|---|---|---|
| 1 | **Ingestion** | файлы/тема пользователя | `MaterialUnit`: нормализованный текст, `id`, `documentId`, `sectionId`, `start/end` (offsets), токены | домен + API-парсеры | `test/unit/api/parsers/`, `test/integration/file_parsing_pipeline_test.dart` |
| 2 | **Understanding** | `MaterialUnit[]` | `KnowledgeMap`: пункты-утверждения `KMItem{id, claim, unitId, start, end, importance}`; без сети | домен (детерминированные правила; модель — только как источник кандидатов) | `test/unit/domain/generation/knowledge_map_test.dart` |
| 3 | **Allocation** | `KnowledgeMap` + заказ | `OrderBudget`: `requested` и бюджеты партий, `Σ бюджетов == requested` | домен | `card_allocator_test.dart`, `output_batching_7_20_test.dart`, `order_budget_test.dart` |
| 4 | **Generation** | партия + id пунктов | ответ модели + `RequestLedger`: запрошено / произведено / восстановимо / обрезано | API (сервис вызова) | `card_generation_service_test.dart`, `generation_truncation_task04_test.dart` |
| 5 | **Validation** | карточки + `MaterialUnit` партии | `CardCandidate`: структурно годна, цитата валидна **по offsets**, пометки качества | домен + API-правила | `content_validator_test.dart`, `quote_offsets_test.dart` |
| 6 | **Dedup** | `CardCandidate[]` + хеши колоды | вердикт на карточку: `exact` (отбросить), `semantic` (пометить, оставить), `distinct` | домен | `generation_pipeline_v8_test.dart`, `dedup_verdict_test.dart` |
| 7 | **Replenish** | долг (`requested − принято`) + причины | новый `OrderBudget` на добор или явный «исчерпано» с причиной | домен (правило) + API (вызовы) | `replenish_planner_test.dart`, `generation_recovery_http_test.dart` |
| 8 | **Persistence** | принятые карточки | журнал запуска (принято/отброшено/долг) + импорт одной транзакцией | данные | `drift_generation_card_store_test.dart`, `generation_ledger_store_test.dart` |
| 9 | **Completion** | журнал + долг | `CompletionVerdict`: `done` только при `принято ≥ requested`, иначе `partial` + число и причина | домен (вердикт) + UI | `generation_pipeline_storage_test.dart`, `generation_completion_verdict_test.dart` |

Тесты в таблице — существующие либо цель среза (`BACKLOG.md`); новые файлы
названы по этапу, чтобы DoD каждого среза был одной командой.

**Уточнение среза 3 (TASK.txt):** Understanding реализуется как **извлечение
кандидатов моделью** (`gen-map-v1` → `KnowledgeUnit` с якорями на блоки,
`lib/api/generation/understanding_service.dart`) с кэшем карты
(`KnowledgeMapCache`, до среза 7 — in-memory). Это буквальная вторая половина
строки таблицы («модель — только как источник кандидатов»): карта остаётся
доменным типом `lib/domain/generation/knowledge_map.dart`, id единиц и приём
подсказок присваивает/проверяет приложение, а детерминированные правила
(пересчёт `salience` по структуре, дедуп пунктов нормализацией, покрытие)
остаются следующими шагами. Толкования — `journal/QUESTIONS.md` Q8/Q9.

**Уточнение среза 4 (TASK.txt):** Allocation реализуется как `AllocationPlan`
(`lib/domain/generation/allocation.dart`) поверх **единиц карты**: вес
`salience × плотность × тип`, распределение методом наибольших остатков,
минимум одна карточка на отобранную единицу, добор «вторым углом»
(`reverse | cloze | application`) и упаковка батчей под профиль модели
(`lib/domain/generation/model_profile.dart`: окно, предел вывода, JSON-схема,
Vision, параллельность; один батч — `вход + оценка выхода ≤ 40 % окна`). Это
консервативное прочтение строки S3 BACKLOG (`OrderBudget`): контракт «Σ бюджетов
== requested» и «нехватка материала отдельно» сохранён инвариантом
`AllocationPlan` и статусами `materialLimited`/`shortfall`, но тип назван по
этапу TASK, а долг и добор (S7) будут строить новый план из `AllocationPlan`,
а не из «мягкой ёмкости на глаз». Толкования — Q10/Q11.

**Уточнение среза 14 (TASK.txt, 2026-11-28):** инвариант плана Allocation
изменён по факту различимых слотов. `unit_id + angle` — один вопрос; у единицы
не больше четырёх слотов (основная карточка и углы `reverse | cloze |
application`, `kMaxCardsPerUnit = 4`). Поэтому `AllocationPlan` требует
`cards.length == capacity` (Σ min(бюджет единицы, 4)) и не допускает двух
одинаковых `slotKey`; заказ больше ёмкости не повторяет слоты: `requested`
остаётся пользовательским, `planned = capacity`, план помечается
`materialLimited`, а прогон завершается `partial` с причиной
`exhausted_material` (число — ёмкость). Добор при исчерпанной ёмкости не
делает ни одного запроса. Толкования — Q26.

**Уточнение среза 5 (TASK.txt):** Generation реализуется как
`CardsBatchEngine` (`lib/api/generation/cards_batch_engine.dart`) поверх
`LlmPort` — вызов на **партию единиц** карты (`CardsBatch`: утверждения с
якорями, карточки плана, принятое этого батча). Один вызов модели на партию,
запросы последовательные; обрезанный ответ делится по **границе единиц** и
добирается остатком, а повторы и добор считаются в журнале
(`GenerationBatchLedger.attempts`), а не в отдельном recovery-бюджете.
Промпт — `gen-cards-v3` с обязательными `unit_id`/`angle`/`quote_ref`; канон
A8.4 не изменён, расширение живёт отдельной проекцией
(`cardsResponseSchemaV3`). Вход-выход этапа: `AllocationPlan` →
`CardsBatchRun` (журнал, принятые карточки, версия промпта). «`RequestLedger`
на запрос» из BACKLOG S4 по смыслу — журнал прогона с числом попыток
(`lib/domain/generation/generation_ledger.dart`). Толкования — Q12–Q14.

**Уточнение среза 6 (TASK.txt):** Validation реализуется как `CardValidator`
(`lib/api/generation/validation/card_validator.dart`): структурные проверки
A8.4 (длины, cloze, теги, LaTeX) и семантические эвристики (ответ не в вопросе,
вопрос самостоятелен, атомарность, осмысленный cloze, язык ru, `quote_ref` по
offsets `ContentModel`, `section_id`/`unit_id` из партии) дают одну из трёх
величин — `accepted | warning | rejected(code)`; отброшенная запись хранится в
`RejectedCard` («показать отброшенные»), карточка с пометкой остаётся. Цитата
принимается только дословно (`substring(start, end) == quote_ref`); почти-цитата
— `quoteNotLiteral` без offsets, отсутствие — `quoteOutOfRange` с обнулением
цитаты (§3.3). Dedup реализуется как `SemanticMatcher`
(`lib/domain/generation/validation/semantic_matcher.dart`): каскад точный ключ →
нормализованный ключ (SPEC A8.5, шаг 9) → символьные шинглы + Жаккар →
эмбеддинги за необязательным `TextEmbeddingProvider`; дубль — **пара**
(`DedupPair`), а не удаление, отчёт по уровням (`DedupReport`) живёт в
`GenerationLedger.dedup`. Новый путь не подключён к конвейеру/UI до S7/S9
(протокол §9). Толкования — Q15–Q16.

**Уточнение среза 7 (TASK.txt):** Replenish реализуется как `ReplenishStage`
(`lib/domain/generation/replenish_stage.dart`) поверх `LlmPort` и журнала
первого прохода: долг — карточки заказа без принятой пары (`unit_id` + `angle`),
добор — только по единицам карты (новые единицы не выдумываются), каждая партия
несёт принятое своих единиц. Предохранители операции (`maxPasses = 3`,
`maxRequests = max(3, requested)`, бюджет токенов от оценок плана, wall clock)
дают `partial` с точной причиной (`ReplenishStopReason`); `exhausted_material` —
не ошибка и не повод добирать (число — в итоге). `ready` возможен только при
закрытых слотах, иначе `partial`; отмена сохраняет принятое. Отчёт прогона
(`GenerationReport.fromReplenish`) собирает заказ, принятое, причины, покрытие
единиц, расход по этапам, версии промптов и длительность. К конвейеру и UI не
подключено (S9, протокол §9); prompt-only отвечает `no_unit_plan` без запросов.
Толкования — Q17.

**Уточнение среза 8 (TASK.txt):** Persistence реализуется как **схема БД v2**
(ADR-051): `generation_runs`, `generation_units`, `generation_batches`,
`card_drafts`, `knowledge_maps`; `generation_jobs` остаётся совместимым
представлением для UI (его поля не удаляются и синхронизируются).
`DriftGenerationRunStore` + `GenerationRunCardSink` (`lib/data/generation/`)
пишут принятую карточку **в момент принятия** (`ARCH §3.5`), поэтому сбой на
пятом батче не теряет первые четыре; импорт черновиков в колоду —
`DriftGenerationCardStore.importRunCards` одной транзакцией и идемпотентно по
(`run_id`, `content_hash`) уникальным индексом. Восстановление —
`GenerationRunSnapshot` + `planGenerationResume`
(`lib/domain/generation/`): выполненные партии не перезапрашиваются, снимок без
единиц карты продолжается с `understanding`. Кэш карты знаний —
`DriftKnowledgeMapCache` (`knowledge_maps`), повторный материал не платит за
Understanding. Форматы хранения — `knowledge_map_json.dart` и
`generated_card_json.dart` (версия 1, строгий разбор). К конвейеру и UI не
подключено (S9, протокол §9). Толкование расхождения с BACKLOG S8 — Q18.

**Уточнение среза 9 (TASK.txt):** Completion и включение пути реализованы как
**флаг `generationPipelineV3` в `app_settings`** (ADR-052): включённый флаг
переключает слой завершения — вердикт `CompletionVerdict` по журналу (`done` ⟺
`принято ≥ заказано`, иначе `partial` с числом и `ShortfallKind`), пометку
почти-дублей вместо удаления (`CardIssueCode.possibleDuplicate`, ARCH §3.4),
«Почему?» по блоку `ContentModel` (`SourceAnchorResolver`, а не склеенная
цитата), метрики прогона (`GenerationMetrics`: yield/1000 входных токенов,
acceptance/duplicate rate по уровням, покрытие единиц, запросов на 10 карточек,
p50/p95 батча) и UI (этапы анализ → план → генерация → проверка, «принято N из M»,
итог и причины недобора, группы по темам, пометки). Этапы Understanding/
Allocation/Generation/Validation/Dedup/Replenish **к production-исполнению не
подключены** этим срезом: у Understanding нет HTTP-вызова, у `GenerationPlan` нет
моста к `AllocationPlan`; флаг, включающий несуществующую проводку, был бы
мёртвой заглушкой. Старый путь не удалён — флаг выключен по умолчанию (протокол
§9). Толкования — Q19–Q21, отчёт «было → стало» — `journal/iteration-8/summary.md`.
**Уточнение среза 10 (TASK.txt):** сквозное включение v3 собрано **тонким
фасадом** `GenerationV3Facade` (`lib/api/generation/generation_v3_facade.dart`):
Understanding (порт `UnderstandingStage` или единственная единица `kind=topic`
для prompt-only) → `planAllocation` → `CardsBatchEngine` → `CardValidator` →
`ReplenishStage` → `CardSink`/импорт → `GenerationReport`. Бюджетов,
калибровок и recovery-логики в фасаде нет; `GenerationPipeline` не растёт
(флаг выключен, legacy — production, Q19/Q21). Контракты среза: шестой класс
недобора `ShortfallKind.duplicates` (долг только из-за дублей), вердикт
`CardVerdict.blocked` с пятью жёсткими кодами (`quoteOutOfRange`,
`answerInQuestion`, `wrongLanguage`, `emptyAfterNormalization`,
`unparseableLatex`), `quoteUnverified` для карточки из единицы без якорей,
`ReplenishPolicy.wallClock = max(10 мин, 2 с × requested)` и предохранители в
отчёте (`ReplenishGuards`), причины недобора **множеством с числами**
(`GenerationReport.shortfallReasons`). Сквозные тесты без сети —
`test/integration/generation_v3_facade_flow_test.dart` («40 из 40»,
«12 из 40 exhausted_material», blocked-карточка вне колоды, prompt-only).
К production-раннеру фасад не подключён: нет HTTP-реализации
`KnowledgeMapCaller`; ограничения — `journal/QUESTIONS.md` Q22 и
`journal/generation-v3/verify-s10.md` §4.
**Уточнение среза 11 (TASK.txt):** гейт, HTTP-карта и проводка фасада.
Гейт — порт `CardGate` (`lib/domain/generation/card_gate.dart`, один метод
`evaluate → accepted|warning|blocked`) на существующем `CardValidator`
(`CardValidatorGate`); его спрашивают **оба** этапа до принятия: `CardsBatchEngine`
(первый проход) и `ReplenishStage` (добор), поэтому в `accepted`, `CardSink` и
`<already_accepted>` попадает только проверенная карточка (ARCH §3.2/§3.5).
`ReplenishPolicy.maxAttemptsPerSlot = 2` — всего попыток слота: вторая блокировка
закрывает слот как `validation_rejects`, число — в
`GenerationReport.shortfallReasons`. Understanding получил HTTP-реализацию порта
`KnowledgeMapCaller` (`HttpKnowledgeMapCaller`: `gen-map-v1`, схема карты,
`usage`, `RetryPolicy` — 429 `Retry-After`/5xx/таймаут, без повторов на 400/401)
и деление обрыва по `max_tokens` целыми блоками раздела
(`blocksPerMapRequest`), а срез 8 подключён к проводке:
`DriftKnowledgeMapCache` в `GenerationV3PathRunner` — повторный материал не платит
за Understanding. Проводка — `GenerationV3PathRunner`
(`lib/api/generation/generation_v3_path.dart`): материалы → `Document`
(`ContentModelBuilder`), Understanding → Allocation → Generation → Validation
(гейт) → Replenish → журнал/импорт, `GenerationPipeline.v3Path` вызывается
только при включённом `generationPipelineV3` (выключен — legacy без изменений).
`GenerationRunResult.report` несёт `GenerationReport`: UI берёт из него «принято
N из M», причины с числами, покрытие единиц и расход токенов, а `report.
understandingFailures` — причину отсутствия карты (`no_text_layer`, помеченные
фрагменты). Толкования — Q23; ограничения — `journal/generation-v3/verify-s11.md` §4.
**Уточнение среза 12 (TASK.txt):** живой измерительный стенд и «было → стало».
Гейт отдаёт **вердикт вместе с кодами причин** (`CardGateResult`, доменный
`CardReasonCode`): пометки принятой карточки живут в `GeneratedCard.gateReasons`
и доезжают до `GenerationReport.warningCodes`/`cleanRate` и предпросмотра
(текст — ARB). `GenerationReport` расширен тем, что нужно стенду и чего в нём
не было: `generated`, `acceptedWithWarnings`, `warningCodes`,
`duplicatesByLevel`, `batchDurations` (отметки времени каждого запроса
модели — первый проход и добор) и `salience` покрытых единиц. Legacy-путь
**тоже собирает `GenerationReport`** из своих же чисел: иначе сравнение путей
шло бы по разным источникам, а `cleanRate` у legacy не существовал бы.
`MetricsCollector` (`lib/domain/generation/metrics_collector.dart`) читает
**только отчёт** и даёт yield/1000 входа, acceptanceRate, cleanRate,
duplicateRate по уровням, coverage, meanSalience покрытых, запросов на 10,
p50/p95 и расход токенов по этапам; JSON пишется в
`journal/generation-v3/live-s12/`, таблица строится из тех же записей, без
ручных чисел. Живая матрица — 2 однофайловых материала (учебный текст
12 разделов, статья 3 раздела) × 20/40/80/150/300 × legacy/v3 на одном
провайдере/модели, с потолками запросов/стоимости/времени; исчерпание —
`not_run` с причиной. Скан без текстового слоя проверяется офлайн-smoke
(Understanding не делает запросов). Флаг по умолчанию включается только при
`cleanRate v3 ≥ legacy` и `coverage v3 ≥ legacy` на всех ячейках, где прогнаны
оба пути; иначе остаётся выключенным, расхождения — в S13.
**Поток данных.** `MaterialUnit` несут offsets — единственный источник истины о
тексте; `KnowledgeMap` ссылается на них, а не копирует текст; партия несёт id
пунктов, поэтому ответ модели привязан к материалу; `CardCandidate` сохраняет
диапазон цитаты, поэтому «Почему?» (A6.4) переживает рефакторинг нарезки;
`RequestLedger`/журнал — единственное место, где считается долг; `Completion`
читает только журнал, а не «сколько вернулось сейчас».

**Сейчас (для сравнения).** Этапы 1, 3, 4, 5 в коде есть; 2 (понимание) — нет:
заголовки разделов уходят в `<outline>`, но модель сразу просит карточки; 6 —
дедуп удаляет почти-дубли; 7 существует как «партия добора» внутри цикла, а не
как этап с долгом; 8 — журнал запуска не хранит принятые карточки (только счётчик);
9 — статус задания выводится из чисел текущего прогона.

## 3. Инварианты

1. **Сумма бюджетов равна заказу, если ёмкость слотов её покрывает.**
   `Σ бюджетов партий == requested`, когда материала достаточно; у каждой
   единицы не больше четырёх различимых слотов (`unit_id + angle`), поэтому
   при заказе больше ёмкости `Σ == capacity < requested` — это отдельный
   статус с числом (`материала ≈ на K из N`), а не молчаливое уменьшение цели
   и не повтор слотов. Проверки: `order_budget_test.dart` (S3),
   `allocation_capacity_test.dart` (S14), `generation_v3_facade_flow_test`
   («300 при 47 единицах»).
2. **Ложный успех запрещён.** `done` возможен только при `принято ≥ requested`;
   любой недобор — `partial` с числом и причиной (`материал исчерпан`, `модель
   обрезала`, `отброшено валидацией`, `дубли`). «Авто»-заказ не становится
   `done` при недоборе. Проверка: `generation_completion_verdict_test.dart` (S9).
3. **Цитата валидна по offsets.** `source_excerpt` — не подстрока «где-то в
   тексте», а диапазон внутри `MaterialUnit`: `start/end` проверяются по границам
   и по равенству текста. Цитата вне диапазона — пометка `quoteOutOfRange`
   (карточка остаётся), иначе цитата обнуляется. Проверка: `quote_offsets_test.dart` (S5).
4. **Смысловой дубль помечается, а не удаляется.** Точный дубль (тот же
   нормализованный текст) отбрасывается — это не потеря. Почти-дубль получает
   `semanticDuplicate` и остаётся в предпросмотре, чтобы пользователь решил сам.
   Проверка: `dedup_verdict_test.dart` (S6).
5. **Сбой не теряет принятое.** Принятые карточки пишутся в журнал запуска по
   ходу (не в память до конца), импорт идемпотентен; падение процесса/приложения
   даёт восстановление из журнала, а не пустой результат. Проверка:
   `generation_ledger_store_test.dart` (S8).

## 4. Что не меняется

- Без WebView, парсеры — чистый Dart (AGENTS.md); домен без Flutter.
- Ключи только в `flutter_secure_storage`; тексты материалов и промпты с
  материалами не логируются.
- Схема ответа модели (A8.4) остаётся канонической; `section_id` из ответа —
  подсказка, а не источник истины (её проверяет этап 5, а не конвейер).
- Импорт в колоду — одной транзакцией; дедуп при импорте остаётся вторым
  рубежом, но перестаёт быть местом, где «исчезают» карточки: скипы
  возвращаются в журнал как отброшенные с причиной.

## 5. Вердикты аудита (кратко; подробно — `docs/generation/AUDIT.md`)

| Гипотеза | Вердикт | Строка-доказательство |
|---|---|---|
| а — цель режется бюджетом одного запроса | опровергнута в плане, подтверждена в исполнении | `generation_pipeline.dart:2075` (`_topUpChunk`), `:1121` |
| б — нет этапа понимания материала | **подтверждена** | `input_planner.dart:1097` (`outlineOf`) |
| в — дефекты компенсируются наслоениями | **подтверждена** | `token_calibration.dart:23`, `_recoveryFor:1352`, `:120` |
| г — дедуп только по хешу `front+back` | опровергнута по букве, подтверждена по следствиям | `_acceptCard:1933`, `_frontSimilarity:1958` |
| д — валидация структурная, без offsets | **подтверждена** | `card_content_validator.dart:232-236`, `:252-257` |
| е — нет бухгалтерии запрошено/валидно/принято | опровергнута по букве, подтверждена по сути | `generation_run.dart:203`, `tables.dart:249-255` |
| ж — ответственности смешаны в одном классе | **подтверждена** | `generation_pipeline.dart:103` (2162 строки) |

## 6. Открытые вопросы (в `journal/QUESTIONS.md`)

- Точный список «9 срезов» в TASK.txt отсутствует: принято соответствие
  «срез = этап» (консервативное толкование).
- Где хранить журнал запуска до импорта (строка `generation_jobs.*_json` против
  staging-таблицы) — решается в S8; схема БД меняется только с ADR.
