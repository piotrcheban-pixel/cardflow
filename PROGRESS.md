# PROGRESS — CardFlow: генерация v3 (внешняя память прогонов)

## Сделано

**Срез 17B (2026-11-28) — контекст «уже создано» в v3 и один замер гипотезы.**
- **Диагноз (до платных прогонов).** В запрос v3 попадало только принятое
  **своего** батча (`<already_accepted>`); принятое других партий и занятые
  `unit_id` — нет. У прежнего пути `<already_created>` есть с среза 13
  (`generation_pipeline.dart:_digestOf`). Красная фаза `red-s17b.txt`:
  `Expected: contains '<already_created>'`, `Actual: '<units>…<budget…'`.
- **`<already_created>` у v3.** `RunCardContext`
  (`lib/domain/generation/run_card_context.dart`): краткие утверждения принятых
  единиц (не карточки: без `front`/`back`) + занятые `unit_id`; блок в
  пользовательском сообщении — `<taken units="…"/>` и `<statement unit_id="…">`.
  Движок пополняет контекст по завершении партии, `ReplenishStage` пересобирает
  его перед каждым запросом добора. **Формулировка `gen-cards-v3` не менялась**
  (байтовая сверка `docs/prompts/gen-cards-v3.txt` зелёная).
- **Предел payload — по числу:** 20 утверждений, 40 `unit_id`, 160 символов на
  утверждение, приоритет — разделы текущей партии; применяет сборщик сообщения
  (`buildCardsUserContent`), поэтому обойти нельзя. Тест «200 единиц = 50» это
  фиксирует.
- **Замер (TASK ч. 2): критерий не выполнен.** 2/2 ячейки `ran`, 06:17, 38 HTTP,
  **0,142368 USD** из 0,30. Против оплаченной `textbook-v3-150`: `dupRate`
  24,4 % → 39,1 %, `unique` 45 → 64, `cleanRate` 93,3 % → 100,0 %, запросов на
  10 уникальных 0,44 → 0,31. Контекст дошёл до платного запроса (1 из 3 карточных
  запросов, 20 утверждений — `request_shapes` в `run.json`). Причина нулевого
  эффекта структурная: на `deepseek-flash` (`maxOutputTokens = 384 000`) заказ
  умещается в **один** запрос генерации, дубли рождаются внутри ответа (L239);
  карта Understanding у ячеек разная — 33 → 41 единица (L238).
- **Вердикт:** дубли — в промпт S18. Правка остаётся (паритет с legacy, тесты, не
  меняет план/пороги), но выигрышем не объявлена; `auto` = legacy, критерий пути
  не пересчитывался.
- **Слепая выборка — измерена.** 60 карточек (30 v3 + 30 legacy) размечены
  владельцем (60/60), ключ открыт после разметки: **доля годных v3 76,7 %**
  (23/30), **legacy 80,0 %** (24/30) → условие S17 п. 12 «v3 не ниже legacy»
  **не подтверждено** (разница — одна карточка, 3,3 п.п.). Автометрика
  `cleanRate` = 100 % у обоих путей (насыщена: дубли откладываются до принятия)
  — с разметкой **не совпадает**, завышение 23,3 / 20,0 п.п.; `dupRate`
  (39,1 % / 3,2 %) считает отложенных, в выборку они не попадают. Оговорки: три
  «негодных» v3 — cloze с сырым `{{c1::…}}` в файле (L240; сборщик исправлен —
  `[…]` + защита от перезаписи), часть «повторов» межпутевая (L241).
- **ADR-055**, Q30, L238–L241 (L237 снят), `verify-s17b.md`, `matrix-s17b.md`,
  `blind-score-17b.md`.

**Срез 17 (2026-11-28) — заморозка метрики, сопоставимый объём, правило пути,
слепая выборка (инструмент).**
- **Метрика заморожена (часть 0).** `OutcomeCounts`: `cleanRate = clean/unique`,
  `dupRate = duplicates/unique`, `blockRate = blocked/attempted`, новая
  `acceptanceRate = accepted/attempted`; `GenerationReport.cleanRate`/
  `duplicateRate` делегируют замороженным определениям (историческое
  `clean/generated` убрано из живого кода). DoD-тест «дубль не двигает
  cleanRate» падал в красной фазе (`Expected: <0.4> Actual: <0.307…>`).
- **Сопоставимый объём.** `path_rule.dart`: `comparableVolume` (отношение
  принятых ≥ 0,8), `volume_mismatch`; пересчёт `tool/recompute_matrix_s17.dart`
  → `matrix-s17.md`: 4 сопоставимых пары, v3 не ниже legacy по чистым на 0 из 4,
  `volume_mismatch` — статья 80 и 300.
- **N* данные не дают.** `derivePathThreshold` + `MaterialPathPoint`: v3 не
  выигрывает ни на 10, ни на 33 единицах (dupRate 35,9 % против 1,2 % на
  учебном тексте, absoluteClean ниже) → `kGenerationPathV3MinUnits = null`,
  авто = legacy, решение несёт `boundaryNotDetermined`.
- **Путь — функция от материала (п. 11).** `GenerationPathMode {auto, v3,
  legacy}` вместо булева флага (`app_settings` JSON `generation_path_mode`,
  старый `generation_pipeline_v3` читается), `selectGenerationPath`,
  `generationPathDecisionProvider`/`generationUsesV3Provider`, настройка —
  три чипа (ARB `settingsGenerationPath*`), ручное переопределение работает.
- **Слепая выборка — инструмент, измерение `not_measured`.** `blind_sample.dart`
  (30+30, seed-перемешивание, в выборке только номер и тексты, ключ отдельно),
  `tool/blind_sample_s17.dart`, `S12Bench` пишет карточки ячейки ключом `cards`
  (следующий замер сохранит их для обоих путей). У существующих ячеек текстов
  карточек нет → `blind-sample-17.md`/`blind-key-17.json` = `not_measured` с
  причиной; выдуманных карточек нет.
- **Legacy `dupRate` офлайн** — `not_measured` (TASK часть 0, п. 2):
  сохранённых карточек в `cells/*.json` нет; числа не додумывались.
- **ADR-054**, Q29, L235–L237, `verify-s17.md`, `matrix-s17.md`.

**Срез 16 (2026-11-28) — дубль не закрывает слот, углы по богатству, честная метрика.**
- **Dedup до принятия, а не после генерации.** `CandidateDeduper` /
  `CascadeDeduper` (`lib/domain/generation/candidate_deduper.dart`) — тот же
  каскад `SemanticMatcher`, что у S13, но спрашивается в момент приёма:
  `CardsBatchEngine.run(..., deduper:)` и `ReplenishStage.run(..., deduper:)`.
  Отложенный дубль не идёт в `CardSink`/журнал, слот остаётся открытым, а
  `duplicates` журнала его считает. Пост-хунтовый этап `_dedup` фасада удалён;
  `GenerationV3Run.dedup` — пары отложенных кандидатов.
- **Повтор с другим углом, две коллизии → duplicate.** `retryAngles` в
  `ReplenishStage`: после коллизии слот запрашивается с первым свободным углом
  `angleCycleFor` (alias «слот запроса → слот заказа»); `maxAttemptsPerSlot = 2`
  распространён на дубли, вторая коллизия закрывает слот
  `ReplenishStopReason.duplicates` (класс `ShortfallKind.duplicates`) и
  `shortfallReasons` считает **незакрытые слоты**, а не отложенные карточки.
- **Ёмкость по богатству.** `unitCapacity` = 1 + salience ≥ 0,8 + ≥ 3
  утверждений/клауз в якорях + вид formula/procedure (потолок 4);
  `allocateUnits`/`allocationCapacity`/`materialCapacity` — той же функцией.
  Короткий факт статьи получает 1–2 карточки, а не 4 (TASK ч. 3).
- **Метрика попыток.** `OutcomeCounts` (`outcome_counts.dart`) из одного
  `GenerationReport` для обоих путей: `attempted/accepted/unique/clean`,
  `cleanRate = clean/attempted`, `dupRate = duplicates/attempted`,
  `blockRate`; `GenerationReport.outcome`, поля в `MetricsCollector.toJson`
  (`attempted/accepted_final/unique/clean/dup_rate/block_rate`). Legacy-путь
  отдаёт в `duplicates` то, что удаляет `_acceptCard` (поведение то же).
- **ADR-053**, Q28, L233–L234 — решения и толкования.
- **Перемер и вердикт** — `journal/generation-v3/live-s16/` (12 ячеек, потолок
  1,00 USD), пересчёт `matrix-s16.md`, `verify-s16.md`.

**Срез 15 (2026-11-28) — пер-юнитные данные, честный перемер, флаг выключен.**
- **Флаг вернулся в выключенное состояние (часть 0).** Критерий S14 выведен из
  агрегата `coverage`, а не измерен пер-юнитными данными (L230). Тест фиксирует
  дефолт (`Expected: false, Actual: <true>` в `red-s15.txt`), ADR-052 снова
  согласован с кодом.
- **Пер-юнитные данные (L230 снят).** `UnitCoverage` — `sectionId`, `produced`,
  `clean`, `warningCodes`; `fromReplenish` считает их по фактическим карточкам
  (принятые + заблокированные гейтом), фасад передаёт `blockedCards`.
  `metrics.unit_coverage` — в `matrix.jsonl`; `code_version` — в каждой строке,
  строки без него — `legacy-schema`. Legacy-разделы: числа распределяются по
  разделам партии равномерно — L231.
- **База `matchedSubset` из данных.** `MatchedUnitBase` — пересечение по общему
  ключу (раздел), «топ-80 по salience» — из фактической значимости единиц,
  порог `kMinMatchedUnits = 10`; `flagCriterion` учитывает число единиц.
- **Честный перемер 12 решающих ячеек (80/150/300 × 2 материала × 2 пути).**
  `code_version 5dc3cb11`, дерево чистое: **12/12 ran**, 0 `not_run`, расход
  **0,431622 USD** из 1,00 (38 логических / 107 HTTP запросов, 14:37). Каждая
  ячейка — `cells/<cellId>.json`; пересчёт `matrix-s15.md` без новых запросов.
- **Критерий флага не выполнен на 6/6 → флаг выключен.** `cleanRate_matched(v3)`
  30,0–46,6 % против порога 95 %: пометка `possible_duplicate` (Dedup S13) —
  23–96 карточек на ячейку — входит в «грязные», у legacy смысловых пометок нет.
  `absoluteClean` провален в 2 ячейках (учебный 80: 25 против 79; статья 300:
  12 против 17). Расхождения — S16 (промпт/углы или решение владельца о
  `possible_duplicate` в критерии).

