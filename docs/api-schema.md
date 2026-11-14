# API-схема генерации CardFlow

**Версия:** 3 (2026-11-14; `max_tokens` и лестница совместимости OpenAI-совместимого
протокола, ADR-021) ·
**Связано:** SPEC A8.1, A8.2, A8.4, A8.5, A8.6; ADR-011; ADR-012; ADR-013; ADR-021
**Источник правды в коде:** `lib/api/generation/card_json_schema.dart` (канон), `provider_schema.dart`
(проекции), `card_response_schema.dart` (валидатор), `cards_json_extractor.dart` (разбор текста ответа),
`lib/domain/generation/` (коды ошибок).

## 1. Каноническая схема ответа модели (A8.4)

Совместима со строгим режимом OpenAI: **все** свойства в `required`, опциональные значения — union-тип
с `null`, на каждом объекте `additionalProperties: false`. Один и тот же JSON ожидается от всех провайдеров,
включая OpenAI-совместимый сервер (для него схема — ещё и локальный контракт fallback-пути, §2).

```json
{
  "type": "object",
  "properties": {
    "cards": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "front": { "type": "string" },
          "back": { "type": "string" },
          "hint": { "type": ["string", "null"] },
          "tags": { "type": "array", "items": { "type": "string" } },
          "card_type": { "type": "string", "enum": ["basic", "basic_reversed", "cloze"] },
          "source_excerpt": { "type": ["string", "null"] },
          "source_file": { "type": ["string", "null"] }
        },
        "required": ["front", "back", "hint", "tags", "card_type", "source_excerpt", "source_file"],
        "additionalProperties": false
      }
    }
  },
  "required": ["cards"],
  "additionalProperties": false
}
```

Пустой массив `cards` — валидный ответ (мало материала / материала нет, правило 13 A8.1). Это **не**
ошибка ответа: UI показывает отдельное сообщение ARB `generationNoCardsFound` («Модель не нашла в
материалах фактов для карточек…», ADR-021), а `generationErrorEmptyResponse` остаётся за случаем, когда
сам провайдер вернул пустой `content` (`emptyResponse`).

## 2. Проекции под провайдеров (A8.2)

| Провайдер | Механизм | Проекция схемы | Ключевые поля |
|---|---|---|---|
| OpenAI | Chat Completions, `response_format: {type: "json_schema", json_schema: {name, strict: true, schema}}` | канон как есть (strict **требует** `additionalProperties: false` и все свойства в `required`; nullable — union с `null`) | `choices[0].message.content`, `message.refusal`, `choices[0].finish_reason`, `usage.prompt_tokens/completion_tokens` |
| OpenAI-совместимый (ADR-013, ADR-021) | Chat Completions с настраиваемым `base_url`; первый запрос — `response_format` со strict-схемой + `max_tokens`, при `badRequest` (любой 4xx, кроме 401/403/429) — лестница из двух упрощений (§2, «лестница совместимости») | канон как есть (как у OpenAI); в fallback-пути схема не передаётся, но ответ проверяется локально по канону | `choices[0].message.content` (JSON может быть в markdown-ограждении или с BOM — извлекается), `message.refusal`, `choices[0].finish_reason`, `usage.*`, `max_tokens` |
| Gemini | `generateContent`, `generationConfig: {responseMimeType: "application/json", responseSchema}` | union `[T,"null"]` → `{type: T, nullable: true}`; типы — `STRING/NUMBER/INTEGER/BOOLEAN/ARRAY/OBJECT`; `additionalProperties` удаляется; `propertyOrdering` = порядок свойств | `candidates[0].content.parts[].text`, `candidates[0].finishReason`, `promptFeedback.blockReason`, `usageMetadata.*` |
| Anthropic | `messages` + `tools` (`emit_cards`) + `tool_choice: {type: "tool", name: "emit_cards"}` | union → `anyOf: [{type: T}, {type: "null"}]`; `additionalProperties` сохраняется | `content[]` с `{type: "tool_use", name: "emit_cards", input.cards}`, `stop_reason`, `usage.input_tokens/output_tokens` |

Эндпоинты и заголовки:

- OpenAI: `POST https://api.openai.com/v1/chat/completions`, `Authorization: Bearer <key>`.
- OpenAI-совместимый (ADR-013): `POST <base_url>/chat/completions`; `<base_url>` — из `app_settings`
  (ключ `generation.openai_compatible`, JSON `{"baseUrl": "…", "model": "…"}`); примеры:
  `https://api.deepseek.com`, `http://localhost:11434/v1` (Ollama), `http://localhost:1234/v1` (LM Studio).
  Путь `/chat/completions` дописывается приложением один раз — полный адрес эндпоинта второй раз не
  добавляется. `Authorization: Bearer <key>` отправляется только если ключ задан (secure storage,
  `cardflow.api_key.openai_compatible`); без ключа заголовка нет. Схемы — `http` и `https`; `https`
  рекомендован для облачных серверов, `http` — для локальных и доверенных (жёсткого запрета нет; ключ по
  `http` — риск пользователя); `userinfo`/query/fragment в адресе запрещены (ADR-013 §3).
- Gemini: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`,
  `x-goog-api-key: <key>` (ключ **не** в URL — SPEC A8.6); `generationConfig.maxOutputTokens` передаётся.
- Anthropic: `POST https://api.anthropic.com/v1/messages`, `x-api-key: <key>`,
  `anthropic-version: 2023-06-01`, `max_tokens` обязателен.
- Лимит ответа OpenAI не передаётся: ограничение — `<limit>` карточек в сообщении, а обрезание
  распознаётся по `finish_reason` (у части моделей параметр устарел, сверка с живым API — L1).
  OpenAI-совместимый передаёт `max_tokens = maxOutputTokens` (8192, ADR-021): серверный дефолт
  DeepSeek — 4096, для 20 карточек этого мало. `max_tokens` не передаётся на третьем шаге лестницы
  совместимости (серверы, требующие `max_completion_tokens`).

**Лестница совместимости (только OpenAI-совместимый, ADR-013 §4, ADR-021).** Первый запрос — как у
OpenAI, со strict-схемой и `max_tokens`. Если сервер не поддерживает `response_format` со strict-схемой
и отвечает `badRequest` (любой 4xx, включая 400/404/422; 401/403/429 не повторяются), выполняется
второй запрос — без `response_format`, но с `max_tokens`; если и он отклонён `badRequest` — третий, без
`response_format` и без `max_tokens` (серверы, требующие `max_completion_tokens`). Больше трёх запросов
не бывает. Ответ на любом шаге проходит ту же локальную валидацию канонической схемы A8.4
(`CardResponseSchema`) и контентные правила — послаблений нет. JSON в markdown-ограждении, с BOM или в
пояснительном тексте извлекается до декодирования (`cards_json_extractor.dart`; только для этого
провайдера — остальные обязаны вернуть чистый JSON). Fallback — не ретрай ADR-012: 4xx транспортом не
повторяются; при 401/403/429/5xx/таймауте fallback не выполняется. Живой DeepSeek (2026-11-14):
strict-запрос → 400 (`This response_format type is unavailable now`), второй запрос с `max_tokens=8192`
→ 200, карточки; проверяется live-тестом `test/live/openai_compatible_deepseek_live_test.dart`.
Поведение OpenAI/Gemini/Anthropic не меняется: у них по-прежнему один запрос, `max_tokens` — по контракту
протокола (Anthropic/Gemini передают, OpenAI — нет).

**Аккаунты провайдеров (ADR-020, итерация 7.5).** Адреса выше — значения по умолчанию
протокола; адрес и модель берутся из аккаунта (`ProviderAccount`), а ключ — из
`ApiKeyStore` по `account.id`. Один протокол (`openai-completions`) обслуживает каталог
DeepSeek / OpenRouter / Moonshot / MiniMax / Groq / Ollama и любую пользовательскую модель API:
`POST <base_url>/chat/completions`, где `<base_url>` — адрес аккаунта. Нативные протоколы тоже
принимают свой базовый адрес (прокси/шлюз): OpenAI — `<base_url>/chat/completions`,
Anthropic — `<base_url>/v1/messages`, Gemini — `<base_url>/v1beta/models/{model}:generateContent`.
Резолвер один — `lib/api/providers/provider_endpoint.dart`; схема только http/https, ключ только
в заголовке.

**Вложения и Vision (ADR-022, итерация 7.8).** Адрес и модель — из аккаунта; `supportsVision`
(JSON `supports_vision`) задаёт, можно ли отправлять изображения. Маршрутизация на каждый файл:

| Файл | Условие | Что уходит провайдеру |
|---|---|---|
| DOCX/PPTX/ODT/XLSX/TXT/MD/RTF | локально извлечён непустой текст | текст в `<materials>` (любая модель; `TextSanitizer` удаляет управляющие символы) |
| JPG/PNG | `supportsVision=true` | OpenAI/совместимые — `image_url` data URI; Gemini — `inlineData`; Anthropic — блок `image` с base64 |
| JPG/PNG | `supportsVision=false` | запрос не выполняется: `visionUnsupported` |
| PDF-скан без текста | Vision + протокол принимает PDF | Gemini — `inlineData application/pdf`; Anthropic — блок `document` с base64 |
| PDF-скан без текста | Vision есть, PDF-протокола нет (OpenAI/совместимые) | `pdfScanUnsupported` |
| PDF-скан без текста | Vision нет | `fileWithoutTextAndVision` |
| любой файл | больше 10 МБ inline | `attachmentTooLarge` |

Каждый файл-вложение — отдельный запрос (1 файл = 1 фрагмент), имя попадает в
`generation_jobs.files` и `sourceFiles`; вложения сохраняются в `GenerationChunkFailure` для
повтора. Inline-base64 увеличивает тело на ~33 %; лимит 10 МБ на файл. Прямые file API
провайдеров и рендер PDF-страниц в изображения в MVP не используются.

**Причина HTTP 400.** Для 4xx (после того как retry/fallback исчерпаны) из тела ответа
извлекается `error.message`/`message`/`detail`, очищается от управляющих символов и
секретоподобных значений, ограничивается 200 символами и передаётся в
`GenerationException.providerReason`; UI показывает «Запрос отклонён: {reason}» (ARB
`generationErrorBadRequestReason`). Тело ответа целиком не показывается и не логируется.

## 3. Причины остановки и ошибки провайдеров

| Ситуация | OpenAI | Gemini | Anthropic | Код CardFlow |
|---|---|---|---|---|
| Обрезано по лимиту | `finish_reason == "length"` | `finishReason == "MAX_TOKENS"` | `stop_reason == "max_tokens"` | `truncated` (3c дробит фрагмент пополам) |
| Отказ модели | `message.refusal != null` | `SAFETY`, `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`, `SPII`, `blockReason` | `stop_reason == "refusal"` | `refused` |
| Пустой ответ | `content` пуст/`null` | нет `candidates`, нет текста | — (для Anthropic пустой `content` — это `invalidResponse`: нет `tool_use`) | `emptyResponse` (OpenAI/Gemini) |
| Нет структурированного ответа | не JSON / схема | не JSON / схема | нет `tool_use` с `emit_cards` | `invalidResponse` |

OpenAI-совместимый сервер разбирается по колонке OpenAI (`choices[0]`, `message.refusal`, `finish_reason`,
`usage.*`); «нет структурированного ответа» дополнительно включает JSON, не найденный после извлечения из
markdown-ограждения/текста, и ответ fallback-пути, не прошедший локальную проверку канонической схемы.

## 4. Локальная валидация (A8.4)

1. **Схема** (целиком): нарушение → `invalidResponse` (сообщение A8.6 «Нейросеть вернула неожиданный
   ответ. Попробовать снова?»), карточки фрагмента не импортируются.
2. **Контентные правила** — карточка остаётся, ставится машинная пометка (`CardIssueCode`, предпросмотр 3c
   покажет и даст отредактировать):

| Пометка | Правило |
|---|---|
| `emptyFront` | `front` пустой после trim |
| `frontTooLong` | `front` > 500 символов |
| `backTooLong` | `back` > 2000 символов |
| `clozeMissing` | `card_type == cloze` и нет ни одного `{{cN::…}}` |
| `latexBroken` | формула `$…$` / `$$…$$` не парсится `flutter_math_fork` |
| `excerptMismatch` | `source_excerpt` после сжатия пробелов не входит в исходный текст → обнуляется |
| `tagsAdjusted` | теги обрезаны до 3, удалены пустые и `#` |

## 5. Коды ошибок слоя генерации

`GenerationErrorCode` (`lib/domain/generation/generation_error.dart`):

