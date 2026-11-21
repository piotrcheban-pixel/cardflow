# Итерация 7.18.3 — ревью

**Снимок:** ветка `main`, зелёные коммиты `ee135b8`, `3f80f6d` + `cf3a741`
(фикс подсчёта вложений без текста). Статус независимого reviewer'а — **L35**:
в сессии он недоступен, поэтому ревью Lead по чек-листу на неизменяемом снимке
(после зелёной фазы и до verify-прогона). Findings исправлены отдельным
fix-коммитом с регрессионными тестами.

## Чек-лист

| Пункт задания | Проверка | Итог |
|---|---|---|
| §2 Anthropic получает все части | `anthropicUserContent` в count-теле; картинки/PDF base64; порядок и подписи совпадают с production | ок (тесты R1–R3) |
| §2 Gemini получает все части | `generateContentRequest` c `systemInstruction` + `contents[].parts.inlineData`; flat-поля запрещены схемой | ок (R4) |
| §2 нет повторного count для посчитанного | early-return при `accuracy == exact`, кэш `ExactTokenCountCache` по полному ключу | ок |
| §2 fallback при ошибке | `ExactTokenCount.unknown` → оценка `P + D`, `native = null`, код ошибки в диагностике | ок |
| §2 нет двойного учёта изображений | `_countedImageTokens` удалён; `estimatedExtraTokens = 0` для Anthropic; тест «не считаются дважды» | ок |
| §2 ключ кэша по содержимому | digest байтов + MIME + подпись + версия формы; изменённая картинка → 2-й вызов | ок |
| §2 секреты/бинарники не в диагностике | тест: нет `base64`, нет закодированных байтов; ключи не участвуют в ключе | ок |
| §3 exact/estimated разделены | `NativeInputCount` → `native/estimatedExtra/margin/effectiveBudget`; mixed = `estimated` | ок |
| §3 UI не выдаёт бюджет за native | отдельные строки «Число провайдера/Оценка добавки/Резерв/Плановый бюджет»; тест «не содержит „нативный“» | ок |
| §3 коэффициенты 3 %/10 % | не менялись; тесты на оба случая | ок |
| §4 три состояния Vision | `ImageInputSupport`, `ModelCapabilities.supportsVision: bool?`, `visionSource`; unknown не блокирует | ок |
| §4 приоритет userConfigured | `resolveModelLimits` userLayer + тест | ок |
| §4 не писать «не поддерживает» при unknown | предупреждение `imagesVisionUnconfirmed`, экранный тест `isNot` строки отказа | ок |
| §5 `max_request_bytes` в unknownFields | `ModelLimits`, `ModelCapabilities`, план, блок «Неизвестные лимиты» | ок |
| §5 отдельное предупреждение payload | `assumedImageLimits` + фактическая проверка байтов не тронуты | ок |
| §6 тесты по списку | см. `summary-7.18.3.md` §5; 24 новых теста | ок |
| §7 нет двойного учёта схемы | Anthropic: `tools` внутри native, добавка 0; Gemini: схема не отправляется, добавка оценена | ок |
| §7 overhead Anthropic/Gemini | system/tools — native; Gemini schema — отдельная оценка; prompt-only тем же путём | ок |
| §7 кэш по полному содержимому | текст + байты + MIME + подпись + модель/провайдер/адрес | ок |
| §7 точность предпросмотра/production | один builder; предпросмотр — оценка (сети нет), production пересобирает после подсчёта; расхождение ограничено запасом (L181) | ок, ограничение |
| §7 предыдущие исправления 7.18.1/7.18.2 | полный набор зелёный, регрессий нет (каталог в `D`, payload, reasoning-резерв) | ок |
| §7 структура KNOWN_LIMITATIONS | исправлена (блок L173–L178 был до заголовка) | ок |

## Findings

| # | Severity | Находка | Исправление |
|---|---|---|---|
| F1 | **high** | Gemini-обёртка `generateContentRequest` не содержала `model` в форме `models/<id>`; endpoint отвечает 400, и **любой** Gemini exact-подсчёт молча деградировал бы к оценке (потеря всей функциональности §2 для Gemini) | `request_token_counter.dart`: `'model': 'models/$model'` в конверте; тест проверяет поле (вторичный live-verified источник подтверждает обязательность, `discovery-7.18.3.md`) |
| F2 | medium | Запрос только из вложений: `_countedUserContent` подставлял пустые материалы, тогда как сервис добавляет строки «Файл: <имя>» → native-число занижено, `exact` неправдив | `generation_pipeline.dart`: тот же fallback, что в `CardGenerationService`; новый интеграционный тест (`native=500`, userContent содержит «Файл:») |
| F3 | medium | Предпросмотр и production могли получить **разные** аккаунты по Vision: `_startGeneration` делал `copyWith(supportsVision: true)` только в момент запроса, а `resolveModelCapabilities` учитывает этот флаг в inferred-слое → планы расходились (предупреждение в предпросмотре, «поддержано» в производстве) | `_requestAccount` разрешает unknown→попытка один раз; запуск использует тот же аккаунт, что и предпросмотр; экранные тесты (unknown разрешает, confirmed false блокирует, userConfigured приоритет) |
| F4 | medium | `journal/KNOWN_LIMITATIONS.md`: блок ограничений 7.18.2 стоял **до** заголовка файла и слипался с ним (строка `… |# Известные ограничения CardFlow`) — структура не соответствовала формату | блок перенесён в раздел 7.18.2 после 7.18.1; L174 снят, L163/L176 обновлены, добавлены L179–L185 |
| F5 | low | lint `curly_braces_in_flow_control_structures` в новом цикле | блок `{ }`; повторный `analyze` — 0 |
| F6 | low | `InputAccuracy`-импорт в «Подробнее» после переписывания `_inputLine` мог стать лишним | проверено `flutter analyze` — 0 issues; импорт используется `NativeInputCount` |
| F7 | low (документировано) | Тело count-запроса не проверяется по `maxRequestBytes`; очень большие вложения могут дать отказ → оценка | зафиксировано L184 (fallback безопасен) |
| F8 | low (документировано) | Для whole-плана из нескольких партий подсчёт — объединение image-частей (верхняя граница, не байт-в-байт конкретной партии) | L182; бюджет не занижается, запас сверху |

## Проверки, подтверждающие отсутствие регрессий

- Полный набор (гейт ниже): 2364+ passed, 0 failed; analyze 0; format 0 changed.
- `test/guards/*` (архитектура/ru-строки/no_secrets) в полном наборе зелёные.
- Диагностика: `generation_exact_tokens_test` проверяет отсутствие тела,
  base64 и ключей.
- Схема БД/`schemaVersion`/`format_version` не менялись: правки — домен/API/UI
  и JSON аккаунта не изменялся (используются существующие поля).

**Открытых high/medium нет.**
