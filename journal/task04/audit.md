# TASK 04 — аудит готовности к реальной генерации (CARDFLOW)

**Дата:** 2026-11-19. **Старт:** `git status --porcelain` → только `?? redesign/`
(каталог владельца не тронут), `HEAD = dba80ec`
(`docs(generation): record TASK 03 reliability work`), ветка `main`, последние
коммиты TASK 03 на месте (`a94357e`, `0dc70d3`, `eb32ef1`, `8581420`,
`2488d31`, `dba80ec`). **Baseline:** `fvm flutter test --no-pub
--exclude-tags golden` → **2110 passed + 8 skipped**, `analyze` 0. Прогоны —
только с `--no-pub` (L64).

Аудит выполнен по фактическому коду и официальной документации провайдеров
(страницы тарифов/моделей открывались 2026-11-19). Документация проекта
(`docs/adaptive-generation-architecture.md`, `docs/generation-pipeline.md`)
сверена с кодом: расхождений, влияющих на генерацию, не найдено — обе описывают
действующий путь TASK 03.

**Главный вывод:** приложение **готово к управляемой проверке одного провайдера**
(DeepSeek, аккаунт владельца), но **не готово** к «массовой» проверке всех
провайдеров: ключей нет (L1/L47), актуальность id моделей каталога не
подтверждена, тарифы большинства моделей неизвестны, платного тестирования в
TASK 04 не выполнялось.

## 1. Провайдеры и адаптеры (по коду)

Слой представлен четырьмя адаптерами (`lib/api/providers/`), а «провайдеры» —
это аккаунты каталога (ADR-020), которые отображаются в протокол:

| Провайдер (пресет) | Адаптер (файл) | Текст | Vision | JSON | Usage | Статус |
|---|---|---|---|---|---|---|
| DeepSeek | `openai_compatible_adapter.dart` | да | по модели; пресет каталога — `false`, у `deepseek-flash` по официальной странице — да | `response_format` со strict-схемой, лестница ADR-021 (strict → без схемы → без `max_tokens`) | `prompt_tokens`/`completion_tokens`/`total_tokens` | **реализовано; success-путь проверялся живьём в прошлых итерациях (L30, 7.11/7.12), в TASK 04 живьём не проверялось**; id моделей каталога устарели (см. §3) |
| OpenAI | `openai_adapter.dart` | да | да (`image_url` data URI) | strict `json_schema` (без лестницы) | `prompt_tokens`/`completion_tokens`/`total_tokens` | реализовано, на реальном API **не проверено** (ключа нет) |
| Anthropic | `anthropic_adapter.dart` | да | да (`image` base64; PDF — `document` + beta-заголовок) | принудительный инструмент `emit_cards` с `input_schema` (не strict JSON Schema) | `input_tokens`/`output_tokens` (total выводится) | реализовано, на реальном API **не проверено** |
| Gemini | `gemini_adapter.dart` | да | да (`inlineData`, включая `application/pdf`) | `responseMimeType: application/json` + `responseSchema` (проекция канона) | `promptTokenCount`/`candidatesTokenCount`/`totalTokenCount` | реализовано, на реальном API **не проверено** |
| OpenRouter | `openai_compatible_adapter.dart` | да | по модели аккаунта | как у OpenAI-совместимого | как у OpenAI | реализовано (общий адаптер), живьём **не проверено** |
| Moonshot (Kimi) | `openai_compatible_adapter.dart` | да | по модели аккаунта | как у OpenAI-совместимого | как у OpenAI | реализовано, живьём **не проверено** |
| MiniMax | `openai_compatible_adapter.dart` | да | по модели аккаунта | как у OpenAI-совместимого | как у OpenAI | реализовано, живьём **не проверено** |
| Groq | `openai_compatible_adapter.dart` | да | по модели аккаунта | как у OpenAI-совместимого | как у OpenAI | реализовано, живьём **не проверено** |
| Ollama (local) | `openai_compatible_adapter.dart` | да | по модели аккаунта | как у OpenAI-совместимого | как у OpenAI | реализовано, на реальном сервере **не проверено** (L32) |

