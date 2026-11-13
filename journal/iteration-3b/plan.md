# Итерация 3b — «Провайдеры». План (шаг 1)

**Дата:** 2026-11-13 · **Режим:** `ИТЕРАЦИИ` · **Ветка:** `main` (рабочее дерево clean, HEAD `68812ff`;
локальный `main` = `origin/main` + docs-коммит закрытия L26; baseline: `fvm flutter test --exclude-tags golden`
→ **603 теста зелёные**)
**Цель SPEC B2/A8.2, A8.4, A8.5, A8.6:** API-слой генерации без UI: 3 адаптера провайдеров (OpenAI / Gemini /
Anthropic), единая каноническая схема ответа и её проекции под возможности провайдера, строгая локальная
валидация (схема + контентные правила A8.4), retry/backoff (429 `Retry-After`, 5xx, таймауты; 400/401/403 —
без повторов), редактирование логов (ключи и материалы не попадают в логи), ключи API — только в
`flutter_secure_storage`, сообщения об ошибках — только из ARB (ru).
Спайки: `journal/iteration-3b/spikes.md` (json_schema 5.2.2 — валидирует A8.4 и ловит нарушения;
`Math.tex(...).parseError` — публичный способ проверки LaTeX без рендера/биндинга). Решения — **ADR-011**,
**ADR-012**.

Граница с итерацией 3c: чанкинг, оценка токенов, дедупликация, `generation_jobs`, экран A6.8, drag-n-drop,
прогресс/отмена/предпросмотр — **не входят** в 3b (нижние слои 3b ими используются без изменений контракта).

## Критерии приёмки итерации (SPEC)

