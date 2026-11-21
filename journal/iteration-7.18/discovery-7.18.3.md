# Итерация 7.18.3 — семантика count_tokens провайдеров (сверка документации)

**Дата сверки:** 2026-11-21. **Живых API-запросов нет**: источники — официальная
документация Anthropic (фетч страницы) и официальный discovery-документ Gemini
API; проверка формы тел — mock-HTTP (`request_token_counter_multimodal_test.dart`).

## Anthropic — `POST /v1/messages/count_tokens`

Источник: <https://platform.claude.com/docs/en/build-with-claude/token-counting>
(фетч 2026-11-21), страница API `.../api/messages/count_tokens`.

Подтверждено:

- «The token counting endpoint accepts the same structured list of inputs for
  creating a message, including support for **system prompts, tools, images, and
  PDFs**».
- Ответ для недопустимых входов — `invalid_request_error`; среди них
  «`image` or `document` blocks with a `url` or `file` source». Прямая цитата:
  «Send images and PDFs as **base64** to count them».
- Примеры: изображение — блок
  `{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":…}}`;
  PDF — блок
  `{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":…}}`.
- Оговорка: «The token count is an estimate. In some cases, the actual number of
  input tokens … might differ by a small amount» → число провайдера точнее
  эвристики, но не гарантия; запас 3 % сохранён (L179).

Вывод для реализации: `system` + `messages[0].content` из тех же
`anthropicUserContent`, что уходит в production, + `tools`/`tool_choice`
(схема карточек документированно входит в tools). Никаких `url`/`file`.

## Gemini — `POST /v1beta/models/{model}:countTokens`

Источник: официальный discovery-документ
`https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta`
(скопирован в `journal/iteration-7.18/gemini-discovery-v1beta.json` при аудите;
в репозиторий не коммитится — сгенерированный 400-КБ артефакт).

Подтверждено схемой:

- `CountTokensRequest` = **либо** `contents: Content[]`, **либо**
  `generateContentRequest: GenerateContentRequest`; описание:
  «`contents` … ignored when `generate_content_request` is set» и
  «`Model`s/`Content`s and `generate_content_request`s are mutually exclusive.
  You can either send `Model` + `Content`s or a `generate_content_request`, but
  never both». `systemInstruction` и `generationConfig` — поля
  `GenerateContentRequest`, а не `CountTokensRequest`: в flat-теле они не
  предусмотрены (старая реализация 7.18.1 отправляла их top-level).
- `Part.inlineData` → `Blob`; `Blob.mimeType` документирует
  `application/pdf` среди поддерживаемых типов → PDF передаётся тем же
  `inlineData`, что и картинки.
- Обёртка `generateContentRequest` требует `model` в форме `models/<id>`
  (path-модель главнее; несовпадение принимается). Без поля endpoint отвечает
  400 — поэтому счётчик передаёт `model: models/<id>` внутри конверта.
  Подтверждено вторичным live-verified источником
  <https://git.spboucher.ai/doc-api/blob/main/docs/gemini/token-counting.md>
  (13 проб countTokens, 2026-09-18): top-level `systemInstruction` → 400
  «Unknown name», wrapper c `model`/`contents`/`systemInstruction` считается
  полностью; `1×1 PNG` → 1089 токенов, одностраничный PDF → 560 (модальности
  видны в `promptTokensDetails`). Наши собственные живые запросы не
  выполнялись (запрет).
- `CountTokensResponse.totalTokens` — «The number of tokens that the `Model`
  tokenizes the `prompt` into»; `promptTokensDetails[]` — «List of modalities
  that were processed in the request input» (подтверждение, что мультимодальный
  вход учитывается, хотя построчной формулы нет — L180).
- Вхождение `generationConfig.responseSchema` в `totalTokens` **не
  подтверждено**: схема — не «prompt», а ограничение вывода. Решение: в
  count-запрос `responseSchema` не отправляется, `schemaTokens` плана
  добавляется отдельной **оценкой** (`estimated_components: response_schema`),
  точность — `estimated` (L163).

Вывод для реализации: тело —
`{"generateContentRequest":{"systemInstruction":{…},"contents":[{"role":"user",
"parts":[text, inlineData…]}]}}`; части — те же `geminiParts`, что в production;
`model` — только в URL.

## Что осталось неподтверждённым

| Вопрос | Статус | Где зафиксировано |
|---|---|---|
| Anthropic: факт `count_tokens` против `usage.input_tokens` | нет живого прогона (запрет) | L179 |
| Gemini: точная формула токенов `inlineData`/PDF | нет живого прогона; только модальности в ответе | L180 |
| Gemini: вхождение схемы в `totalTokens` | не документировано → оценка отдельно | L163 |
| Лимит тела count-эндпоинта | не документирован; при отказе — оценка | L184 |
| OpenAI/Gemini/Anthropic ключи | в окружении отсутствуют (L1) | L1 |