**Не поддерживается / не реализовано (подтверждено кодом):**
- **streaming** — ни один адаптер не отправляет `stream: true` и не разбирает
  SSE; весь слой работает одним JSON-ответом (Google/Anthropic streaming не
  задействован).
- **PDF для OpenAI/OpenAI-совместимых** — `pdfScanUnsupported` до сети
  (`attachment_parts.dart`, `_validateAttachments`).
- **WebP во вложениях** — домен знает `webp`, но выбор файла принимает только
  JPG/PNG (`attachmentMediaTypeForFileName`).
- **Реальный `max_tokens` у OpenAI** — адаптер его **не передаёт** (осознанно,
  комментарий в `openai_adapter.dart`: поле устарело у части моделей). Верхняя
  граница вывода у OpenAI не задаётся; обрезание распознаётся по
  `finish_reason`.

### 1.1 Точки и авторизация

| Протокол | Endpoint | Авторизация | Проекция схемы |
|---|---|---|---|
| OpenAI | `POST {base}/chat/completions` (`https://api.openai.com/v1`) | `Authorization: Bearer <key>` | канон как есть |
| OpenAI-compatible | `POST {base_url}/chat/completions` (адрес аккаунта обязателен) | `Authorization: Bearer <key>`, если ключ задан | канон как есть |
| Anthropic | `POST {base}/v1/messages` | `x-api-key`, `anthropic-version: 2023-06-01` (+`anthropic-beta: pdfs-2024-09-25` для PDF) | union → `anyOf` |
| Gemini | `POST {base}/v1beta/models/{model}:generateContent` | `x-goog-api-key` (ключ **не** в URL) | union → `nullable`, типы в верхнем регистре |

Базовый адрес — из аккаунта (`ProviderAccount.base_url`); путь достраивает
`ProviderEndpoint.parse` (схема только `http/https`, userinfo/query/fragment
запрещены). Ключи не попадают в URL.

### 1.2 Ошибки HTTP (по коду `GenerationHttpClient._fromStatusCode`)

| Статус | Код | Повтор | Примечание |
|---|---|---|---|
| 401/403 | `invalidApiKey` | нет (fatal для пайплайна) | UI — переход в настройки |
| 429 | `rateLimited` | да, по `Retry-After` (если ≤ 60 с), иначе backoff | `Retry-After` переносится в сбой фрагмента |
| 5xx | `serverUnavailable` | да, экспоненциальный backoff с jitter | |
| 413 | `payloadTooLarge` | нет; пайплайн дробит фрагмент | |
| 400 + текст про контекст | `contextOverflow` | нет; пайплайн дробит фрагмент | распознаётся по `providerReason` |
| прочие 4xx (400/402/404/422) | `badRequest` | нет лестницей (только OpenAI-совместимый) | `providerReason` — очищенная причина |

**Наблюдение TASK 04 (не дефект, ограничение):** 404 «model not found»
(типичный исход устаревшего id модели) сводится к `badRequest` с причиной
провайдера. Отдельного кода `modelNotFound` нет — при живом прогоне это будет
видно как `generationErrorBadRequestReason`; в план TASK 05 заложена
предварительная проверка id модели.

## 2. Возможности модели и лимиты запроса (по коду)

- Источники: `resolveModelCapabilities` (аккаунт → пресет → unknown),
  `resolveGenerationRequestLimits` (единый лимит image-частей/байт/тела),
  `CapabilitySource` для каждого значения, `unknownFields`/`assumptionFields`.
- Неизвестная характеристика — `null`/`unknown`, не 0 и не «типовое» число.
- Допущения приложения (не факты модели): 8 image-частей, 10 МБ на
  изображение, 24 МБ на запрос, 32 МБ тела, `maxOutputTokens = 8192`,
  1024 токена/карточку, конверт 16 токенов, резерв при неизвестном окне
  6000/2048.
- `ProviderAccount.contextTokens` (16 000) **не** считается окном модели.

