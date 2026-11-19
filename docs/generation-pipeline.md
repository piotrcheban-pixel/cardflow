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
      или GenerationPlanBuilder.buildPromptOnly → PromptOnlyPlanner
        (обвязка считается тем же builder-ом; резерв сводки продолжения)
  → PlanValidity: invalid → ошибка ARB до сети; valid/warnings → выполнение
  → PlannedChunk → GenerationRequest (materialsText, wishes, limit,
      documentImageParts = префикс каталога, continuation, maxOutputTokens)
  → CardGenerationService (ключ → Vision/PDF → адаптер → HTTP → схема A8.4 →
      контент-правила; оценка собранного запроса тем же оценщиком)
      → GenerationDiagnostics (debug): тело ошибки провайдера, сырой ответ модели
      → image_query/image_id → ImageSearchService/файл → GeneratedCard.image
      → TokenCalibrationSample (план vs запрос vs usage)
  → восстановление: truncated → лимит → резерв вывода → дробление;
      context overflow/413 → GenerationPlanSplitter по единицам;
      429/auth/сеть — без дробления; Retry-After сохраняется в сбое
  → generation_jobs (running → done | partial | error | cancelled)
  → GenerationRunResult (карточки + ошибки фрагментов + plan + токены + дубли +
      calibration + recovery + sentDocumentImageIds)
  → экран предпросмотра (чекбоксы, редактирование, повтор упавших, картинка,
      предупреждение «запрошено/достижимо», изображения по статусам,
      частичный успех/fatal)
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
| домен | `lib/domain/generation/token_accounting.dart` | `TokenValue` (exact/estimate/reserve/unknown), калибровка по `usage` |
| домен | `lib/domain/generation/generation_continuity.dart` | компактная сводка prompt-only: покрытые темы/вопросы, бюджет 1200 токенов |
| домен | `lib/domain/generation/generation_request_limits.dart` | лимиты image-частей/байт/тела с источником (user/preset/assumption) |
| домен | `lib/domain/generation/generation_recovery_budget.dart` | бюджет восстановления: max(12, fragments/8), cap 64 |
| api | `lib/api/generation/generation_request_estimator.dart` | оценка фактически собранного запроса тем же оценщиком |
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
запуска строит предпросмотр плана тем же `GenerationPlanBuilder` и показывает
«фрагментов/запросов/запрошено/достижимо». Перед отправкой сервис оценивает
**фактически собранный** `userContent` тем же `ContentTokenEstimator`
(`GenerationRequestEstimator`): системный промпт, каноническая схема, материалы,
пожелания, каталог, сводка продолжения и image-части. Оценка сохраняется в
`GenerationResult.estimatedInputTokens` и сравнивается с `usage` провайдера
(`TokenCalibrationReport`): `estimate`/`reserve`/`exact`/`unknown` не
смешиваются, отсутствие `usage` фиксируется явно. Факт одного запроса не
используется как гарантия для другого.

`promptOnly`-план дополнительно резервирует `continuationReserveTokens` на
сводку уже созданных карточек (1200 токенов на запрос после первого) и учитывает
её байты в проверке тела; без резерва продолжение могло вывести план за окно.

## 4. Планирование фрагментов

- Единица — `TextPiece` раздела `ParsedDocument`; упаковка жадная по порядку до
  мягкой цели. Мягкая цель подстраивается под заказ: при заказе больше
  `outputCap` карточек на запрос целевое число фрагментов
  `ceil(requested/outputCap)`, цель — 80 % среднего объёма материала на
  фрагмент, но не ниже 512 токенов (`minSoftTargetMaterialTokens`). Это не даёт
  скрыто занизить `achievableCards`, когда материала хватает.
- Иерархия дробления: раздел → абзац → предложение → строка → руна;
  жёсткое деление не рвёт суррогатную пару; жёсткий предел —
  `inputBudget`/`maxRequestBytes`.
- Изображения — единицы содержимого: сохраняют `image_id`, привязку к
  разделу/странице; не вошедшие в image-части остаются в каталоге
  (`catalogOnly`), всё, что не поместилось, — в `plan.omitted` с причиной.
  `plan.images` хранит статус каждого изображения: `sentToModel`, `catalogOnly`,
  `unsupportedModel`, `omittedBudget/omittedPayload`. Одинаковые байты не
  отправляются частями дважды (SHA-256), второе изображение остаётся каталогу.
