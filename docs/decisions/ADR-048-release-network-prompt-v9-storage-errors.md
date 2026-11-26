# ADR-048 — Release-сеть Android, production-промпт `gen-ru-v9` и ошибки локального хранилища

**Дата:** 2026-11-26 · **Итерация:** «Диагностика и фикс пайплайна генерации» ·
**Связано:** SPEC A8.5/A8.6, ADR-005, ADR-021, ADR-024, ADR-042, ADR-047

## Контекст

Owner-note: «Сломалась генерация карточек. И на Windows, и на Android вылетает
общая ошибка „Не удалось получить карточки. Попробуйте ещё раз“».
Диагностика (журнал `journal/fix-generation/diagnosis.md`) установила:

1. Реальный запрос production-путём с ключом владельца **работает**: DeepSeek
   отвечает 200, карточки разбираются и проходят схему A8.4; pipeline с
   настоящей drift-БД, кэшем характеристик и калибровкой даёт 10/10 карточек.
2. В `generation_jobs` **нет ни одной неудачной попытки** после 2026-11-22:
   сбой происходит до/на первой записи журнала либо на другой платформе.
3. Release-APK `app-release.apk` (1.0.1) **не содержит
   `android.permission.INTERNET`**: `main`-манифест не объявлял разрешение, а
   debug/profile-манифесты в release не попадают. Значит на Android release
   невозможен ни один сетевой запрос (генерация, поиск картинок, проверка
   ключа).
4. Пайплайн слал **`gen-ru-v8`**, хотя `systemPromptVersion` и схема ответа —
   `gen-ru-v9` (ADR-042): блок сторон изображений модель не получала.
5. Ошибки записи `generation_jobs` (например, `SQLITE_READONLY` — тот же класс
   сбоя, что в ADR-047) доходили до экрана произвольным исключением drift, и
   экран показывал общую строку. Причина терялась: `jobRepository.save` стоял
   вне защищённого участка пайплайна, а UI-catch `on Object` не имел доменного
   кода.

## Решение

### 1. `INTERNET` в release-манифесте Android

`android/app/src/main/AndroidManifest.xml` объявляет
`<uses-permission android:name="android.permission.INTERNET"/>`. Guard-тест
`test/guards/android_manifest_internet_test.dart` проверяет объявление в
`main`-манифесте (именно он собирается в release). Проверка артефакта —
`aapt2 dump permissions app-release.apk`.

### 2. Production шлёт `gen-ru-v9`

По умолчанию `gen-ru-v9` используют `CardGenerationService`,
`GenerationPlanBuilder` (материалы и prompt-only), `GenerationRequestEstimator`
и нативный `count_tokens` в `GenerationPipeline` — один и тот же текст в
бюджете плана и в запросе. `gen-ru-v8` остаётся константой и файлом для
истории. Живой прогон (10 карточек, тема «трансформаторы») подтвердил контракт
v9: модель возвращает `question_image_ids`/`answer_image_ids` и `image: null`
без искусственных запросов картинок.

### 3. Сбой локального хранилища — отдельный доменный код

- `GenerationErrorCode.storageUnavailable` +
  `GenerationFailureReason.storage` (`storage_unavailable`);
- `DriftGenerationJobRepository.save/jobById` и
  `DriftGenerationCardStore.existingContentHashes` оборачивают любые сбои
  drift/SQLite/ФС в `GenerationException(storageUnavailable)` (сырой текст — в
  `details`, без ключей и материалов);
- `GenerationPipeline` переводит сырые исключения хранилища в тот же код
  (`isStorageFailure` по маркерам ADR-047/`storage_failure.dart`), включая
  запись начального задания (перенесена внутрь защищённого участка) и чтение
  журнала при повторе;
- UI показывает причину из ARB
  (`generationErrorStorageUnavailable` — «хранилище недоступно: проверьте
  свободное место и права доступа…») вместо общей строки; catch-all
  использует `generationErrorMessage` и пишет в debug-диагностику только тип
  исключения (ADR-024, без секретов и текстов ответа);
- `storageUnavailable` — фатальный и неретраиваемый код: «Повторить
  неудавшиеся» не поможет, причина не в модели.

### 4. `tool/debug_generation.dart`

Постоянный диагностический инструмент: реальный запрос к DeepSeek тем же
промптом/параметрами (тема «трансформаторы», 10 карточек, strict-лестница
ADR-021), вывод статуса и сырого тела, затем разбор production-экстрактором и
схемой A8.4. Ключ — только из `DEEPSEEK_API_KEY`, значение не печатается.

### 5. HTTP 402 — отдельный код «нет баланса»

`_fromStatusCode` раньше отправлял 402 в общий `badRequest` с причиной
провайдера (например, «Insufficient Balance»). Добавлен
`GenerationErrorCode.insufficientBalance` → ARB «Недостаточно средств на
балансе провайдера. Проверьте баланс или ключ API». Код фатальный и не
повторяется: дальнейшие запросы при пустом балансе только тратят время.
401/403 остаются `invalidApiKey` («Ключ доступа недействителен…»).

## Последствия

- Android release снова может обращаться к сети; без разрешения генерация на
  телефоне принципиально невозможна.
- Промпт, схема и `generation_jobs.prompt_version` согласованы; оценки токенов
  считаются по тому же тексту, что уходит провайдеру.
- Пользователь видит причину сбоя локального хранилища; журнал задания
  сохраняет понятный код (`storage_unavailable`), debug-лог — тип исключения.
- Ограничение: сбой записи журнала теперь виден, но приложение по-прежнему не
  «самолечится» от запрета записи в каталог данных (L204 в силе).