**Срез 14 (2026-11-28) — ёмкость плана, честный статус, решение о флаге.**
- **Ёмкость различимых слотов — инвариант плана.** `kMaxCardsPerUnit = 4`
  (`null | reverse | cloze | application`); `allocateUnits` больше четырёх
  карточек на единицу не раскидывает, излишек распределяется с ограничением
  (доли сверх 4 обрезаются, остаток — по убыванию веса). `AllocationPlan`
  проверяет конструктором: `cards.length == allocationCapacity(units)` и нет
  двух одинаковых `slotKey`; `materialLimited` = «заказ больше ёмкости»,
  `capacity` — отдельный геттер. 47 единиц × 4 = 188: `planned == 188`,
  `requested == 300`, `shortfall == 112`, повторов слотов нет.
- **Честный итог 188/300.** `ReplenishStage` при `materialLimited` и закрытых
  слотах меняет `complete` на `exhausted_material`, `materialCapacity` = ёмкость
  плана (188), `remaining` = 112; вердикт `partial`, `jobStatus == partial`,
  добор не делает ни одного запроса. Регресс-тест на фасаде до фикса падал
  `Expected: partial, Actual: done` (`red-s14.txt`).
- **Сопоставимая база.** `MatchedSubset` (пересечение единиц, `cleanRate_matched`,
  «топ-N по salience»), `GenerationReport.absoluteClean`,
  `CollectedMetrics.absoluteClean`/`absolute_clean`. Пересчёт существующей
  матрицы — `tool/recompute_matrix_s14.dart` → `matrix-s14.md` (новых платных
  прогонов 0).
- **Критерий флага — окончательный:** `cleanRate_matched(v3) ≥ 95 %` и
  `absoluteClean(v3) ≥ absoluteClean(legacy)` на всех решающих ячейках
  80/150/300. Выполнено на 6 из 6 → `generationPipelineV3` по умолчанию `true`,
  legacy — выключением флага. Тесты, проверяющие legacy-путь, теперь задают
  флаг **явно** (`legacyGenerationSettings()` + override
  `effectiveAppSettingsProvider` — иначе первый синхронный `read` видит
  `defaults`). Предпросмотр показывает «Материала примерно на 188 карточек».

**Срез 13 (2026-11-28) — Dedup в цепи, стоимость Understanding, честная база.**
- **Dedup в фасаде.** `GenerationV3Facade._dedup` вызывает существующий
  `SemanticMatcher` (каскад exact → normalized → semantic → embeddings) по
  принятым прогона и целевой колоде (`deckCards` в
  `GenerationV3PathRunner`, production-проводка — `DriftCardRepository
  .cardsByDeck`). Новых правил нет. Дубль **не удаляется**: `GeneratedCard`
  получает `CardIssueCode.possibleDuplicate` (чип предпросмотра
  `generation-mark-possible-duplicate` уже существовал) и
  `CardReasonCode.possibleDuplicate` (новый код, ARB
  `generationReasonPossibleDuplicate`, `cleanRate` считает пометку «грязной»).
  `DedupReport` — в `GenerationV3Run.dedup`, `duplicatesByLevel` — в отчёте,
  `duplicateMarked` — число помеченных карточек (не пар).
- **Персист пар (L219 снят).** Схема **v3** (`schemaVersion = 3`):
  `card_drafts.is_duplicate_of` + `dedup_level` (nullable), миграция 2 → 3;
  `DriftGenerationRunStore.saveDedupMarks` пишет `UPDATE` по
  `run_id + content_hash` после этапа Dedup; `GenerationRunSnapshot.dedup`
  восстанавливает пары (одинаковое содержимое — маркер `same:`),
  `importRunCards` пометки не теряет. Снимки: `drift_schemas/
  drift_schema_v3.json`, `test/**/generated/schema_v3.dart`.
- **Проба strict-схемы один раз на прогон.** `lib/domain/generation/
  schema_compat_profile.dart` (ключ провайдер + модель + схема) передаётся
  `HttpKnowledgeMapCaller` и `AdapterCardsBatchPort`: первая `400`
  запоминается, остальные разделы/батчи идут сразу без strict. DoD:
  **12 разделов → 13 запросов** (было 24), **10 батчей → 11** (было 20).
  Запросы Understanding — `KnowledgeMapRawResponse.attempts` →
  `UnderstandingResult.requests` → `GenerationReport.understandingRequests`.
- **Честная база сравнения.** `cleanRate` = принято без пометок /
  **произведено** (не / принято); `duplicateRate` — тоже; `duplicateMarked`
  в отчёте; `lib/domain/generation/matrix_comparison.dart` — правила
  «20/40 нерешающие, решение по 80/150/300», `tool/recompute_matrix_s13.dart`
  пересчитывает `live-s12/matrix-s13.md` из **существующего** `matrix.jsonl`
  (новых платных прогонов 0). На честной базе v3 хуже legacy на 2 решающих
  ячейках (учебный 300: 97,3 vs 98,6; статья 300: 97,9 vs 100) → флаг
  выключен.
- **Разбор 188/300 статьи.** Остановка `complete` (не `max_passes` и не
  `exhausted_material`): 188 различимых слотов `unit_id + angle`, 112
  карточек плана повторяют занятые (188 / 4 = 47 единиц при полном наборе
  углов). Повтор слотов в плане — L229, аллокацию/пороги срез не менял.

**Срез 12 (2026-11-28) — живые прогоны и метрики «было → стало».**
- **Коды гейта в отчёте и UI.** `CardGateResult` (`verdict` + `List<CardReasonCode>`),
  `CardReasonCode` — доменный тип (`lib/domain/generation/card_reason_code.dart`,
  `card_validator.dart` реэкспортирует для старых импортов). `CardValidatorGate`
  пробрасывает коды существующего валидатора без новых проверок; принятая с
  пометкой карточка несёт `GeneratedCard.gateReasons`. `GenerationReport`
  получил `generated`, `acceptedWithWarnings`, `warningCodes`, `cleanRate`,
  `duplicatesByLevel`, `batchDurations`, `salience` единиц; предпросмотр
  показывает код причины чипом с ARB-текстом (`generationReason*`).
- **Единый источник метрик.** `MetricsCollector`
  (`lib/domain/generation/metrics_collector.dart`) читает **только**
  `GenerationReport`: yield/1000 входа, acceptanceRate, cleanRate,
  duplicateRate по уровням, coverage, meanSalience покрытых, запросов на 10,
  p50/p95, расход токенов по этапам. Legacy-путь теперь тоже собирает
  `GenerationReport` из своих чисел (`generation_pipeline.dart`); p50/p95 —
  из новых отметок времени батчей (`CardsBatchRun`/`ReplenishOutcome`).
- **Стенд и матрица.** `test/live/generation_matrix_s12_live_test.dart` +
  `test/live/support/s12_bench.dart`: 2 материала (12/3 раздела) ×
  20/40/80/150/300 × legacy/v3, реальные ключи, `live-s12/{matrix.jsonl,
  matrix.md,run.json}`. Итог: **20/20 ran**, 148 HTTP, 43 legacy-вызова,
  29,6 мин, **0,66 USD** при потолке 2,50; v3 — 20/40/80/150 полностью,
  299/300 (учебный) и 188/300 (статья) — честный `partial`; coverage 100 %
  у обоих путей.
- **Две лестницы ADR-021, найденные живым прогоном.** `HttpKnowledgeMapCaller`
  и `AdapterCardsBatchPort` строили strict-запрос без упрощения: DeepSeek
  отвечал 400, v3 давал `provider_error`/0 карточек. Добавлены те же три
  ступени (strict+`max_tokens` → без схемы+`max_tokens` → без схемы и
  `max_tokens`, ≤3 запроса, только `badRequest`); `runResultOf` теперь берёт
  статус из `verdict.jobStatus`, а не из `report.stage` (299/300 — `partial`,
  не ложный `done`).
- **Флаг не включён.** Строгий критерий TASK не выполнен: cleanRate v3 ниже
  legacy на 3 ячейках (учебный 300: 97,7 vs 100; статья 20: 95 vs 100; статья
  300: 98,4 vs 100), coverage равен 100 % везде. Расхождения — `verify-s12.md`
  §4–§5, `journal/generation-v3/s13-handoff.md`.

**Срез 11 (2026-11-28) — гейт в доборе, HTTP-карта знаний, проводка фасада.**
- `lib/domain/generation/card_gate.dart` — порт `CardGate` (один метод
  `evaluate → accepted|warning|blocked`) и `CardValidatorGate`
  (`lib/api/generation/validation/`) поверх существующего `CardValidator`:
  `blocked` — жёсткий дефект или структурно отброшенная запись, `warning` —
  пометка, новой логики проверок нет.
- Гейт стоит **до принятия** в первом проходе (`cards_batch_engine.dart`) и в
  доборе (`replenish_stage.dart`): блокированное не идёт в `CardSink`, в контекст
  партии и в `accepted` (журнал пишет его как `invalid`). Добор не закрывает слот
  такой карточкой; `ReplenishPolicy.maxAttemptsPerSlot = 2` (всего попыток,
  включая первый проход), вторая блокировка слота закрывает его как
  `validation_rejects`, причина — в `GenerationReport.shortfallReasons`.
  Фасад создаёт один гейт на прогон и передаёт обоим этапам; пост-валидация
  удалена (один путь, не два).
- `lib/api/generation/http_knowledge_map_caller.dart` — HTTP-реализация
  `KnowledgeMapCaller` поверх существующих адаптеров, `GenerationTransport` и
  `RetryPolicy`: промпт `gen-map-v1`, схема карты (`canonicalKnowledgeMapSchema`
  → проекция протокола), `usage` каждого ответа. Обрыв по `max_tokens` →
  `truncated`, а `UnderstandingService` делит фрагмент **целыми блоками по
  лимиту вывода** (`blocksPerMapRequest`), не пополам; повторный обрыв части —
  фолбэк среза 3 (фрагмент помечен, прогон продолжается).
- `lib/api/generation/generation_v3_path.dart` — production-проводка:
  `UnderstandingService` + `DriftKnowledgeMapCache`, `CardsBatchEngine` +
  `AdapterCardsBatchPort`, `ReplenishStage` с гейтом, `GenerationRunCardSink`/
  `importRunCards`; `GenerationPipeline.v3Path` вызывается только при
  включённом `generationPipelineV3` (выключен — legacy без изменений),
  `app_providers.dart` собирает путь реальными реализациями.
- `GenerationRunResult.report` — `GenerationReport` доезжает до результата:
  предпросмотр берёт «принято N из M», причины недобора **с числами**, покрытие
  единиц и расход токенов из отчёта, а не из вердикта/счётчиков; причина
  отсутствия карты (`no_text_layer`, помеченные фрагменты) — строкой ARB.
  ARB: `generationReportShortfall/Coverage/Tokens`, `generationUnderstandingNoText/Failed`.

