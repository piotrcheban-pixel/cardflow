# Итерация 3c — красная фаза (шаг 2)

**Дата:** 2026-11-14 · **HEAD:** `79c7e44` (docs: plan iteration 3c) · **Команда:**
`fvm flutter test test/unit/domain/generation test/unit/api/generation/generation_pipeline_test.dart test/unit/data/generation test/widget/generation --reporter compact`

**Итог красного прогона:** `Some tests failed` — новые тесты падают; часть уже прошла (чистые
`TokenEstimator`/каталог моделей/`GenerationJob`, поскольку это контракты, зафиксированные из SPEC).
Скелеты домена/API/данных компилируются; UI-скелеты компилируются и падают на отсутствующих элементах.
Фрагменты вывода (ожидалось / получено):

## UI — экран генерации

```
generation_screen_test.dart: рендер: заголовок, зона прикрепления, пожелания, кнопка [E]
Expected: exactly one matching candidate
  Actual: _KeyElementFinder:<zero widgets with key [<'generation-attach-zone'>] ...>
```
Ожидалось: зона прикрепления, подпись, пожелания, кнопка «Сгенерировать»; получено: скелет
`Scaffold` с одним заголовком.

```
generation_screen_test.dart: старт: запрос с документами и именем колоды из файла [E]
UnimplementedError: GenerationPipeline.run
```
Ожидалось: `runner.lastRequest` с документом `лекция.txt`, именем колоды `лекция`, провайдером
`openai`, `gpt-4o-mini`; получено: исключение скелета пайплайна.

```
generation_screen_test.dart: нет ключа: баннер и переход в настройки [E]
Expected: exactly one matching candidate
  Actual: ... zero widgets with text "Ключ доступа не задан"
```

## UI — предпросмотр

```
generation_preview_screen_test.dart: рендер: карточки, выбор, дубли и токены [E]
Expected: exactly one matching candidate
  Actual: ... zero widgets with text "Первый вопрос"
```
Ожидалось: карточки, счётчик «Выбрано: 2 из 2», дубли, токены, кнопки импорта; получено: пустой
`Scaffold`.

```
generation_preview_screen_test.dart: частичный успех: ошибки фрагментов и повтор [E]
Expected: exactly one matching candidate
  Actual: ... zero widgets with text "Не удалось обработать фрагменты"
```

## Пайплайн (API)

```
generation_pipeline_test.dart: успех: один фрагмент → карточки, токены, задание done [E]
UnimplementedError: GenerationPipeline.run
```
Ожидалось: `status = done`, 1 карточка, `tokensUsed = 30`, `chunkCount = 1`, сохранённое задание
`done` с `cardsCount = 1`; получено: `UnimplementedError`.

```
generation_pipeline_test.dart: fatal-ошибка invalidApiKey останавливает пайплайн и job = error [E]
UnimplementedError: GenerationPipeline.run
```
Ожидалось: один вызов модели, `job.status = error`, `errorCode = 'invalidApiKey'`.

```
generation_pipeline_test.dart: truncated: фрагмент делится пополам и повторяется один раз [E]
UnimplementedError: GenerationPipeline.run
```
Ожидалось: 2 вызова, второй текст — половина первого, `status = done`.

## Чанкер

```
generation_chunker_test.dart: маленький документ — один фрагмент, текст и файл сохранены [E]
Expected: an object with length of <1>
  Actual: []
```
Ожидалось: 1 фрагмент с текстом `Раздел 1`, `sourceFiles = ['лекция.txt']`; получено: пустой список.
Аналогично падают упаковка по бюджету, деление oversized-раздела, `splitInHalf`, `sourceFiles`.

## Данные

```
drift_generation_job_repository_test.dart: save → jobById: все поля задания [E]
UnimplementedError: DriftGenerationJobRepository.save
```
Ожидалось: сохранение/чтение `generation_jobs` (status, provider, model, prompt_version, files_json,
tokens_used, cards_count, chunk_count, result_deck_id); получено: `UnimplementedError`.

```
drift_generation_card_store_test.dart: импорт в новую колоду [E]
UnimplementedError: DriftGenerationJobRepository.save
```
Ожидалось: создание колоды, 2 строки карточек с `content_hash` и `state = new`, обновление задания;
получено: `UnimplementedError`.

## План зелёной фазы

1. Домен: чанкер (упаковка/oversized/splitInHalf) — до зелёного `test/unit/domain/generation`.
2. API: `GenerationPipeline` (job, progress/cancel, split-once, dedup, retry) — до зелёного
   `generation_pipeline_test.dart`.
3. Данные: job-репозиторий и импорт карточек — до зелёного `test/unit/data/generation`.
4. UI: экран генерации и предпросмотр — до зелёного `test/widget/generation`.
5. Проводка: провайдеры, роутер, входы, настройки ключей; интеграционный тест production-проводки.