| # | Критерий | Источник | Проверка |
|---|---|---|---|
| C1 | Каноническая схема A8.4 — единая: все свойства в `required`, nullable — union с `null`, `additionalProperties: false` на каждом объекте, enum `basic/basic_reversed/cloze` | A8.4 | unit-тест структуры схемы + тест `json_schema.validate` (валидный/невалидный ответ) |
| C2 | Проекции схемы: OpenAI — как есть (strict); Gemini — union → `nullable: true`, типы в верхнем регистре, без `additionalProperties`, `propertyOrdering`; Anthropic — union → `anyOf` с `null` | A8.2, A8.4 | unit-тесты проекций (нет union-типов у Gemini, nullable на месте, JSON-сериализуемость) |
| C3 | OpenAI-адаптер: `POST /v1/chat/completions`, `Authorization: Bearer`, `response_format: {type: json_schema, json_schema: {strict: true}}`; разбор `content`; ошибки: `finish_reason == length` → `truncated`, `message.refusal` → `refused`, пустой контент → `emptyResponse` | A8.2 | unit-тесты на эталонных ответах (полный, refusal, length, пустой, мусор) |
| C4 | Gemini-адаптер: `POST /v1beta/models/{model}:generateContent`, ключ в заголовке `x-goog-api-key` (не в URL), `generationConfig: {responseMimeType, responseSchema}`; разбор `candidates[0].content.parts[].text`; `finishReason`: `MAX_TOKENS` → `truncated`, `SAFETY`/`RECITATION`/`BLOCKLIST`/`PROHIBITED_CONTENT`/`SPII` → `refused`, пустой candidate → `emptyResponse` | A8.2, A8.6 | unit-тесты; проверка, что ключа нет в URL |
| C5 | Anthropic-адаптер: `POST /v1/messages`, `x-api-key` + `anthropic-version`, `tools` с `emit_cards` + `tool_choice`, `input_schema`; разбор `tool_use` блока; `stop_reason`: `max_tokens` → `truncated`, `refusal` → `refused`, нет `tool_use` → `invalidResponse` | A8.2 | unit-тесты (tool_use, нет tool_use, max_tokens, refusal) |
| C6 | Локальная валидация поверх схемы: `front` не пустой ≤500; `back` ≤2000; cloze — регулярка `\{\{c\d+::.+?\}\}` и хотя бы один пропуск; `tags` обрезаются до 3, пустые и `#` удаляются; LaTeX через `flutter_math_fork` — при ошибке пометка, карточка не отбрасывается; `source_excerpt` нормализуются пробелы и проверяется вхождение в исходный текст, иначе `null` | A8.4 | unit-тесты валидатора (каждое правило, карточка с пометкой остаётся) |
| C7 | Вызов модели: системный промпт скрыт в коде с версией `gen-ru-v2`; пользовательское сообщение — блоки `<materials>`, `<wishes>`, `<limit>N</limit>`; пожелания только в `<wishes>` | A8.1, A8.5 | unit-тесты `systemPrompt`/`buildGenerationUserContent` |
| C8 | Retry/backoff: 429 — пауза по `Retry-After` (секунды или HTTP-date), иначе экспоненциальный backoff с джиттером; 5xx, таймауты, сетевые ошибки — так же; максимум 4 попытки; 400/401/403 — без повторов; отмена не повторяется | A8.6 | unit-тесты политики + интеграционный тест HTTP-цикла (fake `HttpClientAdapter`: 429→200, 5xx×4, 401, таймаут, отмена) |
| C9 | Логи: перехватчик Dio не выводит `Authorization`, `x-api-key`, `x-goog-api-key`, `key` в query и тексты материалов; тела запросов/ответов в логи не пишутся | A8.6, 3.4 | unit-тесты санитайзеров + тест перехватчика: ни значение ключа, ни материал не встречаются в выводе |
| C10 | Ключи API только в `flutter_secure_storage`; нет ключей в коде/логах/БД/экспорте; Android Auto Backup уже отключён (`allowBackup=false`) | 3.4, A8.6 | unit-тест `SecureApiKeyStore` (fake backend), guard `no_secrets`; факт manifest |
| C11 | Ошибки для UI: только коды и строки ARB; 8 кодов (`missingApiKey`, `invalidApiKey`, `badRequest`, `rateLimited`, `serverUnavailable`, `timeout`, `network`, `cancelled`, `emptyResponse`, `truncated`, `refused`, `invalidResponse`); сырые `DioException`/стектрейсы не утекают; 429 — «Повтор через N секунд» | A6.8, A8.6 | unit-тесты маппинга (непустые, уникальные, без текста исключения) + ARB |
| C12 | Production-проводка: `app_providers` собирает `ApiKeyStore` → `GenerationHttpClient` (retry+redaction) → адаптеры → `CardGenerationService`; живой граф проверен интеграционным тестом с fake HTTP-адаптером и fake key store (ключ → запрос → ответ → валидация → карточки) | урок H1 (итерация 2) | `test/integration/generation_pipeline_test.dart` на production-провайдерах |
| C13 | Документация: ADR-011, ADR-012, `docs/api-schema.md`, `docs/system-prompt.md`; `docs/dependencies.md` — вердикт спайков `json_schema`/`flutter_math_fork` | §11, критерий 8 | ревью файлов |
| C14 | Качество: все тесты зелёные, `analyze` 0, `dart format` применён, покрытие рукописного кода ≥80%, guard-тесты зелёные, `build windows --release` | B6 | `fvm flutter test --coverage`, `analyze`, `format`, `build windows` |
| C15 | Независимое ревью на снимке зелёной фазы; high/medium закрыты fix-коммитами с новыми тестами | процесс, шаги 4–5 | `journal/iteration-3b/review.md`, fix-коммит |

## Задачи (TDD: red → green на каждую)

### Домен (`lib/domain/generation/`, без Flutter)
- **T1. `GenerationProvider`** (`generation_provider.dart`): enum `openai/gemini/anthropic` + `wireName`,
  `fromWire` (как `CardType`). Нужен для `generation_jobs.provider`, настроек (итерация 7).
- **T2. `GenerationErrorCode` + `GenerationException`** (`generation_error.dart`): коды C11, `retryAfter`,
  `details` (не в UI).
