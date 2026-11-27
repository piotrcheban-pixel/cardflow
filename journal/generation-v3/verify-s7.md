# Срез 7 — Replenish и partial: проверка

**Дата:** 2026-11-27/28 · **Ветка:** `main` · **TASK:** «Срез 7. Replenish и
partial» · **План:** `docs/generation/ARCH.md` (этапы 7/9), `BACKLOG.md` (S7),
ADR-050 · **Толкования:** Q17 (`journal/QUESTIONS.md`).

**Факты старта.** `HEAD = edaf80d` (docs среза 6), `git status` — только прежние
неотслеживаемые каталоги аудита. Baseline: `flutter test --no-pub
--exclude-tags golden` → **3043 passed + 17 skipped**, `exit 0` (срез 6).

## Что сделано

| Файл | Роль |
|---|---|
| `lib/domain/generation/replenish_stage.dart` (новый) | `ReplenishStage`: добор только по карточкам долга (`unit_id` + `angle`) и только по единицам карты; контекст принятого своих единиц; предохранители (`ReplenishPolicy`) с точной причиной (`ReplenishStopReason`); `exhausted_material` — не ошибка и не повод добирать (`materialCapacity`); `ready` только при закрытых слотах; отмена сохраняет принятое |
| `lib/domain/generation/generation_report.dart` (новый) | `GenerationReport.fromReplenish`: `requested`, `accepted`, причины машинными кодами, покрытие единиц (`UnitCoverage`), расход токенов по этапам, версии промптов, длительность; `isComplete` требует закрытых слотов |
| `lib/api/generation/cards_batch_engine.dart` | `_addUsage` больше не обнуляет сумму расхода первым сложением (накопитель `const TokenUsage()` — «расхода ещё нет», а не «неизвестен»): `CardsBatchRun.usage` всегда был `null` |
| `test/unit/domain/generation/replenish_stage_test.dart` (новый) | 25 тестов: f(requested), бюджет, политика; добор по единицам долга; контекст принятого; перефразирование не даёт прогресса; DoD-четыре; предохранители с точной причиной; «успех только при закрытых слотах»; коды причин и учёт расхода |
| `test/unit/domain/generation/generation_report_test.dart` (новый) | 4 теста: недобор (покрытие, причины, расход по этапам, время), полный заказ, provider_error, отброшенные карточки |
| `test/unit/api/generation/replenish_stage_wiring_test.dart` (новый) | 1 интеграционный тест на production-проводке: `CardsBatchEngine` (сбой 3-го батча) → `ReplenishStage` → `GenerationReport` |

**Правила добора.** Долг — только слоты заказа без принятой пары
(`unit_id` + `angle`; `primary` = `null`), а не «сколько вернулось сейчас».
План прохода строится из карточек долга по единицам **исходного** плана: новые
единицы знания не выдумываются. Карточка модели засчитывается, только если
закрывает слот долга; повтор принятого/незаказанный угол считаются `surplus`,
не уменьшают долг и не дают прогресса — «не добирать перефразированием принятых
фактов». Партия несёт `<already_accepted>` своих единиц (front + утверждение).

**Предохранители (TASK п. 2).** `maxPasses = 3`; `maxRequests =
max(3, requested)` — один запрос на заказанную карточку, минимум три, считая
первый проход (`attempts` журнала); `tokenBudget = Σ batch.totalTokens ×
(maxPasses + 1)` — факт `usage`, при неизвестном расходе — оценка партии;
`wallClock = 10 минут` от начала операции. Перед каждым запросом: отмена →
время → токены → запросы. Исчерпание любого — `partial` с точной причиной
(`max_passes`/`max_requests`/`token_budget`/`wall_clock`).

**Исчерпание материала (TASK п. 3).** Два случая: (а) первый проход уже
объявил партию исчерпанной — слоты её единиц не запрашиваются вовсе; (б) проход
добора не закрыл ни одного слота — добор останавливается. В обоих случаях
`materialCapacity = accepted` — «материала достаточно примерно на N качественных
карточек», а не ошибка.

**Ложный успех запрещён.** `GenerationStage.ready` — только при
`unfilledSlots == 0` и `accepted ≥ requested`; иначе `partial` (или `cancelled`
без принятого). Отмена с принятым → `partial` (DoD «отмена → partial с
сохранением»).