## 3. Модели: каталог и официальная проверка (2026-11-19)

Значения в каталоге — **preset-derived** (не provider-confirmed). Ниже — что
подтверждено официальными страницами в этой задаче, а что осталось неизвестным.

| id модели (каталог) | Провайдер | Окно (каталог) | Vision (каталог) | Официальная проверка | Тариф |
|---|---|---:|---|---|---|
| `deepseek-chat` | DeepSeek | 128 000 | нет | **в актуальной таблице моделей отсутствует** (там `deepseek-flash`, `deepseek-v4-pro`; legacy-имена — `deepseek-v4-flash*`) | **неизвестен** |
| `deepseek-reasoner` | DeepSeek | 128 000 | нет | в актуальной таблице отсутствует | **неизвестен** |
| `gpt-4o` | OpenAI | 128 000 | да | цена подтверждена (`$2.50`/`$10.00` standard) | подтверждён |
| `gpt-4o-mini` | OpenAI | 128 000 | да | цена подтверждена (`$0.15`/`$0.60` standard) | подтверждён |
| `claude-3-5-haiku-latest` | Anthropic | 200 000 | да | **в актуальной таблице тарифов отсутствует** (перечислены Fable 5.2 / Opus 5.5 / Sonnet 5.5 / Haiku 5.5 и legacy) | **неизвестен** |
| `claude-3-5-sonnet-latest` | Anthropic | 200 000 | да | там же отсутствует | **неизвестен** |
| `gemini-2.0-flash` | Gemini | 1 048 576 | да | официальная страница тарифов недоступна из окружения (редирект на `aistudio.google.com`) — **не проверено** | **неизвестен** |
| `gemini-2.5-flash` | Gemini | 1 048 576 | да | то же | **неизвестен** |
| `openai/gpt-4o-mini` | OpenRouter | 128 000 | да | цена зависит от маршрута/аккаунта OpenRouter | **неизвестен** |
| `anthropic/claude-3.5-sonnet` | OpenRouter | 200 000 | да | то же | **неизвестен** |
| `deepseek/deepseek-chat` | OpenRouter | 128 000 | нет | то же | **неизвестен** |
| `kimi-latest` | Moonshot | 128 000 | нет | официальные страницы не проверялись в TASK 04 | **неизвестен** |
| `moonshot-v1-8k` | Moonshot | 8 000 | нет | не проверялось | **неизвестен** |
| `MiniMax-Text-01` | MiniMax | 128 000 | нет | не проверялось | **неизвестен** |
| `abab6.5s-chat` | MiniMax | 32 000 | нет | не проверялось | **неизвестен** |
| `llama-3.3-70b-versatile` | Groq | 131 072 | нет | не проверялось | **неизвестен** |
| `llama-3.1-8b-instant` | Groq | 131 072 | нет | не проверялось | **неизвестен** |
| `llama3.1` / `qwen2.5` | Ollama | 131 072 / 32 768 | нет | локальный сервер, не проверялся (L32) | локальный (не тарифицируется) |

**Подтверждено официальной страницей DeepSeek** (`api-docs.deepseek.com/quick_start/pricing`,
2026-11-19): актуальные модели — `deepseek-flash` (DeepSeek-V4.1-Flash-1017) и
`deepseek-v4-pro`; контекст **1M**, максимальный вывод **384K**, JSON-вывод ✓,
tool calls ✓, Vision ✓ у `deepseek-flash` (у `deepseek-v4-pro` — нет). Тариф
`deepseek-flash`: вход $0.15 (off-peak) … $0.30 (peak) за 1M, выход $0.60 …
$1.20 за 1M, cache-hit $0.003/$0.006. Off-peak — вдвое дешевле; peak: 01–04 и
06–10 UTC в рабочие дни.

**Следствия:**
1. `deepseek-chat`/`deepseek-reasoner` в каталоге — **устаревшие id**; живой
   прогон на них может получить 404/400. Для TASK 05 план — `deepseek-flash`
   (официальный id, он же использовался владельцем в 7.12).
