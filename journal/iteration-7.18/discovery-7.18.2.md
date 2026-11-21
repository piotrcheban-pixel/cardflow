# Итерация 7.18.2 — discovery провайдеров: итоговая таблица (§3.3)

**Дата проверки:** 2026-11-21 (сверка документации — ADR-039 §6a, повторная
2026-11-21). **Живых API-запросов не было** — разбор проверен mock-HTTP и
фикстурами; недоступная документация оставляет поле `unknown`.

## Таблица

| Провайдер | Discovery | Реально извлекается | Остаётся unknown | Подтверждённое значение: откуда | sourceRef | Дата | Фикстуры и тесты | Ручная настройка |
|---|---|---|---|---|---|---|---|---|
| **DeepSeek** | `GET {base}/models`, политика `documented` (пресет `deepseek`) | `id` (список моделей), `context_window` → окно (total input+output), `max_output_tokens` → лимит вывода, `input_modalities` → `supportsImageInput` | отдельный `max_input_tokens`, цены, tokenizer, rate limits | поля модели из ответа API (`providerApi`), семантика — `totalInputPlusOutput` по политике пресета | `https://api.deepseek.com/models` (без query) | 2026-11-21 | фикстуры `openai_compatible/models_with_fields.json`, inline в `model_discovery_test.dart` §7.18.1; тесты: «documented: поля провайдера принимаются», «DeepSeek: input_modalities» | контекст/выход/images — «Характеристики модели» → «Изменить»; `max_input_tokens` только вручную |
| **Anthropic** | `GET {base}/v1/models` + пагинация `after_id`/`has_more`/`last_id` | `id`, `max_input_tokens` → **и** окно, и отдельный лимит входа, `max_tokens` → вывод, `capabilities.image_input` → Vision, `capabilities.pdf_input` → PDF | единый `context_length`, цены, tokenizer, rate limits | поля ответа (`providerApi`), семантика `inputOnly` (документация: окно = вход) | `https://api.anthropic.com/v1/models` | 2026-11-21 | `anthropic/page1.json`, `page2.json`; тесты «две страницы after_id», «capabilities.image_input» | контекст/вход/выход/images; PDF — через аккаунт |
| **Gemini** | `GET {base}/v1beta/models` + `pageToken`/`nextPageToken`, фильтр по `supportedGenerationMethods` | `name` → id (без `models/`), `inputTokenLimit` → окно и лимит входа, `outputTokenLimit` → вывод | цены, capabilities-флаги, tokenizer | поля ответа (`providerApi`), семантика `inputOnly` | `https://generativelanguage.googleapis.com/v1beta/models` | 2026-11-21 | `gemini/page1.json`, `page2.json`; тест «pageToken, name без models/, только generateContent» | контекст/вход/выход; responseSchema в `countTokens` — L160 |
| **OpenRouter** | `GET {base}/api/v1/models`, политика `documented`, `pricingIsPerToken` | `context_length` и `top_provider.context_length` → **min**, `max_completion_tokens`/`top_provider.max_completion_tokens` → вывод, `architecture.input_modalities` → Vision, `pricing.prompt/completion` → USD за 1M | гарантированный output, стабильность upstream-метаданных | поля ответа (`providerApi`), семантика `totalInputPlusOutput` | `https://openrouter.ai/api/v1/models` | 2026-11-21 | `openrouter/models_success.json`; тест «min(context) и цены за токен → за 1M» | цены/лимиты вручную, если ответ не отдал |
| **OpenAI** | `GET {base}/models`, политика `idsOnly` | только `id` (список моделей) | **все** лимиты, цены, capabilities | — (лимитов в ответе нет) | `https://api.openai.com/v1/models` | 2026-11-21 | `openai_compatible/models_success.json`, `models_empty.json`; тесты «idsOnly: лимиты не выдумываются», «пустой список» | контекст/вход/выход/images — целиком вручную |
| **Groq** | `GET {base}/models`, политика `documented`, семантика `unknown` | `id`, `context_window` (**семантика не документирована** → читается как total с предупреждением? нет: остаётся `providerApi` + `unknown` семантика), `max_completion_tokens` (если присутствует) | `max_input_tokens`, цены, capabilities, tokenizer | поле ответа (`providerApi`) | `https://api.groq.com/openai/v1/models` | 2026-11-21 | inline-тест `documented`; `model_discovery_errors_test.dart` (401/таймаут/типы) | семантику окна и лимит входа задать вручную |
| **Moonshot** | `GET {base}/v1/models`, политика `documented`, семантика `unknown` | `id`, `context_length`, `supports_image_in` → Vision, `supports_reasoning` → `isReasoningModel` | семантика `context_length`, `max_output_tokens`, цены | поле ответа (`providerApi`) | `https://api.moonshot.ai/v1/models` | 2026-11-21 | inline-тест «Moonshot: supports_image_in и supports_reasoning» | семантику окна — вручную (иначе консервативный план + `contextUnconfirmed`) |
| **MiniMax** | `GET {base}/v1/models`, политика `idsOnly` (ответ — OpenAI-минимум) | только `id` | лимиты, цены, capabilities | — | `https://api.minimax.io/v1/models` | 2026-11-21 | `models_success.json` (idsOnly), `model_discovery_errors_test.dart` | контекст/выход/images — вручную |
| **Ollama** | `GET /api/tags` + `POST /api/show` (нативно) | `models[].model`/`name` → список, `model_info.<arch>.context_length` → окно, `capabilities` → Vision | **семантика окна** (`num_ctx` может быть меньше), `max_output_tokens`, цены | поля `/api/show` (`providerApi`), семантика `unknown` | `http://host/api/show` (без query) | 2026-11-21 | `ollama/tags.json`, `show.json`; тесты «context_length и vision», «модели нет локально», «семантика окна неизвестна» | `num_ctx` — вручную (иначе предупреждение `ollama_num_ctx_assumption`) |
| **Произвольный OpenAI-совместимый** | `GET {base}/models`, политика `idsOnly` | только `id` | все лимиты | — (вендорские поля не документированы и не читаются) | `{base}/models` | 2026-11-21 | `models_wrong_types.json`, `models_empty.json`; тесты «поля неверного типа», «пустой список», «data не список» | контекст/вход/выход/images — вручную |

