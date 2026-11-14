# Пайплайн генерации карточек (SPEC A6.8, A8.5)

Документ описывает вертикальный срез итерации 3c «Экран генерации»: от прикреплённых файлов до
импортированных карточек. Решения — **ADR-015**; слой провайдеров — ADR-011/012/013.

## 1. Поток

```
файлы (picker / drag-n-drop)
  → FileParsingService (изолят, ParsedDocument, ошибки по файлу)
  → TokenEstimator + GenerationChunker (разделы, бюджет модели, <limit>)
  → GenerationPipeline (последовательно, progress/cancel)
      → CardGenerationService (ключ → адаптер → HTTP → схема A8.4 → контент-правила)
      → generation_jobs (running → done | partial | error | cancelled)
  → GenerationRunResult (карточки + ошибки фрагментов + токены + дубли)
  → экран предпросмотра (чекбоксы, инлайн-редактирование, повтор упавших)
  → GenerationCardStore.importGeneratedCards (одна транзакция, дедуп,
    создание/дополнение колоды, generation_jobs.result_deck_id)
  → экран колоды
```

## 2. Слои и файлы

| Слой | Файл | Ответственность |
|---|---|---|
| домен | `lib/domain/generation/token_estimator.dart` | оценка токенов (≈2,5 символа/токен) |
| домен | `lib/domain/generation/generation_model.dart` | каталог моделей и бюджет входа |
| домен | `lib/domain/generation/generation_chunker.dart` | нарезка по разделам/абзацам, `<limit>`, split-in-half |
| домен | `lib/domain/generation/generation_job.dart` | статусы и сущность задания, контракт репозитория |
| домен | `lib/domain/generation/generation_run.dart` | запрос/результат/прогресс/ошибки фрагмента |
| домен | `lib/domain/generation/document_gateway.dart` | контракт пикера документов |
| домен | `lib/domain/generation/generation_card_store.dart` | хеши колоды и импорт карточек |
| api | `lib/api/generation/generation_pipeline.dart` | оркестрация: оценка, чанкинг, вызовы, дедуп, job |
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
- `truncated` → `splitInHalf` один раз; повторное обрезание — ошибка фрагмента с повтором.

## 5. Ошибки

| Код | Поведение пайплайна | UI |
|---|---|---|
| `cancelled` | остановка, уже полученные карточки возвращаются | «Генерация отменена» |
| `truncated` | split-once; затем ошибка фрагмента | «Повторить неудавшиеся» |
| `missingApiKey`, `providerNotConfigured`, `invalidApiKey` | fatal: остановка всего задания; если карточки уже получены — `partial` + `fatalErrorCode`, иначе исключение | переход в настройки / сообщение + предпросмотр |
| `rateLimited`, `serverUnavailable`, `timeout`, `network`, `emptyResponse`, `refused`, `invalidResponse` | ошибка фрагмента, остальные фрагменты продолжаются | частичный успех + повтор |
| `noMaterials` | генерация не начинается | «Нет текста для генерации…» |

`generation_jobs.error_code` — машинный код (имя `GenerationErrorCode`) или `unexpected` при сбое
инфраструктуры/БД; не текст.

## 6. Дедупликация и импорт

- Хеш — `contentHashOf(front, back)` (нижний регистр, ё→е, сжатые пробелы, без пунктуации).
- Пайплайн исключает дубли между фрагментами и с существующими карточками целевой колоды; для
  `basic_reversed` учитываются оба направления.
- Импорт повторяет дедупликацию внутри транзакции; `basic_reversed` создаёт две строки с взаимными
  `sibling_id`; `state = new`, `content_hash` заполняется всегда.
- Имя колоды: из поля; пусто — имя первого файла без расширения, иначе ARB «Сгенерированные карточки».
  Для существующей колоды имя не меняется.
- `generation_jobs.result_deck_id` и `cards_count` обновляются в транзакции импорта.

## 7. UI

- Маршруты: `/generate` (новая колода), `/decks/:deckId/generate` (дополнить колоду),
  `/generation/preview` (предпросмотр; результат передаётся через состояние экрана).
- Входы: Split-кнопка «Создать» на «Колодах» → «Сгенерировать карточки»; меню действий колоды на
  экране «Колода» → «Сгенерировать карточки».
- Зона прикрепления: `DropTarget` (`desktop_drop 0.8.4`) на ПК + `file_picker` на всех платформах;
  форматы A8.3; подпись и ошибки — только ARB.
- Ключи OpenAI/Gemini/Anthropic — на экране «Настройки генерации» (блок «Ключи API»); «Проверить»
  (A6.6) — итерация 7, кнопка не рисуется.

## 8. Ограничения

- Оценка токенов эвристическая; фактический расход — из `usage` ответа.
- Живые вызовы OpenAI/Gemini/Anthropic не проверены (L1); DeepSeek success-путь — L30 (3b).
- Реальные файлы с устройств (L23), 25 МБ/OOM (L25), платформенный secure storage (L28),
  негативные HTTP-контракты (ADR-014) — известные ограничения.
- Реальный drag-n-drop на ОС (L33) и эвристическая оценка токенов (L34) — известные ограничения.
- `desktop_drop` 0.8.4 вместо 0.9.x — конфликт `cross_file` (L8, `docs/dependencies.md` §7).
