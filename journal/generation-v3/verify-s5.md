# Verify — срез 5 «Generation: батчи по единицам через существующие адаптеры» (2026-11-27)

**Срез:** `TASK.txt` «Срез 5. Generation: батчи по единицам через существующие
адаптеры». Контракт этапов — `docs/generation/ARCH.md`, `BACKLOG.md` (S4),
ADR-050. Толкования — `journal/QUESTIONS.md` Q12–Q14.
**Старт:** ветка `main`, `HEAD = 6fd31bb` (docs среза 4); baseline
`flutter test --no-pub --exclude-tags golden` — **2948 passed + 17 skipped**.

## Что сделано

| Файл | Назначение |
|---|---|
| `lib/api/generation/provider_result.dart` | `ProviderResult` (content, `ProviderFinishReason`, usage, refusal, rawError, detail) и `ProviderResponseNormalizer`: исход любого из четырёх адаптеров (успех / обрезка / отказ / пусто / ошибка протокола) — один тип; отмена пробрасывается, а не становится «ошибкой батча» |
| `lib/api/generation/cards_batch_port.dart` | `AdapterCardsBatchPort implements LlmPort` поверх **существующих** `buildRequest`/`parseResponse` и `GenerationTransport`: промпт `gen-cards-v3`, схема v3 в `response_schema` (проекция под протокол), поштучная проверка карточек, обязательные `unit_id`/`angle`/`quote_ref`, спасение полных карточек из оборванного JSON, ошибки — `GenerationException` (решение о повторе принимает движок) |
| `lib/api/prompts/cards_prompt.dart` | версия `gen-cards-v3`: роль, `<units>` с утверждением и якорями, `<budget cards>` со списком `<card unit_id angle>`, `<already_accepted>` (front + утверждение текущего батча), правила углов, LaTeX, запрет инструкций из материала; `buildCardsUserContent`; копия — `docs/prompts/gen-cards-v3.txt` (тест сверяет байты) |
| `lib/api/generation/cards_batch_engine.dart` | `CardsBatchEngine`: последовательный проход по `AllocationPlan` (без параллельных запросов), принятое — в `CardSink` по ходу, повторы по `RetryPolicy` (429 `Retry-After`, 5xx/таймаут/сеть), 400/401/413/402 — без повторов, обрезка — деление **по единицам** и добор остатка, отмена сохраняет принятое; `CardsBatchRun` (журнал, карточки, версия промпта, `cancelled`) |
| `lib/api/generation/batch_job_recorder.dart` | `gen-cards-v3` → `generation_jobs.prompt_version`; статус задания не меняется (S9) |
| `lib/domain/generation/cards_batch.dart` | `CardsBatch` (номер партии, единицы с якорями, карточки плана, принятое батча, `topUp`), `AcceptedCard` (front + statement), `splitBatchByUnits` — деление по **границе единиц**, а не по половине карточек |
| `lib/domain/generation/generation_ledger.dart` | `attempts` у партии и прогона: повторы и добор считаются в журнале, а не в отдельном recovery-бюджете; `record` счётчик попыток не сбрасывает |
| `lib/domain/generation/generated_card.dart` | `unitId`, `angle`, `quoteRef` — привязка к единице карты знаний (wire `unit_id`/`angle`/`quote_ref`) |
| `lib/domain/generation/ports.dart` | `LlmPort.generate(CardsBatch batch, {account, maxOutputTokens})` — партия вместо «текста фрагмента»; `CancellationSignal` (домен не знает про Dio) |
| `lib/api/generation/card_json_schema.dart` | расширение `gen-cards-v3` отдельной схемой (`cardsResponseSchemaV3`, `cardsResponseV3CardItemSchema`, `localCardV3ItemSchema`); канон A8.4 для `gen-ru-v9` **не изменён** |
| `lib/api/generation/provider_schema.dart`, адаптеры | необязательная `responseSchema`: адаптер использует готовую проекцию и не смешивает два набора правил; логика запроса/разбора не переписана |
| `test/.../request_ledger_test.dart` (17) | DoD-команда S4: 20/40/80, `truncated` → деление по единицам → добор, обрез одной единицы (одна повторная попытка), 429 → `Retry-After`, 400/401 без повторов, отмена посреди батча, версия промпта в задании, счётчики журнала |
| `test/.../cards_prompt_test.dart` (8) | версия, фрагменты правил, `<units>`/`<budget>`/`<already_accepted>`, байтовая копия промпта |
| `test/.../provider_result_test.dart` (12) | единый результат для 4 протоколов, обрезка, отказ, пусто, ошибка протокола, отмена |
| `test/.../cards_batch_port_test.dart` (6) | запрос промптом v3 со схемой v3, карточки с привязкой, поштучный отказ без `unit_id`/`quote_ref`, неизвестный угол, спасение из обрезки, ошибка без choices |
| `test/unit/domain/generation/ports_test.dart` | фейк `LlmPort` по новой сигнатуре + тест `CancellationSignal` (+1) |

