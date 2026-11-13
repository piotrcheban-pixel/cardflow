# ADR-011 — Генерация: каноническая схема, адаптеры провайдеров, локальная валидация

**Дата:** 2026-11-13 · **Статус:** принято (итерация 3b) · **Связано:** SPEC A8.1, A8.2, A8.4, A8.5, A8.6;
ADR-012; `journal/iteration-3b/plan.md`, `spikes.md`; `docs/api-schema.md`, `docs/system-prompt.md`

## Контекст

SPEC A8.2 требует три адаптера (OpenAI Chat Completions со `strict` JSON Schema, Gemini `generateContent`
с `responseSchema`, Anthropic `messages` + инструмент `emit_cards` с `tool_choice`), единую каноническую
схему A8.4 и её приведение к возможностям провайдера. Строгий режим не гарантирует валидный JSON:
нужны проверка причины остановки, локальная валидация схемы и контентных правил (A8.4), коды ошибок и
понятные сообщения (A8.6). UI-экран A6.8 и пайплайн чанков — итерация 3c, поэтому контракт 3b должен быть
достаточным для 3c и не содержать UI.

Спайк S1: `json_schema` 5.2.2 валидирует каноническую схему A8.4 и возвращает ошибки по путям.
Спайк S2: `Math.tex(...).parseError` — публичный способ проверки LaTeX без рендера и биндинга.

## Варианты

1. **По адаптеру на провайдера с собственными схемами и разбором** (реализуемо, но три копии схемы
   и правил → дрейф; A8.4 требует единую каноническую схему).
2. **Одна каноническая схема + программные проекции + адаптеры только про транспорт** (выбран):
   схема задаётся один раз, проекции детерминированы и тестируются, адаптеры знают только «как положить
   схему в запрос» и «где в ответе карточки и причина остановки».
3. Пакет-валидатор `json_schema_builder` вместо `json_schema` — спайк показал, что текущий пакет справляется;
   менять зависимость незачем.

## Решение

### 1. Каноническая схема — в коде, одна на проект

`lib/api/generation/card_json_schema.dart`: `const Map<String, Object?> canonicalCardsResponseSchema` —
ровно A8.4 (все свойства в `required`, nullable — `type: ["string","null"]`, `additionalProperties: false`
на каждом объекте, enum `basic/basic_reversed/cloze`). Копия в `docs/api-schema.md` — документация;
источник правды — код. `CardResponseSchema` (`card_response_schema.dart`) оборачивает `JsonSchema.create`
и отдаёт `List<String> validate(Object? json)` (пути/описания ошибок) — типы `json_schema` наружу не утекают.

### 2. Проекции схемы — рекурсивный конвертер, не дубликаты

`lib/api/generation/provider_schema.dart`:

- **OpenAI:** каноническая схема как есть (union с `null` и `additionalProperties:false` соответствуют
  strict-режиму), `response_format: {type: "json_schema", json_schema: {name: "cards_response",
  strict: true, schema: …}}`.
- **Gemini:** union `[T, "null"]` → `{type: <T в верхнем регистре>, nullable: true}`; типы —
  `STRING/NUMBER/INTEGER/BOOLEAN/ARRAY/OBJECT`; `additionalProperties` удаляется (нет в `Schema` API);
  у объектов добавляется `propertyOrdering` (порядок свойств канонической схемы). `required` сохраняется.
- **Anthropic:** union `[T, "null"]` → `anyOf: [{type: T}, {type: "null"}]` (SPEC A8.4 разрешает именно
  этот вариант при отказе от union); `additionalProperties` сохраняется.

Проекции строятся из канонической схемы программно — при изменении A8.4 правки в одном месте.

### 3. Контракт адаптера — чистые функции, без Dio

`lib/api/providers/generation_provider_adapter.dart`:

```dart
class ProviderRequest { final Uri uri; final Map<String, String> headers; final Map<String, Object?> body; }
class ProviderRawResponse { final String cardsJson; final TokenUsage usage; }

abstract interface class GenerationProviderAdapter {
  GenerationProvider get provider;
  ProviderRequest buildRequest({required String apiKey, required String model,
      required String systemPrompt, required String userContent, required int maxOutputTokens});
  ProviderRawResponse parseResponse(Map<String, Object?> json);
}
```

- OpenAI: `POST https://api.openai.com/v1/chat/completions`, `Authorization: Bearer <key>`, сообщения
  `system`+`user`, `response_format` со strict-схемой; проверяются `choices[0].message.content`,
  `message.refusal`, `finish_reason == "length"`, пустой контент.
- Gemini: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`,
  ключ — **только** в заголовке `x-goog-api-key` (SPEC A8.6: не в URL), `systemInstruction`, `contents`,
  `generationConfig.responseMimeType/responseSchema`; проверяются `candidates[0]`, `finishReason`
  (`MAX_TOKENS` → обрезано; `SAFETY`/`RECITATION`/`BLOCKLIST`/`PROHIBITED_CONTENT`/`SPII` → отказ), пустой текст.
- Anthropic: `POST https://api.anthropic.com/v1/messages`, `x-api-key` + `anthropic-version: 2023-06-01`,
  `tools: [{name: "emit_cards", input_schema: …}]`, `tool_choice: {type: "tool", name: "emit_cards"}`;
  проверяются `stop_reason` (`max_tokens` → обрезано, `refusal` → отказ) и наличие `tool_use`-блока:
  его отсутствие — невалидный ответ. `max_tokens` передаётся из запроса (требование Anthropic).