**Срез 10 (2026-11-28) — сквозное включение v3 и правки по решениям владельца.**
- `ShortfallKind.duplicates` — шестой класс недобора: долг только из-за дублей
  даёт `duplicates`, а не `validationRejects` (`generation_ledger.dart`).
- `CardVerdict.blocked` — четвёртый вердикт; жёсткие коды `quoteOutOfRange`,
  `answerInQuestion`, `wrongLanguage` (было `languageNotRussian`),
  `emptyAfterNormalization` (новый), `unparseableLatex` (было `latexBroken`)
  блокируют карточку: в колоду не идёт, в «показать отброшенные» остаётся
  (`card_validator.dart`, `CardValidationReport.blocked/blockedCards`).
- `quote_ref == null` + единица без якорей → `CardReasonCode.quoteUnverified`
  («без источника», warning). `KnowledgeUnitKind.topic` и единица без якорей
  разрешены для prompt-only; `KnowledgeMap.unanchoredUnitIds`.
- `ReplenishPolicy.wallClock` — `max(10 мин, 2 с × requested)` от заказа
  (`wallClockFor`, `wallClockForRequested`); `ReplenishGuards` в итоге добора и
  в `GenerationReport.guards`.
- `GenerationReport.shortfallReasons` — причины недобора **множеством с
  числами** (дубли и валидация своими счётчиками, остаток — причиной остановки).
- `lib/api/generation/generation_v3_facade.dart` — тонкий фасад: Understanding →
  Allocation → Generation → Validation → Dedup/Replenish → журнал/импорт →
  отчёт, без бюджетов/калибровок/recovery. Сквозные тесты (без сети):
  `test/integration/generation_v3_facade_flow_test.dart` — «40 из 40»,
  «12 из 40 exhausted_material», blocked-карточка вне колоды, prompt-only
  «без источника».
- UI: пометка «Без источника» (`generation-mark-no-source`), ARB-строка и
  причина недобора `duplicates`; литералов нет.

**Срез 9 (2026-11-28) — флаг, UI, «Почему?» по anchors, метрики, отчёт.**
- `AppSettings.generationPipelineV3` (JSON `generation_pipeline_v3`, по умолчанию
  `false`, ADR-052) → `generationRunnerProvider` → `GenerationPipeline(pipelineV3:)`;
  переключатель `settings-generation-pipeline-v3` на экране «Провайдеры».
- `lib/domain/generation/completion_verdict.dart`: `done` ⟺ `принято ≥ заказано`,
  отмена с принятым → `partial`, сбой без карточек → `failed`, причины —
  `ShortfallKind`, `jobStatus` из вердикта (на пути v3).
- `lib/domain/generation/generation_metrics.dart`: yield/1000 вх. токенов,
  acceptance/duplicate rate (в т.ч. по уровням каскада), покрытие единиц,
  запросов на 10 карточек, p50/p95; `GenerationRunResult.metrics/verdict/
  possibleDuplicates`, `GenerationDiagnostics.runMetrics`.
- Путь v3: почти-дубль помечается и остаётся (`CardIssueCode.possibleDuplicate`),
  точный отбрасывается; `lib/api/generation/source_anchor.dart` даёт блок
  источника для «Почему?» (`sourceAnchorText/SourceSection`).
- UI: `generation_v3_progress.dart` (4 этапа, «принято N из M»); предпросмотр —
  вердикт + причины недобора, группы по первому тегу, пометки «Возможный дубль»,
  «Обратная сторона», «Предупреждение: N», лист «Почему?» с текстом блока.
- Отчёт «было → стало»: `journal/iteration-8/summary.md`; метрики 4 сценариев —
  `journal/generation-v3/scenarios-s9.txt` (v1 vs v3 на одной проводке).
- Legacy не удалён (флаг выключен по умолчанию, Q21); этапы v3 к проводке не
  подключены (Q19).
**Срез 8 (2026-11-28) — Persistence: черновики, миграция, идемпотентный импорт.**
- **Схема v2** (ADR-051, `lib/data/db/tables.dart`, `app_database.dart`):
  `generation_runs`, `generation_units`, `generation_batches`, `card_drafts`,
  `knowledge_maps`; таблицы SPEC A5 не менялись, `generation_jobs` продолжает
  заполняться (совместимое представление для UI). `schemaVersion = 2`,
  шаговая миграция 1 → 2 (`createTable` + явный `createIndex` — `Migrator`
  индексы сам не создаёт), понижение/неизвестная версия — fail-fast.
  Снимки: `drift_schemas/drift_schema_v2.json` (`schema dump`),
  `test/unit/data/db/migrations/generated/*` и `test/migrations/generated/*`
  (`schema steps` + `schema generate`). `.bak` перед миграцией —
  `backupBeforeMigration` в `database_opener.dart` (ADR-005 §5).
- `lib/data/generation/drift_generation_run_store.dart`: `openRun` (идемпотентен
  по `runId`, не сбрасывает принятое), `saveStage`, `saveBatch`, `saveDraft`
  (`InsertMode.insertOrIgnore` + уникальный `idx_card_drafts_run_hash`),
  `saveDeckId`, `loadRun`, `unitsOfRun`, `latestResumableRunId`;
  `GenerationRunCardSink implements CardSink` — карточка пишется в момент
  принятия, сбой на 5-м батче не теряет первые 4.
- `lib/domain/generation/generation_run_snapshot.dart` + `run_resume.dart`:
  `GenerationBatchStatus` (`pending|running|done|failed`), `GenerationBatchRecord`,
  `RunCardDraft`, `GenerationRunSnapshot` (`resumeBatchIndex`, `resumeStage`,
  `isResumable`), `planGenerationResume` — выполненные партии не
  перезапрашиваются; без единиц карты → `understanding`; все партии выполнены →
  `replenishing`; завершённый прогон не восстанавливается.
- `lib/data/generation/drift_knowledge_map_cache.dart`: `DriftKnowledgeMapCache`
  на `knowledge_maps` — повторный материал не платит за Understanding после
  перезапуска; повреждённая строка — промах. Форматы `knowledge_map_json.dart`
  и `generated_card_json.dart` (v1, строгий разбор).
- `DriftGenerationCardStore.importRunCards`: импорт черновиков **одной
  транзакцией**, идемпотентно по (`run_id`, `content_hash`), отметки
  `imported_card_id`/`imported_at` в той же транзакции; `_resolveDeck` общий с
  `importGeneratedCards`.
- Конвейер, UI и `generationV3` **не менялись** (подключение — S9).

**Срез 7 (2026-11-28) — Replenish и partial.**
- `lib/domain/generation/replenish_stage.dart`: `ReplenishStage` — долг это
  слоты заказа без принятой пары (`unit_id` + `angle`); добор идёт только по
  карточкам долга и единицам **исходного** плана (новые единицы не выдумываются);
  каждая партия несёт `<already_accepted>` своих единиц. В принятое идёт только
  карточка, закрывающая слот; повтор принятого/чужой угол — `surplus` (долг не
  уменьшает и прогресса не даёт). Предохранители: `maxPasses = 3`,
  `maxRequests = max(3, requested)` (вся операция, включая первый проход),
  `tokenBudget` от оценок плана (факт `usage`, при неизвестном — оценка партии),
  `wallClock` 10 мин от начала. Исчерпание → `partial` с точной причиной
  (`ReplenishStopReason`: `max_passes`/`max_requests`/`token_budget`/`wall_clock`/
  `provider_error`/`cancelled`/`no_unit_plan`). `exhausted_material` — не ошибка
  и не повод добирать (уже объявленные исчерпанными единицы не запрашиваются,
  проход без закрытых слотов останавливает добор), число — `materialCapacity`.
  `ready` только при закрытых слотах и `accepted ≥ requested`; отмена сохраняет
  принятое (`partial`; `cancelled` — только без принятого).
- `lib/domain/generation/generation_report.dart`: `GenerationReport.fromReplenish`
  — `requested`, `accepted`, причины машинными кодами, покрытие единиц
  (`UnitCoverage`), расход токенов по этапам (`generating`/`replenishing`),
  версии промптов (подставляет вызывающий слой), длительность; `isComplete`
  требует закрытых слотов.
- `lib/api/generation/cards_batch_engine.dart`: фикс среза 5 — `_addUsage`
  начинал сумму с `const TokenUsage()` и по правилу «неизвестное обнуляет
  сумму» всегда возвращал `null`; теперь «ещё нет расхода» ≠ «неизвестно».
- Старый конвейер, UI, схема БД и `generationV3` **не менялись**; подключение —
  S9 (протокол §9). Prompt-only — `no_unit_plan` без запросов.
- Тесты (+30): `replenish_stage_test.dart` (25),
  `generation_report_test.dart` (4),
  `replenish_stage_wiring_test.dart` (1 — движок со сбоем 3-го батча → этап →
  отчёт на production-проводке).

**Срез 6 (2026-11-27) — Validation и каскад дедупликации.**
- `lib/api/generation/validation/card_validator.dart`: `CardValidator` —
  структурные проверки A8.4 (длины 500/2000, cloze, теги до 3, LaTeX) и
  семантические эвристики с машинным кодом `CardReasonCode` (ответ не в
  вопросе; вопрос самостоятелен — «этот»/«выше»/«см. рис.»; атомарность —
  перечисление >3; осмысленный cloze; язык ru; `quote_ref` по offsets;
  `section_id`/`unit_id` из партии). Вердикт `accepted | warning | rejected`;
  отброшенное не исчезает (`RejectedCard` хранит исходный JSON). Цитата
  принимается только дословно (`substring(start, end) == quote_ref`),
  почти-цитата — `quoteNotLiteral` без offsets, отсутствие — `quoteOutOfRange`
  с обнулением (ARCH §3.3); ищутся только содержательные блоки.
- `lib/domain/generation/validation/semantic_matcher.dart`: каскад точный ключ →
  нормализованный ключ → символьные шинглы + Жаккар (0.7) → эмбеддинги за
  интерфейсом `TextEmbeddingProvider`; дубль — пара (`DedupPair`), карточки не
  удаляются; сверка с колодой через `existing`.
- `lib/domain/generation/dedup_report.dart`: `DedupLevel` (wire-коды),
  `DedupPair`, `DedupReport` (пары, счётчики по уровням, сильнейший уровень по
  порядку каскада).
- `lib/domain/generation/generation_ledger.dart`: `dedup`/`withDedup` — отчёт по
  уровням в журнале, переживает `record`/`attempt`/`markCause`/`replace`;
  арифметика заказа не менялась.
