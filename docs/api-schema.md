# API-схема генерации CardFlow

**Версия:** 1 (итерация 3b) · **Связано:** SPEC A8.1, A8.2, A8.4, A8.5, A8.6; ADR-011; ADR-012
**Источник правды в коде:** `lib/api/generation/card_json_schema.dart` (канон), `provider_schema.dart`
(проекции), `card_response_schema.dart` (валидатор), `lib/domain/generation/` (коды ошибок).

## 1. Каноническая схема ответа модели (A8.4)

Совместима со строгим режимом OpenAI: **все** свойства в `required`, опциональные значения — union-тип
с `null`, на каждом объекте `additionalProperties: false`. Один и тот же JSON ожидается от всех провайдеров.

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

Пустой массив `cards` — валидный ответ (мало материала / материала нет, правило 13 A8.1).

## 2. Проекции под провайдеров (A8.2)

| Провайдер | Механизм | Проекция схемы | Ключевые поля |
|---|---|---|---|
| OpenAI | Chat Completions, `response_format: {type: "json_schema", json_schema: {name, strict: true, schema}}` | канон как есть (union с `null` и `additionalProperties` допустимы в strict) | `choices[0].message.content`, `message.refusal`, `choices[0].finish_reason`, `usage.prompt_tokens/completion_tokens` |
| Gemini | `generateContent`, `generationConfig: {responseMimeType: "application/json", responseSchema}` | union `[T,"null"]` → `{type: T, nullable: true}`; типы — `STRING/NUMBER/INTEGER/BOOLEAN/ARRAY/OBJECT`; `additionalProperties` удаляется; `propertyOrdering` = порядок свойств | `candidates[0].content.parts[].text`, `candidates[0].finishReason`, `promptFeedback.blockReason`, `usageMetadata.*` |
| Anthropic | `messages` + `tools` (`emit_cards`) + `tool_choice: {type: "tool", name: "emit_cards"}` | union → `anyOf: [{type: T}, {type: "null"}]`; `additionalProperties` сохраняется | `content[]` с `{type: "tool_use", name: "emit_cards", input.cards}`, `stop_reason`, `usage.input_tokens/output_tokens` |

Эндпоинты и заголовки:

- OpenAI: `POST https://api.openai.com/v1/chat/completions`, `Authorization: Bearer <key>`.
- Gemini: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`,
  `x-goog-api-key: <key>` (ключ **не** в URL — SPEC A8.6).
- Anthropic: `POST https://api.anthropic.com/v1/messages`, `x-api-key: <key>`,
  `anthropic-version: 2023-06-01`, `max_tokens` обязателен.

## 3. Причины остановки и ошибки провайдеров

| Ситуация | ОткрыAI | Gemini | Anthropic | Код CardFlow |
|---|---|---|---|---|
| Обрезано по лимиту | `finish_reason == "length"` | `finishReason == "MAX_TOKENS"` | `stop_reason == "max_tokens"` | `truncated` (3c дробит фрагмент пополам) |
| Отказ модели | `message.refusal != null` | `SAFETY`, `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`, `SPII`, `blockReason` | `stop_reason == "refusal"` | `refused` |
| Пустой ответ | `content` пуст/`null` | нет `candidates`, нет текста | нет текстового/`tool_use` контента | `emptyResponse` |
| Нет структурированного ответа | не JSON / схема | не JSON / схема | нет `tool_use` с `emit_cards` | `invalidResponse` |

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
| `invalidApiKey` | 401/403 | нет | «Ключ доступа недействителен. Проверьте ключ в настройках» |
| `badRequest` | 400 и прочие 4xx | нет | «Запрос отклонён. Проверьте выбранную модель и ключ в настройках» |
| `rateLimited` | 429 после попыток | да, по `Retry-After` | «Превышен лимит запросов. Повтор через N секунд» |
| `serverUnavailable` | 5xx после попыток | да (backoff) | «Провайдер временно недоступен. Попробуйте позже» |
| `timeout` | таймаут соединения/приёма | да (backoff) | «Нет подключения к интернету» |
| `network` | нет сети / обрыв соединения | да (backoff) | «Нет подключения к интернету» |
| `cancelled` | отменено пользователем | нет | «Генерация отменена» |
| `emptyResponse` | пустой контент модели | нет | «Нейросеть вернула пустой ответ. Попробуйте ещё раз» |
| `truncated` | обрезано | 3c: дробление фрагмента | «Нейросеть вернула неожиданный ответ. Попробовать снова?» |
| `refused` | отказ/safety | нет | «Нейросеть вернула неожиданный ответ. Попробовать снова?» |
| `invalidResponse` | не JSON / схема / нет tool_use | нет | «Нейросеть вернула неожиданный ответ. Попробовать снова?» |

Сырые `DioException`, ответы провайдеров, стектрейсы и `details` в UI не попадают — только строки ARB.

## 6. Ретраи и таймауты (A8.6)

- Максимум 4 попытки. 429 — пауза по `Retry-After` (секунды или HTTP-date), иначе экспоненциальный
  backoff с full jitter (`base 1 s`, `cap 30 s`); 5xx/таймауты/сеть — тот же backoff.
- 400/401/403 (и прочие 4xx), отмена, ошибки разбора и схемы — без повторов.
- Таймауты: соединение 15 с, отправка 60 с, приём 180 с.

## 7. Безопасность

- Ключи — только `flutter_secure_storage` (`cardflow.api_key.<provider>`); в БД/экспорте/логах нет.
- Логи: `Authorization`, `x-api-key`, `x-goog-api-key`, query `key`/`api_key` редактируются; тела запросов
  и ответов не логируются (материалы пользователя и ответ модели в логи не попадают).
- Материалы пользователя уходят только в выбранный провайдер в составе сообщения; собственного сервера нет.