- Запрос получает `documentImageParts` — **префикс** `documentImages`; сервис
  отправляет ровно его (без повторного отбора/переранжирования), каталог
  остаётся полным. Легаси-вызов без явных частей сохраняет старый отбор.
- `<limit>` фрагмента — `budgetCardsPerRequestCap` из output budget и
  `maxCardsPerRequest`; универсального 20 нет.
- **D.5:** если фрагментов больше запрошенных карточек, соседние совместимые
  фрагменты укрупняются (сначала одного документа), с повторной проверкой
  бюджета/изображений/тела; порядок и `unitIds` сохраняются. Если укрупнить
  нельзя — безопасное число фрагментов и предупреждение `cardsAboveRequested`.
- **D.7:** распределение заказа без нулей: сумма = `min(requested, chunks × cap)`,
  каждый фрагмент ≥ 1; при невыполнимости — `requestedAbovePlan` и явные
  `requestedCards`/`achievableCards`.
- **Prompt-only:** нет материалов — `GenerationPlanBuilder.buildPromptOnly`
  (внутри `PromptOnlyPlanner`) создаёт `ChunkKind.promptOnly` фрагменты с пустым
  `<materials>`; число запросов — `ceil(requested / cardsByOutputCap)`, сумма
  лимитов равна заказу, тема уходит в `<wishes>`. Обвязка (системный промпт,
  схема, обёртка) считается тем же builder-ом, что и для материалов; на каждый
  запрос после первого резервируется компактная сводка уже созданных карточек
  (`GenerationContinuityState`, 1200 токенов). Сводка добавляется после
  исходных пожеланий, не переписывая их. Фиктивных `ContentUnit`/`TextPiece` нет.
- Вложения (`GenerationAttachment`) — единицы по `groupKey`/страницам; сервис
  передаёт их image-частями при Vision. Число частей и байт — из возможностей
  аккаунта (`max_images_per_request`, `max_image_bytes`, `max_request_bytes`),
  иначе документированное допущение (8 частей / 10 МБ / 24 МБ / 32 МБ) с
  источником `unknown` в `unknownFields`/`assumptionFields`; не вошедшие
  остаются в каталоге.
- **Восстановление:** `truncated` сначала уменьшает ожидаемый вывод, затем
  поднимает резерв до `outputCap`, затем дробит по единицам; при `limit == 1`
  последняя попытка делит на две части по 1 карточке. `contextOverflow`/
  `payloadTooLarge` дробят только проблемный фрагмент; `rateLimited`/сеть/auth
  не дробят материалы, `Retry-After` переносится в сбой. Глубина ≤ 3, бюджет —
  `max(configured, fragments/8)` до 64 дополнительных запросов; исчерпание
  видно в результате.

## 5. Ошибки

| Код | Поведение пайплайна | UI |
|---|---|---|
| `cancelled` | остановка, уже полученные карточки возвращаются | «Генерация отменена» |
| `truncated` | уменьшение лимита → подъём резерва → дробление по единицам; затем ошибка фрагмента | «Повторить неудавшиеся» |
| `contextOverflow` | дробление проблемного фрагмента (при `limit == 1` — последняя попытка с двумя частями по 1); иначе ошибка фрагмента (не повторяется) | «Материала слишком много…» |
| `payloadTooLarge` | дробление/сокращение image-частей (последняя попытка с `limit == 1`); иначе ошибка (не повторяется) | «Запрос слишком большой…» |
| `missingApiKey`, `providerNotConfigured`, `invalidApiKey` | fatal: остановка всего задания; если карточки уже получены — `partial` + `fatalErrorCode`, иначе исключение | переход в настройки / сообщение + предпросмотр |
| `rateLimited`, `serverUnavailable`, `timeout`, `network`, `emptyResponse`, `refused`, `invalidResponse`, `visionUnsupported`, `fileWithoutTextAndVision`, `pdfScanUnsupported`, `pdfScanVisionRequired`, `attachmentTooLarge` | ошибка фрагмента, остальные фрагменты продолжаются; `rateLimited`/auth не дробятся; `Retry-After` (если был) — в сбое фрагмента | частичный успех + повтор (+ «повторите через N с») |
| `noMaterials` | генерация не начинается | «Нет материалов для генерации: прикрепите файл или напишите тему» |