2. Каталог занижает окно DeepSeek (128k против 1M) и не знает про Vision у
   `deepseek-flash` (пресет `supportsVision: false`). Это консервативно для
   планирования, но неверно для стратегии изображений — в live-конфигурации
   есть явный флаг `CARDFLOW_LIVE_VISION=1`, значение не подменяется молча.
3. Каталог Anthropic, вероятно, устарел (Claude 3.5 в актуальной таблице
   тарифов нет) — живьём не проверялось, ключа нет.
4. Цены приложения не содержат (L133): тариф в стоимость не подставляется;
   `GenerationPricing` заполняется только пользователем (UI-полей пока нет).

## 4. API-ключи и безопасность (проверено по коду)

| Вопрос | Факт | Файл/механизм |
|---|---|---|
| Где вводятся | диалог провайдера, поле `obscureText`, без автоподстановки сохранённого значения | `provider_account_dialogs.dart` |
| Где хранятся | только `flutter_secure_storage`, ключ `cardflow.api_key.<id>`; в `app_settings`/БД не пишутся | `secure_api_key_store.dart`, `drift_provider_accounts_store.dart` |
| Запись | write → read-back → только потом сохранение аккаунта; при расхождении — ошибка ARB | `generation_settings_screen.dart` |
| Удаление | `keyStore.delete` + удаление аккаунта из списка | там же |
| Истёкший/неверный ключ | 401/403 → `invalidApiKey` (fatal), UI — сообщение и переход в настройки | `generation_http_client.dart`, `generation_error_message.dart` |
| Заголовки в логах | `Authorization`, `x-api-key`, `x-goog-api-key`, `proxy-authorization` редактируются; тела запросов не логируются | `log_redaction.dart`, `redacting_log_interceptor.dart` |
| Debug-диагностика | только debug (`!dart.vm.product`), sink инжектируется, текст редактируется и обрезается | `generation_diagnostics.dart` |
| Исключения | `GenerationException.details` — только тип/статус; `providerReason` — очищенная причина ≤ 200 символов; тела не попадают | `generation_http_client.dart` |
| `DioException.toString()` | проверено по исходникам dio 5.11.1: сообщение **не** содержит URI/заголовков (только тип/статус/`error`), поэтому `$error` в диагностике ключей не выносит | `pub-cache/dio-5.11.1/lib/src/dio_exception.dart` |
| Guard | `no_secrets_test` сканирует репозиторий формами `sk-…`, `sk-ant-…`, `AIza…` | `test/guards/no_secrets_test.dart` |

**Найдено и исправлено в TASK 04:**
1. **Диагностика и `providerReason` не редактировали секретные query-параметры
   и часть форматов ключей.** Единый санитайзер `redactSecretsInText`
   (`log_redaction.dart`) теперь маскирует `Authorization`/`x-api-key`/
   `x-goog-api-key`-значения, `Bearer …`, `sk-`, `AIza`, `gsk_`, `xai-`,
   `nvapi-`, а также `?key=`/`&api_key=`/`&apikey=`/`&token=`. Он используется
   и HTTP-клиентом, и диагностикой (раньше были две разные регулярки).
   *Реальной утечки не было* (Dio не печатает URI; тела запросов не
   логируются) — это защита от будущих текстов ошибок и новых провайдеров.
2. **Битый JSON провайдера классифицировался как `network`.** Dio с
   `ContentType: application/json` падал в трансформере до создания `Response`;
   `GenerationHttpClient` видел `DioException.unknown` без статуса → `network`,
   а `network` **повторяется** в пайплайне (до 4 попыток). Теперь транспорт
   запрашивает `ResponseType.plain` и разбирает тело сам
   (`_decodeJsonObject`): битый JSON → `invalidResponse` без повторов. Это
   подтверждено локальным HTTP-тестом (`test/integration/generation_recovery_http_test.dart`).

**Не менялось:** механизм авторизации, хранение ключей, read-back, формат
`generation_jobs`, схема БД.

## 5. Инфраструктура live-тестирования: было и стало

