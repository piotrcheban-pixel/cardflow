# Итерация «Диагностика и фикс пайплайна генерации» — итог

**Дата:** 2026-11-26 · **Режим:** ИТЕРАЦИИ · **ADR:** ADR-048 ·
**Диагностика:** `journal/fix-generation/diagnosis.md`

## Причины (измерены, не гипотезы)

1. **Android release: в APK нет `android.permission.INTERNET`.**
   `aapt2 dump permissions app-release.apk` (сборка 1.0.1) показывал только
   `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`: `main`-манифест не объявлял
   INTERNET, а debug/profile-манифесты в release не попадают. Ни один сетевой
   запрос на Android в release не мог выполниться — генерация, поиск картинок
   и проверка ключа падали на первом же обращении.
2. **Production слал `gen-ru-v8`, а схема ответа и `systemPromptVersion` — v9.**
   `CardGenerationService`, `GenerationPlanBuilder` (оба метода),
   `GenerationRequestEstimator` и `count_tokens`-промпт в пайплайне остались на
   v8: модель не получала контракт сторон изображений (ADR-042). Тест
   «production: системный промпт по умолчанию — gen-ru-v8» закреплял ошибку.
3. **Общая строка «Не удалось получить карточки» скрывала инфраструктурный
   сбой.** В `generation_jobs` после 2026-11-22 нет ни одной неудачной попытки:
   сбой происходил до/на первой записи журнала. `jobRepository.save` начального
   задания стоял вне `try`, а репозиторий не оборачивал `SQLITE_READONLY`/
   `FileSystemException` — UI-catch `on Object` показывал общую строку.
4. **Строгий `response_format` DeepSeek отвергает штатно** (`400 this
   response_format type is unavailable now`), лестница ADR-021 переходит на
   запрос без схемы и получает валидный JSON — это не причина сбоя, но
   зафиксировано в диагностике.

## Что сделано

- `android/app/src/main/AndroidManifest.xml`: `INTERNET` + guard-тест
  `test/guards/android_manifest_internet_test.dart`; собранный APK проверен
  `aapt2` (разрешение присутствует).
- Production переведён на `gen-ru-v9` во всех точках (сервис, план, оценщик,
  `count_tokens`); `card_generation_service_test` сверяет v9 и блок сторон;
  `generation_plan_builder_test`/`generation_payload_bytes_test` — v9.
- `GenerationErrorCode.storageUnavailable` + `GenerationFailureReason.storage`:
  `DriftGenerationJobRepository.save/jobById`,
  `DriftGenerationCardStore.existingContentHashes` и пайплайн
  (`isStorageFailure`, `storage_failure.dart`) переводят сбои хранилища в
  доменный код; начальная запись задания — внутри `try`; UI-строки ARB
  `generationErrorStorageUnavailable`/`generationReasonStorage`; catch-all
  экранов показывает причину и пишет в debug-диагностику только тип исключения
  (`GenerationDiagnostics.unexpectedFailure`).
- Постоянный инструмент `tool/debug_generation.dart`: реальный запрос тем же
  промптом/параметрами (тема «трансформаторы», 10 карточек, лестница ADR-021),
  статус + сырое тело, разбор production-экстрактором и схемой; ключ только из
  env и не печатается.
- Live-тест `test/live/generation_pipeline_live_test.dart` (тег `live`, флаг
  `CARDFLOW_LIVE_TESTS=1`): production-пайплайн, тема «трансформаторы»,
  10 карточек, проверка карточек и версии промпта.

## Доказательства (выводы команд в сессии)

- `tool/debug_generation.dart`: strict `400` (194 Б) → без схемы `200`
  (9166 Б) → `РАЗБОР: cards=10 rejected=0 rootInvalid=false`.
- Полный production-граф с настоящей drift-БД (копия), кэшем характеристик,
  калибровкой и реальным поиском картинок: `status=done cards=10 failures=0
  tokens=12006`.
- Настоящий экран `GenerationScreen` на Windows (`integration_test`, реальный
  secure storage, копия БД, реальная сеть): генерация запускается, общая ошибка
  не воспроизводится (тем же кодом и ключом).
- Живой pipeline-тест: `LIVE pipeline: status=partial cards=9 failures=0
  tokens=18002 prompt=gen-ru-v9`.
- Новый APK: `√ Built app-release.apk`; `aapt2 dump permissions` →
  `uses-permission: name='android.permission.INTERNET'`.

## Гейты

`fvm flutter test --no-pub --coverage --exclude-tags golden` → **2745 passed +
17 skipped**; покрытие рукописного кода **90,9 % (23153/25476)**; `analyze` 0;
`dart format --set-exit-if-changed lib test tool` → 614/0;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (98,1 с);
`fvm flutter build apk --release --no-pub` → `app-release.apk` (101,3 МБ,
1.0.1+2). Схема БД, `schemaVersion` и `format_version` не менялись.

**Ограничения:** L206 (реальное Android-устройство после фикса INTERNET),
L207 (Windows-сбой не воспроизведён в среде агента — причина теперь видна
пользователю), L208 (`tool` требует ключ), L209 («Авто» без числа карточек
строит 383-карточный план).
