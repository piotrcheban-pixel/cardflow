# Пайплайн генерации карточек (SPEC A6.8, A8.5)

Документ описывает production-путь генерации от прикреплённых файлов (или темы
без файлов) до импортированных карточек. Решения — ADR-015; провайдеры —
ADR-011/012/013; адаптивное планирование — `docs/adaptive-generation-architecture.md`
(разделы D, Q), TASK 02B-FINAL.

## 1. Поток

```
файлы (picker / drag-n-drop) — необязательны (ADR-024)
  → изображения JPG/PNG и PDF-сканы: GenerationAttachment (Vision)
  → PDF-скан: первые ≤ 3 страницы → PNG (pdfrx + image, изолят), groupKey
  → FileParsingService (изолят, ParsedDocument, ошибки по файлу) + TextSanitizer
      → PDF: нечитаемый текстовый слой (U+FFFD/битая кодировка) → garbledText
  → GenerationRunRequest (документы, вложения, documentImages, тема/пожелания,
       requestedCards, аккаунт)
  → GenerationPlan (до первого запроса):
      GenerationPlanBuilder.inventoryOf → ContentInventory
      GenerationChunkPlanner.plan: бюджет D.1, семантическое дробление,
        изображения как единицы, D.5-укрупнение, лимиты D.7, предупреждения
      или PromptOnlyPlanner (тема без материалов, несколько запросов)
  → PlanValidity: invalid → ошибка ARB до сети; valid/warnings → выполнение
  → PlannedChunk → GenerationRequest (materialsText, wishes, limit,
      image-parts, каталог img1…, maxOutputTokens из плана)
  → CardGenerationService (ключ → Vision/PDF → адаптер → HTTP → схема A8.4 →
      контент-правила)
      → GenerationDiagnostics (debug): тело ошибки провайдера, сырой ответ модели
      → image_query/image_id → ImageSearchService/файл → GeneratedCard.image
  → восстановление: context overflow/413 → GenerationPlanSplitter по единицам;
      truncated → дробление/сокращение вывода; 429/auth — без дробления
  → generation_jobs (running → done | partial | error | cancelled)
  → GenerationRunResult (карточки + ошибки фрагментов + plan + токены + дубли)
  → экран предпросмотра (чекбоксы, редактирование, повтор упавших, картинка,
      предупреждение «запрошено/достижимо» и omitted)
  → GenerationCardStore.importGeneratedCards (одна транзакция, дедуп,
    MediaStore + media для иллюстраций, создание/дополнение колоды,
    generation_jobs.result_deck_id)
  → экран колоды
```

## 2. Слои и файлы