- **T3. `GeneratedCard` / `CardIssueCode`** (`generated_card.dart`): immutable-карточка из ответа модели +
  машинные пометки (`emptyFront`, `frontTooLong`, `backTooLong`, `clozeMissing`, `latexBroken`,
  `excerptMismatch`, `tagsAdjusted`); `cardType` — существующий `CardType`.
- **T4. `TokenUsage` + `GenerationResult`** (`generation_result.dart`): карточки, пометки, расход токенов,
  провайдер/модель/версия промпта. Без БД и UI.
- **T5. `ApiKeyStore`** (`api_key_store.dart`): интерфейс `read/write/delete(provider)` — как контракт
  домена (реализация — data).

### Схема и промпт (`lib/api/generation/`)
- **T6. Каноническая схема A8.4** (`card_json_schema.dart`) + `CardResponseSchema`
  (`card_response_schema.dart`): `json_schema`-валидация, метод `validate(Object?) -> List<String>`.
- **T7. Проекции схемы** (`provider_schema.dart`): `openAiStrictSchema()`, `geminiSchema()`,
  `anthropicToolSchema()` — рекурсивный конвертер от канонической схемы (без дублирования).
- **T8. Системный промпт** (`system_prompt.dart`): текст A8.1 дословно, `systemPromptVersion = 'gen-ru-v2'`.
- **T9. Сборка пользовательского сообщения** (`generation_prompt.dart`): `<materials>`, `<wishes>`,
  `<limit>N</limit>`; пожелания — только в `<wishes>`; лимит — целое 1..N.
- **T10. Проверка LaTeX** (`latex_checker.dart`): `Math.tex(expression).parseError == null` через
  `flutter_math_fork`; извлечение `$…$`/`$$…$$` из текста (`extractLatexFormulas`).

### Адаптеры (`lib/api/providers/`)
- **T11. Контракт** (`generation_provider_adapter.dart`): `ProviderRequest {uri, headers, body}`,
  `ProviderRawResponse {cardsJson, usage}`, `buildRequest(...)`, `parseResponse(Map)`.
- **T12. OpenAI** (`openai_adapter.dart`) — C3.
- **T13. Gemini** (`gemini_adapter.dart`) — C4.
- **T14. Anthropic** (`anthropic_adapter.dart`) — C5.
- **T15. HTTP-цикл** (`lib/api/http/generation_http_client.dart`): Dio-отправка, классификация
  `DioException`/статусов → `GenerationException`, цикл попыток по политике, отмена.
- **T16. RetryPolicy** (`lib/api/http/retry_policy.dart`): C8, инжектируемые jitter/now для
  детерминированных тестов; `parseRetryAfter` (секунды и HTTP-date).
- **T17. Редактирование логов** (`lib/api/http/log_redaction.dart`, `redacting_log_interceptor.dart`):
  C9; sink инжектируется, в проде — `debugPrint` только в debug.
- **T18. Валидатор контента** (`lib/api/generation/card_content_validator.dart`): C6 на декодированных
  карточках; ошибка разметки LaTeX — пометка, не удаление; `source_excerpt` обнуляется при невхождении.
- **T19. Сервис** (`lib/api/generation/card_generation_service.dart`): ключ из `ApiKeyStore` → промпт →
  адаптер → HTTP → разбор → схема → контент-валидация → `GenerationResult`.
- **T20. Хранилище ключей** (`lib/data/security/secure_api_key_store.dart`): `FlutterSecureStorage`
  через узкий интерфейс `SecureKeyValueStore` (fake в тестах); ключи `cardflow.api_key.<provider>`.

### UI-контракт ошибок и локализация
- **T21. `lib/ui/generation/generation_error_message.dart`** + ARB (C11); ключи `generationError*`.
- **T22. Production-проводка** (`app_providers.dart`): `apiKeyStoreProvider`, `generationHttpClientProvider`,
  `cardGenerationServiceProvider`; интеграционный тест C12.

### Ревью, проверка, память
- **T23. Ревью** независимым reviewer на снимке зелёной фазы (`journal/iteration-3b/review.md`),
  fix-итерация отдельным коммитом с новыми тестами.
