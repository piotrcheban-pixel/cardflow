# Verify — срез 11: гейт в доборе, HTTP-карта знаний, проводка фасада

**Дата:** 2026-11-28 · **Ветка:** `main` · **Старт:** `HEAD` после docs среза 10
· **Срез:** `TASK.txt` «Срез 11. Гейт в доборе, HTTP-карта знаний, проводка
фасада». **Толкования:** `journal/QUESTIONS.md` Q23.

Baseline старта: `flutter test --no-pub --exclude-tags golden` —
**3174 passed + 17 skipped**; `analyze` 0; `dart format` 0 changed.

## 1. Что сделано (по пунктам TASK)

| Пункт | Что | Где | Чем подтверждено |
|---|---|---|---|
| 1 | Порт `CardGate` с одним методом `evaluate(card) → accepted\|warning\|blocked`; реализация — существующий `CardValidator` (`CardValidatorGate`), новой логики проверок нет | `lib/domain/generation/card_gate.dart`, `lib/api/generation/validation/card_validator_gate.dart` | `card_validator_gate_test` 4/4: accepted, warning, blocked (`quoteOutOfRange`), структурно отброшенная → blocked |
| 2 | Журнал увеличивает accepted **только после гейта**: движок спрашивает гейт до `CardSink` и контекста партии, блокированное пишется как `invalid`; добор закрывает слот только после гейта | `cards_batch_engine.dart`, `replenish_stage.dart` | `generation_v3_facade_flow_test`: `quoteOutOfRange` в доборе → `accepted = 0`, `unfilledSlots = 1`, `CompletionVerdict.fromReport` — `partial`; красная фаза — `red-s11.txt` |
| 3 | `ReplenishPolicy.maxAttemptsPerSlot = 2` (всего попыток, включая первый проход): вторая блокировка слота закрывает его как `ReplenishStopReason.validationRejects`, причина — в `shortfallReasons` | `replenish_stage.dart`, `generation_report.dart` | `generation_v3_facade_flow_test`: ровно 2 запроса модели, третьего нет, `shortfallReasons = {validation_rejects: 1}` |
| 4 | Первый проход и добор идут **через один гейт**: фасад создаёт `CardValidatorGate` на прогон (материал, единицы плана, единицы без якорей) и передаёт его и движку, и `ReplenishStage`; пост-валидация в фасаде удалена (один путь) | `generation_v3_facade.dart` | сквозные тесты §2; `blocked-карточка` в колоде отсутствует числом |
| 5 | HTTP-реализация порта `KnowledgeMapCaller` поверх тех же адаптеров и `RetryPolicy`: промпт `gen-map-v1`, схема карты (`canonicalKnowledgeMapSchema` → проекция протокола), `usage` в отчёт, обрыв по `max_tokens` → деление фрагмента **целыми блоками по лимиту вывода** (не пополам) | `http_knowledge_map_caller.dart`, `understanding_service.dart`, `generation_report.dart` | `http_knowledge_map_caller_test` 8/8 (в т.ч. 429 `Retry-After` = 7 с, таймаут, 401 без повторов, пустой ответ, обрыв); `understanding_split_test` 3/3 (4 блока при лимите 192 → 1 запрос + 2 части) |
| 6 | Невалидный ответ фрагмента помечает фрагмент, прогон продолжается (фолбэк среза 3 переиспользован: `json_parse`/`schema_invalid`/`truncated`/`provider_error`); отмена пробрасывается | `understanding_service.dart` | `understanding_split_test` (повторный обрыв одного блока → `truncated`, без исключения), существующие `understanding_service_test` |
| 7 | Кэш карты на БД подключён: `GenerationV3PathRunner` использует `DriftKnowledgeMapCache` + `UnderstandingService`; повторный прогон того же материала не делает запросов Understanding | `generation_v3_path.dart`, `app_providers.dart` | `understanding_cache_wiring_test` 2/2 (счётчик вызовов); `generation_v3_path_wiring_test` — второй прогон на реальной in-memory drift-БД: `mapCalls` остаётся 1, `cardCalls` растёт до 2 |
| 8 | Фасад вызывается из production-раннера при включённом `generationPipelineV3`; выключен — legacy без изменений (флаг + наличие `v3Path` — оба условия) | `generation_pipeline.dart` (`v3Path`), `app_providers.dart` (`generationV3PathProvider`) | `generation_pipeline_v3_path_test` 2/2: включён → путь v3, legacy-вызовов 0; выключен → путь v3 не вызван, legacy работает |
| 9 | `GenerationReport` доезжает до `GenerationRunResult.report`; предпросмотр берёт из него «принято N из M», причины недобора с числами, покрытие единиц и расход токенов | `generation_run.dart`, `generation_preview_screen.dart`, ARB | `generation_preview_report_test` 3/3: отчёт 6 из 8 против вердикта 9 из 10 — UI показывает 6 из 8; причины `{exhausted_material: 2}`, покрытие 1 из 2, токены 150 |
| 10 | Неудачное Understanding (скан без текстового слоя) → отчёт с кодом `no_text_layer` и строкой ARB, без падения и без пустого предпросмотра | `generation_v3_facade.dart`, `generation_report.dart`, UI | `generation_v3_facade_flow_test` (скан → `understandingFailures = [no_text_layer]`, 0 запросов); `generation_preview_report_test` (строка причины видна) |

