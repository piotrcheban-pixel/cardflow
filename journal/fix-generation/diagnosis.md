# Диагностика: «Не удалось получить карточки» на Windows и Android

**Дата:** 2026-11-26 · **Итерация:** «Диагностика и фикс пайплайна генерации» ·
**Ключ:** `DEEPSEEK_API_KEY` из User scope, значение не выводилось.

## 1. Фактические данные приложения (без гипотез)

Копия БД `%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite`
(`cardflow_diag.sqlite`, `PRAGMA integrity_check` → `ok`, `user_version` = 1).
Таблица `generation_jobs` (последние строки):

| created_at (UTC) | status | model | prompt | cards | error |
|---|---|---|---|---|---|
| 2026-11-22 10:37 | done | deepseek-flash | gen-ru-v9 | 40 | — |
| 2026-11-21 14:12 | done | deepseek-flash | gen-ru-v8 | 30 | — |
| 2026-11-17 19:37 | partial | deepseek-flash | gen-ru-v6 | 134 | truncated |
| 2026-11-17 19:35 | error | deepseek-flash | gen-ru-v4 | 0 | invalidResponse |

**Наблюдение:** после успешной генерации 2026-11-22 в журнале **нет ни одной
новой записи** — ни `running`, ни `error`. Значит текущий сбой происходит до
первой записи `generation_jobs` (или на другой платформе): последняя
«неудачная генерация» в БД относится к 2026-11-17 (`invalidResponse`, код
`gen-ru-v4`), а не к текущему owner-note.

Аккаунт (`app_settings`): `openai_compatible` → `https://api.deepseek.com`,
`deepseek-flash`, ключ в Windows secure storage присутствует (файл
`flutter_secure_storage.dat`, чтение через реальный плагин в integration-тесте
успешно). Кэш характеристик: контекст 1 048 576, вывод 393 216; калибровка
612 токенов/карточку.

## 2. Реальный запрос — production-промпт и параметры

`tool/debug_generation.dart` (`fvm dart run`, ключ из env; тема
«трансформаторы», 10 карточек, `max_tokens=8192`, strict-лестница ADR-021):

```
=== попытка: strict + max_tokens ===
POST https://api.deepseek.com/chat/completions
bytes=35981 max_tokens=8192
status=400 elapsed=757ms bytes=194
RAW BODY:
{"error":{"message":"This response_format type is unavailable now ...",
          "type":"invalid_request_error","code":"invalid_request_error"}}

=== попытка: без response_format + max_tokens ===
status=200 elapsed=10041ms bytes=9166
РАЗБОР: cards=10 rejected=0 rootInvalid=false
```

**Вывод по 400:** DeepSeek штатно не принимает `response_format: json_schema`;
лестница ADR-021 переходит на запрос без схемы и получает валидный JSON.
Это не сбой и не требует правки формата схемы.

Прогон полного production-пайплайна (реальный `GenerationPipeline` +
`CardGenerationService` + HTTP, in-memory журнал) на тех же данных:

```
план: стратегия=promptOnly, частей=1, партий=2, заказ=10, достижимо=10
РЕЗУЛЬТАТ: status=done cards=10 failures=0 tokens=16607
```

Прогон с настоящей drift-БД (копия), `DriftGenerationJobRepository`,
`MediaStore`, кэшем характеристик, калибровкой и **реальным поиском картинок**:

```
РЕЗУЛЬТАТ: status=done cards=10 failures=0 tokens=12006 за 50,7 с
job row: done cards=10 error=null prompt=gen-ru-v9
```

Отдельно проверен «настоящий» экран `GenerationScreen` (Windows
`integration_test`, реальный secure storage, копия БД, реальная сеть): экран
загружает провайдера, принимает тему и запускает генерацию; общая ошибка не
воспроизводится. Побочное наблюдение: «Авто» без числа карточек строит план на
383 карточки (10 партий), поэтому прогон долгий — это поведение 7.20/ADR-043,
а не сбой.

## 3. Причина Android release: в APK нет `INTERNET`

`aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk`
(артефакт 1.0.1, 2026-11-25):

```
package: ru.example.cardflow
permission: ru.example.cardflow.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='ru.example.cardflow.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

`android.permission.INTERNET` **отсутствует**. `main`-манифест не объявлял его
никогда (проверено `git log -S`), а `debug`/`profile`-манифесты, где он есть,
в release-сборку не попадают. Без разрешения `SocketException` возникает на
любом запросе: генерация в release-APK не может работать в принципе.

## 4. Причина общей строки вместо причины

`generationErrorGeneric` («Не удалось получить карточки. Попробуйте ещё
раз») показывается только в `on Object`-ветках (`generation_screen.dart`,
`generation_preview_screen.dart`). Все ответы модели и HTTP имеют доменные
коды (`GenerationException`), поэтому общая строка указывает на
инфраструктурный сбой. Наиболее вероятный из них на Windows — отказ записи
`generation_jobs` (`SQLITE_READONLY`; тот же класс, что ADR-047): в этом случае
журнал не получает записи, что и наблюдается в БД. `jobRepository.save`
начального задания стоял **вне** `try` пайплайна, а репозиторий не оборачивал
исключение drift — UI не мог показать причину.

## 5. Дополнительно найденное: production слал `gen-ru-v8` при схеме v9

`CardGenerationService.systemPrompt`, `GenerationPlanBuilder` (оба метода),
`GenerationRequestEstimator` и `count_tokens`-промпт в пайплайне по умолчанию
использовали `gen-ru-v8`, а `systemPromptVersion` и схема ответа — `gen-ru-v9`.
Модель не получала контракт сторон изображений (`question_image_ids` /
`answer_image_ids` / `image.side`) и возвращала legacy-поля v5–v8. Тест
`card_generation_service_test` это «закреплял» ожиданием v8.

## 6. Что сделано

- `INTERNET` в `main`-манифесте + guard-тест; проверка собранного APK.
- Production переведён на `gen-ru-v9` во всех точках (сервис, план, оценщик,
  count_tokens); живые прогоны — 10/10 карточек с полями v9.
- `GenerationErrorCode.storageUnavailable` + `GenerationFailureReason.storage`:
  сбои drift/SQLite/ФС из репозиториев и пайплайна доходят до UI конкретной
  причиной; debug-диагностика пишет только тип исключения.
- `tool/debug_generation.dart` — постоянный инструмент диагностики (ключ из
  env, без печати значения).
- Live-тест пайплайна `test/live/generation_pipeline_live_test.dart`
  (тег `live`, только по `CARDFLOW_LIVE_TESTS=1`).