- **T24. Verify:** полный `fvm flutter test --coverage`, `analyze`, `format`, покрытие, `build windows`,
  сверка C1–C14 → `journal/iteration-3b/verify.md`; `KNOWN_LIMITATIONS.md`.
- **T25. Память:** `docs/api-schema.md`, `docs/system-prompt.md`, `journal/iteration-3b/summary.md`,
  `STATE.md`, `AGENTS.md` (устойчивые факты), шаг 7.

## Вне объёма итерации 3b (осознанно)

- Экран A6.8, drag-n-drop, список файлов, прогресс, отмена по кнопке, предпросмотр — **итерация 3c**.
- Чанкинг (A8.5 шаг 5), оценка токенов до отправки, дедупликация (шаг 9), повторы с дроблением фрагмента
  (шаг 8), `generation_jobs` — **итерация 3c**; 3b отдаёт типизированный `truncated` для этого.
- «Проверить» ключ в настройках (A6.6) — итерация 7: 3b даёт `ApiKeyStore` и адаптеры, экрана нет.
- Live-вызовы провайдеров — ключей нет (L1): адаптеры проверяются эталонными JSON-ответами и fake HTTP.
- Модели по умолчанию/списки моделей для селектора — итерация 7 (сейчас `model` — параметр запроса).

## Риски

| Риск | Митигация |
|---|---|
| Точные JSON-контракты провайдеров не проверены живьём (L1) | эталонные ответы по актуальной документации + явные проверки причин остановки; live-тесты под тегом `live` и skip без ключей; ограничение в KNOWN_LIMITATIONS |
| `json_schema` 5.2.2 — Boost-лицензия, «needs-runtime-spike» | спайк выполнен: схема A8.4 валидируется, нарушения ловятся; вердикт — `approved` в `docs/dependencies.md` |
| Провайдерные схемы (Gemini nullable/`anyOf`) могут быть отвергнуты API | проекции изолированы и покрыты тестами; при живом отказе — точечная правка проекции (ADR-012 §4), ядро не меняется |
| Утечка ключа/материалов в логи | собственный перехватчик без тел; тела не логируются вовсе; тест на отсутствие значений; guard `no_secrets` |
| Ретраи дублируют запрос (модель дорогая) | ретрай только для 429/5xx/таймаутов/сети; 400/401/403 и отмена — без повторов; максимум 4 попытки |
| `flutter_math_fork` тянет Flutter в API-слой | изоляция в `latex_checker.dart` + инъекция проверки в валидатор; domain остаётся без Flutter (architecture guard) |
| Случайный jitter делает тесты флаки | `RetryPolicy` принимает jitter-функцию и `now`; в тестах — детерминированные значения |

## ADR итерации

- **ADR-011** — каноническая схема + проекции, контракт адаптеров и локальной валидации, ошибки и маппинг.
- **ADR-012** — retry/backoff/timeouts/отмена, редактирование логов, хранение ключей.

## Порядок работы

1. Спайки (`journal/iteration-3b/spikes.md`) + план + ADR-011/012 + `docs/api-schema.md` +
   `docs/system-prompt.md` + `docs/dependencies.md` → коммит `docs:`.
2. Красная фаза: тесты T1–T22 (+ интеграционный), скелеты типов с `UnimplementedError`, прогон;
   фрагменты «ожидалось/получено» в `journal/iteration-3b/red-api.md` → коммит `test:`.
3. Зелёная фаза по слоям: домен (T1–T5) → схема/промпт (T6–T10) → адаптеры (T11–T14) → http (T15–T17) →
   валидатор/сервис/хранилище (T18–T20) → UI-маппинг/ARB (T21) → проводка (T22); после каждого слоя
   тесты + `analyze`/`format` → коммиты `feat:`/`fix:`.
4. Ревью T23 (независимый reviewer, снимок после зелёного коммита); fix-итерация отдельным коммитом.
5. Verify T24; docs/STATE/AGENTS/summary T25; ретроспектива.