## 2. Красная и зелёная фазы

- **Красная фаза** — `journal/generation-v3/red-s11.txt`: гейт временно
  отключён у первого прохода; **4 прошло / 3 упало**, падения
  assertion-level, ровно на DoD-тестах:
  `Expected: an object with length of <1> Actual: []`,
  `Expected: <0> Actual: <1>` (accepted вырос без гейта),
  `Expected: <2> Actual: <1>` (вторая попытка на слот без гейта не тратится).
  После возврата гейта — 7/7 зелёные.
- Полный прогон: `flutter test --no-pub --coverage --exclude-tags golden` →
  **3200 passed + 17 skipped**, exit 0 (+26 к baseline), лог —
  `journal/generation-v3/green-s11-full.txt`.
- `analyze --no-pub lib test` — **No issues found**;
  `dart format --set-exit-if-changed lib test` — **706 files, 0 changed**.
- Покрытие рукописного кода — **90.8 % (26627/29311)** при пороге 80 %;
  лог — `journal/generation-v3/coverage-s11.txt`. Новые файлы:
  `card_validator_gate.dart` и др. покрыты сквозными тестами;
  `card_gate.dart` — только объявления, в lcov не измеряется (прецедент
  `ports.dart`).
- Guards (`architecture`, `ru_strings`, `no_secrets`, `no_webview`,
  `contrast`) — в полном прогоне, зелёные.

## 3. Что из S10 не работало и чем подтверждено, что теперь работает

| Ограничение S10 | Что было | Чем подтверждено теперь |
|---|---|---|
| «Валидация в доборе» — `ReplenishStage` закрывал слот карточкой, которую фасад потом блокировал | слот формально закрыт, карточка в колоду не идёт; вердикт добора этого не видел | Гейт внутри добора: `quoteOutOfRange` → слот **остаётся открытым**, `accepted` не растёт, `unfilledSlots = 1` (`generation_v3_facade_flow_test`, красная фаза `red-s11.txt`) |
| «Понимание без HTTP» — у `KnowledgeMapCaller` не было реализации | фасад нельзя было подключить к раннеру: Understanding падал бы или требовал фейк | `HttpKnowledgeMapCaller`: 8 тестов (запрос `gen-map-v1`, схема, `usage`, 429/таймаут/401/пустой/обрыв) |
| «Кэш карты не подключён» — `DriftKnowledgeMapCache` был только в данных | повторный материал платил за Understanding | `generation_v3_path_wiring_test`: второй прогон на реальной БД — `mapCalls = 1`, `cardCalls = 2`; `understanding_cache_wiring_test` — счётчик вызовов |
| «Фасад не подключён к production-раннеру» | флаг v3 переключал только слой завершения; `GenerationV3Facade` жил в тестах | `generation_pipeline_v3_path_test`: флаг включён → вызывается путь v3 (legacy-модель не вызывается), выключен → legacy; production-проводка — `generationV3PathProvider` в `app_providers.dart` |
| «Отчёта нет в `GenerationRunResult`» — «принято N из M» из вердикта | предпросмотр не мог показать причины с числами, покрытие, расход | `GenerationRunResult.report`; `generation_preview_report_test`: отчёт 6 из 8 против вердикта 9 из 10 — UI показывает отчёт; причины/покрытие/токены — из отчёта |
| «Скан без текста — пустой предпросмотр» | причина отсутствия карты не доезжала до UI | `no_text_layer` в `report.understandingFailures` + строка ARB в предпросмотре (`generation_preview_report_test`) |

## 4. Остаточные ограничения (осознанные, не маскируются)

1. **Первый проход и добор — один гейт, но не одна валидация ответа.** Блокированная
   карточка не пишется в `CardSink`, однако `CardsBatchEngine` и `ReplenishStage`
   по-прежнему не хранят `CardValidationReport` с пометками (warning-причины
   карточки в предпросмотр не попадают): порт отдаёт вердикт без кодов причин.
   Расширение порта — отдельный срез.
2. **Путь v3 и отмена.** `CancellationSignal` проверяется между запросами;
   in-flight HTTP не прерывается (`LlmPort` среза 5 не принимает токен отмены).
3. **Путь v3 и несколько файлов.** Материалы объединяются в один `Document`
   (разделы всех файлов, границы сдвинуты); `source_file` карточек в этом пути
   не заполняется (черновик `generated_card_json` его не несёт) — известное
   ограничение до среза с источниками.
4. **Авто-режим (заказ не указан) на пути v3** — по одной карточке на единицу
   карты (минимум одна): это не legacy-«ёмкость раздела», а явная консервативная
   политика (Q23).
5. **Живые прогоны не выполнялись** (S12; `CARFLOW_LIVE_TESTS=1` — по отдельному
   разрешению владельца). Тест пути v3 — фейковый транспорт без сети.
6. **Файлы >300 строк.** `generation_pipeline.dart` (2451 — legacy,
   удаляется после default-on), `replenish_stage.dart` (1050 — исполнитель
   добора с проходами/попытками/журналом), `card_validator.dart` (810 — правила
   и порядок кодов), `generation_v3_path.dart` (340 — сборка портов и конверт
   результата; при втором потребителе можно вынести конверт).
