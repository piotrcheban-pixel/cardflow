# TASK 05 — предварительный аудит (CARDFLOW)

**Дата:** 2026-11-19, 11:37–12:10 MSK. **Старт:** `git status --porcelain` →
только `?? redesign/` (каталог владельца не читался и не изменялся),
`HEAD = 6bdf3e4` (`docs(journal): list TASK 04 final commits`), ветка `main`.
**Baseline:** `fvm flutter test --no-pub --exclude-tags golden` →
**2157 passed + 16 skipped**, `analyze` 0. Прогоны — только с `--no-pub` (L64).

Платных API-запросов в TASK 05 **не выполнялось**. Всё ниже проверено по коду,
официальной документации провайдера и офлайновым тестам. Ключ DeepSeek
присутствует в Windows User scope (значение не выводилось, длина не
сохранялась в артефактах); в env процесса агента его нет — L30.

## 1. Главный вывод

Инфраструктура TASK 04 была **не готова** к сценариям A–C в том виде, в каком
они сформулированы в TASK 05:

1. каталог DeepSeek не содержал актуальных id (`deepseek-flash`,
   `deepseek-v4-pro`), а моделью по умолчанию был legacy `deepseek-chat`;
   из-за этого unknown-модель в планировщике давала **1 карточку на запрос**
   вместо 7, и Test B на 40 карточек потребовал бы 40 логических запросов;
2. `CARDFLOW_LIVE_MAX_REQUESTS` фактически считал HTTP-обмены (`postJson`), а
   не логические запросы; отчёт смешивал logical/HTTP/attempts/retries;
3. бюджет был **на каждый тест**, а не на прогон A–C: три теста могли
   израсходовать 3× лимита;
4. не было предварительной оценки стоимости **каждого** запроса: только
   сценарная проверка до запуска; retries и recovery не были связаны с
   лимитом стоимости;
5. отчёт не содержал цен, estimated/actual cost, ретраев, latency и
   per-request детализации; `note` не редактировался;
6. сценарии Test A/B не соответствовали TASK 05 (3/20 карточек вместо 5/40),
   а continuity и importability не проверялись;
7. не было структуры ручной оценки карточек (8 критериев) и полей для TEST C
   (покрытие документа, важные факты, связи с разделами).

Все семь пунктов исправлены минимальными изменениями; production-адаптеры,
`CardGenerationService` и `GenerationPipeline` не подменялись.

## 2. DeepSeek: model ID, endpoint, формат, лимиты, Vision, цены

### 2.1 Что фактически было

| Вопрос | Факт до изменений |
|---|---|
| id в предыдущих успешных live-тестах | `deepseek-chat` (L30, 7.11/7.12 — отчёты и коммиты); в 7.12 владелец отдельно прогонял `deepseek-flash` |
| id в preset по умолчанию | `deepseek-chat`, второй — `deepseek-reasoner`, окно 128 000, Vision `false` |
| id в production adapter | `ProviderAccount.modelId`; для нового аккаунта — preset default, то есть `deepseek-chat` |
| endpoint | `ProviderAccount.baseUrl` = `https://api.deepseek.com`, адаптер `OpenAiCompatibleAdapter` строит `POST /chat/completions` |
| формат | OpenAI Chat Completions: `messages`, `model`, `max_tokens`, `response_format`; strict `json_schema` не поддерживается — лестница ADR-021 (strict → без схемы → без `max_tokens`) |
| harness vs production | тот же `generationAdapters`, тот же `CardGenerationService`/`GenerationPipeline`; до правки harness без override тоже брал `deepseek-chat` |

### 2.2 Что подтверждено официальной документацией (2026-11-19)

Источники: <https://api-docs.deepseek.com/quick_start/pricing> и
<https://api-docs.deepseek.com/api/create-chat-completion> (открыты 2026-11-19,
не являются платным запросом).

- актуальные id: **`deepseek-flash`** (DeepSeek-V4.1-Flash-1017) и
  **`deepseek-v4-pro`**; поля `model` принимают только эти значения;