**Было:** три файла `test/live` (DeepSeek OpenAI-compatible, метрики картинок,
Wikimedia), тег `live`, skip при отсутствии ключа. Не было: явного разрешения
при наличии ключа, бюджета запросов, предварительной стоимости, учёта
фактических запросов, записи калибровки, ограничения HTTP-попыток.

**Стало (TASK 04):**
- `test/live/support/live_test_config.dart` — конфигурация по окружению:
  `CARDFLOW_LIVE_TESTS`, `_PROVIDER`, `_MODEL`, `_BASE_URL`, `_MAX_REQUESTS`,
  `_MAX_COST_USD`, `_ALLOW_UNKNOWN_COST`, `_TIMEOUT_SEC`, `_ENABLE_PROMPT_ONLY`,
  `_ENABLE_MATERIALS`, `_ENABLE_IMAGES`, `_ENABLE_RECOVERY`, `_VISION`,
  `_REPORT`. **Значения по умолчанию исключают запросы** (`enabled=false`,
  `maxRequests=0`, `maxCost=0`), отсутствие ключа — skip, не падение.
- `test/live/support/live_pricing.dart` — тарифы **только** с официальных
  страниц, с URL и датой проверки; неизвестный тариф отсутствует в таблице.
- `test/live/support/live_cost.dart` — предварительная стоимость; неизвестно →
  `null` + причина + блокировка автоматического запуска.
- `test/live/support/live_budget.dart` — бюджет логических запросов,
  транспорт-обёртка (размер тела, время, счётчик), лимитер HTTP-попыток.
- `test/live/support/live_scenarios.dart` — планы Test A–E и их стоимость.
- `test/live/support/live_fixtures.dart` — нейтральные материалы и фикстуры
  (текст, большой конспект, PNG, PDF с изображением через `PdfParser`).
- `test/live/support/live_quality.dart` — измеримые критерии качества и
  markdown-отчёт.
- `test/live/support/live_run_report.dart` — запись прогона (провайдер, модель,
  версия оценщика, оценки/факты токенов, байты тела, число изображений, время,
  статус, число запросов восстановления) — отсутствующие поля `null`.
- `test/live/support/live_harness.dart` — проводка: production-адаптеры
  (`generationAdapters`), сервис, пайплайн, бюджет, отчёт.
- `test/live/support/local_provider_server.dart` — локальный HTTP-endpoint для
  Test F (413/429/таймаут/контекст/битый JSON/обрезка) — без оплаты.
- `test/live/adaptive_generation_live_test.dart` — Test A–E (пропускаются
  по умолчанию).
- `test/unit/live/live_infrastructure_test.dart` — 28 офлайновых тестов
  инфраструктуры (умолчания, бюджет, стоимость, отчёт, качество, тарифы).
- `test/integration/generation_recovery_http_test.dart` — 10 тестов на реальном
  сокете loopback (Test F).

**Одно место правды для адаптеров:** список вынесен из `app_providers.dart` в
`lib/api/providers/generation_adapters.dart` и реэкспортируется, поэтому
live-тест использует ровно те адаптеры, что и приложение.

## 6. Остающиеся ограничения (новые — L137–L142)

- id моделей каталога не подтверждены и частично устарели (§3);
- тарифы большинства моделей неизвестны → платные прогоны этих моделей
  блокируются без ручного разрешения;
- Vision-флаг пресета DeepSeek неверен для `deepseek-flash` (обходится флагом
  live-конфигурации, UI-поля «модель принимает изображения» для пресета нет);
- негативные живые контракты (401/403/429/`Retry-After`) по-прежнему не
  проверяются на реальных ключах — ADR-014; локальный endpoint покрывает
  транспорт и разбор, но не поведение провайдера;
- ручная приёмка GUI и живой прогон остаются за владельцем (L67/L75/L78).

## 7. Что не изменялось

Архитектура генерации (план/бюджет/восстановление), схема БД и
`schemaVersion`, `format_version`, UI (кроме нулевых правок не было), каталог
`redesign/` (не читался и не изменялся), механизм авторизации.
