# Итерация 7.18.3 — мультимодальный подсчёт и финальные исправления

**Задача:** закрыть блокирующий дефект 7.18 — нативный `count_tokens` не видел
мультимодальный материал, из-за чего «точный» вход был занижен на целые
изображения/PDF; развести число провайдера, оценку и резерв; не превращать
неизвестный Vision в подтверждённый `false`; честно показывать неизвестный
`max_request_bytes`. Без новой архитектуры.

**Старт:** `git status --porcelain` → пусто; `HEAD = origin/main = 8332df2`;
baseline **2340 passed + 16 skipped**, `analyze` 0. Красная фаза — коммит
`cac4586`, 16 assertion-level падений (`red-7.18.3.md`).

## 1. Мультимодальный `count_tokens` (§2)

- `RequestTokenCounter.count(..., attachments)`; тела собираются **теми же**
  функциями, что production-запросы (`anthropicUserContent`, `geminiParts`):
  - Anthropic: `messages[0].content` = text + `image`/`document` base64-блоки
    (подписи каталога — текстовыми блоками), `system`, `tools`/`tool_choice`;
  - Gemini: `generateContentRequest` c `systemInstruction` и `contents[].parts`
    (text + `inlineData`) — flat-поля `systemInstruction`/`generationConfig`
    схемой `CountTokensRequest` не предусмотрены (были дефектом: системный
    промпт не считался).
- PDF: Anthropic — `document`/`application/pdf`; Gemini — `inlineData` с
  `application/pdf` (документирован в `Blob.mimeType`).
- `responseSchema` Gemini в count-запрос **не отправляется** (вхождение в
  `totalTokens` не подтверждено); `schemaTokens` плана добавляются отдельной
  оценкой `response_schema` (§7 задания, L163).
- Конвейер передаёт `_countedRequest`: пользовательское сообщение тем же
  `buildGenerationUserContent` (включая «Файл: …» для запроса без текста) и
  image-части всех партий плана с id/подписями каталога; для whole-плана это
  консервативная верхняя граница (L182).
- Кэш: `exactTokenCacheKey` включает digest байтов, MIME и подпись части +
  версию формы; изменённая картинка при том же тексте даёт новый ключ.
- `_countedImageTokens` удалён: изображения уже в числе провайдера. Если
  подсчёт недоступен/упал — оценка `P + D`, `nativeInputTokens = null`.
- Диагностика — только источник/число/код ошибки; тела, байты и base64 в лог не
  попадают (тест).

## 2. `exact` ≠ бюджет с резервом (§3)

`NativeInputCount` + `RequestBudget`:

```
nativeInputTokens     — ровно число count_tokens (с частями)
estimatedExtraTokens  — добавка, которую провайдер не посчитал (+ components)
marginTokens          — 3 % если посчитано нативно ВСЁ, иначе 10 %
effectiveBudgetTokens = native + estimatedExtra + margin
accuracy              = exact только при estimatedExtra == 0
```

Смешанный результат (native + оценённая схема Gemini) — `estimated`, запас
10 %; коэффициенты 3 %/10 % не менялись. UI «Подробнее»: отдельные строки
«Число провайдера», «Оценка добавки (компоненты)», «Резерв бюджета», «Плановый
бюджет»; строка «Вход» не называет бюджет числом провайдера. Предупреждения
плана локализованы единым маппингом (`plan_warning_message.dart`).

## 3. Неизвестный Vision (§4)

- `ModelLimits.imageInputSupport: supported | unsupported | unknown`
  (`imageInputSupportOf`): отсутствие значения и `assumption` не подтверждают
  «нет»; `assumption: true` — попытка отправки.
- `ModelCapabilities.supportsVision` стал `bool?` (по умолчанию `null` =
  неизвестно); добавлен `visionSource`, чтобы подтверждённое `false`
  (`userConfigured`/`providerApi`/`officialCatalog`) не терялось при обратной
  проекции; `modelCapabilitiesFromLimits` передаёт три состояния.
- InputPlanner: `unknown` → изображения отправляются + предупреждение
  `imagesVisionUnconfirmed`; `unsupported` → прежнее поведение (каталог / план
  невыполним для вложений); `supported` — без изменений.
- Экран генерации: блокирует только подтверждённое `unsupported`; при `unknown`
  запрос уходит с `supportsVision: true` (провайдер сам подтвердит/отклонит),
  пользователь видит предупреждение. Приоритет `userConfigured` сохранён.

## 4. `max_request_bytes` (§5)

- `ModelLimits.unknownFields`, `ModelCapabilities.unknownFields` и
  `_unknownFields` плана содержат `max_request_bytes`, пока лимит не подтверждён.
- 32 МБ остаются допущением приложения: отдельное предупреждение
  `assumedImageLimits` + проверка фактических байтов тела в сервисе; в UI —
  блок «Неизвестные лимиты».

## 5. Новые/обновлённые тесты (+24 к baseline)

- `test/unit/api/generation/request_token_counter_multimodal_test.dart` — 5
  (Anthropic image, PDF, несколько изображений, Gemini inlineData/envelope,
  ключ кэша по дайджесту/MIME/подписи).
- `test/unit/domain/generation/token_breakdown_test.dart` — 5
  (native/estimated/reserve/budget, mixed, ошибка, коэффициенты).
- `test/unit/domain/generation/unknown_vision_and_limits_test.dart` — 8
  (три состояния, userConfigured, max_request_bytes, assumedImageLimits).
- `test/integration/generation_exact_tokens_test.dart` — 10 (exact, кэш,
  ошибка, нет двойного учёта, digest-кэш, mixed Gemini, вложения без текста,
  диагностика без байтов).
- Обновлены `request_token_counter_test.dart`, `generation_plan_details_test.dart`
  (+3), `generation_screen_test.dart` (+1 unknown Vision, подтверждённое false),
  `model_capabilities_test.dart`, `generation_planning_test.dart`,
  `image_catalog_budget_test.dart`, интеграционные Vision-сценарии.
- Полный набор: **2364 passed + 16 skipped + 0 failed**.

## 6. Сверка документации провайдеров

`discovery-7.18.3.md`: Anthropic count_tokens принимает system/tools/images/PDF,
но **только base64** (url/file → `invalid_request_error`); Gemini
`CountTokensRequest` = `contents` XOR `generateContentRequest`,
`systemInstruction`/`generationConfig` — только внутри конверта, `inlineData`
поддерживает `application/pdf`, вхождение `responseSchema` в `totalTokens` не
подтверждено. Живых запросов нет.

## 7. Ограничения

`journal/KNOWN_LIMITATIONS.md`: исправлена структура (блок L173–L178 7.18.2
стоял **до** заголовка файла и слипался с ним), L174 снят, L163/L176 обновлены,
добавлены L179–L185 (оценка Anthropic, модальности Gemini, предпросмотр,
whole-партии, отказ провайдера при unknown Vision, тело count-запроса,
`max_request_bytes`).

## 8. Ворота и CI

См. `verify-7.18.3.md` (гейты §6 задания) и `review-7.18.3.md` (ревью
неизменяемого снимка).