| Код | Причина | Повторяется | Сообщение UI (ARB) |
|---|---|---|---|
| `missingApiKey` | ключ не задан в настройках | — | «Ключ доступа не задан. Добавьте ключ в настройках» |
| `providerNotConfigured` | не заданы/некорректны адрес или модель OpenAI-совместимого сервера; запрос в сеть не выполняется (ADR-013 §7) | нет | «Сервер не настроен. Укажите адрес и модель в настройках» |
| `invalidApiKey` | 401/403 | нет | «Ключ доступа недействителен. Проверьте ключ в настройках» |
| `badRequest` | 400 и прочие 4xx | нет | «Запрос отклонён. Проверьте выбранную модель и ключ в настройках»; с `providerReason` — «Запрос отклонён: {reason}» |
| `rateLimited` | 429 после попыток | да, по `Retry-After` | «Превышен лимит запросов. Повтор через N секунд» |
| `serverUnavailable` | 5xx после попыток | да (backoff) | «Провайдер временно недоступен. Попробуйте позже» |
| `timeout` | таймаут соединения/приёма | да (backoff) | «Нет подключения к интернету» |
| `network` | нет сети / обрыв соединения | да (backoff) | «Нет подключения к интернету» |
| `cancelled` | отменено пользователем | нет | «Генерация отменена» |
| `emptyResponse` | пустой контент модели | нет | «Нейросеть вернула пустой ответ. Попробуйте ещё раз» |
| `truncated` | обрезано | 3c: дробление фрагмента | «Нейросеть вернула неожиданный ответ. Попробовать снова?» |
| `refused` | отказ/safety | нет | «Нейросеть вернула неожиданный ответ. Попробовать снова?» |
| `invalidResponse` | не JSON / схема / нет tool_use | нет | «Нейросеть вернула неожиданный ответ. Попробовать снова?» |
| `noMaterials` | после санитизации текст пуст, вложений нет | нет | «В файле нет текста (скан или пустая форма)» |
| `visionUnsupported` | картинка, а `supportsVision=false` | нет | «Модель не поддерживает изображения» |
| `fileWithoutTextAndVision` | PDF-скан, а `supportsVision=false` | нет | «В файле нет текста. Модель не поддерживает изображения» |
| `pdfScanUnsupported` | PDF-скан, протокол не принимает PDF | нет | «PDF-скан не поддерживается выбранной моделью» |
| `attachmentTooLarge` | вложение больше 10 МБ | нет | «Файл больше 10 МБ. Уменьшите файл и попробуйте снова» |

Кодов 18: двенадцать из ADR-011 §5, `providerNotConfigured` (ADR-013), `noMaterials` (3c) и четыре
кода вложений (ADR-022). Сырые `DioException`, стектрейсы и `details` в UI не попадают — только
строки ARB. Исключение — очищенный `providerReason` для 400 по требованию владельца (ADR-022 §5).

## 6. Ретраи и таймауты (A8.6)

- Максимум 4 попытки. 429 — пауза по `Retry-After` (секунды или HTTP-date), иначе экспоненциальный
  backoff с full jitter (`base 1 s`, `cap 30 s`); 5xx/таймауты/сеть — тот же backoff.
- **Осознанный cap (ADR-012 §1):** если `Retry-After` больше `maxRetryAfter` (60 с), автоматический
  повтор не выполняется — пользователь видит «Повтор через N секунд» и повторяет вручную; UI не
  блокируется на минуты. `maxRetryAfter` настраивается в `RetryPolicy`.
- 400/401/403 (и прочие 4xx), отмена, ошибки разбора и схемы — без повторов. Отмена прерывает и
  паузу перед повтором (не ждёт backoff/`Retry-After`).
- Таймауты: соединение 15 с, отправка 60 с, приём 180 с.

## 7. Безопасность

- Ключи — только `flutter_secure_storage` (`cardflow.api_key.<provider>`); в БД/экспорте/логах нет.
- OpenAI-совместимый: адрес и модель — в `app_settings` (`generation.openai_compatible`; не секрет), ключ —
  только secure storage (`cardflow.api_key.openai_compatible`, необязателен). Схемы — `http` и `https`;
  `https` рекомендован для облачных, `http` — для локальных/доверенных (жёсткого запрета нет; ключ по
  `http` — риск пользователя); `userinfo`/query/fragment из адреса вычищаются (ADR-013 §3).
- Логи: `Authorization`, `x-api-key`, `x-goog-api-key`, query `key`/`api_key` редактируются; тела запросов
  и ответов не логируются (материалы пользователя и ответ модели в логи не попадают).
- Причина 400 (`providerReason`) — только серверное объяснение: управляющие символы удаляются,
  ключеподобные строки (`sk-…`, `AIza…`, `Bearer …`) редактируются, длина ≤ 200 символов; тело
  ответа и заголовки не показываются.
- Изображения/PDF-сканы уходят только выбранному провайдеру как base64-части запроса; локальные
  копии вложений не сохраняются (вложения живут в памяти экрана генерации).
- Материалы пользователя уходят только в выбранного провайдера (для OpenAI-совместимого — на адрес из
  настроек) в составе сообщения; собственного сервера CardFlow нет.