- `maxOutputTokens` контракта: Anthropic — обязательный `max_tokens`; Gemini — `generationConfig.maxOutputTokens`;
  OpenAI — **не передаётся** осознанно (у части моделей параметр устарел/несовместим; ограничение —
  `<limit>` карточек, обрезание распознаётся по `finish_reason`; сверка с живым API — L1).

**Flutter в API-слое.** `lib/api/` в целом не зависит от Flutter, но проверка LaTeX по SPEC A8.4 требует
`flutter_math_fork` (рендер-пакет). Разрешённая точка входа — только
`lib/api/generation/latex_checker.dart` (`Math.tex(...).parseError`); валидатор получает проверку
функцией `latexChecker` (инъекция), поэтому остальная логика валидации остаётся чистой и тестируемой.
Architecture guard (`test/guards/architecture_test.dart`) проверяет `lib/domain/`; для `lib/api/` правило
фиксируется здесь: не тянуть `package:flutter/material.dart`/`material_ui` в API, Flutter — только для
LaTeX-проверки.

`parseResponse` бросает `GenerationException` с кодом (см. п. 5); «обрезано» — отдельный код `truncated`,
чтобы итерация 3c могла делить фрагмент пополам (A8.5 шаг 8), не разбирая провайдерные детали.

### 4. Локальная валидация: схема — целиком, контент — пометками

- Схема: ответ модели декодируется и валидируется канонической схемой. Нарушение схемы — ошибка
  `invalidResponse` (сообщение A8.6 «Нейросеть вернула неожиданный ответ»), а не «полукарточки».
- Контентные правила (`card_content_validator.dart`) карточку **не удаляют**, а помечают машинными
  кодами `CardIssueCode` (предпросмотр 3c покажет пометку и даст отредактировать):
  `emptyFront` (front пустой), `frontTooLong` (>500), `backTooLong` (>2000), `clozeMissing` (для cloze
  нет `{{cN::…}}`), `latexBroken` (формула не парсится `flutter_math_fork`), `excerptMismatch`
  (цитата после нормализации пробелов не входит в исходный текст — обнуляется, но карточка остаётся),
  `tagsAdjusted` (теги обрезаны до 3/убраны пустые/`#`).
- LaTeX проверяется через `Math.tex(expression).parseError` (спайк S2) в `latex_checker.dart`;
  валидатор принимает инъектируемую функцию — тесты не зависят от рендера.
- Дедупликация и нормализация хешей — итерация 3c (A8.5 шаг 9), в 3b не дублируется.

### 5. Коды ошибок и сообщения

`lib/domain/generation/generation_error.dart`:
`GenerationErrorCode { missingApiKey, invalidApiKey, badRequest, rateLimited, serverUnavailable, timeout,
network, cancelled, emptyResponse, truncated, refused, invalidResponse }`;
`GenerationException(code, {Duration? retryAfter, String? details})`, `details` — не в UI.
UI-маппинг — `lib/ui/generation/generation_error_message.dart` + строки ARB (итерация 3b, шаг T21):
сырые `DioException`/стектрейсы не показываются. Для 429 показывается «Повтор через N секунд»
(`Retry-After`), для truncated/refused/invalidResponse — «Нейросеть вернула неожиданный ответ.
Попробовать снова?», для timeout/network — «Нет подключения к интернету», пустой ответ — «Нейросеть
вернула пустой ответ. Попробуйте ещё раз».

**Отступление от буквальной формулировки SPEC A6.8.** SPEC приводит сообщение «Ключ API недействителен.
Проверьте ключ в настройках», но процесс (п. 3.1, приоритет выше SPEC по SPEC §0.3) разрешает латиницу
в UI только в брендах и именах форматов, а «API» — не бренд. UI-строка: «Ключ доступа недействителен.
Проверьте ключ в настройках»; смысл и место действия сохранены, guard `ru_strings` не ослабляется.

### 6. Промпт

- Системный промпт A8.1 — константа `systemPromptGenRuV2` (`lib/api/generation/system_prompt.dart`),
  версия `gen-ru-v2` в `generation_jobs.prompt_version` (3c). Текст не показывается и не редактируется UI.
- Пользовательское сообщение (`generation_prompt.dart`): `<materials>…</materials>`, затем
  `<wishes>…</wishes>` (только если пожелания непустые), затем `<limit>N</limit>` — A8.1/A8.5.
- Решение о суммаризации/чанкинге фрагментов — 3c; 3b строит сообщение из готового текста фрагмента.

## Последствия

- Три провайдера используют один валидатор и одну схему; различия — только в проекции схемы и конверте
  ответа, поэтому новый провайдер (post-MVP) добавляется адаптером без правок валидации.
- Ошибки провайдеров нормализованы в 12 кодов; UI и журнал `generation_jobs.error_code` (3c) говорят на
  одном языке.
- Живые вызовы не проверены (L1) — контракты зафиксированы тестами на эталонных ответах; проверка при
  появлении ключа.
- Пометки качества карточек не блокируют импорт: A8.4 требует «не пропускать без пометки», а не отбрасывать.