| Слой | Файл | Ответственность |
|---|---|---|
| домен | `lib/domain/generation/token_estimator.dart` | оценка токенов (≈2,5 символа/токен) |
| домен | `lib/domain/generation/generation_attachment.dart` | вложение (JPG/PNG/PDF-скан/страница PDF), MIME, сигнатуры, `groupKey` |
| домен | `lib/domain/generation/generation_card_image.dart` | иллюстрация из поиска (bytes, MIME, query, attribution) |
| домен | `lib/domain/generation/card_image_finder.dart` | порт поиска иллюстраций (реализация — `lib/api/images/`) |
| домен | `lib/domain/cards/occlusion.dart` | `occlusion_json` v1 и базовая маска по центру |
| домен | `lib/domain/text/text_sanitizer.dart` | управляющие символы, пустые строки, trim |
| домен | `lib/domain/generation/generation_budget.dart` | бюджет D.1: окно − вывод − обвязка − запас; трассировка источников |
| домен | `lib/domain/generation/generation_chunk_planner.dart` | планировщик: единицы, изображения, D.5-укрупнение, D.7-лимиты |
| домен | `lib/domain/generation/generation_plan.dart` | `GenerationPlan`/`PlannedChunk`/`UnitSpan`/`PlanValidity` |
| домен | `lib/domain/generation/prompt_only_planner.dart` | prompt-only план: тема без материалов, несколько запросов |
| домен | `lib/domain/generation/generation_plan_splitter.dart` | восстановление: дробление по единицам/страницам |
| домен | `lib/domain/generation/content_token_estimator.dart` | оценка единиц: текст и изображения с источником |
| домен | `lib/domain/generation/generation_chunker.dart` | совместимый фасад (`chunksFromPlan`), не production-путь |
| домен | `lib/domain/generation/generation_job.dart` | статусы и сущность задания, контракт репозитория |
| домен | `lib/domain/generation/generation_run.dart` | запрос/результат/прогресс/ошибки фрагмента |
| домен | `lib/domain/generation/document_gateway.dart` | контракт пикера документов |
| домен | `lib/domain/generation/generation_card_store.dart` | хеши колоды и импорт карточек |
| api | `lib/api/generation/generation_plan_builder.dart` | `ContentInventory` из документов/вложений + обвязка плана |
| api | `lib/api/generation/generation_pipeline.dart` | оркестрация плана: запросы, восстановление, поиск картинок, дедуп, job |
| api | `lib/api/parsers/pdf_scan_renderer.dart` | PDFium → PNG первых страниц скана (изолят) |
| api | `lib/api/parsers/pdf_text_quality.dart` | порог U+FFFD/UTF-8: нечитаемый текстовый слой PDF → `garbledText` |
| api | `lib/api/generation/generation_diagnostics.dart` | debug-only тело ошибки провайдера, сырой ответ модели, итог поиска картинки |
| api | `lib/api/images/image_search_service.dart` | Openverse: поиск, скачивание, JPEG/PNG, троттлинг |
| api | `lib/api/generation/generation_caller.dart` | узкий интерфейс вызова модели (реализует сервис 3b) |
| api | `lib/api/generation/generation_cancellation.dart` | отмена (обёртка Dio `CancelToken`) |
| data | `lib/data/generation/drift_generation_job_repository.dart` | `generation_jobs` (upsert/чтение) |
| data | `lib/data/generation/drift_generation_card_store.dart` | импорт в транзакции, дедуп, `basic_reversed` |
| data | `lib/data/generation/file_picker_document_gateway.dart` | `file_picker` 13.3.3 + лимит 25 МБ |
| ui | `lib/ui/generation/generation_screen.dart` | A6.8: файлы, пожелания, провайдер/модель, прогресс |
| ui | `lib/ui/generation/generation_preview_screen.dart` | предпросмотр, редактирование, импорт |
| ui | `lib/ui/generation/generation_*` | форматирование размера/токенов, сообщения ARB |

## 3. Бюджеты моделей

Единственный расчёт — `GenerationBudget.compute` (D.1):

```
outputCap   = caps.maxOutputTokens ?? min(config.defaultOutputCap (8192),
              contextWindow / 2, если окно известно)
reserved    = min(outputCap, limit × perCardOutput + jsonEnvelope)
fixed       = systemPrompt + schema + wrapper + catalog + imageTokens
safety      = известно окно ? max(256, 5 % окна) : не применяется
inputBudget = окно ? окно − reserved − fixed − safety
                   : config.unknownContextInputBudget (6000, assumption)
              затем min(maxInputTokens − fixed, bytes(maxRequestBytes))
```

Клампинга 2000 больше нет: нехватка — `PlanValidity.invalid(contextWindowTooSmall)`
до сети. Для 8k-моделей резерв вывода ограничен половиной окна, поэтому план не
резервирует 8192 в окне 8000. `512` остался только явным порогом минимально
рабочего бюджета (`GenerationBudgetConfig.minWorkableInputTokens`), а не
«молчаливым полом». Оценка обвязки умножается на число запросов в
`GenerationEstimate.totalTokens`.

Оценка до отправки (`GenerationRunResult.estimatedTokens`) — из плана; UI до
запуска показывает ориентировочную оценку тем же оценщиком единиц (без
«1000 токенов на изображение» и без зашитых 8 image-parts). Фактический расход —
из `usage` ответа.

## 4. Планирование фрагментов

- Единица — `TextPiece` раздела `ParsedDocument`; упаковка жадная по порядку до
  мягкой цели `limitTarget × tokensPerCardMaterial` (конфиг, не метаданные
  модели), жёсткий предел — `inputBudget`/`maxRequestBytes`.
- Иерархия дробления: раздел → абзац → предложение → строка → руна;
  жёсткое деление не рвёт суррогатную пару.
- Изображения — единицы содержимого: сохраняют `image_id`, привязку к
  разделу/странице; не вошедшие в image-parts остаются в каталоге
  (`catalogOnly`), всё, что не поместилось, — в `plan.omitted` с причиной.
- `<limit>` фрагмента — `budgetCardsPerRequestCap` из output budget и
  `maxCardsPerRequest`; универсального 20 нет.
