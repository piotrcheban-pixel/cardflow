# Пайплайн генерации карточек (SPEC A6.8, A8.5)

Документ описывает вертикальный срез итерации 3c «Экран генерации»: от прикреплённых файлов до
импортированных карточек. Решения — **ADR-015**; слой провайдеров — ADR-011/012/013.

## 1. Поток

```
файлы (picker / drag-n-drop) — необязательны (итерация 7.10, ADR-024)
  → изображения JPG/PNG и PDF-сканы: GenerationAttachment (Vision)
  → PDF-скан: первые ≤ 4 страницы → PNG (pdfrx + image, изолят), groupKey
  → FileParsingService (изолят, ParsedDocument, ошибки по файлу) + TextSanitizer
      → PDF: нечитаемый текстовый слой (U+FFFD/битая кодировка) → garbledText
  → нет файлов, есть тема в пожеланиях: один фрагмент с пустым <materials>
  → TokenEstimator + GenerationChunker (разделы, бюджет модели, <limit>, вложения/группы)
  → GenerationPipeline (последовательно, progress/cancel)
      → CardGenerationService (ключ → проверка Vision/PDF → адаптер → HTTP → схема A8.4 → контент-правила)
      → GenerationDiagnostics (debug): тело ошибки провайдера, сырой ответ модели
      → image_query → ImageSearchService (Openverse) → GeneratedCard.image
          (итог поиска — тоже в debug-диагностику)
      → occlusion без картинки → basic + пометка; с картинкой → базовая маска
      → generation_jobs (running → done | partial | error | cancelled)
  → GenerationRunResult (карточки + ошибки фрагментов + токены + дубли)
  → экран предпросмотра (чекбоксы, инлайн-редактирование, повтор упавших, картинка)
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
| домен | `lib/domain/generation/generation_model.dart` | каталог моделей и бюджет входа |
| домен | `lib/domain/generation/generation_chunker.dart` | нарезка по разделам/абзацам, `<limit>`, split-in-half, вложения |
| домен | `lib/domain/generation/generation_job.dart` | статусы и сущность задания, контракт репозитория |
| домен | `lib/domain/generation/generation_run.dart` | запрос/результат/прогресс/ошибки фрагмента |
| домен | `lib/domain/generation/document_gateway.dart` | контракт пикера документов |
| домен | `lib/domain/generation/generation_card_store.dart` | хеши колоды и импорт карточек |
| api | `lib/api/generation/generation_pipeline.dart` | оркестрация: оценка, чанкинг, вызовы, поиск картинок, дедуп, job |
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

`GenerationModel.contextTokens` — окно контекста. Бюджет входа фрагмента:

```
inputBudget = contextTokens − 8192 (ответ) − оценка(системный промпт + обёртка) − 512
inputBudget = max(inputBudget, 2000)
```

Для OpenAI-совместимого сервера (ADR-013) списка моделей нет: модель из `app_settings`, бюджет —
`16000` токенов (консервативно; локальные модели часто 8k–32k). Если модели нет в каталоге, бюджет
входа — `8000` токенов (`kFallbackInputTokenBudget`), без повторного вычитания резерва ответа.
Оценка до отправки — вход (материалы + системный промпт + обёртка); фактический расход — из `usage`
ответа (L34). При >100 000 входных токенов — предупреждение, но генерация не блокируется.

## 4. Чанкинг

- Единица — раздел `ParsedDocument` (`start/end`, заголовок).
- Соседние разделы склеиваются, пока оценка ≤ бюджета; между ними — пустая строка.
- Раздел больше бюджета: абзацы → строки → жёсткое деление по символам (запас 20 %).
- `<limit>` фрагмента — не больше 20 карточек (`kMaxCardsPerChunk`).
- **Prompt-only (ADR-024):** если файлов нет, а `<wishes>` задаёт тему, чанкер не даёт
  фрагментов — пайплайн создаёт один фрагмент с пустым `materialsText`; сервис шлёт пустой
  `<materials>` + `<wishes>`. Если темы нет — прежний `noMaterials` без сети. Оценка токенов
  учитывает системный промпт, обёртку и текст пожеланий.
- Вложения (`GenerationAttachment`) — отдельный фрагмент на файл: текст `materialsText` пуст,
  `images` содержит файл; оценка — `kImageTokenEstimate` (1000) на вложение. Смешивать
  изображение с текстом другого файла в MVP нельзя.
- Страницы одного PDF-скана имеют общий `groupKey` и идут **одним** фрагментом (несколько
  image parts); `generation_jobs.files` содержит имя PDF без дублей (ADR-023 §1).
- Если PDF-парсер извлёк < 50 символов (или `scannedPdf`), экран генерации рендерит первые
  ≤ 4 страницы в PNG; при сбое рендера — fallback на PDF-документ для Anthropic/Gemini.
- `image_query` из ответа модели разрешается после дедупликации: кэш по запросу, картинка
  кладётся в `GeneratedCard.image`; `occlusion` без картинки понижается до `basic`. Байты
  в `MediaStore` пишет импорт, а не пайплайн.
- `truncated` → `splitInHalf` один раз; фрагмент с вложением не дробится; повторное обрезание —
  ошибка фрагмента с повтором.

## 5. Ошибки

| Код | Поведение пайплайна | UI |
|---|---|---|
| `cancelled` | остановка, уже полученные карточки возвращаются | «Генерация отменена» |
| `truncated` | split-once; затем ошибка фрагмента | «Повторить неудавшиеся» |
| `missingApiKey`, `providerNotConfigured`, `invalidApiKey` | fatal: остановка всего задания; если карточки уже получены — `partial` + `fatalErrorCode`, иначе исключение | переход в настройки / сообщение + предпросмотр |
| `rateLimited`, `serverUnavailable`, `timeout`, `network`, `emptyResponse`, `refused`, `invalidResponse`, `visionUnsupported`, `fileWithoutTextAndVision`, `pdfScanUnsupported`, `pdfScanVisionRequired`, `attachmentTooLarge` | ошибка фрагмента, остальные фрагменты продолжаются | частичный успех + повтор |
| `noMaterials` | генерация не начинается | «Нет материалов для генерации: прикрепите файл или напишите тему» |

`generation_jobs.error_code` — машинный код (имя `GenerationErrorCode`) или `unexpected` при сбое
инфраструктуры/БД; не текст.

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
- Ключи OpenAI/Gemini/Anthropic — на экране «Настройки генерации» (блок «Ключи API»); «Проверить»
  (A6.6) — итерация 7, кнопка не рисуется.

## 8. Ограничения

- Оценка токенов эвристическая; фактический расход — из `usage` ответа.
- Живые вызовы OpenAI/Gemini/Anthropic не проверены (L1); DeepSeek success-путь — L30 (3b).
- Реальные файлы с устройств (L23), 25 МБ/OOM (L25), платформенный secure storage (L28),
  негативные HTTP-контракты (ADR-014) — известные ограничения.
- Реальный drag-n-drop на ОС (L33) и эвристическая оценка токенов (L34) — известные ограничения.
- `desktop_drop` 0.8.4 вместо 0.9.x — конфликт `cross_file` (L8, `docs/dependencies.md` §7).
- PDF-страницы рендерятся максимум 4 штук; Openverse-поиск зависит от доступности публичного
  API и анонимного лимита (~1 запрос/с) — при 429 карточка остаётся без картинки (L57). На хосте
  агента живой Openverse-запрос не завершается за 20 с (L61): производственная проводка проверена
  интеграционным тестом с реальным `ImageSearchService` и fake-Dio, debug-диагностика показывает
  причину отказа.
- Атрибуция CC-картинок не переносится в БД (в `media` нет метаданных); изображения
  используются локально (L58). Живые Vision-вызовы PDF-страниц у облачных провайдеров
  не проверялись (L52/L53 в силе).