- legacy-имена `deepseek-v4-flash`, `deepseek-v4-flash-vision-exp` ещё
  принимаются и обслуживаются Flash-моделью; `deepseek-chat` /
  `deepseek-reasoner` в актуальной таблице **отсутствуют** — их доступность
  как legacy-алиасов **UNKNOWN** (не подтверждена и не опровергнута);
- BASE URL (OpenAI Format): `https://api.deepseek.com`; endpoint
  `POST /chat/completions` — совпадает с конфигурацией приложения;
- контекст **1M**, максимальный вывод **384K**; `max_tokens` — от 1 до 393216,
  по умолчанию 8K в non-thinking и 64K в thinking mode;
- JSON Output `{"type":"json_object"}` — да; strict `json_schema` в
  документации Chat Completions не заявлен (приложение и раньше получало 400
  на strict и переходило на tolerant);
- Vision: `deepseek-flash` — **да**, `deepseek-v4-pro` — **нет**;
- цены за 1M токенов, peak: flash input $0.30 / output $1.20, v4-pro
  $1.32 / $3.96; off-peak вдвое ниже (flash $0.15/$0.60); cache-hit
  $0.006 / $0.044 (peak). Peak — 01:00–04:00 и 06:00–10:00 UTC в рабочие дни.
  На момент аудита (08:37 UTC, четверг) действует **peak**; смета ниже —
  верхняя.

### 2.3 Расхождения и минимальное исправление

| # | Расхождение | Исправление |
|---|---|---|
| D1 | В каталоге не было `deepseek-flash`/`deepseek-v4-pro`; unknown-модель давала output cap 2048 → 1 карточка/запрос, Test B = 40 запросов | В `provider_preset.dart` добавлены `deepseek-flash` (1M, Vision) и `deepseek-v4-pro` (1M, без Vision); **default = `deepseek-flash`**; legacy-имена сохранены в конце списка для уже сохранённых аккаунтов |
| D2 | `deepseek-chat` — модель по умолчанию, хотя в актуальной документации её нет | default переведён на `deepseek-flash`; legacy-модели не выбираются по умолчанию, но остаются для старых аккаунтов (удаление — отдельное продуктовое решение) |
| D3 | Пресет DeepSeek `supportsVision: false` не соответствовал flash | у `deepseek-flash` `supportsVision: true`; `CARDFLOW_LIVE_VISION` больше не нужен для flash |
| D4 | Планировщик не использует `ProviderAccount.contextTokens`; без записи в каталоге окно неизвестно | запись в каталоге теперь даёт 1M и output cap 8192 → 7 карточек/запрос, Test B = 6 запросов |

**Важно:** доступность legacy `deepseek-chat`/`deepseek-reasoner` на живом
endpoint остаётся **UNKNOWN**: это не проверялось платным запросом. TASK 05
использует только `deepseek-flash`.

### 2.4 Неизвестные характеристики (не маскируются)

- фактическая поддержка legacy `deepseek-chat`/`deepseek-reasoner` — UNKNOWN;
- как именно `max_tokens` учитывает reasoning-токены thinking mode (по
  умолчанию включён) — UNKNOWN; возможна обрезка/рост стоимости;
- тарификация отклонённого strict-запроса (400) — UNKNOWN; в смете заложен
  риск, cost guard освобождает резерв такого 400;
- тарификация повторов 429/5xx/таймаута — UNKNOWN; типично не тарифицируется,
  но официально не подтверждено;
- точный токенизатор — эвристика 2,5 симв./токен (L122); факт — только `usage`.

## 3. Аудит live-инфраструктуры (что было не так)