- **D.5:** если фрагментов больше запрошенных карточек, соседние совместимые
  фрагменты укрупняются (сначала одного документа), с повторной проверкой
  бюджета/изображений/тела; порядок и `unitIds` сохраняются. Если укрупнить
  нельзя — безопасное число фрагментов и предупреждение `cardsAboveRequested`.
- **D.7:** распределение заказа без нулей: сумма = `min(requested, chunks × cap)`,
  каждый фрагмент ≥ 1; при невыполнимости — `requestedAbovePlan` и явные
  `requestedCards`/`achievableCards`.
- **Prompt-only:** нет материалов — `PromptOnlyPlanner` создаёт
  `ChunkKind.promptOnly` фрагменты с пустым `<materials>`; число запросов —
  `ceil(requested / cardsByOutputCap)`, сумма лимитов равна заказу, тема уходит
  в `<wishes>`. Фиктивных `ContentUnit`/`TextPiece` нет.
- Вложения (`GenerationAttachment`) — единицы по `groupKey`/страницам; сервис
  передаёт их image-частями при Vision. Число частей и байт — из возможностей
  аккаунта (`max_images_per_request`, `max_image_bytes`), иначе документированное
  допущение (8 частей / 10 МБ / 24 МБ); не вошедшие остаются в каталоге.
- **Восстановление:** `truncated` сначала дробит фрагмент по единицам (сумма
  лимитов детей = лимит родителя), если дробить нечего — сокращает ожидаемый
  вывод; `contextOverflow`/`payloadTooLarge` дробят только проблемный фрагмент;
  `rateLimited`/сеть/auth не дробят материалы. Глубина ≤ 3, бюджет восстановления
  ≤ 12 дополнительных запросов на запуск.

## 5. Ошибки

| Код | Поведение пайплайна | UI |
|---|---|---|
| `cancelled` | остановка, уже полученные карточки возвращаются | «Генерация отменена» |
| `truncated` | дробление по единицам/сокращение вывода; затем ошибка фрагмента | «Повторить неудавшиеся» |
| `contextOverflow` | дробление проблемного фрагмента; иначе ошибка фрагмента (не повторяется) | «Материала слишком много…» |
| `payloadTooLarge` | дробление/сокращение image-частей; иначе ошибка (не повторяется) | «Запрос слишком большой…» |
| `missingApiKey`, `providerNotConfigured`, `invalidApiKey` | fatal: остановка всего задания; если карточки уже получены — `partial` + `fatalErrorCode`, иначе исключение | переход в настройки / сообщение + предпросмотр |
| `rateLimited`, `serverUnavailable`, `timeout`, `network`, `emptyResponse`, `refused`, `invalidResponse`, `visionUnsupported`, `fileWithoutTextAndVision`, `pdfScanUnsupported`, `pdfScanVisionRequired`, `attachmentTooLarge` | ошибка фрагмента, остальные фрагменты продолжаются; `rateLimited`/auth не дробятся | частичный успех + повтор |
| `noMaterials` | генерация не начинается | «Нет материалов для генерации: прикрепите файл или напишите тему» |

`generation_jobs.error_code` — машинный код (имя `GenerationErrorCode`) или
`unexpected` при сбое инфраструктуры/БД; не текст. Причины фрагментов —
`GenerationFailureReason` (`json_parse`, `schema_invalid`, `truncated`,
`context_overflow`, `payload_too_large`, `unsupported_modality`, …).

**Текст PDF.** `PdfParser` санитизирует текст (C1-управляющие, BOM, zero-width, одиночные
суррогаты — `TextSanitizer`, итерация 7.10) и проверяет его `PdfTextQuality`: если замен
`U+FFFD` не меньше 5 и их доля строго больше 5 %, файл считается нечитаемым
(`ParserErrorCode.garbledText`, ARB «PDF содержит нечитаемый текст»). Раньше такой текст уходил
в запрос и провайдер отвечал 400 или мусором. Диагностика (ADR-024) пишет тело ошибки
провайдера и сырой ответ модели только в debug; для 400 UI показывает безопасную причину
(`providerReason`).

## 6. Дедупликация и импорт

- Хеш — `contentHashOf(front, back)` (нижний регистр, ё→е, сжатые пробелы, без пунктуации).
- Пайплайн исключает дубли между фрагментами и с существующими карточками целевой колоды; для
  `basic_reversed` учитываются оба направления.