- Старый валидатор, конвейер, UI, адаптеры и схема БД **не менялись**; новый
  путь не подключён (флаг `generationV3` — S7/S9, протокол §9).
- Тесты (+51): `card_validator_test.dart` (24), `quote_offsets_test.dart` (7),
  `semantic_matcher_test.dart` (14), `dedup_report_test.dart` (6), фикстура
  `test/fixtures/validation/duplicate_pairs.json`.

**Срез 5 (2026-11-27) — Generation: батчи по единицам через существующие
адаптеры.**
- `lib/api/generation/provider_result.dart`: `ProviderResult` (content,
  `ProviderFinishReason` stop/length/refusal/empty/error, usage, refusal,
  rawError, detail) + `ProviderResponseNormalizer` — исход любого из четырёх
  адаптеров в один тип; отмена пробрасывается, остальные исключения —
  результат с кодом. Адаптеры не переписаны.
- `lib/api/generation/cards_batch_port.dart`: `AdapterCardsBatchPort
  implements LlmPort` поверх существующих `buildRequest`/`parseResponse` и
  `GenerationTransport`: промпт `gen-cards-v3`, проекция схемы v3, поштучная
  проверка карточек (обязательные `unit_id`/`angle`/`quote_ref`), спасение
  полных карточек из оборванного ответа, ошибки — `GenerationException`.
- `lib/api/prompts/cards_prompt.dart`: `gen-cards-v3` (единицы с утверждением
  и якорями, `<budget cards>` со строками `<card unit_id angle>`,
  `<already_accepted>` только текущего батча, правила четырёх углов, LaTeX,
  запрет инструкций из материала); копия — `docs/prompts/gen-cards-v3.txt`
  (байтовая сверка тестом).
- `lib/api/generation/cards_batch_engine.dart`: `CardsBatchEngine` —
  последовательный проход по `AllocationPlan`, принятое в `CardSink` по ходу,
  повторы по `RetryPolicy` (429 `Retry-After`, 5xx/таймаут/сеть), 400/401/413/
  402 без повторов, обрезка — деление **по единицам** и добор остатка (для
  неделимой единицы одна повторная попытка), отмена сохраняет принятое;
  `CardsBatchRun` несёт журнал, карточки, `promptVersion`, `cancelled`.
- `lib/api/generation/batch_job_recorder.dart`: `gen-cards-v3` →
  `generation_jobs.prompt_version`; статус задания не меняется (S9).
- `lib/domain/generation/cards_batch.dart`: `CardsBatch`, `AcceptedCard`,
  `splitBatchByUnits` (деление по границе единиц, а не по половине карточек).
- `lib/domain/generation/generation_ledger.dart`: `attempts` у партии и
  прогона (повторы и добор в журнале, не в recovery-бюджете).
- `lib/domain/generation/ports.dart`: `LlmPort.generate(CardsBatch, …)`,
  `CancellationSignal`; `generated_card.dart`: `unitId`/`angle`/`quoteRef`.
- `lib/api/generation/card_json_schema.dart` + `provider_schema.dart` +
  4 адаптера: расширение `gen-cards-v3` отдельной схемой
  (`cardsResponseSchemaV3`), канон A8.4 не изменён, адаптеры получили
  необязательную `responseSchema`.
- Старый конвейер, UI и схема БД не менялись; путь не подключён (флаг
  `GenerationSettings.generationV3` — S7).
- Тесты (+44): `request_ledger_test.dart` (17), `cards_prompt_test.dart` (8),
  `provider_result_test.dart` (12), `cards_batch_port_test.dart` (6),
  `ports_test.dart` (+1).

**Срез 4 (2026-11-27) — Allocation: веса, Гамильтон, упаковка батчей.**
- `lib/domain/generation/model_profile.dart`: `ModelProfile` (`id`,
  `provider`, `contextWindow`, `maxOutputTokens`, `supportsJsonSchema`,
  `supportsVision`, `concurrency`), `batchTokenBudget` (`contextWindow × 40 %`,
  доля — `batchWindowShare`), `maxCardsPerBatch`, `fitsBatch` (выход ≤ предела
  и вход + выход ≤ бюджета); каталог `kModelProfiles` — **4 провайдера**
  (DeepSeek, OpenAI, Anthropic, Gemini; 8 моделей с id из `kProviderPresets`),
  консервативный профиль для неизвестной модели. В логике упаковки чисел нет.
- `lib/domain/generation/allocation.dart`: `unitDensity` (доля значимых слов
  утверждения, пол `kMinUnitDensity = 0.25`), `kindWeight` (множители вида),
  `unitWeight` = `salience × плотность × тип`; `allocateUnits` — метод
  наибольших остатков на `BigInt` (точная сумма, минимум 1 на отобранную
  единицу, отбор самых весомых при заказе меньше числа единиц, равные
  остатки — по порядку карты); `AllocationAngle`
  (`reverse/cloze/application`), `AllocatedCard.angle` — основная карточка
  `angle == null`, добор только углами, предпочтение по виду единицы и цикл;
  `packBatches` — батчи по единицам (`вход + оценка выхода ≤ 40 % окна`,
  выход ≤ `maxOutputTokens`, общий вход карточек одной единицы, резерв схемы
  только при `supportsJsonSchema`), батч, не влезающий в профиль, —
  `ArgumentError`; `AllocationPlan` — инвариант «Σ бюджетов == заказ»,
  `materialLimited`/`shortfall`, `waves` по `concurrency`.
- Старый планировщик (`CardAllocator`/`GenerationChunkPlanner`/
  `OutputBatchPlanner`), конвейер, UI и схема БД **не менялись**: новый этап не
  подключён к старому пути (протокол §9).
- Тесты (+43): `model_profile_test.dart` (9), `allocation_test.dart` (34), в
  том числе два DoD-property-теста (200 случайных карт; сумма == заказ, минимум
  1, детерминизм, ни один батч не превышает профиль, добор только углами).

**Срез 3 (2026-11-27) — Understanding: KnowledgeMap, промпт gen-map-v1, разбор
и кэш.**
- `lib/domain/generation/knowledge_map.dart`: `KnowledgeUnit` (`id`,
  `sectionId`, `topic`, `kind`, `statement`, `anchors`, `salience`,
  `splittable`), `KnowledgeAnchor`, `KnowledgeMap` (индекс по id **O(1)**,
  `unitsOfSection`, `splittableUnits`, дубли id — `ArgumentError`),
  `KnowledgeUnitKind` (`definition/fact/relation/formula/procedure`) и
  каноническая JSON-схема `gen-map-v1` по образцу A8.4 (strict: все поля в
  `required`, nullable `section_id`, `additionalProperties: false`).
- `lib/api/prompts/understanding_prompt.dart`: отдельная версия `gen-map-v1` —
  только извлечение атомарных единиц, без правил оформления карточек;
  `buildUnderstandingUserContent` (`<section>` + `<block id>`); копия —
  `docs/prompts/gen-map-v1.txt` (тест сверяет байты).
- `lib/api/generation/knowledge_map_caller.dart`: контракт вызова модели
  (`KnowledgeMapRequest`, `KnowledgeMapRawResponse` с `usage`/`truncated`).
- `lib/api/generation/knowledge_map_parser.dart`: id единицы присваивает
  приложение (`ku:<fragmentId>#<индекс ответа>`), `section_id` — подсказка,
  поштучная проверка единиц (схема, `salience` 0..1, якоря из запроса),
  причины `json_parse` / `schema_invalid`.
- `lib/api/generation/understanding_service.dart`: фрагмент = раздел
  `ContentModel`; невалидный/обрезанный ответ или сбой провайдера **помечают
  фрагмент**, остальные обрабатываются; отмена пробрасывается; кэш только
  полной карты; `usage` — только факт из ответов (неизвестное слагаемое делает
  сумму `null`, а не нулём).
- `lib/data/generation/in_memory_knowledge_map_cache.dart`: in-memory
  реализация порта `KnowledgeMapCache<KnowledgeMap>` (БД — срез 7).
- Тесты (+42): `knowledge_map_test.dart` (8), `knowledge_map_parser_test.dart`
  (13 + golden-фикстура), `understanding_prompt_test.dart` (4),
  `understanding_service_test.dart` (11),
  `in_memory_knowledge_map_cache_test.dart` (5).

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

**Срез 17B.** Гейты: `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib
test tool` → **No issues found!**; `dart format --set-exit-if-changed lib test
tool` → **0 changed** (754 файла); `flutter test --no-pub --coverage
--exclude-tags golden` → **3302 passed + 21 skipped, exit 0**
(`green-s17b-full.txt`), покрытие рукописного кода **90,9 % (27537/30307)** при
пороге 80 % (`coverage-s17b.txt`). Красная фаза — `red-s17b.txt`
(assertion-level: `Expected: contains '<already_created>'`,
`Expected: <1> Actual: <0>`). Целевые прогоны — `green-s17b-targeted.txt`
(31) и 47 (добор + фасад). Живой замер 17B: 2/2 ячейки `ran`, 38 HTTP,
**0,142368 USD** из 0,30 (`live-s17b/run.json`), контекст дошёл до 1 из 3
карточных запросов (20 утверждений, `request_shapes`). Пересчёт —
`dart run tool/recompute_matrix_s17b.dart` → `matrix-s17b.md` (12 ячеек базы,
0 новых запросов); выборка — `dart run tool/blind_sample_s17b.dart` →
`blind-sample-17b.md` + `blind-key-17b.json` (60 карточек, `measured`);
разметка владельцем — 60 из 60, расчёт доли годных —
`dart run tool/blind_score_s17b.dart` → `blind-score-17b.md`: **v3 76,7 %,
legacy 80,0 %**, `cleanRate` 100 % / 100 % (не различает пути, завышение
23,3 / 20,0 п.п.). Защита от перезаписи размеченной выборки проверена запуском
без `--force` (`blind-sample-guard-s17b.log`, `exit 3`, файл не изменён),
маскировка cloze — на копии (`blind-sample-probe.log`, 4 пропуска `[…]`,
0 сырых `{{c1::` в вопросах). DoD-тесты: `run_context_test` 6/6,
`replenish_stage_test` (+1), `cards_prompt_test` (промпт не тронут).

