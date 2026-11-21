# Итерация 7.18.3 — красная фаза

**Дата:** 2026-11-21. **HEAD старта:** `8332df2` (= `origin/main`, рабочее дерево
пусто). **Baseline:** полный набор 7.18.2 — **2340 passed + 16 skipped**.

Красная фаза — один коммит `cac4586` (`test(generation): red-фаза 7.18.3 …`):
новые тесты против **нового контракта** (приёмник `attachments`,
`NativeInputCount`, `supports_image_input`/`max_request_bytes` в unknown,
`imagesVisionUnconfirmed`) при сохранённой старой реализации. Логи:
`journal/iteration-7.18/red-7.18.3.log` (основной прогон, **16 assertion-level
падений**), `red-7.18.3-unknown-vision.log` (4 падения по Vision/лимитам).

## Кто и почему падал (ожидалось / получено)

| # | Тест | Ожидалось | Получено | Причина (дефект) |
|---|---|---|---|---|
| R1 | Anthropic: изображение уходит base64 image-блоком | `messages[0].content` — список с `type=image`, `source.type=base64` | `content` — строка; `type 'String' is not a subtype of 'List<Object?>'` | счётчик отправлял только текст; изображения в `count_tokens` не уходили |
| R2 | Anthropic: PDF уходит base64 document-блоком | блок `type=document`, `media_type=application/pdf` | строковое content | PDF не передавался в подсчёт |
| R3 | Anthropic: несколько изображений и подписи каталога | 3 image-блока + 3 text-блока в порядке production | строковое content | порядок/подписи не проверялись — частей не было вовсе |
| R4 | Gemini: inlineData внутри `generateContentRequest` | `body.generateContentRequest` c `systemInstruction`, `contents[].parts[].inlineData` | `Null check operator used on a null value` | тело было плоским (`systemInstruction`/`generationConfig` top-level), т.е. полям не место в `CountTokensRequest` |
| R5 | ключ кэша учитывает байты, MIME-тип и подпись | изменённые байты → другой ключ | `Expected: not '611afa70…' / Actual: '611afa70…'` | кэш зависел только от текста: подмена картинки возвращала старое число |
| R6 | exact: native отдельно, запас 3 % | `accuracy=exact`, `margin=30`, `budget=1030`, `native=1000` | `accuracy=estimated` | `RequestBudget` не разделял число провайдера и оценку |
| R7 | mixed: native + оценённая схема | `estimatedExtraTokens=300`, `margin=130`, `budget=1430` | `300 → 0` | добавка не моделировалась |
| R8 | без нативного подсчёта | `nativeInputTokens=null` | `6000` | «готовый» подсчёт подменял отсутствие числа |
| R9 | estimate остаётся estimate при `countedInputTokens` | запас 10 % (=200) | 60 (3 %) | флаг «точное» включался по факту любого числа, а не по составу |
| R10 | ошибка подсчёта → оценка | `nativeInputTokens=null` | 7471 | ошибка провайдера не отличалась от точного числа |
| R11 | Anthropic: изображения уходят в count_tokens | `attachments` счётчика = 1 | `[]` | конвейер не передавал части |
| R12 | кэш учитывает изменение байтов (pipeline) | 2 вызова счётчика | 1 | см. R5 |
| R13 | Gemini: native + schemaOverhead = mixed | `accuracy=estimated`, `estimatedExtraTokens=schemaTokens` | `accuracy=exact`, добавка 0 | `responseSchema` считался «нативно посчитанным» без подтверждения |
| R14 | ошибка подсчёта с изображением | `native=null` | 8128 | та же коллизия, что R10 |
| R15 | custom-аккаунт без `visionConfigured` | `capabilities.supportsVision == null` | `false` | неизвестность проецировалась в подтверждённое `false` |
| R16 | неизвестный Vision: изображения отправляются с предупреждением | план валиден (`isInvalid=false`), `imagesVisionUnconfirmed`, `imagesSentToModel=1` | `isInvalid=true` | план блокировался на неизвестности |
| R17 | неизвестный Vision: вложение не блокирует план | `isInvalid=false` | `true` | то же для пользовательских вложений |
| R18 | `max_request_bytes` в unknownFields | содержит `max_request_bytes` | `[context_window, max_output_tokens, supports_image_input, pricing]` | 32 МБ молча жили как «характеристика модели» |

После красной фазы реализация велась по слоям (домен → API → UI) и
зафиксирована зелёными коммитами `ee135b8` и `3f80f6d`; полный набор —
**2364 passed + 16 skipped** (см. `verify-7.18.3.md`).