`generation_jobs.error_code` — машинный код (имя `GenerationErrorCode`) или
`unexpected` при сбое инфраструктуры/БД; не текст. Причины фрагментов —
`GenerationFailureReason` (`json_parse`, `schema_invalid`, `truncated`,
`context_overflow`, `payload_too_large`, `unsupported_modality`, …).

**Разбор тела ответа (TASK 04).** Транспорт запрашивает `ResponseType.plain` и
разбирает JSON сам (`_decodeJsonObject`): битый JSON провайдера — это
`invalidResponse`, а не `network`. До этого Dio с `ContentType: application/json`
падал в трансформере до создания ответа, ошибка классифицировалась как сетевая и
**повторялась** (до 4 попыток) — то есть битый ответ стоил денег. 404
«модель не найдена» отдельного кода не имеет: это `badRequest` с очищенной
причиной провайдера (L140).

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
- **План в предпросмотре (TASK 02B-FINAL/TASK 03):** если план не может выдать весь заказ,
  показывается «Запрошено N карточек, план может выдать M…»; если укрупнить фрагменты
  не удалось и сумма лимитов больше заказа — предупреждение «план может выдать до M»;
  отброшенные единицы (`plan.omitted`) — отдельной строкой. Заказ не подменяется:
  `requestedCards` и `achievableCards` приходят из плана. Дополнительно до запуска
  показываются фрагменты/запросы, неизвестные возможности модели, допущения по
  лимитам изображений, изображения без поддержки модели и только в каталоге;
  невалидный план блокирует запуск с причиной.
- **Количество карточек (TASK 03, L132):** числовое поле «Сколько карточек» с
  валидацией положительного целого (технический предел `int`, не 20/200);
  значение передаётся в `GenerationRunRequest.requestedCards` и имеет приоритет
  над разбором пожеланий. Пустое поле — прежний разбор.
- **Частичный успех/fatal (TASK 03):** предпросмотр показывает постоянный баннер
  «Частичный результат: обработано K, с ошибкой L» и «Генерация остановлена: …»
  (fatal с уже полученными карточками), а не только краткое сообщение на
  предыдущем экране.
- **Изображения (TASK 03):** строка «передано модели / только в каталоге / без
  поддержки изображений / исключено» строится из `GenerationPlan.images`;
  «осталось в каталоге» не выдаётся за «модель видела». `Retry-After` — в
  причине фрагмента. Восстановление показывает число дополнительных запросов.
- Ключи OpenAI/Gemini/Anthropic — на экране «Настройки генерации» (блок «Ключи API»); «Проверить»
  (A6.6) — итерация 7, кнопка не рисуется.

## 8. Ограничения

- Оценка токенов остаётся эвристикой (2,5 симв./токен; изображения —
  размер/байты), без точного токенизатора; TASK 03 добавил единый механизм
  оценки и калибровку `estimated*` vs `usage`, но не точность формулы
  (L122). `usage` обрезанного/невалидного ответа адаптеры не возвращают —
  такие запросы учитываются как «без usage» (L135).
- Реальные возможности провайдеров частично неизвестны — план помечает их
  `unknownFields`/`capabilitySources` и использует документированные допущения
  (8 image-частей, 10/24/32 МБ) только при отсутствии значения аккаунта (L133).
- Prompt-only continuity — компактная сводка (до 1200 токенов), а не полный
  контекст предыдущих ответов: модель может повторить факт, не попавший в
  сводку; семантического дедупа нет (L130 частично).
- Пределы парсеров (страницы/области/изображения PDF, L-05…L-11) и усечение
  строк каталога (L-32/L-33) не менялись; отброшенные парсером изображения
  план не видит (L134).
- Бюджет восстановления — предохранитель `max(12, fragments/8)` до 64; при
  массовых переполнениях часть фрагментов остаётся с ошибкой, успешные
  сохраняются (L128).
- Живые вызовы OpenAI/Gemini/Anthropic не проверены (L1); DeepSeek success-путь —
  L30 (3b).
- Реальные файлы с устройств (L23), 25 МБ/OOM (L25), платформенный secure
  storage (L28), негативные HTTP-контракты (ADR-014) — известные ограничения.
- Реальный drag-n-drop на ОС (L33) — известное ограничение.
- `desktop_drop` 0.8.4 вместо 0.9.x — конфликт `cross_file` (L8,
  `docs/dependencies.md` §7).