**Срез 17.** Гейты: `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib
test tool` → **No issues found!**; `.fvm\versions\3.47.9\bin\dart.bat format
--set-exit-if-changed lib test tool` → **0 changed** (747 файлов);
`flutter test --no-pub --coverage --exclude-tags golden` → **3295 passed +
20 skipped, exit 0** (`green-s17-full.txt`), покрытие рукописного кода
**90,9 % (27463/30218)** при пороге 80 % (`coverage-s17.txt`, `tool/coverage_check.dart`);
guards зелёные в полном прогоне. Красная фаза — `red-s17.txt`: assertion-level
`Expected: <0.4> Actual: <0.3076923076923077>` (дубль двигал cleanRate) и
`Expected: <0.666…> Actual: <0.4>`; новые модули сначала не компилировались
(новое API). Пересчёт ячеек — `dart run tool/recompute_matrix_s17.dart` →
`matrix-s17.md` (12 ячеек, 0 новых запросов); выборка — `dart run
tool/blind_sample_s17.dart` → `blind-sample-17.md` + `blind-key-17.json`
(`not_measured`). DoD-тесты: `outcome_counts_test` 7/7 (в т. ч. «дубль не
двигает cleanRate»), `path_rule_test` 7/7, `generation_path_test` 5/5,
`blind_sample_test` 6/6, `app_settings_pipeline_flag_test` 5/5.

**Срез 16.** Гейты: `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib
test tool` → **No issues found!**; `dart format --set-exit-if-changed lib test
tool` → **0 changed** (739 файлов); `flutter test --no-pub --coverage
--exclude-tags golden` → **3276 passed + 20 skipped, exit 0**
(`green-s16-full.txt`), покрытие рукописного кода **90,9 % (27318/30059)** при
пороге 80 % (`coverage-s16.txt`); guards зелёные в полном прогоне. Живой
перемер: `flutter test test/live/generation_matrix_s16_live_test.dart` с
`CARDFLOW_LIVE_TESTS=1` → **exit 0**, **12/12 ячеек ran**, 0 not_run/failed,
40 логических / 113 HTTP запросов, 16:00, **0,347353 USD** из 1,00
(`live-s16/run.json`, `code_version ade25b33`, `code_dirty: false`). Пересчёт —
`dart run tool/recompute_matrix_s16.dart` → `live-s16/matrix-s16.md`: 6 решающих
пар, критерий **0 выполнено / 6 не выполнено** → флаг выключен. DoD-тесты:
`candidate_deduper_test` 5/5, `outcome_counts_test` 6/6,
`replenish_stage_test` (+2: дубль не закрывает слот, вторая коллизия →
duplicate), `generation_v3_facade_flow_test` (+2: 8/8 принято без пометок,
вторая коллизия → 2 запроса), `allocation_test` (+5: ёмкость по богатству),
`generation_pipeline_test` (+1: legacy `dupRate = 1/3`).

**Срез 13.** Гейты: `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib
test tool` → **No issues found!**; `dart format --set-exit-if-changed lib test`
→ **0 changed** (725 files); `flutter test --no-pub --coverage --exclude-tags
golden` → **3234 passed + 18 skipped**, `exit 0` (+20 к baseline 3214 + 18),
покрытие рукописного кода **90,9 % (27019/29740)** при пороге 80 %
(`green-s13-full.txt`, `coverage-s13.txt`); guards зелёные в полном прогоне.
Красная фаза — `red-s13.txt` (+55 / −5, assertion-level: `Expected: <13>
Actual: <12>`, `Expected: an object with length of <5> Actual: [4 DedupMark]`,
миграция 1 → 3 падала на дубле колонок). Миграции — `SchemaVerifier` 1 → 3 и
2 → 3, схема v3 (dump = onCreate), `schema_test` 27/27.
DoD-тесты: `generation_v3_facade_flow_test` («3 пары помечены своими
уровнями, ни одна не удалена», «пара уже в колоде ловится до импорта»),
`http_knowledge_map_caller_test` («12 разделов = 13 запросов»),
`cards_batch_port_test` («10 батчей = 11 запросов»),
`drift_generation_run_store_test` (+3: перезапуск, одинаковое содержимое,
неизвестный уровень), `drift_run_import_test` (+1), `matrix_comparison_test`
(9), `schema_compat_profile_test` (1). Пересчёт матрицы —
`journal/generation-v3/live-s12/matrix-s13.md` (6 решающих пар, v3 хуже на 2).

**Срез 12.** Гейты: `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib
test` → **No issues found!**; `dart format --set-exit-if-changed lib test` →
**0 changed**; `flutter test --no-pub --coverage --exclude-tags golden` →
**3214 passed + 18 skipped**, `exit 0` (+14 к baseline 3200 + 17), покрытие
рукописного кода **90,4 % (26849/29694)** при пороге 80 % (`coverage-s12.txt`,
`green-s12-full.txt`). Живая матрица — `flutter test
test/live/generation_matrix_s12_live_test.dart` с `CARDFLOW_LIVE_TESTS=1`:
**exit 0**, 20/20 ячеек `ran`, 148 HTTP, 29:34, **0,6589 USD** при потолке
2,50 (`live-s12/run.json`); таблица — `live-s12/matrix.md`; `REQUIRE_300=1`
подтвердил живой прогон на 300 карточек (v3 299/300 — `partial`). Найденные
живьём дефекты закрыты тестами: `http_knowledge_map_caller_test` 10/10,
`cards_batch_port_test` 7/7, `generation_v3_path_wiring_test` 2/2.

**Срез 11.** Красная фаза — `journal/generation-v3/red-s11.txt` (**4 прошло /
3 упало**, assertion-level, ровно DoD-тесты: `Expected: an object with length
of <1> Actual: []`, `Expected: <0> Actual: <1>`, `Expected: <2> Actual: <1>`;
гейт отключался у первого прохода и возвращён). Гейты:
`.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` → **No issues
found!**; `dart format --set-exit-if-changed lib test` → **706 files, 0
changed**; `flutter test --no-pub --coverage --exclude-tags golden` →
**3200 passed + 17 skipped**, exit 0 (+26 к baseline 3174 + 17); покрытие
рукописного кода **90.8 % (26627/29311)** при пороге 80 %; guards в полном
прогоне. Новые тесты: `card_validator_gate_test` (4),
`http_knowledge_map_caller_test` (8), `understanding_split_test` (3),
`understanding_cache_wiring_test` (2), `generation_v3_path_wiring_test` (1),
`generation_pipeline_v3_path_test` (2), `generation_preview_report_test` (3),
`generation_v3_facade_flow_test` (+3). Полный лог —
`green-s11-full.txt`, покрытие — `coverage-s11.txt`, итоги — `verify-s11.md`.

**Срез 9.** Гейты: `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib
test` → **No issues found!**; `.fvm\versions\3.47.9\bin\dart.bat format
--set-exit-if-changed lib test` → **0 changed**; `.fvm\versions\3.47.9\bin\flutter.bat
test --no-pub --coverage --exclude-tags golden` → **3155 passed + 17 skipped** (baseline 3109 + 17; +46 новых), `exit 0`.
Красная фаза — `journal/generation-v3/red-s9.txt` (**3 прошло / 17 упало**,
assertion-level: `Expected: <40> Actual: <null>`). Новые тесты:
`completion_verdict_test` (13), `generation_metrics_test` (8),
`app_settings_pipeline_flag_test` (4), `source_anchor_test` (5),
`generation_pipeline_v3_flag_test` (4), `generation_v3_progress_test` (4),
`generation_v3_preview_test` (5), `generation_paths_compare_test` (4 — те же 4
сценария на v1/v3, таблица «было → стало»). Guard `ru_strings_test` поймал
латиницу «v3» в заголовке настройки — переименовано, тест зелёный. Полные логи —
`journal/generation-v3/{red-s9.txt,scenarios-s9.txt,green-s9-full.txt,
analyze-s9.txt,format-s9.txt}`, отчёт — `journal/iteration-8/summary.md`.
**Срез 8.** Гейты: `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib
test` → **No issues found!**; `.fvm\versions\3.47.9\bin\dart.bat format
--set-exit-if-changed lib test` → **681 files, 0 changed**;
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --exclude-tags golden` →
**3109 passed + 17 skipped**, `exit 0` (baseline 3073 + 17 skipped, +36).
DoD-команды: `schema_migration_v2_test.dart` 4 passed,
`drift_generation_run_store_test.dart` 12 passed, `drift_run_import_test.dart`
5 passed, `drift_knowledge_map_cache_test.dart` 12 passed, `schema_test.dart`
27 passed, `test/migrations/migration_test.dart` 5 passed. Красная фаза:
`SchemaVerifier` — «comparing idx_card_drafts_run_hash: The actual schema does
not contain anything with this name» (индекс не создавался `createTable`) и
`Bad state: Too many elements` в тесте восстановления. Итоги —
`journal/generation-v3/verify-s8.md`. БД-тесты только in-memory drift + одна
файловая БД для `.bak`; полный прогон — 3:13.

**Срез 7.** Красная фаза — `journal/generation-v3/red-s7.txt` (**3 прошло /
27 упало**, 0 ошибок компиляции, 51 assertion-level маркер:
`Expected: <3> Actual: <0>`, `Expected: ReplenishStopReason:<…complete>
Actual: <…noUnitPlan>`). Гейты: `.\.fvm\versions\3.47.9\bin\flutter.bat analyze
--no-pub lib test` → **No issues found!**; `.\.fvm\versions\3.47.9\bin\dart.bat
format --set-exit-if-changed lib test` → **665 files, 0 changed**;
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
--exclude-tags golden` → **3073 passed + 17 skipped**, `exit 0` (baseline 3043 +
17 + 30); покрытие рукописного кода **90.9 % (25300/27847)** при пороге 80 %;
`replenish_stage.dart` — **98.8 % (241/244)**, `generation_report.dart` —
**100 % (68/68)**, `cards_batch_engine.dart` — 90.2 % (110/122),
`generation_ledger.dart` — 99.2 % (120/121). Регрессия движка после фикса
`_addUsage` — `request_ledger_test.dart` **17 passed**. DoD: 40/12 →
`partial` + `exhausted_material` (запросов нет), сбой 3-го батча → добор
(4 → 6), `max_passes` после 3 проходов, отмена → `partial` с сохранением
(2 → 3). Полный лог — `green-s7-full.txt`, покрытие — `coverage-s7.txt`,
итоги — `verify-s7.md`.