Старый конвейер (`GenerationPipeline`, `CardGenerationService`), UI, схема БД и
канон A8.4 **не менялись**: новый путь не подключён к пайплайну (протокол §9,
флаг `GenerationSettings.generationV3` — S7).

## DoD из TASK.txt

1. **`LlmPort` реализуется поверх существующих адаптеров, они не переписаны,
   нормализация в единый `ProviderResult`** — `provider_result_test`:
   одинаковый `ProviderResult` (контент, `stop`, usage 10/5) для OpenAI-совместимого,
   OpenAI, Gemini и Anthropic; обрезка (`length`/`MAX_TOKENS`/`max_tokens`),
   отказ (`refusal → refusal`), пустой ответ (`emptyResponse`), ответ не по
   протоколу (`invalidResponse`), сбой транспорта (код + detail), отмена
   пробрасывается. `cards_batch_port_test`: запрос собирается **тем же**
   адаптером (`/chat/completions`, `messages`, `response_format`).
2. **`prompts/cards_prompt.dart` — `gen-cards-v3`: единицы с anchors и бюджет на
   входе, карточки с `unit_id`/`angle`/`quote_ref` на выходе** —
   `cards_prompt_test`: версия, `<units>`/`<anchor block>`/`<statement>`,
   `<budget cards="3">` со строками `<card unit_id angle>`, правила всех четырёх
   углов, `<already_accepted>` только `front` + утверждение; копия
   `docs/prompts/gen-cards-v3.txt` совпадает байт в байт.
3. **Обрезка по `max_tokens` — по единицам, а не пополам; повторы в журнале,
   а не в recovery-бюджете** — `request_ledger_test`: после `truncated` остаток
   делится по границе единиц (A-cloze отдельно от B), число запросов
   `ledger.attempts` = первый + две части; обрез одной (неделимой) единицы —
   ровно одна повторная попытка, второй обрез — `shortfall == truncated`;
   повторы 429 учитываются как отдельные попытки (`attempts == партии + 1`).
4. **Контекст «уже принято» — только `front` + `statement` текущего батча** —
   `cards_prompt_test` (формат блока, пустое принятое — блока нет) и
   `request_ledger_test` (вторая часть партии получает принятое первой, но не
   других партий; `AcceptedCard` не содержит `back`).
5. **DoD-тесты с фейковым `LlmPort`, без сети и ключей** — все 49 тестов среза
   используют `_FakeLlmPort`/`_FakeTransport`; ни один не читает ключи и не
   ходит в сеть (`GenerationTransport` подменён).
6. **20/40/80 карточек** — три теста группы «заказ 20/40/80»: принято ровно
   столько, `remaining == 0`, `isComplete`, `attempts == числу партий`, каждая
   принятая карточка имеет `unit_id` и `quote_ref`, сумма бюджетов партий ==
   `plan.cards.length`.
7. **429 → `Retry-After`; 400/401 → без повторов** — 429: пауза ровно 7 с
   (инжектированная функция вместо `Future.delayed`), после неё успех,
   `attempts = партии + 1`; `badRequest`/`invalidApiKey`: пауз нет, один запрос,
   `shortfall == providerError`.
8. **Отмена посреди батча сохраняет принятое** — партия отдала одну карточку и
   упёрлась в лимит, «Отмена» нажата во время неё: принятая карточка в
   `run.acceptedCards` и в `CardSink`, `cancelled == true`, причина
   `cancelled`, новых запросов нет.