- PDF-страницы рендерятся максимум 3 штуки (`PdfScanRenderer.maxPages`);
  поиск иллюстраций зависит от доступности публичных API и анонимного лимита —
  при 429 карточка остаётся без картинки (L57), поиск ограничен бюджетом 90 с.
- Атрибуция CC-картинок не переносится в БД (в `media` нет метаданных);
  изображения используются локально (L58). Живые Vision-вызовы PDF-страниц у
  облачных провайдеров не проверялись (L52/L53 в силе).

## 9. Управляемые испытания на реальных API (TASK 04)

Платные запросы **не** входят в обычный прогон и в CI. Инфраструктура —
`test/live/support/`, управляемый набор — `test/live/adaptive_generation_live_test.dart`.

- **По умолчанию запросы запрещены:** тег `live` + `CARDFLOW_LIVE_TESTS=1`;
  без него тесты пропускаются даже при наличии ключа. `maxRequests=0` и
  `maxCost=0` по умолчанию — запуск невозможен. `CARDFLOW_LIVE_SCENARIOS`
  (id через запятую) дополнительно ограничивает набор: C и D делят флаг
  `_ENABLE_MATERIALS`, поэтому для A–C список обязателен.
- **Параметры:** `CARDFLOW_LIVE_PROVIDER`/`_MODEL`/`_BASE_URL`, `_MAX_REQUESTS`,
  `_MAX_COST_USD`, `_ALLOW_UNKNOWN_COST`, `_TIMEOUT_SEC`,
  `_ENABLE_PROMPT_ONLY`/`_MATERIALS`/`_IMAGES`/`_RECOVERY`, `_VISION`, `_REPORT`.
  Отсутствие ключа (`DEEPSEEK_API_KEY`, `OPENAI_API_KEY`, …) — безопасный skip.
- **Бюджет (TASK 05):** `LiveRecordingCaller` + `LiveRequestBudget` считают
  **логические** запросы (`GenerationCaller.generate`, включая recovery);
  `LiveProbeTransport` + отдельный `LiveRequestBudget` — HTTP-обмены
  (`postJson`, включая strict → tolerant); `LiveAttemptLimiter` — физические
  попытки (включая повторы 429/5xx). Бюджеты можно сделать общими на файл —
  тогда A+B+C делят один лимит, а не получают по копии на тест.
- **Стоимость (TASK 05):** тарифы только с официальных страниц, с URL и датой
  проверки (`test/live/support/live_pricing.dart`). Неизвестный тариф → `null`
  и блокировка автоматического запуска; ноль вместо неизвестности не
  подставляется. `LiveCostGuard` в `LiveAttemptLimiter` резервирует
  предварительную оценку **каждой физической попытки** до отправки и
  засчитывает факт из `usage` после ответа; strict-400 освобождает резерв;
  превышение `CARDFLOW_LIVE_MAX_COST_USD` блокирует запрос до отправки.
- **Отчёт:** `LiveRunRecord` (JSON Lines, `build/live/live-runs.jsonl`) —
  провайдер, модель, версия оценщика, `logicalRequests`/`httpRequests`/
  `httpAttempts`/`retries`/`recoveryRequests`, оценки/факты токенов, цены и
  `estimatedCostUsd`/`actualCostUsd`, per-request `requestCosts[]`, байты
  тела, число изображений, latency, статус. Отсутствующие поля — `null`;
  материалы и ключи в отчёт не попадают; `note` редактируется.
- **Каталог DeepSeek (TASK 05):** `deepseek-flash` (1M, Vision) — модель по
  умолчанию; `deepseek-v4-pro` (1M, без Vision); legacy `deepseek-chat`/
  `deepseek-reasoner` оставлены для сохранённых аккаунтов (в актуальной
  документации DeepSeek их нет — L137).
- **Test F без оплаты:** локальный endpoint (`local_provider_server.dart`)
  проверяет на реальном сокете 413, 429 + `Retry-After`, таймаут, context
  overflow, битый JSON, `truncated`, 5xx, 401 — обычным офлайновым тестом
  `test/integration/generation_recovery_http_test.dart`.
- **Ограничения:** `journal/KNOWN_LIMITATIONS.md` L137–L142 (актуальные id
  DeepSeek добавлены, но legacy-имена сохранены и в документации
  отсутствуют; неизвестные тарифы остальных моделей; отсутствие
  `modelNotFound`; непроверенные живые негативные контракты; тарификация
  strict-400/повторов не подтверждена).