**Ключевое правило:** если поле не документировано/отсутствует или имеет
неверный тип — значение `unknown` (`Sourced.absent()`), а не 0 и не «типовое
число». Определение по имени модели запрещено: `foo-128k` остаётся `unknown`
(тест «имя модели не даёт лимита»).

## Обработка ошибок (проверено тестами)

`test/unit/api/models/model_discovery_errors_test.dart` — **14 тестов**, все
зелёные до правк 7.18.2 (дефекта не было):

| Случай | Anthropic | Gemini | Ollama | OpenAI-совместимый |
|---|---|---|---|---|
| 401/403 | `unauthorized` + `keepsPrevious` | `unauthorized` | `unauthorized` | `unauthorized` + `keepsPrevious` |
| Таймаут | `timeout` | `timeout` | `timeout` | `timeout` |
| Пустой список | `success` + `model_not_in_list` | `success` + `model_not_in_list`, модели пусты | `success`, без `show` | `success` + `model_not_in_list` |
| Неверный тип поля | `max_input_tokens: "200000"`, `capabilities: "..."` → unknown | `inputTokenLimit: true` → unknown | `model_info.context_length: "8192"` → unknown | `models_wrong_types.json` |
| Отсутствующее поле | unknown | unknown | unknown | unknown |
| Тело не объект/`data` не список | — | — | — | `error` + `no_data` |

Кэш: ошибка не стирает последнее удачное значение (`keepsPrevious`), TTL 7 дней,
инвалидация по смене `baseUrl`/`modelId`/ключа — `model_capability_service_test.dart`
(7.18, без изменений).

## Что требует ручной настройки (вывод)

- OpenAI, MiniMax, произвольные совместимые: **все** лимиты (ответ API их не
  отдаёт); для качественного плана нужен контекст в «Характеристики модели».
- Moonshot/Groq/Ollama: семантика окна не документирована → план
  консервативен (`contextUnconfirmed`), окно лучше указать вручную.
- Цены не приходят почти нигде (кроме OpenRouter) — стоимость в «Подробнее»
  будет «неизвестна», пока тариф не задан.
- `max_input_tokens` приходит только у Anthropic и Gemini.
- Vision: подтверждён у DeepSeek (`input_modalities`), Anthropic
  (`capabilities.image_input`), OpenRouter (`architecture.input_modalities`),
  Moonshot (`supports_image_in`), Ollama (`capabilities`). У OpenAI/Gemini/
  MiniMax/generic — `unknown` или из каталога пресета; при `unknown` UI
  показывает «неизвестно», а не «поддерживается».