**Срез 6.** Красная фаза — `journal/generation-v3/red-s6.txt` (**6 прошло /
45 упало**, assertion-level: `Expected: <1> Actual: <0>`,
`Expected: DedupLevel:<DedupLevel.exact> Actual: <null>`,
`Expected: <3> Actual: <0>`, `Expected: throws GenerationException
Actual: <Closure…>`). Гейты: `.\.fvm\versions\3.47.9\bin\flutter.bat analyze
--no-pub lib test` → **No issues found!**; `.\.fvm\versions\3.47.9\bin\dart.bat
format --set-exit-if-changed lib test` → **660 files, 0 changed**;
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
--exclude-tags golden` → **3043 passed + 17 skipped**, `exit 0` (baseline
2992 + 17 + 51); покрытие рукописного кода **90.8 % (24989/27535)** при
пороге 80 %; `card_validator.dart` — 87.7 % (214/244), `semantic_matcher.dart` —
96.4 % (81/84), `dedup_report.dart` — 70.8 % (34/48, непокрыты
`fromWire`/`==`/`toString`), `generation_ledger.dart` — 99.2 % (120/121).
DoD: тест на каждую проверку + ложные срабатывания; фикстура — 3 пары на своих
уровнях, 2 «ловушки» без пар; отчёт по уровням в `GenerationLedger.dedup`.
Полный лог — `journal/generation-v3/green-s6-full.txt`, покрытие —
`coverage-s6.txt`, итоги — `verify-s6.md`.

**Срез 5.** Красная фаза — `journal/generation-v3/red-s5.txt` (**9 прошло /
24 упало**, assertion-level: `Expected: <10> Actual: <null>`, `Expected: true
Actual: <false>` для копии промпта, `GenerationException не брошен`).
Гейты: `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` →
**No issues found!**; `.\.fvm\versions\3.47.9\bin\dart.bat format
--set-exit-if-changed lib test` → **0 changed**;
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
--exclude-tags golden` → **2992 passed + 17 skipped**, `exit 0` (baseline
2948 + 17 + 44); покрытие рукописного кода **90.8 % (24657/27156)** при
пороге 80 %; `cards_prompt.dart` — 100 %, `batch_job_recorder.dart` — 100 %,
`cards_batch_port.dart` — 93.5 %, `cards_batch_engine.dart` — 88.5 %,
`generation_ledger.dart` — 99.2 %. DoD-команда S4
(`test/unit/api/generation/request_ledger_test.dart`) — **17 passed**. Полный
лог — `journal/generation-v3/green-s5-full.txt`, покрытие —
`coverage-s5.txt`, итоги — `verify-s5.md`.

**Срез 4.** Красная фаза — `journal/generation-v3/red-s4.txt` (**9 прошло /
33 упало**, падения assertion-level: `Expected: <40000> Actual: <0>`,
`Expected: a numeric value within <1e-9> of <0.8333…> Actual: <0.0>`,
`Expected: [5, 3, 2] Actual: []`, `Expected: <1000000> Actual: <0>`,
`Expected: AllocationAngle.<cloze> Actual: AllocationAngle.<reverse>`). Гейты:
`.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` → **No issues
found!**; `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed
lib test` → **643 files, 0 changed**; `.\.fvm\versions\3.47.9\bin\flutter.bat
test --no-pub --coverage --exclude-tags golden` → **2948 passed + 17 skipped**,
`exit 0` (baseline 2905 + 17 + 43); покрытие рукописного кода **90.9 %
(24302/26744)** при пороге 80 %; `allocation.dart` — **100.0 % (190/190)** ≥
DoD-порога 95 %, `model_profile.dart` — 100.0 % (30/30). Полный лог —
`journal/generation-v3/green-s4-full.txt`, покрытие —
`coverage-s4.txt`, итоги — `verify-s4.md`.