| # | Дефект | Последствие | Исправление |
|---|---|---|---|
| L1 | `LiveProbeTransport.budget` считал каждый `postJson`, включая strict→tolerant; в отчёте это называлось `requests` | лимит «логических запросов» на деле был лимитом HTTP-обменов; 8 логических запросов DeepSeek = 16 обменов, лимит 15 обрезал бы Test C | введён `LiveRecordingCaller` (считает `GenerationCaller.generate`), `LiveRequestBudget` разделён на logical и HTTP; отчёт содержит `logicalRequests`/`httpRequests`/`httpAttempts`/`retries` |
| L2 | Бюджеты создавались в каждом тесте | A+B+C могли потратить 3× `maxRequests`/`maxCost` | общие `logicalBudget`, `httpBudget`, `attemptLimiter`, `costGuard` на файл; harness принимает их извне |
| L3 | Не было оценки стоимости каждого запроса | лимит `maxCost` проверялся только по сценарию до запуска | `LiveCostGuard` в `LiveAttemptLimiter`: резерв до отправки каждой физической попытки, факт из `usage` после ответа, освобождение на 400/401/403/отмене |
| L4 | Отчёт не содержал цен/стоимости/ретраев/latency/per-request деталей | нельзя проверить фактический расход и калибровку по каждому фрагменту | `LiveRunRecord` расширен: цены, `estimatedCostUsd`, `actualCostUsd`, `guard*`, `wallClockMs`, `requestCosts[]` |
| L5 | `note` писался как есть | потенциальная утечка ключа в свободном тексте | `redactSecretsInText(note)` перед записью |
| L6 | Сценарии A/B были 3/20 карточек, continuity не проверялась | не соответствовало TASK 05 | A = 5, B = 40 (6 запросов), проверка `LiveCallRecord.hasContinuation` со второго запроса |
| L7 | Не проверялась importability карточек | preview/import мог отбросить карточку после успешного HTTP | проверка `CardDraft.validate()` для каждой карточки; фактическая запись в drift — офлайновый интеграционный тест |
| L8 | Не было ручной рубрики | качество сводилось к JSON-валиду | 8 критериев 0/1/2, `LiveScenarioAssessment`, markdown для `results/` |
| L9 | Test D делил флаг `_ENABLE_MATERIALS` с Test C, поэтому команда A–C запускала бы D | выход за объём TASK 05 и лишние расходы | добавлен `CARDFLOW_LIVE_SCENARIOS` — явный список id; A–C не задевают D/E |

## 4. Безопасность и данные

- ключ читается только из окружения (`LiveTestConfig.apiKey`), наружу —
  `present/absent`; значение не печаталось;
- тела запросов не логируются; `GenerationDiagnostics` — debug-only,
  редактирует секреты; `RedactingLogInterceptor` — только debug;
- `LiveRunRecord` содержит только числа, id провайдера/модели и машинные коды;
- `note` редактируется `redactSecretsInText` (заголовки, `Bearer`, `sk-`,
  `AIza`, `gsk_`, `xai-`, `nvapi-`, query `key`/`api_key`/`token`);
- тестовые материалы — нейтральные учебные тексты, без персональных данных;
- `DEEPSEEK_API_KEY` присутствует в User scope; в env процесса — отсутствует.
  Для запуска ключ надо прочитать из реестра и передать **дочернему**
  процессу, не печатая (L30).

## 5. Ограничения области

- `redesign/` не читался, не изменялся, не коммитился;
- push/deploy не выполнялись;
- схема БД, `schemaVersion`, `format_version`, API-ключи не менялись;
- production-адаптеры, `CardGenerationService`, `GenerationPipeline`,
  `GenerationPlanBuilder` не переписывались;
- единственное production-изменение — данные каталога провайдеров DeepSeek
  (актуальные id/окно/Vision/default), обоснованное официальной страницей
  2026-11-19.

## 6. Проверки, выполненные в аудите

- `git status`, `HEAD`, baseline-прогон;
- чтение production-кода: `provider_preset.dart`, `provider_account.dart`,
  `model_capabilities.dart`, `generation_budget.dart`, `prompt_only_planner.dart`,
  `generation_pipeline.dart`, `card_generation_service.dart`,
  `generation_http_client.dart`, `retry_policy.dart`, `live_*`;
- официальные страницы DeepSeek (pricing, chat completions);
- проверка ключа: present/absent;
- офлайновые прогоны: targeted, Test F, live-skip, analyze, format (см.
  `readiness-report.md`).