9. **Версия промпта пишется в job** — `BatchJobRecorder` пишет
   `gen-cards-v3` в `generation_jobs.prompt_version` (фейковое хранилище:
   `saves == 1`, `promptVersion == 'gen-cards-v3'`, статус `running` не
   тронут); без рекордера версия остаётся в `CardsBatchRun.promptVersion`.

## Красная фаза

`journal/generation-v3/red-s5.txt` — тесты и скелеты типов написаны до
реализации: **9 прошло / 24 упало**, падения assertion-level
(`Expected: <10> Actual: <null>`, `Expected: [5, 3, 2]`-подобные списки углов,
`Expected: contains '<already_accepted>'`, `Expected: true Actual: false` для
`file.existsSync()` копии промпта, `GenerationException не брошен`).
Четыре правки тестов после красной фазы — ошибки самого теста, не подгонка
кода: индекс партии `[0]` вместо `[1]`; деление считается по **остатку**
долга (вторая часть — 1 карточка A, а не 2); фикстура обрезанного ответа
передаёт `finish_reason: length`; у Anthropic-ошибки нет `usage` (адаптер
бросает до разбора) — ожидание исправлено, а не реализация.

## Гейты итогового снимка

- `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` →
  **No issues found!**
- `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` →
  **0 changed**.
- `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
  --exclude-tags golden` → **2992 passed + 17 skipped**, `exit 0`
  (baseline 2948 + 44); полный лог —
  `journal/generation-v3/green-s5-full.txt`.
- `.\.fvm\versions\3.47.9\bin\dart.bat run tool\coverage_check.dart --min=80` →
  покрытие рукописного кода **90.8 % (24657/27156)**, порог 80 % пройден;
  новые файлы: `cards_prompt.dart` **100 % (27/27)**,
  `batch_job_recorder.dart` **100 % (5/5)**, `cards_batch_port.dart`
  **93.5 % (101/108)**, `cards_batch_engine.dart` **88.5 % (108/122)**,
  `generation_ledger.dart` **99.2 % (117/118)**, `provider_result.dart`
  77.8 % (21/27 — непокрыты `toString`/ветки `detail`), `cards_batch.dart`
  71.2 % (47/66 — непокрыты `==`/`toString`/`withAccepted`). Лог —
  `journal/generation-v3/coverage-s5.txt`.
- DoD-команда BACKLOG S4:
  `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub
  test\unit\api\generation\request_ledger_test.dart` → **17 passed**

## Ограничения и толкования (Q12–Q14)

- **Канон A8.4 не изменён.** Три поля (`unit_id`, `angle`, `quote_ref`) живут в
  отдельной схеме `cardsResponseSchemaV3()`: старый промпт `gen-ru-v9` в
  production не должен требовать полей, которых он не знает (strict-схема
  отвергла бы такие ответы). Это самое консервативное чтение «не менять схему
  A8.4, кроме добавления полей» (Q12).
- **`quote_ref` — дословная цитата якоря**, а не id блока: проверка диапазона
  по offsets — этап Validation (S5 архитектуры, следующий срез TASK) (Q13).
- **Движок и порт — в API-слое** (`lib/api/generation/`), домен получил только
  `CardsBatch`/`splitBatchByUnits`/`attempts`; `ProviderResult` — API
  (нормализация над адаптерами), а не доменный тип (Q14).
- Новый путь **не подключён** к `GenerationPipeline`/UI и не включён флагом;
  глобальный добор долга между партиями — S7, а не этот срез.
- Отмена **между** запросами проверяется `CancellationSignal`; оборвать уже
  отправленный HTTP-запрос порт в этом срезе не может (у `LlmPort` нет токена
  транспорта — домен не импортирует Dio). В production проводка S7 передаст
  отмену транспорту, как в старом пути (`GenerationCancellation.token`).
- Живых вызовов API с промптом `gen-cards-v3` в срезе нет (TASK: фейковый
  `LlmPort`, без сети и ключей); живые прогоны — после подключения пути.
- `ProviderResult` не восстанавливает `usage` там, где адаптер бросает
  исключение до разбора расхода (Anthropic без `tool_use`): неизвестное
  слагаемое остаётся `null`, а не нулём.