**Не подключено.** Конвейер, UI, схема БД, старый путь `gen-ru-v9` и
`generationV3` не менялись (протокол §9): подключение — S9. Prompt-only отвечает
`no_unit_plan` без запросов: у режима нет карты знаний, а `CardsBatch` требует
единицы.

## Гейты

| Команда | Результат |
|---|---|
| `flutter test --no-pub test/…/replenish_stage_test.dart test/…/generation_report_test.dart test/…/replenish_stage_wiring_test.dart` (красная фаза) | **3 прошло / 27 упало**, 0 ошибок компиляции, 51 assertion-level маркер — `journal/generation-v3/red-s7.txt` |
| то же после реализации | **30 passed**, `exit 0` — `journal/generation-v3/green-s7.txt` |
| `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` | **No issues found!** |
| `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` | **665 files, 0 changed** |
| `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage --exclude-tags golden` | **3073 passed + 17 skipped**, `exit 0` (baseline 3043 + 17 + 30) — `green-s7-full.txt` |
| `.\.fvm\versions\3.47.9\bin\dart.bat run tool\coverage_check.dart --min=80` | покрытие рукописного кода **90.9 % (25300/27847)**, порог 80 % пройден — `coverage-s7.txt` |
| `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/api/generation/request_ledger_test.dart` (регрессия движка после фикса `_addUsage`) | **17 passed** |

**Покрытие новых/затронутых файлов:** `replenish_stage.dart` — **98.8 %**
(241/244; непокрыты `ReplenishPolicy`-аксессоры равенства и `_PassRun`-ветка
`stop`), `generation_report.dart` — **100 % (68/68)**,
`cards_batch_engine.dart` — 90.2 % (110/122), `generation_ledger.dart` — 99.2 %
(120/121).

**DoD среза (TASK.txt):**
1. 40 запрошено, материал на 12 → `partial`, `accepted = 12`, причина
   `exhausted_material`, запросов добра нет, `materialCapacity = 12` — тест
   «40 запрошено, материал на 12…»;
2. сбой на 3-м батче → добор, `accepted` растёт (4 → 6) — тест «сбой на третьем
   батче…» (и интеграционный `replenish_stage_wiring_test` — движок → этап);
3. бесконечный цикл невозможен: после 3 проходов `max_passes`, `partial`,
   запросов ровно 3 — тест «бесконечный цикл невозможен…»;
4. отмена → `partial` с сохранением (принято 2 → 3) — тест «отмена → partial…».

## Ограничения и толкования

1. **Не подключено к конвейеру/UI** (S9, протокол §9): данные готовы —
   `ReplenishOutcome`, `GenerationReport`.
2. **`maxRequests = max(3, requested)`**, а не доля заказа: предохранитель
   ограничивает разгон, а не экономит; реально добор ограничивают проходы и
   бюджет (Q17).
3. **Повторы — не задача этапа.** `RetryPolicy` живёт в `CardsBatchEngine`
   (срез 5); ошибка в партии добора останавливает этап `provider_error`,
   принятое сохраняется, «Повторить неудавшиеся» (S9) перезапускает добор.
4. **Принятое — только закрывающие слот карточки.** Лишние карточки ответа
   видны в `ReplenishPass.surplus`; иначе повтор принятого закрывал бы долг.
5. **Prompt-only — `no_unit_plan` без запросов**: добор по единицам без карты
   знаний невозможен; режим остаётся на старом пути до своего среза.
6. **Обрезка ответа** (`truncated`) в доборе не делит партию: незакрытые слоты
   уходят в следующий проход (ограничены `maxPasses`), принятое сохраняется.
7. **Отчёт не пишет версии промптов сам** — их подставляет вызывающий слой
   (`promptVersions`): у домена промптов нет.
8. **Найден и исправлен дефект среза 5:** `CardsBatchEngine._addUsage` начинал
   сумму с `const TokenUsage()` (все поля `null`) и по правилу «неизвестное
   слагаемое обнуляет сумму» всегда возвращал `null`; расход прогона не
   сохранялся, а отчёт по этапам был бы пустым. Исправлено с тестом в
   `replenish_stage_wiring_test.dart` (150 + 150 = 300).