**Срез 3.** Красная фаза — `journal/generation-v3/red-s3.txt` (29 падений
assertion-level: `Expected: <3> Actual: <0>`, `Expected: true Actual: <false>`,
`Expected: 'gen-map-v1' Actual: 'gen-map-v0'`). Гейты:
`.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` → **No issues
found!**; `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed
lib test` → **639 files, 0 changed**;
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage --exclude-tags
golden` → **2905 passed + 17 skipped**, `exit 0` (baseline 2863 + 17 + 42);
покрытие рукописного кода **90.8 % (24082/26524)** при пороге 80 %;
`knowledge_map_parser.dart` — **100 % (61/61)**, `understanding_service.dart` —
95.0 % (95/100), `knowledge_map.dart` — 75 % (48/64, непокрыты только
`==`/`hashCode`/`toString`/`blockIds`), `knowledge_map_caller.dart` — 33.3 %
(2/6, объявления контракта; прецедент `ports.dart`). Полный лог —
`journal/generation-v3/green-s3-full.txt`, итоги — `verify-s3.md`.

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

- **Не ждать эффекта контекста «уже создано» на одной партии.** Живой замер
  S17B: на `deepseek-flash` (`maxOutputTokens = 384 000`) заказ 150 умещается в
  **один** запрос генерации, блок `<already_created>` в нём пуст по построению, а
  все 25 дублей родились внутри ответа. Контекст дошёл только до добора. Правило:
  до интерпретации `dupRate` смотреть число партий (`request_shapes` в
  `live-s17b/run.json`), а дубли внутри одной партии относить к работе промпта
  (S18), а не к контексту.
- **Не сравнивать ячейки v3 «на одном материале» без оговорки о карте.** Карта
  Understanding строится моделью заново в каждом прогоне: 33 → 41 единица,
  ёмкость плана 56 → 73, поэтому разница `dupRate` двух ячеек правке не
  атрибутируется (L238). Разброс прогонов виден и на legacy: 50 → 62 принятых
  без единой правки.
- **`flutter.bat` в песочнице не запускается — не тратить на него шаги.**
  `.fvm/versions/3.47.9` — junction на `C:\Users\piotr\fvm` (запись вне рабочей
  папки запрещена), а `bin/internal/shared.bat` крутится на замке и вызывает
  PowerShell. Рабочий путь: `dart.exe --packages=<root>/packages/flutter_tools/
  .dart_tool/package_config.json <root>/bin/cache/flutter_tools.snapshot <cmd>`
  при `FLUTTER_ROOT=<root>`, запуск с widened access (pipe-каналы). Вывод — в
  файл через `*>`; обычный `|`/`Tee-Object` в песочнице падает.
- **`dart run tool/...` в песочнице падает на build hooks** (native assets →
  `cmd.exe`): инструменты запускать widened-доступом или `Start-Process` с
  файловыми редиректами (`-RedirectStandardOutput`).


- **Не считать «слепую выборку сделанной», если карточек нет в сохранённом.**
  В S17 TASK требовал 60 карточек из `cells/*.json`, а ячейки среза 16 несут
  только метрики: текстов карточек нет. Правильный ответ — `not_measured` с
  причиной плюс инструмент и запись карточек в следующий замер
  (`S12Bench` → `cards`), а не выдуманные карточки и не «пустой, но
  заполненный» файл. Проверять наличие данных **до** планирования среза.
- **Определение метрики менять только в одном месте.** В S17 `cleanRate` жил в
  трёх местах (`OutcomeCounts`, `GenerationReport`, `MetricsCollector`) и после
  смены знаменателя давал бы разные числа в одной таблице. Правило: одно
  определение + делегирование (`report.cleanRate => outcome.cleanRate`),
  пересчёт старых ячеек — только из счётчиков, сохранённые доли не читать.
- **Не писать `expect` на `null`-намеренный геттер, не проверив пустой ввод.**
  `OutcomeCounts.cleanRate` при `unique == 0` — `null`; тест «нет попыток»
  проверяет все четыре доли, иначе «0 из 0» превращается в ноль.
- **PowerShell `-replace` с обратными кавычками и кириллицей в одном
  выражении ломается на парсере.** В S17 правка строки с `` `kPathThresholdReason `` в
  `tool/recompute_matrix_s17.dart` упала `ParserError`; такие строки править
  `edit`-инструментом, а не `-replace`.
- **Контрактный тест dedup-в-цикле писать ДО проводки и снимать red-лог.**
  В S16 тесты `CandidateDeduper`/«дубль не закрывает слот» добавлены вместе с
  реализацией: падения, которые я видел, были дефектами проводки (deduper не
  запоминал карточки до конца цикла → пары внутри одного ответа не ловились;
  повтор шёл тем же углом → слот закрывался второй коллизией), а не
  зафиксированной красной фазой. Правило: сначала тест + `red-s16.txt`, затем
  код; красная фаза должна падать в assertion-level, а не только компиляцией.
- **Проверять, что тестовый порт сохраняет поля карточки.** `_FakeLlmPort`
  в facade-тестах при `overrideCard` терял `angle`, и «повтор с другим углом»
  выглядел как незапрошенный угол: слот не потреблял попытку, добор зацикливался
  (3 запроса вместо 2). При подмене карточки в фейке копировать все поля,
  включая `angle`.
- **Колода для dedup загружается ДО первого запроса.** В тесте «пара уже в
  колоде» забыт `targetDeckId` в `run(...)` — deduper получил пустую колоду, и
  карточка-дубль принялась. Проверять, что аргумент дошёл до `CascadeDeduper`,
  а не только что loader передан в фасад.
- **Dedup в фасаде — после приёма, но до импорта; строки черновиков уже есть.**
  Инвариант S11 (пишем по ходу) не ломается, если пометка — `UPDATE`
  `card_drafts` после этапа Dedup (`is_duplicate_of`/`dedup_level`), а не поле
  в `card_json`. Импорт вызывать **после** Dedup — иначе «уже в колоде»
  ловится после записи (тест `events == ['dedup', 'import']`).
- **Одинаковое содержимое в прогоне — один `content_hash`.** `DedupMark`
  нельзя хранить парой с тем же hash: `DedupPair` требует разные id, и
  `loadRun` упал бы на assert. Для точного дубля внутри прогона
  восстанавливается пара-маркер `same:<hash>`.
- **Миграция `addColumn` — только для `from >= 2`.** При апгрейде с v1
  `m.createTable(cardDrafts)` берёт актуальное определение таблицы (уже с
  новыми колонками), и безусловный `addColumn` даёт «duplicate column name».
- **`cleanRate` теперь к `generated`, а не к `accepted`.** Тесты
  `metrics_collector_test` — 8/14, не 0.8; `generation_report_test` с
  `generated = 2` остаётся 1/2. Колонку «было» считать отдельной функцией
  (`cleanRateOfAccepted`), не подменять метрику.
- **Профиль совместимости — на прогон, а не на вызов.** `attempts`-список
  лестницы строится один раз в `extract`/`generate`: запоминание отказа внутри
  текущей лестницы не должно обрывать уже начатые ступени (тест «3 ступени»
  остаётся 3 запроса). Запросы Understanding считать `attempts` ответа, а не
  вызовом `extract` — иначе лестница исчезает из отчёта.
- **`stage == ready` при `accepted < requested` — это `complete` по слотам,
  а не потолок материала.** `_unfilledSlots` считает повторы слотов
  удовлетворёнными; 188/300 статьи = 188 слотов, 112 повторных карточек плана
  (L229). Не «чинить» пороги добора, не выдавать за `exhausted_material`.
- **Пересчёт матрицы — из `matrix.jsonl`, не новым платным прогоном.** Скрипт
  `tool/recompute_matrix_s13.dart` читает существующие 20 ячеек; в отчёте
  колонка «было» показывает разницу баз, «нерешающая» — 20/40.

- **Лестница ADR-021 нужна в КАЖДОМ HTTP-вызове модели, а не только в
  `CardGenerationService`.** В S12 живой v3 сначала дал 12 × `provider_error`
  (Understanding), затем 0/20 (Generation): `HttpKnowledgeMapCaller` и
  `AdapterCardsBatchPort` строили strict `json_schema`, DeepSeek отвечал 400.
  Лестница добавлена в оба места; unit-тесты на фейковом транспорте это ловят,
  но **обязательно проверять новый вызов живым прогоном** — оба дефекта нашлись
  только на реальном провайдере.
- **Статус v3 — из вердикта, а не из этапа.** `runResultOf` ставил
  `status: report.stage.jobStatus`, и 299/300 с этапом `ready` показывался как
  `done` — ложный успех. Теперь `status: verdict.jobStatus`; тест
  `generation_v3_path_wiring_test` («299 из 300 — partial»).
- **`cleanRate` legacy и v3 считает не одно и то же.** У legacy в `issues`
  попадает `imageQueryAdjusted` (коррекция поиска картинки), у v3 внешнего
  поиска в фасаде нет; на учебном 20 legacy дал 75 % без содержательных
  дефектов. Сравнивать «в лоб» можно только с оговоркой в отчёте (§4), а не
  делать вывод «legacy качественнее».
- **Матрицу не запускать без потолков и дедлайна.** 260 запросов / 2,50 USD /
  75 мин дали 20/20 ячеек, 0,66 USD и 29,6 мин; без дедлайна маленький бюджет
  (60 запросов) обрывал матрицу на 7/20. Исчерпание — `not_run` с причиной.
- **Не записывать `started_at` в `run.json` в `finally` как «начало».** Первый
  прогон записал туда время окончания; поле исправлено механически
  (`finished_at` + вычисленный `started_at`), тест теперь хранит старт до прогона.
- **Не читать `matrix.jsonl` через `Test-Path` в другой оболочке при
  параллельном прогоне**: файл дописывается по ячейке; для отчёта брать
  `matrix.md`/`run.json` после `exit 0`.

- **Гейт — до принятия, а не «валидация после».** Если закрывать слот карточкой,
  а блокировать её потом, `accepted` растёт и вердикт добора врёт (S10).
  В срезе 11 `CardValidatorGate` спрашивают оба этапа до `CardSink`/`satisfied`;
  пост-валидация фасада удалена — двух путей быть не должно.
- **`maxAttemptsPerSlot` — всего попыток слота, включая первый проход.** Вторая
  блокировка закрывает слот как `validation_rejects`; «третья блокировка» из
  TASK.txt недостижима, DoD «две попытки на слот» и есть это правило (Q23).
  В фасаде счётчик попыток инициализируется `CardsBatchRun.blockedCards` —
  иначе добор не знает, что слот уже тратил попытку.
- **`shortfallReasons` при `validation_rejects` считать по `remaining`, а не по
  `invalid`.** На один закрытый слот пришлось две отброшенные записи модели;
  число `invalid` (2) объяснило бы одну потерю дважды. Счётчик `report.invalid`
  остаётся числом отброшенных записей и с `shortfallReasons` не смешивается.
- **`Gateway`/путь v3 — `understanding` возвращает `UnderstandingResult`, а не
  `KnowledgeMap`.** Иначе `usage` Understanding и коды помеченных фрагментов не
  доезжают до отчёта (п. 5/10), и «скан без текста» выглядит пустым прогоном.
- **Не звать модель в prompt-only/скане без единиц.** `plan.cards.isEmpty` →
  отчёт собирается без запросов (`unfilledSlots = requested`), а не падение
  `planAllocation`.
- **`GenerationV3PathRunner` не должен строить `MediaStore` заранее.**
  `mediaStoreProvider` в тестах — `UnimplementedError`; импортёр читает его
  лениво в момент импорта. Иначе проводка ломает тесты, где runner нужен без
  импорта.
- **Не сравнивать `GenerationRunResult.report` и вердикт в UI «на глаз».** Тест
  предпросмотра намеренно даёт расходящиеся числа (вердикт 9 из 10, отчёт 6 из 8):
  UI обязан показывать отчёт — иначе источник незаметно вернётся к счётчикам.
- **`dart format` применять до полного прогона.** В этом прогоне формат шёл
  отдельной командой после кода и до теста — 15 файлов, 0 changed на проверке.

- **Флаг «переключает путь» проверять на одной проводке и в двух прогонах.**
  Сценарии среза 9 сравнивают `pipelineV3: false/true` на одном `GenerationPipeline`
  с одним и тем же фейком: иначе «было → стало» сравнивает разные тесты, а не пути.
  Моменты времени в фейках (`p50=0 мс`) в отчёт идут с оговоркой, что это не сеть.
- **Не давать фейку возвращать похожие `front` в каждом ответе.** Срез 9 сначала
  получил `marked=19 из 20` и `accept=1.00` в сценарии «материала достаточно»:
  триграммы одинаковых заготовок давали почти-дубли чаще, чем сценарий предполагал.
  Короткие непохожие факты + намеренная почти-пара — только тогда числа читаемы.
- **`Object.hash` в Dart принимает до 20 позиционных аргументов.** Добавление двух
  полей `GeneratedCard` в `hashCode` дало `Too many positional arguments` — поля
  складывать вложенным `Object.hash(...)`, а не дописывать в конец.
- **ARB-строки не содержат латиницу вне allow-list.** `ru_strings_test` поймал «(v3)»
  в заголовке настройки; технические имена (`pipelineV3`, `basic_reversed`) живут в
  коде, а не в тексте для пользователя.
- **Форматировать перед полным прогоном, а не во время.** `dart format` пишет файлы:
  запушенный вместе с `flutter test` он меняет `test/` под работающим прогоном
  (ретроспектива итерации 4). В срезе 9 формат шёл до теста в одной команде.

- **`CardsBatchEngine._addUsage` нельзя начинать с `const TokenUsage()` по
  правилу «неизвестное слагаемое обнуляет сумму»**: накопитель — «расхода ещё
  нет», а не «неизвестен». С этим правилом `CardsBatchRun.usage` всегда был
  `null` (нашёл срез 7), и отчёт «расход по этапам» показывал пусто. Сумма
  полей сохраняется, если известно хотя бы одно слагаемое.
- **Прогресс добора считать только по закрытым слотам** (`unit_id` + `angle`),
  а не по числу вернувшихся карточек: иначе повтор принятого закрывает долг и
  `accepted ≥ requested` даёт ложный `ready`. Лишние карточки —
  `ReplenishPass.surplus`, они не входят в accepted.
- **`Migrator.createTable` не создаёт объявленные `@TableIndex`.** Шаг миграции
  обязан вызывать `m.createIndex(idxCardDraftsRunHash)`; иначе `SchemaVerifier`
  падает на «The actual schema does not contain anything with this name», а
  уникальность ключа идемпотентности импорта держится только на коде.
- **`SchemaVerifier.startAt(1)` + `AppDatabase` автоматически делает onUpgrade
  до v2.** Нельзя «поставить» БД на версию 1, открыв `AppDatabase`; для данных
  «до миграции» — `testWithDataIntegrity` (createItems в `Batch`, `RawValuesInsertable`
  + `Variable<Object>(value)`: `Value<T>` — не Expression, а `Expression<D extends Object>`).
- **`generation_jobs` — не view, а живая таблица.** Совместимое с UI
  представление поддерживается записью в обе сущности (`openRun`/`saveStage`/
  `saveDeckId`); не переименовывать и не удалять её поля, даже когда
  `generation_runs` стала источником восстановления.
- **Ключ идемпотентности — `contentHashOf(front, back)`,** а не хеш JSON
  черновика: иначе повторный импорт прогона и дедуп колоды считались бы по
  разным ключам (`cards.content_hash`).
- **Не писать байты изображений в черновик.** `card_drafts.card_json` —
  структура без картинок; байты раздувают транзакцию и дублируют `MediaStore`
  (L220). После перезапуска картинка разрешается заново.
- **Не персистить `DedupReport`.** В БД только счётчики партий; пары живут в
  памяти прогона (L219). Вердикт Completion читает числа журнала.
- **`sqlite3` в 3.9: `Database.dispose()` устарел** — использовать `close()`
  (иначе `analyze` даёт `deprecated_member_use`); drift-`isNull`/`isNotNull`
  конфликтуют с matcher — прятать в импорте или не импортировать drift вовсе.
- **`maxRequests` должен включать первый проход.** Доля `ceil(requested/2)`
  при 3 батчах и 6 карточках равна числу уже сделанных запросов — добор
  запрещён ещё до старта (поймано тестом `maxPasses`). Принято
  `max(3, requested)`.
- **`assert(wallClock > Duration.zero)` в const-конструкторе не компилируется**:
  сравнение `Duration` не вычисляется при компиляции (`Constant evaluation
  error`). Положительность — обязанность вызывающего.
- **План без единиц (prompt-only): `unfilled` считать от `requested − accepted`,
  а не по `plan.cards`.** Иначе пустой план выглядит как «заказ закрыт»
  (`complete`/`ready` при нуле принятого) — поймано тестом `no_unit_plan`.
- **Не расширять `ShortfallKind` ради причин предохранителей.**
  `generation_ledger_test` закрепляет 5 wire-кодов; `max_passes`/`max_requests`/
  `token_budget`/`wall_clock` живут в `ReplenishStopReason`, а отчёт несёт их
  вместе с `ShortfallKind` — точность без ломки журнала.
- **Красную фазу перепроверять на финальном наборе тестов.** Первый прогон
  среза 7 дал 2/19 на ранних ожиданиях; после уточнения `f(requested)` и
  добавления тестов лог перезаписан (3/27, 0 ошибок компиляции) — иначе
  red-коммит не соответствует сохранённому логу.
- **`ReplenishPass.surplus` — не «принято»:** ответ может закрыть 0 слотов, но
  вернуть карточки; такие карточки не идут в `accepted` и не делают `ready`.
- **Валидатор и дедуп среза 6 не подключать к конвейеру/UI.** Это отдельные
  этапы, как Allocation/Generation: подключение — S7 (добор/долг) и S9
  (предпросмотр «показать отброшенные») за флагом `generationV3` (протокол §9).
  Валидатор не переписывает `card_content_validator.dart`: тот обслуживает
  production `gen-ru-v9` и остаётся fallback `contains` для prompt-only.
- **«Буквально совпадает» — это `substring(start, end) == quote_ref`.** Не
  сравнивать через `contains`/нормализацию и не писать offsets для
  почти-цитаты: регистр/«ё»/тире/пробелы дают `quoteNotLiteral` без offsets
  (нормализация меняет длину строки), отсутствие — `quoteOutOfRange` с
  обнулением. Цитату искать только в `contentBlocks`: подпись рисунка — мусор.
- **Шинглы — символьные, не словесные.** На словесных 3-шинглах одна вставка
  слова роняет Жаккара до ≈0,55 при пороге 0,7 — почти-дубль не ловится.
  Проверено на фикстуре; порог `similarityThreshold = 0.7`.
- **«Выше/ниже» ловить только в текстовых ссылках.** Голое «выше» даёт ложное
  срабатывание на «давление выше уровня моря». Рабочая форма —
  `(?:сказан|описан|указан|приведен|приведён|рассмотрен)\p{L}*\s+(?:выше|ниже)`;
  первый зелёный прогон поймал баг: «описан выше» (муж. род) не совпадал с
  формой «описано».
- **`Document` требует, чтобы блок был указан в `section.blockIds`.** Тестовая
  фикстура «строка = блок» падала `Invalid argument(s): Блок … принадлежит …,
  но не указан в blockIds раздела`, а не на логике валидатора.
- **`CardReasonCode.isRejecting` — единственное место, где живёт деление
  «отбросить/пометить».** Не размазывать по проверкам: rejected — только
  структурно непригодная запись (нет строк, неизвестный тип, пустой front),
  всё содержательное — warning (A8.4: не отбрасывать молча).
- **Фикстура дедупа не должна переиспользовать один и тот же текст в разных
  парах**: одинаковые карточки дадут лишние пары (exact вместо normalized),
  и «ловушка» перестанет быть ловушкой.
- **Не создавать `const GenerationLedger(...)`.** После среза 6 конструктор
  не const (`dedup` по умолчанию — `DedupReport.empty()`); `replace` обязан
  передавать `dedup: dedup`, иначе отчёт теряется на первом же `record`.

- **Канон A8.4 не расширять ради `gen-cards-v3`.** Три поля живут в отдельной
  схеме `cardsResponseSchemaV3()` (Q12): добавить их в канон и `required` —
  значит потребовать их и от старого промпта `gen-ru-v9`, который их не знает
  (strict-схема отвергнет ответ, и production-генерация сломается до
  включения нового пути). Адаптеры получили только необязательную
  `responseSchema`.
- **Обрезку делить по остатку долга, а не по всем карточкам единицы.** После
  `truncated` принятые карточки уже есть; повторный запрос целой единицы
  заказал бы их снова (дубли в бюджете). `splitBatchByUnits` получает долг
  (`_debtOf`: пара `unit_id` + `angle`), а не исходные карточки партии.
- **Контекст «уже принято» собирать на момент запроса.** Партия в очереди
  создаётся до ответа предыдущей части: её `accepted` — снимок, поэтому перед
  `port.generate` делается `slice.withAcceptedContext(context)`; без этого
  вторая часть партии видит устаревший контекст (тест поймал: 1 вместо 2).
- **`GenerationLedger.fromPlan` — про старый `GenerationPlan`.** Для
  `AllocationPlan` бюджеты партий берутся
  `GenerationLedger.fromBudgets(plan.batches.map((b) => b.cards.length))`.
- **`ProviderResult.isError` — «нет контента для разбора», а не
  `finishReason == error`.** Иначе обрезанный ответ без контента (Anthropic
  бросает `truncated` до `tool_use`) считался бы не ошибкой, а обрезанный с
  контентом — ошибкой; оба случая важны движку по-разному.
- **Не ждать `usage` от исключения адаптера.** Anthropic при `max_tokens` без
  `tool_use` бросает до разбора расхода: `ProviderResult.usage` — `null`, а не
  выдуманные числа.
- **В тестах фейка-порта, который в обработчике читает `port.calls`, — только
  `late final port; port = _FakeLlmPort(onGenerate: …)`.** Обычный
  `final port = _FakeLlmPort(onGenerate: (b) { if (port.calls…) })` — ошибка
  компиляции «local variable referenced before it is declared».
- **Не изобретать маркер отмены через фиктивный `GenerationResult`.** Цикл
  повторов держать в `run` с локальным флагом `cancelledNow`: иначе появляется
  «магический» результат-заглушка и путаница с причиной партии.
- **Фикстура обрезанного ответа обязана содержать `finish_reason: length`.**
  Иначе порт считает ответ успешным и падает `json_parse` на оборванном JSON
  (наш первый зелёный прогон это поймал).
- **Промпт `gen-cards-v3` не должен содержать подстановок Dart и сырых
  шаблонов** (`$`, `${`, `TODO`); cloze-разметка `{{c1::…}}` в тексте
  допустима и проверяется тестом копии байт в байт.
- **Негативный тест с `const`-конструктором и `assert` — ошибка компиляции, а
  не проверка.** `const KnowledgeAnchor(blockId: '', ...)` внутри `const`-списка
  вычисляется на этапе компиляции: тест не загружается («Constant evaluation
  error»), а не падает assertion-level. Негативные кейсы конструировать без
  `const` (см. `knowledge_map_test.dart`, инварианты).
- **`prefer_initializing_formals` и приватные именованные параметры.**
  Конструктор с `required KnowledgeMapCaller caller` + `_caller = caller` даёт
  info-замечание; `this._caller` в именованном параметре запрещён языком.
  Коллабораторы сервиса/парсера — публичные `final`-поля (`this.caller`,
  `this.cache`, `this.parser`), тесты и последующие этапы читают их напрямую.
- **`KnowledgeMapCache` не дублировать новым интерфейсом.** Порт уже объявлен в
  `lib/domain/generation/ports.dart` (`KnowledgeMapCache<M>`, срез 2, Q6);
  срез 3 добавляет только реализацию `InMemoryKnowledgeMapCache` и подставляет
  `KnowledgeMapCache<KnowledgeMap>`.
- **Кэш карты писать только при полном успехе.** Иначе битый/упавший фрагмент
  «запомнится» как готовая карта, и повторный прогон не позовёт модель.
  Ключ кэша включает версию промпта (`gen-map-v1`), иначе смена промпта вернёт
  карту, построенную другой инструкцией.
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
- **«Плотность» единицы — отношение, а не длина.** Доля значимых слов в
  `statement` (пол 0,25), не число символов: иначе нарушается запрет среза 4
  «никакого распределения по числу символов», а короткая формула `PV = nRT`
  проигрывала бы длинной фразе из предлогов. Служебные слова — список
  `_stopWords` в `allocation.dart`.
- **40 % окна — бюджет одного батча, и он не единственный предел.**
  `ModelProfile.fitsBatch` проверяет **и** `output ≤ maxOutputTokens`, **и**
  `input + output ≤ batchTokenBudget`; тест с `outputTokens: 10000` при
  `maxOutputTokens: 8192` — ложное ожидание, которое упало уже после
  реализации (в красной фазе оно маскировалось нулевым стабом).
- **Отрицательные кейсы конструкторов с `assert` конструировать без `const`.**
  Повтор урока среза 3 (там был `KnowledgeAnchor`): `const ModelProfile(...)` с
  нарушенным инвариантом — ошибка компиляции, а не `throwsAssertionError`.
  В срезе 4 так проверяются `ModelProfile`, `UnitBudget`, `AllocationBatch`,
  `AllocationPlan`.
- **Красную фазу не снимать через `Tee-Object | Select-Object -First N`.**
  `Select-Object -First` закрывает пайплайн и обрывает запись лога (в срезе 4
  лог обрезался на 201 строке из 358). Полный вывод — редиректом в файл
  (`flutter test ... > file 2>&1`), хвост — отдельной командой.
- **Ёмкость плана — предел, а не заказ (S14 переопределил S4).** Инвариант
  `AllocationPlan` теперь `cards.length == allocationCapacity(units)` (Σ
  min(бюджет единицы, 4)) и «нет двух одинаковых `slotKey`»; `materialLimited`
  значит «заказ больше различимой ёмкости», а не «единиц нет вовсе». План с
  `cards.length < requested` при непустых единицах **легален** — это и есть
  `materialLimited`; «мягкий» путь без ёмкости, наоборот, запрещён.
  Итог прогона — `partial` + `exhausted_material`, число — `capacity`.
- **Срез 4 не подключает `AllocationPlan` к `GenerationChunkPlanner`.** Старый
  путь планирования остаётся до этапов Generation/Replenish (BACKLOG S4/S7):
  подключение раньше создаст два расходящихся плана.

## СЛЕДУЮЩЕЕ ДЕЙСТВИЕ

Срез 17B закрыт полностью, включая часть 3: у v3 есть контекст «уже создано»
(утверждения принятых единиц + занятые `unit_id`, усечение по числу), сделан
один платный замер (2 ячейки, **0,142368 USD** из 0,30), критерий
предрегистрации **не выполнен** (`dupRate` 24,4 % → 39,1 %), слепая выборка
(60 карточек) **размечена владельцем и посчитана**: доля годных **v3 76,7 %**
(23/30), **legacy 80,0 %** (24/30), при `cleanRate` 100 % у обоих путей.
Отчёт — `journal/generation-v3/verify-s17b.md` (§4–§5), числа —
`matrix-s17b.md` и `blind-score-17b.md`, решения — ADR-055 (+ наблюдение в
ADR-054), толкования — Q30, ограничения — L238–L241, L237 снят.

Следующий прогон: `read TASK.txt` (верхний блок) → верхний блок
`journal/STATE.md` («срез 17B») → `journal/generation-v3/verify-s17b.md` §4–§5.

1. **S18 — дубли и качество в промпт `gen-cards-v3`.** Числа для промпта:
   25 дублей в ячейке 150 (`dupRate` 39,1 %, у legacy 3,2 %), 3 cloze-дефекта
   «ответ в вопросе», человеческая доля годных 76,7 % против 80,0 %. Пороги
   валидатора и определения метрик не меняются; после правки — один замер той
   же ячейки и сравнение с `textbook-v3-150-context` **и** с оплаченной
   `textbook-v3-150`.
2. **Слепая выборка S18 — на разных материалах** (снимает межпутевые «повторы»,
   L241) и с маскировкой cloze (`[…]`, уже в сборщике). Показывать
   человеческую долю годных рядом с `dupRate`/`cleanRate`: `cleanRate` = 100 %
   насыщен и выводов не подтверждает (ADR-054, наблюдение 17B).
3. **Перемер шести решающих ячеек** (TASK ч. 4 п. 10, потолок 1,00 USD) —
   только если критерий §7/§0 станет положительным; сейчас не запускать.