- Импорт повторяет дедупликацию внутри транзакции; `basic_reversed` создаёт две строки с взаимными
  `sibling_id`; `state = new`, `content_hash` заполняется всегда.
- Иллюстрация (`GeneratedCard.image`) пишется в `MediaStore` (`media/<uuid>.jpg|png`) и строку
  `media` в той же транзакции; `cards.media_json = [media.id]`; `occlusion_json` сохраняется
  для occlusion. При откате транзакции записанные файлы удаляются (ADR-023 §3).
- Имя колоды: из поля; пусто — имя первого файла без расширения, иначе ARB «Сгенерированные карточки».
  Для существующей колоды имя не меняется.
- `generation_jobs.result_deck_id` и `cards_count` обновляются в транзакции импорта.

## 7. UI

- Маршруты: `/generate` (новая колода), `/decks/:deckId/generate` (дополнить колоду),
  `/generation/preview` (предпросмотр; результат передаётся через состояние экрана).
- Входы: Split-кнопка «Создать» на «Колодах» → «Сгенерировать карточки»; меню действий колоды на
  экране «Колода» → «Сгенерировать карточки».
- Зона прикрепления: `DropTarget` (`desktop_drop 0.8.4`) на ПК + `file_picker` на всех платформах;
  форматы A8.3 + изображения JPG/JPEG/PNG; PDF без текста (< 50 символов) показывается как
  «Скан — страницы отправятся как изображения», при сбое рендера — «Скан — отправится как
  изображение»; подпись и ошибки — только ARB. Перед запуском проверяются `supportsVision`
  (для страниц — `pdfScanVisionRequired`) и PDF-возможность протокола выбранного аккаунта
  (ADR-022/ADR-023).
- **Файлы необязательны (ADR-024):** без вложений генерация запускается по теме из поля
  пожеланий; без темы — ARB «Напишите тему или описание — файлы не обязательны». Оценка
  токенов показывается и для prompt-only. Если файлы приложены, но ни один не разобран и темы
  нет — прежнее «Ни один файл не удалось прочитать».
- Предпросмотр показывает найденную иллюстрацию, подпись «Изображение с маской» для occlusion
  и пометку «Нет изображения для карточки с маской»; картинка не редактируется (только
  front/back/чекбокс).
- **План в предпросмотре (TASK 02B-FINAL):** если план не может выдать весь заказ,
  показывается «Запрошено N карточек, план может выдать M…»; если укрупнить фрагменты
  не удалось и сумма лимитов больше заказа — предупреждение «план может выдать до M»;
  отброшенные единицы (`plan.omitted`) — отдельной строкой. Заказ не подменяется:
  `requestedCards` и `achievableCards` приходят из плана.
- Ключи OpenAI/Gemini/Anthropic — на экране «Настройки генерации» (блок «Ключи API»); «Проверить»
  (A6.6) — итерация 7, кнопка не рисуется.

## 8. Ограничения

- Оценка токенов эвристическая (2,5 симв./токен; изображения — размер/байты),
  без калибровки по `usage` (L122); реальные возможности провайдеров частично
  неизвестны — план помечает их `unknownFields` и использует документированные
  допущения.
- Пределы парсеров (страницы/области/изображения PDF, L-05…L-11) и усечение
  строк каталога (L-32/L-33) не менялись; числового поля «сколько карточек» в UI
  нет (L-44) — заказ читается из пожеланий без клампа.
- Живые вызовы OpenAI/Gemini/Anthropic не проверены (L1); DeepSeek success-путь —
  L30 (3b).
- Реальные файлы с устройств (L23), 25 МБ/OOM (L25), платформенный secure
  storage (L28), негативные HTTP-контракты (ADR-014) — известные ограничения.
- Реальный drag-n-drop на ОС (L33) — известное ограничение.
- `desktop_drop` 0.8.4 вместо 0.9.x — конфликт `cross_file` (L8,
  `docs/dependencies.md` §7).
- PDF-страницы рендерятся максимум 3 штуки (`PdfScanRenderer.maxPages`);
  Openverse-поиск зависит от доступности публичного API и анонимного лимита —
  при 429 карточка остаётся без картинки (L57), поиск ограничен бюджетом 90 с.
- Атрибуция CC-картинок не переносится в БД (в `media` нет метаданных);
  изображения используются локально (L58). Живые Vision-вызовы PDF-страниц у
  облачных провайдеров не проверялись (L52/L53 в силе).
