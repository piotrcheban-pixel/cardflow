# STATE — текущее состояние CardFlow

## TASK 04 — импорт файлов, генерация, изображения, производительность (2026-11-27)

**Дата:** 2026-11-27 · **Итерация:** TASK 04 «Исправление импорта файлов,
генерации, изображений и производительности». Документы —
`journal/task04/import-audit/{audit.md,report.md}`, ADR-049
(`docs/decisions/ADR-049-file-import-and-truncated-response.md`). Прежние
документы TASK 04 (мобильный UX/UI) не перезаписывались.

**Старт:** ветка `main`, `HEAD = ddfdde0`, `git status` — только прежние
неотслеживаемые каталоги аудитов (`audit/`, `review_visual/`, …).
**Baseline:** `fvm flutter test --no-pub --exclude-tags golden` →
**2750 passed + 17 skipped**, `exit 0`.

**Первопричины (измерены по исходникам зависимостей и коду):**
1. **PDF на Android.** `PdfParser`/`PdfScanRenderer`/`PdfImageExtractor`
   вызывали `pdfrxInitialize()` без `tmpPath`; в `pdfrx_engine 0.9.1`
   не-Windows-ветка читает `Platform.environment['HOME']!`. В Android-процессе
   `HOME` не задан → `null check` **до** открытия документа →
   `unreadableFile` («Не удалось прочитать файл»). На Windows ветка
   `LOCALAPPDATA`, поэтому ни локально, ни в CI дефект не воспроизводился.
   Проверено по `android_file_picker 2.1.5`: выбранный файл уже копируется в
   кэш, `content://` до парсера не доходит — гипотеза о `content://` как
   первопричине не подтвердилась (устойчивости всё равно не было: URI без
   пути/ошибка чтения роняли весь выбор).
2. **Форматы.** `.ppt` отсутствовал в `DocumentFormat`; `.doc`/`.xls` давали
   общее «формат не поддерживается»; на Android MIME-фильтр `FileType.custom`
   скрывал `.md`/`.rtf`; ошибка пикера показывалась общей строкой.
3. **«Запрошено 50, получено 32».** Обрыв ответа по лимиту вывода
   (`finish_reason: length`/`MAX_TOKENS`/`max_tokens`) адаптер превращал в
   `GenerationException(truncated)` **до** разбора тела — все уже полученные
   карточки фрагмента выбрасывались, восстановление дробило лимит заново, а
   причина недобора не доходила до UI.
4. **Картинки.** Поиск был best effort, но исключение при разрешении
   изображений вне `findImage` могло выйти из цикла партии и оборвать запуск.
5. **Лента.** `FeedCardView` уменьшал фото (`max(96, min(160, h·0,24))`) против
   классики (`max(140, h·0,42)`); «рядом с текстом» включалось по ширине окна,
   а не карточки.
6. **Лаги.** `AnimatedBuilder` перестраивал всё содержимое карточки каждый
   кадр, `BoxShadow` пересчитывался каждый кадр, `Image.memory` декодировал
   оригинал 4K, `_FeedFace` ставил post-frame колбэк в `build`.

**Сделано (3 коммита):**
- `cb88425` `fix(import)`: `pdfium_bootstrap.dart` (`ensurePdfiumInitialized`
  с явным `tmpPath`, каталог из `path_provider` в main-изоляте),
  `withCacheDirectory` в парсерах/рендерере/экстракторе, guard
  `pdfium_android_cache_test`, материализация `content://` во временный файл +
  `releaseDocument`, коды `fileAccessDenied`/`corruptFile`/`passwordProtected`/
  `docFormatNotSupported`/`pptFormatNotSupported`, `.ppt` в форматах и пикере,
  `FileType.any` на мобильных, `ParserDiagnostics`, показ причины пикера.
- `cf4cf33` `fix(generation)`: `ProviderRawResponse.truncated` (4 адаптера),
  `CardsJsonExtractor.salvageCards`, `truncated/salvagedCards` в результате и
  ран-результате, `truncatedChunks`/`imageResolveFailures`, защищённый участок
  вокруг разрешения картинок, `GenerationDiagnostics.runSummary`/
  `partialResponse`, диалог «Создано меньше, чем запрошено» + строка
  предпросмотра об обрывах.
- `4c9605b` `fix(ui)`: `CardImageBudget.side` (общий бюджет для классики/ленты/
  тренировки, порог `cardWidth >= 760`), `RepaintBoundary` + `cacheWidth` в
  `CardImageView`, переворот без перестройки содержимого (`_showBack` по
  listener, transform-only `AnimatedBuilder`), тень только в покое, лента не
  планирует проверку переполнения каждый кадр.
- `docs`: ADR-049, `journal/task04/import-audit/{audit,report}.md`,
  `docs/generation-pipeline.md`, `KNOWN_LIMITATIONS` (L210–L218), `AGENTS.md`.

**Новые тесты:** `pdfium_android_cache_test` (guard), `pdfium_bootstrap_test`,
`formats_task04_test`, `generation_truncation_task04_test`,
`generation_task04_resilience_test`, `card_image_parity_test`,
`card_animation_performance_test`; обновлены `pdf_parser_test`,
`file_parsing_service_test`, `file_picker_document_gateway_test`,
`cards_json_extractor_test`, адаптерные тесты, ARB-тесты,
`generation_screen_test`, `order_batches_7_20_test`.

**Гейты итогового снимка:** `fvm flutter test --no-pub --coverage
--exclude-tags golden` → **2801 passed + 17 skipped** (+51 к baseline);
покрытие рукописного кода **90,8 % (23 484/25 868)** (порог 80 % пройден);
`fvm flutter analyze --no-pub lib test` → **0 issues**;
`fvm dart format --set-exit-if-changed lib test` → **0 changed**;
`fvm flutter build windows --release --no-pub` → `cardflow.exe`. Схема БД,
`schemaVersion`, `format_version` и FSRS-логика **не менялись**.

**Ограничения:** L210–L218 (нет Android-устройства для живой проверки PDF;
`.doc/.ppt` не поддерживаются осознанно; спасаются только закрытые карточки;
полноэкранный просмотр декодирует оригинал; тень выключена во время движения;
«Отмена» диалога недобора не сохраняет карточки; диагностика — debug-only).

**Push/CI:** push в `origin/main` выполнен по разрешению владельца
(`ddfdde0..5d0327a`). CI run
[`46000290063`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/46000290063)
(`5d0327a`) — **9/9 job success** (`format + analyze`, `test` × 3 ОС,
`build desktop` × 3, `build mobile` Android + iOS), 14,3 мин.

---

## Предыдущая итерация (2026-11-26)

**Дата:** 2026-11-26 · **Итерация:** «Диагностика и фикс пайплайна генерации»
(`journal/fix-generation/{diagnosis,summary}.md`, ADR-048) — owner-note: на
Windows и Android генерация падает общей строкой «Не удалось получить карточки».
**Режим:** ИТЕРАЦИИ.

**Старт:** `HEAD = origin/main = f8cc926`, ветка `main`, `git status` — только
неотслеживаемые каталоги аудита. **Baseline:** `flutter test` **2739 passed +
16 skipped**. **Гейты итогового снимка:** `flutter test --coverage
--exclude-tags golden` → **2750 passed + 17 skipped** (+11 тестов), покрытие
рукописного кода **90,9 % (23160/25483)**; `analyze` 0;
`dart format --set-exit-if-changed lib test tool` 614/0;
`flutter build windows --release --no-pub` → `cardflow.exe` (98,1 с);
`flutter build apk --release --no-pub` → `app-release.apk` (101,3 МБ,
`versionName 1.0.1`, versionCode 2), `aapt2 dump permissions` →
**`android.permission.INTERNET`**. Схема БД/`schemaVersion`/`format_version` и
FSRS-логика не менялись.

**Причины (измерены, не гипотезы):**
1. **Android release.** APK 1.0.1 собран **без `android.permission.INTERNET`**
   (`aapt2`): `main`-манифест не объявлял разрешение, а debug/profile-манифесты
   в release не попадают. На Android в release не мог выполниться ни один
   сетевой запрос — генерация, поиск картинок, проверка ключа.
2. **Промпт/схема.** Production слал **`gen-ru-v8`**, хотя
   `systemPromptVersion` и схема ответа — **`gen-ru-v9`** (ADR-042): модель не
   получала контракт сторон изображений (`question_image_ids`/
   `answer_image_ids`/`image.side`).
3. **Общая строка вместо причины.** В `generation_jobs` после 2026-11-22 нет
   неудачных попыток: сбой шёл до/на первой записи журнала. `jobRepository.save`
   начального задания стоял **вне** `try`, а drift/SQLite-исключения (в т.ч.
   `SQLITE_READONLY`, L204) не переводились в доменный код — UI-catch `on Object`
   показывал общую строку.
4. **Запрос и парсинг исправны.** `tool/debug_generation.dart`: strict
   `response_format` DeepSeek → штатный `400` (194 Б) → запрос без схемы `200`
   (9166 Б) → `cards=10 rejected=0 rootInvalid=false`. Полный production-граф с
   настоящей drift-БД (копия), кэшем характеристик, калибровкой и реальным
   поиском картинок → `status=done cards=10 failures=0`; настоящий
   `GenerationScreen` на Windows (реальный secure storage, копия БД, сеть)
   запускает генерацию без общей ошибки.

**Сделано:**
- `INTERNET` в `android/app/src/main/AndroidManifest.xml` + guard
  `test/guards/android_manifest_internet_test.dart`; APK пересобран и проверен
  `aapt2`.
- Production переведён на `gen-ru-v9` во всех точках (`CardGenerationService`,
  `GenerationPlanBuilder`, `GenerationRequestEstimator`, `count_tokens` в
  пайплайне); тесты `card_generation_service_test` (v9 + блок сторон),
  `generation_plan_builder_test`, `generation_payload_bytes_test` обновлены.
- `GenerationErrorCode.storageUnavailable` + `GenerationFailureReason.storage`
  (`storage_unavailable`): `DriftGenerationJobRepository.save/jobById`,
  `DriftGenerationCardStore.existingContentHashes` и пайплайн
  (`storage_failure.dart`, `_unexpectedAsGeneration`) переводят сбои хранилища
  в доменный код; начальная запись задания внутри `try`; ARB
  `generationErrorStorageUnavailable`/`generationReasonStorage`; catch-all
  экранов генерации и повтора показывает причину и пишет в debug-диагностику
  только тип исключения (`GenerationDiagnostics.unexpectedFailure`).
- HTTP **402** — отдельный `GenerationErrorCode.insufficientBalance` и строка
  «Недостаточно средств на балансе провайдера. Проверьте баланс или ключ API»;
  401/403 остаются `invalidApiKey`. Widget-тесты экрана подтверждают: причина
  хранилища показывается вместо общей строки, сырой текст не утекает.
- `tool/debug_generation.dart` — постоянный инструмент: реальный запрос тем же
  промптом/параметрами, статус + сырое тело, production-разбор; ключ только из
  `DEEPSEEK_API_KEY`, не печатается.
- Live-тест `test/live/generation_pipeline_live_test.dart` (тег `live`,
  `CARDFLOW_LIVE_TESTS=1`) — production-пайплайн, тема «трансформаторы»,
  10 карточек; прогон: `status=partial cards=9 failures=0 prompt=gen-ru-v9`.
- Новые тесты: guard манифеста, storage-путь пайплайна (3), ошибка репозитория
  на настоящей readonly-БД, строки ARB хранилища, живой pipeline-тест.
  Диагностические временные тесты и `tool/debug_pipeline.dart` удалены.

**Коммиты:** `2bd24a3` (INTERNET в main-манифесте + guard), `931a7e8`
(production `gen-ru-v9`, `storageUnavailable` и понятные строки), `d4b594b`
(live pipeline + `tool/debug_generation.dart`), `b020c87`
(диагностика/ADR-048/STATE), `8a339c9` (UI-тесты причины), `f411fe9`
(HTTP 402 «нет баланса»), далее docs/CI.
**Push:** `f8cc926..127dd48` (ветка `main`, 2026-11-26). **CI:** run
[`45892725049`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/45892725049)
(`127dd48`) — **9/9 job success** (`format + analyze`, `test` × 3 ОС,
`build desktop` × 3, `build mobile` Android + iOS); artifact
`cardflow-android-release-apk` содержит APK с `INTERNET`.

---

**Дата:** 2026-11-25 · **Итерация:** «Фикс экспорта и сохранения настроек»
(`journal/fix-export-settings/diagnosis.md`, ADR-047) — два дефекта из
owner-note после установки 1.0.0. **Режим:** ИТЕРАЦИИ.

**Старт:** `HEAD = origin/main = 0d5446c`, ветка `main`, `git status` — только
неотслеживаемые каталоги аудита. **Baseline:** `flutter test` **2706 passed +
16 skipped**. **Гейты итогового снимка (`79fc764`):** `flutter test --coverage
--exclude-tags golden` → **2739 passed + 16 skipped** (+33 теста), покрытие
рукописного кода **90,2 % (24092/26703)**, всего 83,5 %; `analyze` 0;
`dart format --set-exit-if-changed lib test` 606/0;
`flutter build windows --release --no-pub` → `cardflow.exe` (58,8 с);
`flutter build apk --release --no-pub` → **`app-release.apk`
(106 177 646 Б, `ru.example.cardflow`, versionName **1.0.1**, versionCode 2)**.
Схема БД, `schemaVersion` и `format_version` не менялись; FSRS-логика не
менялась.

**Причины (измерены, не гипотезы):**
1. **Экспорт.** `FilePickerGateway.saveZipFile` вызывал `FilePicker.saveFile`
   **без** `initialDirectory` → нативный `IFileSaveDialog` стартовал в корне
   профиля (`C:\Users\piotr\`), Windows отвечал «У вас нет разрешения на
   сохранение файлов в этом месте». Воспроизведено на живой сборке.
2. **Настройки.** Падала **запись в SQLite**, а не JSON и не провайдер:
   `DriftRemoteException: SqliteException(8): attempt to write a readonly
   database` (`SQLITE_READONLY`). Каталог данных приложения в среде запуска
   запрещён к записи (зонд `PathAccessException … errno = 5`), ACL при этом
   даёт пользователю `FullControl`. Код записи редизайн не менял: в
   `settings_screen.dart` (`3967d20`) изменилась только панель разделов;
   `app_providers.dart` не менялся вовсе. Контрольный опыт с доступным
   каталогом: `daily_new_limit` 20 → 21 в UI **и** в
   `app_settings.value_json` — проводка исправна.

**Сделано:**
- **Экспорт:** каталог по умолчанию `getDownloadsDirectory()` → «Документы» →
  `null` (только desktop; на мобильных SAF), `FileSystemException` из плагина и
  из дописывания → `ArchiveException(ArchiveErrorCode.writeDenied)` → строка
  ARB «Нет прав на запись в эту папку. Выберите другую»; заголовок диалога
  локализован («Сохранить ZIP-архив колоды» вместо «Save File», находка F12).
- **Настройки:** `SettingsDiagnostics` (debug-only: тип, текст drift/SQLite,
  8 кадров стека) через `settingsDiagnosticsProvider`;
  `classifyAppSettingsWriteFailure` + `AppSettingsWriteException`
  (`writeDenied`/`unknown`, блокировка БД намеренно не `writeDenied`);
  экран показывает «папка данных приложения недоступна для записи» вместо
  бессмысленного «попробуйте ещё раз»; интеграционный тест на **файловой**
  drift-БД (изменение → save → переоткрытие → read).

**Проверки:** unit/widget — `file_picker_gateway_test` (+13: initialDirectory,
порядок каталогов, откаты резолвера, `FileSystemException → writeDenied`,
заголовок), `deck_screen_test` (русская строка вместо системного текста),
`settings_screen_test` (отдельная строка при отказе), новые
`app_settings_write_error_test` (включая настоящую readonly-БД через драйвер),
`settings_persistence_file_db_test`, `settings_diagnostics_test`. Красные фазы
с выводом — `journal/fix-export-settings/red-{export,settings}.txt`.
Живая release-сборка: диалог открывается в **Downloads** с заголовком
«Сохранить ZIP-архив колоды» и именем `Электротехника.zip`; изменение
настроек при запрещённом каталоге показывает строку о правах; при доступном —
сохраняется (снимки в `journal/fix-export-settings/screenshots/`).
Не ослаблен ни один тест.

**Коммиты:** `4494a49` (red экспорт), `c76290f` (red настройки), `28f0dcd`
(fix экспорт), `0c2fb65` (fix настройки), `63406ab` (контракт ARB),
`ec9e377` (docs/ADR-047), `d0d3b1a` (версия 1.0.1+2), `d60bb7d` (polish),
`79fc764` (guard + версия в тесте из контракта), далее docs/STATE.
**Push:** выполнен 2026-11-25, `0d5446c..79fc764` (ветка `main`).
**CI:** run
[`45678359533`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/45678359533)
(`79fc764`) — **9/9 job success** (`format + analyze`, `test` × 3 ОС,
`build desktop` × 3, `build mobile` Android + iOS); artifact
`cardflow-android-release-apk` (50 137 605 Б zip, APK 106 177 646 Б).
Журнальный коммит `03a6249` — run
[`45683524007`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/45683524007),
также **9/9 job success**.
Предыдущий прогон (`45671962176`) упал на **одном** тесте — жёсткий `'1.0.0'`
в `settings_screen_test` после выпуска 1.0.1+2; закрыто `79fc764`.
**Известный локальный нюанс:** `flutter build apk` после `flutter test`
переиспользует `GeneratedPluginRegistrant.java` с dev-плагином
`integration_test` и падает на javac; лечится удалением этого
(неотслеживаемого, регенерируемого) файла перед сборкой — в CI не
воспроизводится.

**Открытые ограничения:** L204 (при отказе прав приложение не самолечится:
причина в debug-логе и адресная строка в UI, но БД не переносится), L205
(живая запись ZIP-файла в ограниченной сессии агента невозможна — диалог и
путь проверены снимком, запись байтов — unit-тестами). Прежние L198–L203
(TASK 04) остаются. **Следующий шаг:** ручная приёмка патча владельцем
(экспорт в «Загрузки» и изменение настроек на его машине/телефоне).

---

## Предыдущая итерация

**Дата:** 2026-11-25 · **Итерация:** «Фикс мобильного Empty State»
(`journal/mobile-empty-state/summary.md`) — owner-note после установки APK: блок
«ИИ не настроен — …» на главном экране на телефоне сжимался в колонку по одной
букве, кнопка «Настроить ИИ» стояла сбоку.
Локальные гейты: `flutter test` **2689 passed + 16 skipped**, покрытие
**90,8 % (22848/25171)**, `analyze` 0, `dart format` 594 файла / 0 changed,
`flutter build windows --release` → `cardflow.exe` (69,1 с).
Схема БД, `schemaVersion` и `format_version` не менялись. **Режим:** ИТЕРАЦИИ.

**Первопричина (измерено):** `Row` из «`Icon` + `Expanded(Text)` + `TextButton`»
отдаёт кнопке неделимую ширину, а `Expanded` — остаток: на 390×844 тексту
оставалось **36,8 px** (42 строки, ~2 символа), на 360×800 — **6,8 px** (77 строк,
по одной букве), при кегле 150 % — **`RenderFlex overflowed by 53 pixels`**.
Второй вклад — hero-панель `AppEmptyState` с отступом 40 px с каждой стороны
(80 из 390 px на пустоту).

**Сделано:** блок на ширине < 600 px (`AppSizes.mobileBreakpoint`) — `Column`:
текст на всю ширину, действие под ним по левому краю; десктоп сохраняет `Row`.
`AppEmptyState` на мобильной ширине — 20 px по горизонтали, 24 по вертикали
(контент на 390 px: 278 → 318 px). Плашка получила внутренний отступ 12 px.
Новый тест `test/widget/decks/decks_mobile_empty_state_test.dart` (+8): кнопка
под текстом на 390 px, отсутствие overflow на 360×800 и при кегле 150 %,
горизонтальный `Row` на 1440×900, отступы панели ≤ 20 px. Тем же правилом
исправлен найденный аудитом `PrimaryProviderBanner` (тот же `Row` на том же
экране: текст 146 px при 390 px и 78,6 px при кегле 150 %) — +3 теста в
`test/widget/settings/provider_audit_test.dart`. Скриншоты 360×800,
390×844 и 1440×900 (реальные Inter + MaterialIcons) — в
`journal/mobile-empty-state/`. Урок о шрифтах/`setSurfaceSize`/`toImage` —
ретроспектива в `AGENTS.md`.

**Следующий шаг:** итерация закрыта локально; на 360×800 третье действие
«Импорт» требует короткой прокрутки (на 390×844 экран помещается целиком).
Открытые ограничения релиза — `audit/FINAL_IMPLEMENTATION_REPORT.md` §11
(реальные мобильные устройства, screen reader, живой поиск картинок, нативные
диалоги), P2-04 частично, APK подписан debug-ключом.

**Push и CI:** `9bb160e..37894ad` (тест red-фазы `1104519`, фикс `e10fe70`,
docs `0b52c0e`, фикс баннера `a0aaf3e`, скриншот `37894ad`) → run
[`45619796606`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/45619796606)
(`37894ad`) — **9/9 job success** (`format + analyze`, `test` × 3 ОС,
`build desktop` × 3, `build mobile` Android + iOS). Предыдущий прогон
(`45617686487`) отменён `concurrency` при следующем push — ожидаемо по
ретроспективе 7.6.

## История прошлых шагов (ниже — до 2026-11-25)

**Дата:** 2026-11-25 · **Итерация:** «Релиз v1.0.0»
(`journal/release-1.0.0/summary.md`) — версия `1.0.0+1`, Windows-артефакт
собран, CI собирает Android **release**-APK и публикует его в Artifacts.
Локальные гейты на релизном снимке: `flutter test` **2678 passed + 16 skipped**,
`analyze` 0, `dart format` 598 файлов / 0 changed,
`flutter build windows --release` → `cardflow.exe` (FileVersion `1.0.0+1`).
Схема БД, `schemaVersion` и `format_version` не менялись. **Режим:** ИТЕРАЦИИ.

**Push и CI релиза:** коммит `7e975bf` (`chore(release): prepare v1.0.0`),
тег `v1.0.0`; `origin/main` `36f8738..7e975bf` → run
[`45603871350`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/45603871350)
(`7e975bf`) — **9/9 job success**; artifact `cardflow-android-release-apk`
(APK `app-release.apk`, 50 050 015 Б). Windows-артефакт локально:
`build\windows\x64\runner\Release\cardflow.exe` (`FileVersion 1.0.0+1`).

**Следующий шаг:** релиз v1.0.0 закоммичен и помечен тегом `v1.0.0`;
открытые ограничения — `audit/FINAL_IMPLEMENTATION_REPORT.md` §11 (реальные
мобильные устройства, screen reader, живой поиск картинок, нативные диалоги)
и частично закрытая P2-04 (пункт «Найти колоду» в панели остаётся действием
по AGENTS.md); APK подписан debug-ключом — для Google Play нужен upload-ключ.

**Дата:** 2026-11-25 · **Итерация:** «аудит 2.0 — доработка по 46 находкам»
(`audit/FINAL_IMPLEMENTATION_REPORT.md`) — **завершена локально**: переработан
экран изучения карточек (типографика 34/28 px, ответ 0,88×, повтор 0,74×,
картинка в фиксированном слоте, прокрутка с подсказкой), добавлен порог
релевантности авто-подбора изображений (`lib/domain/generation/image_relevance.dart`),
после импорта есть путь назад, сетка колод получила компактный список, первый
запуск — приветствие, генерация — широкую колонку и пресеты количества,
провайдеры/настройки/статистика/квизы приведены к дизайн-системе, добавлено
жирное начертание OpenDyslexic. Схема БД и `schemaVersion` не менялись.
Гейты: `flutter test` **2678 passed + 16 skipped**, `analyze` 0,
`dart format` 0 changed, `flutter build windows --release` — ок.

**Дата:** 2026-11-21 · **Итерация:** `7.20` «Заказ карточек и партии ответа»
(`journal/iteration-7.20/summary.md`) — **завершена локально, push/CI ниже**:
заказ больше не ограничивается ни мягкой ёмкостью материала, ни бюджетом одного
ответа (ADR-043). 40 карточек при вместимости 16 → 3 партии 16/16/8, сумма 40;
нехватка материала — отдельный статус «материала хватает примерно на M из N»;
технический предел — число партий. Схема БД и `schemaVersion` не менялись.
**Режим:** ИТЕРАЦИИ.

**Следующий шаг:** итерация 7.20 закрыта; открытые ограничения — L194–L196
(«авто» без разделов = одна партия, эвристичность `estimatedCapacity`,
сравнение заполненных и сбалансированных партий на живых прогонах).

**Push и CI 7.20:** `0d3c35b..02bf726` (audit `1e7a327`, red `4952867`, feat
allocator `208ffb7`, feat партии/предупреждения `1f1df1a`, fix top-up `56dc93c`,
docs `389f358`, fix ревью `6bf7889`, журнал `02bf726`) → run
[`44936474031`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44936474031)
(`02bf726`) — **9/9 job success** (`format + analyze`, `test` × 3 ОС,
`build desktop` × 3, `build mobile` Android + iOS). Журнальный коммит `2196e17`
(эта запись) → run
[`44937971970`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44937971970)
— также **9/9 job success**.

## Итерация 7.20 — заказ и партии (2026-11-21)

**Задача:** пользователь запросил 40 карточек, а план сообщал «может выдать 32:
бюджета модели не хватает на весь заказ». Ограничение вывода должно
ограничивать **одну** партию, но не общий заказ; при необходимости приложение
само делит генерацию на последовательные партии.

**Факты старта:** `git status --porcelain` → пусто; `HEAD = origin/main =
0d3c35b`; baseline — полный набор зелёный (7.19), `analyze` 0.

**Первопричина:** `CardAllocator.allocate` зажимал сумму заказа мягкой ёмкостью
материала (`min(requested, Σcapacity)`), а `PlanWarningCode.requestedAbovePlan`
объяснял это бюджетом модели. Бюджет вывода в этой арифметике не участвовал:
зонд на `GenerationPlanBuilder` показал одинаковый «achievable» при
`maxOutputTokens` 2 000/8 192/64 000. «16 на ответ» из задания —
`cardsFor(8192 − 2048) = 16`. Аудит — `journal/iteration-7.20/audit.md`.

**Сделано (ADR-043, TDD):**
- мягкая ёмкость материала — предпочтение распределения; остаток заказа
  распределяется по весам точно (`Σ planned == requestedCards`);
- `estimatedCapacity`/`materialLimited` и
  `PlanWarningCode.materialCapacityBelowRequested` вместо ложной причины;
- партии заполняются до вместимости (`batchCount`/`batchSizes`,
  `batchSizesFor` для раскладки изображений); технический предохранитель числа
  партий (`maxChunks`) до построения списка;
- резерв оценки — по максимальной партии; дополнительная партия
  перераспределения недостачи — не больше вместимости ответа;
- UI: «Запрошено: N карточек», числа плана и распределение в «Подробнее»,
  фактически созданное количество при исчерпании материала.

**Тесты (+47):** `card_allocator_soft_capacity_test.dart` (21),
`output_batching_7_20_test.dart` (26), `card_order_plan_7_20_test.dart` (18),
`card_order_batches_flow_7_20_test.dart` (6), `order_batches_7_20_test.dart` (5);
обновлены ожидания, фиксировавшие дефект, — с комментарием причины.

**Ревью (снимок `6bf7889`, L35):** high/critical нет; R1–R3 (medium) и R4–R5
(low) закрыты fix-коммитом `6bf7889` с тестами; `review.md`.

**Гейты (2026-11-21):** `gen-l10n` ок; `dart format` 567/0; `analyze` — No
issues; полный набор **2534 passed + 16 skipped + 0 failed**; покрытие
**91.5 % (20294/22174)**; `build windows --release` → `cardflow.exe` (62,3 с);
Windows smoke — **All tests passed!** (11 с). Живых API-запросов нет.

## Итерация 7.19 — изображения: первопричина и две стороны (2026-11-21)

**Задача:** установить, почему одинаковая абстрактная картинка появляется на
разных карточках, устранить механизм подмены; реализовать независимые
изображения вопроса и ответа (выбор ИИ, редактор, отображение, совместимость).

**Факты старта:** `git status --porcelain` → пусто; ветка `main`;
`HEAD = origin/main = 16766f8`; baseline **2365 passed + 16 skipped**,
`analyze` 0. Красная фаза `287eb29` — assertion-level: production-проводка
сохранила нарисованный PNG 22 906 Б вместо пустого медиа; `CardImageView` на
обратной стороне.

**Первопричина №1:** `GenerationPipeline._placeholderOrNothing` +
`PlaceholderImageGenerator` рисовали декоративный PNG (градиент, круги,
полосы, иконка `diagram` = оси и столбики) при любой неудаче привязки
изображения и сохраняли его как обычное медиа (`media`, файл,
`<path>.meta.json`, `isPlaceholder`). Палитра — `contentHash % 8`, поэтому
карточки выглядели одинаково. Промпт v8 требовал картинку каждой карточке;
`main.dart` ретраил заглушки при старте. Фактическая БД: **80 из 207** медиа —
заглушки, 68 `kind=diagram`, 15 визуальных групп (крупнейшая — 16 карточек).

**Первопричина №2:** плоский `mediaIds` + `CardContentView`, берущий
`mediaIds.first` независимо от стороны; схема v8 не давала модели выбрать
сторону. Фактическая карточка владельца (сценарий B) показывала PNG из PDF с
искомой формулой на лицевой стороне.

**Сделано (ADR-041/042, TDD):**
- Заглушки: генератор удалён; pipeline не создаёт изображения; явные пометки
  (`imageIdUnknown`, `imageNotFound`, `imageInvalid`); `PlaceholderMediaPurger`
  удаляет старые заглушки при старте; фоновый ретрай удалён; проверка
  сигнатуры/MIME до записи; `MediaIntegrityChecker` + `tool/media_integrity_report.dart`.
- Стороны: `CardMediaSides` (media_json v2), `Card`/`CardDraft` с двумя
  коллекциями и порядком; схема ответа v9 (`question_image_ids`,
  `answer_image_ids`, `image.side`, совместимость v5–v8); промпт `gen-ru-v9`
  (v8 сохранён дословно); pipeline разрешает сторону из каталога фрагмента и
  внешний поиск только для выбранной стороны; Occlusion — общий холст.
- UI: `CardContentView` по стороне, явные состояния «нет файла»/«ошибка
  декодирования» с повтором (классика/лента/тренировка/«Тест»/«Ввод»/«Верно-
  неверно»); редактор двух сторон (добавить/удалить/заменить/порядок/перенос,
  несколько изображений); предпросмотр показывает обе стороны; живая карточка
  генерации — только изображения вопроса (ревью R1).
- Совместимость: legacy-массив → сторона вопроса; старые архивы без сторон;
  экспорт/импорт с `question_media_ids`/`answer_media_ids`; перезапуск приложения.

**Тесты (+60):** `image_sides_7_19_test.dart` (5), `image_placeholder_red_7_19_test.dart`
(1, регрессия production-проводки), `image_side_selection_test.dart` (12),
`card_media_sides_test.dart` (13), `card_media_sides_data_test.dart` (10),
`media_integrity_test.dart` (8), `card_sides_display_test.dart` (8),
`card_form_sides_test.dart` (6), плюс A11 в pipeline-тестах и правки схемных
тестов. Ни один существующий тест не ослаблен; тесты заглушек 7.14 заменены
тестами их отсутствия (ADR-041).

**Ревью (снимок `6486b28`, L35):** high нет; R1/R2 (medium) закрыты fix-коммитом
с тестами — утечка answerMedia в живую карточку генерации и неработающий
«Повторить» в сессиях; R3/R4 (порядок «хранимое ↔ новое», расширение WebP)
исправлены; R5–R7 — L188–L193. Legacy-сторона: безопасная политика ADR-042
(стимул — вопрос, остальное — ответ). `review.md`.

**Гейты (2026-11-21):** `gen-l10n` ок; `dart format` 566/0; `analyze` — No
issues; полный набор **2425 passed + 16 skipped + 0 failed**; покрытие
**91.5 % (20177/22060)**; `build windows --release` → `cardflow.exe` (61,8 с);
Windows smoke — **All tests passed!** (11 с). Живых API-запросов нет.

## Итерация 7.18.3 — мультимодальный подсчёт и честный бюджет (2026-11-21)

**Задача:** закрыть блокирующий дефект 7.18 — `count_tokens` не видел
мультимодальный материал; развести число провайдера, оценку и резерв; не
превращать неизвестный Vision в `false`; честно показывать неизвестный
`max_request_bytes`. Без новой архитектуры.

**Факты старта:** `git status --porcelain` → пусто; ветка `main`;
`HEAD = origin/main = 8332df2`; baseline **2340 passed + 16 skipped**,
`analyze` 0. Красная фаза `cac4586` — 16 assertion-level падений
(`red-7.18.3.md`).

**Найдено и исправлено (каждая — отдельным коммитом с регрессионным тестом):**
1. F1 (high) — Gemini-конверт `generateContentRequest` без `model` в форме
   `models/<id>`: endpoint отвечает 400, любой Gemini exact-подсчёт молча
   деградировал к оценке `72d8e3e`;
2. F2 (medium) — запрос только из вложений: `_countedUserContent` без строк
   «Файл: <имя>» → native-число занижено `cf3a741`;
3. F3 (medium) — предпросмотр и production получали разные аккаунты по
   Vision (`copyWith` только при запуске) `72d8e3e`;
4. F4 (medium) — `KNOWN_LIMITATIONS.md`: блок L173–L178 стоял **до** заголовка
   и слипался с ним — структура исправлена, L174 снят, L163/L176 обновлены,
   добавлены L179–L185.

**Реализация (§2–§5):**
- `RequestTokenCounter.count(..., attachments)`; Anthropic — base64
  `image`/`document`-блоки, Gemini — `generateContentRequest` c
  `model`/`systemInstruction`/`contents[].parts.inlineData`; тела собираются
  теми же `anthropicUserContent`/`geminiParts`, что production. PDF —
  document/inlineData `application/pdf`.
- `exactTokenCacheKey` включает digest байтов, MIME, подпись части, версию
  формы; изменённая картинка → новый ключ. `_countedImageTokens` удалён:
  изображения входят в число провайдера.
- `NativeInputCount` + `RequestBudget`: `nativeInputTokens`,
  `estimatedExtraTokens`/`components`, `marginTokens`, `effectiveBudgetTokens`;
  `exact` только при нулевой добавке (Gemini `responseSchema` — отдельная
  оценка, mixed → `estimated`, запас 10 %). 3 %/10 % не менялись.
- UI «Подробнее»: отдельные строки «Число провайдера», «Оценка добавки»,
  «Резерв бюджета», «Плановый бюджет»; предупреждения плана локализованы.
- `ModelLimits.imageInputSupport` (3 состояния), `ModelCapabilities.supportsVision`
  стал `bool?` + `visionSource`; unknown → отправка + `imagesVisionUnconfirmed`,
  подтверждённое false — прежнее поведение; `max_request_bytes` в
  `unknownFields`/«Неизвестные лимиты».

**Новые тесты (+25):** `request_token_counter_multimodal_test.dart` (5),
`token_breakdown_test.dart` (5), `unknown_vision_and_limits_test.dart` (8),
`generation_exact_tokens_test.dart` (10, из них +4 и 1 новый сценарий),
`generation_plan_details_test.dart` (+3), `generation_screen_test.dart` (+1),
`request_token_counter_test.dart`, `model_capabilities_test.dart` и
интеграционные Vision-сценарии — обновлены под новый контракт.

**Гейты (2026-11-21):** `gen-l10n` ок; `dart format` 550/0; `analyze` — No
issues; полный набор **2365 passed + 16 skipped + 0 failed**; покрытие
**92,1 % (19743/21437)**; `build windows --release` → `cardflow.exe` (66,2 с);
Windows smoke — **All tests passed!** (11 с). Живых API-запросов нет.
Подробно — `verify-7.18.3.md`, ревью — `review-7.18.3.md`, семантика
провайдеров — `discovery-7.18.3.md`.

**Push и CI:** `8332df2..1e32ee6` (6 коммитов итерации, включая red-фазу) →
run [`44909643704`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44909643704)
(`1e32ee6`) — **9/9 job success** (`format + analyze`, `test` × 3 ОС,
`build desktop` × 3, `build mobile` Android + iOS). Итоговый HEAD фиксируется
строкой ниже после docs-коммита с этими результатами.

## Итерация 7.18.2 — финальный аудит 7.18 (2026-11-21)

**Задача:** заключительная проверка соответствия `docs/prompts/iteration-7.18.md`
без новой архитектуры и без изменения работающего кода там, где дефекта нет.

**Факты старта:** `git status --porcelain` → пусто; ветка `main`;
`HEAD = origin/main = 170a413`; baseline **2302 passed + 16 skipped**,
`analyze` 0; красная фаза — 15 assertions (`red-7.18.2.md`).

**Найдено (5 high/medium, каждая — отдельный fix-коммит + регрессионный тест):**
1. F1 (high) — текст каталога `<images>` не входил в `D`: `catalogTokens = 0`,
   `materialTokens`/`inputTokens` занижены `b9b294a`;
2. F2 (high) — `count_tokens` считает только текст, конвейер подставлял его как
   весь вход → стоимость изображений = 0 `fe47d5a`;
3. F3 (high) — `requestBytes` плана без обвязки (промпт/схема/JSON, +29 КБ) и
   без проверки фактического тела: 34,7 МБ уходили при лимите 20 МБ `eb616f8`;
4. F4 (medium) — `isReasoningModel` терялся в проекции, резерв рассуждения не
   вычитался из партии `76b93e7`;
5. F5 (medium) — UI не показывал `supportsImageInput`; `copyWith` терял
   `visionConfigured`, каталог перекрывал явный Vision `55747b5`.

Плюс `257409b` — каталог и резерв рассуждения в «Подробнее»; `4642bf1` —
формат/импорт.

**Новые тесты (+38):** `image_catalog_budget_test.dart` (6),
`generation_payload_bytes_test.dart` (7, включая Anthropic и T5),
`reasoning_reserve_test.dart` (5), `generation_exact_tokens_test.dart` (+1),
`model_discovery_errors_test.dart` (14 — зелёные до правок),
`model_capability_section_test.dart` (+3), `generation_screen_test.dart` (+1),
`model_capability_settings_test.dart` (+1), `generation_plan_details_test.dart` (+1).

**Гейты (2026-11-21):** `gen-l10n` ок; `dart format` 546/0; `analyze` — No
issues found; полный набор **2340 passed + 16 skipped + 0 failed** (baseline
2302+16); покрытие **92,0 % (19581/21286)**; `build windows --release` →
`cardflow.exe` (69,6 с); Windows smoke — **All tests passed!** (11 с).
Живых API-запросов нет. Подробно — `verify-7.18.2.md`, архитектура — §5
`summary-7.18.2.md`, discovery-таблица — `discovery-7.18.2.md`.

**Push и CI:** `170a413..df4c29d` (8 коммитов) → run
[`44900761883`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44900761883)
(`df4c29d`) — **9/9 job success** (`format + analyze`, `test` × 3 ОС,
`build desktop` × 3, `build mobile` Android + iOS). Итоговый HEAD фиксируется
строкой ниже после docs-коммита с этими результатами.

## Итерация 7.18.1 — закрытие остатков 7.18 (2026-11-21)

**Задача:** заключительный аудит соответствия `docs/prompts/iteration-7.18.md`
и закрытие обязательных пробелов без новой архитектуры.

**Факты старта:** `git status --porcelain` → пусто; ветка `main`;
`HEAD = origin/main = d66b0ff`; baseline `fvm flutter test --no-pub
--exclude-tags golden` → **2256 passed + 16 skipped**, `analyze` 0.

**Аудит отчёта 7.18:** кроме заявленных L156/L159/L160/L161 найдено:
production-сервис слал `gen-ru-v7` (high), каталог `<images>` не входил в
`requestBytes`, recovery менял только ярлык стратегии, сброс терял Vision,
«Подробнее» брало лимиты исходного аккаунта.

**Сделано (TDD, red → green, отдельные коммиты):**
- `4072f4e` — prompt-only через `GenerationChunkPlanner`/`InputPlanner`/
  `OutputBatchPlanner`; `PromptOnlyPlanner` удалён; тема — в обвязке каждого
  запроса, разделов нет.
- `e30562a` — production и builder по умолчанию шлют `gen-ru-v8`.
- `c007328` — `RequestTokenCounter.supports` + `ProtocolRequestTokenCounter`,
  один подсчёт на план, `ExactTokenCountCache` (sha256 содержимого), ошибка →
  оценка, `InputAccuracy`/`inputTokenSource` в `InputPlan`; Anthropic `tools`,
  Gemini `generationConfig`; `<part>1 из 0</part>` убран.
- `0e72b61`, `bd99ace` — recovery: 413/подтверждённый 400 → части ≤0.8
  бюджета; wholeDocument → fragmented с реальными частями/focus; остальные
  партии части делятся заранее; ≤3 операций на запрос; прочие 400/401/403 без
  переплана; `bodyBytes` включает каталог.
- `c646c61` — `max_input_tokens`/`capabilities_configured_at` в JSON v2,
  `userConfigured` с датой, UI «Изменить»/«Сбросить», тест применения на экране
  провайдеров.
- `39ade40` — `GenerationPlanDetails` («Подробнее»), `buildRunPlan` — единая
  точка предпросмотра и конвейера, калиброванный builder, лимиты из кэша.
- `0e42437` — discovery: DeepSeek `input_modalities`, Anthropic
  `capabilities.image_input/pdf_input`, Moonshot `supports_image_in/reasoning`,
  Ollama семантика `unknown`.
- `6b374d7`, `419b625`, `9f42da6`, `bd99ace`, `50ca263` — фиксы ревью:
  каталог в байтах запроса, Vision при сбросе, лимиты выбранной модели,
  реальные части recovery, ARB без латиницы.

**Гейты:** `gen-l10n` ок; `dart format` **542/0**; `analyze` **0**; полный
набор → **2302 passed + 16 skipped + 0 failed**; покрытие **91.7 %
(19433/21185)**; `build windows --release` → `cardflow.exe` (65,8 с); Windows
smoke → **All tests passed!** (11 с). +46 тестов net, 0 ослаблений.

**Журнал/ревью:** `journal/iteration-7.18/{summary,verify,review}.md`
(разделы 7.18.1); `KNOWN_LIMITATIONS.md` L154–L173; `docs/generation-planning.md`
§9; ADR-039 §6a. Находки ревью: high R1 и medium R2–R11 закрыты
регрессионными тестами; открытых high/medium нет.

## Итерация 7.18 — планирование генерации (фаза 0, 2026-11-20)

**Задача:** планировать генерацию по реальным характеристикам модели с
источником каждого числа, по фактическому размеру запроса и по заказанному
числу карточек; три решения независимы (вход / распределение / партии).

**Факты старта:** `git status --porcelain` → только
`?? docs/prompts/iteration-7.18.md`; `HEAD = ab57f17`, ветка `main` (в шапке
STATE было `REDESIGN 2`, старт `c50dafe` — HEAD на 5 коммитов новее: визуальный
QA и независимое ревью редизайна). Каталога `journal/iteration-7.18/` не было →
фаза 0. Baseline: `fvm flutter test --no-pub --exclude-tags golden` →
**2193 passed + 16 skipped + 0 failed** (3:55, сводка
`journal/iteration-7.18/baseline-test.txt`); `fvm flutter analyze --no-pub` →
**No issues found (95,3 с)**. Первый `analyze` без `--no-pub` завис на
`pub get --example` (L64 подтверждён; зависшие процессы остановлены).

**Аудит:** `journal/iteration-7.18/audit.md` — карта цепочки, ответы на §2.5,
таблица «понятие → класс», 12 находок, противоречия задания с кодом
(`gen-ru-v7` уже занят → новый промпт `gen-ru-v8`; `tokensPerCard` 1024 → 300 по
§3.4; предпросмотр плана строится вторым вызовом builder-а; D.1 заменяется
формулами §3.4), предложенный план и номера ADR-039/ADR-040.

**Итог (2026-11-21):** ADR-039 (происхождение/discovery/кэш) и ADR-040
(whole-document-first, распределение, партии, `gen-ru-v8`) реализованы TDD;
red-фаза `f191375`, коммиты по слоям. Характеристики: `Sourced<T>`,
`ModelLimits`, слоистый резолвер, discovery по протоколам, JSON v1
`generation.model_capabilities` (TTL 7 дней), сервис обновления; нативный
`count_tokens` Anthropic/Gemini + exact-путь (в конвейер не подключён — L156).
План: независимые Input/Card/Batch, `inputPlan`/`allocation`, стабильный
префикс сообщения и стабильные display-id изображений. Конвейер: focus/part/
already_created/outline, исчерпание разделов и однократное перераспределение,
почти-дубли триграмм ≥0.85, калибровка `generation.calibration` v1,
`chunk_count` = части входа. UI: блок «Характеристики модели» (источник/дата,
refresh/reset). Гейты: **2256 passed + 16 skipped**, analyze 0, format 533/0,
покрытие **91.7 %**, Windows release `cardflow.exe` (`verify.md`); ревью —
`review.md` (high/critical нет, R1/R2 закрыты `ddc0946`). Ограничения
L154–L161. Живых API-запросов не было.

План, матрица экранов, дизайн-система, визуальный QA и приёмка REDESIGN 2 —
`journal/redesign/03_IMPLEMENTATION_PLAN.md`, `01_SCREEN_MATRIX.md`,
`02_DESIGN_SYSTEM.md`, `04_VISUAL_QA.md`, `05_ACCEPTANCE.md`; решение —
ADR-038.

## REDESIGN 2 — этапы A–C (2026-11-19)

**Задача:** перенести макет `redesign/2` (Gemini/Stitch) в существующий
Flutter-UI целиком, сохранив домен, данные, API, маршруты и все сценарии.

**Факты старта:** `git status --porcelain` → только `?? redesign/`;
`HEAD = c50dafe`, ветка `main`. Baseline: `analyze` — 0; тесты —
**2176 passed + 16 skipped + 1 failed**. Единственный красный —
`test/guards/no_secrets_test.dart`: guard находил ключеподобную строку
(`sk-ant-…`) в **неотслеживаемом** снимке дизайна
`redesign/2/public/assets/aistudio/Paste_…`; снимок очищен
(`sk-ant-REDACTED`), guard не ослаблен — тест зелёный. Прогоны — только
с `--no-pub` (L64).

**Сделано (этап A — дизайн-система):**
- `lib/ui/theme/app_tokens.dart`: палитра light/dark из макета, радиусы,
  отступы, размеры оболочки, тени, длительности; ADR-038.
- `lib/ui/theme/app_typography.dart`: Inter (переменный, SIL OFL,
  `assets/fonts/Inter-Variable.ttf` + `OFL-Inter.txt`), шкала макета,
  tabular-цифры.
- `lib/ui/theme/app_theme.dart` переписан: явные роли `ColorScheme` (не
  fromSeed), компонентные темы Material (кнопки, поля, чипы, диалоги,
  листы, снекбары, меню, сегменты, переключатели, слайдеры, tooltip);
  повышенный контраст — `fromSeed(contrastLevel: 1)`, динамический цвет и
  шрифт дислексии сохранены.
- `lib/ui/components/`: `app_layout.dart` (страница/шапка/ширина),
  `app_surfaces.dart` (панель, секция, KPI, чип, бейдж, прогресс, пусто,
  ошибка, скелетоны), `app_dialogs.dart` (диалог/лист по правилу ADR-036).

**Сделано (этап B — оболочка):** `app_shell.dart` переписан: постоянная
панель 240 px + верхняя панель 56 px (≥1024), Drawer <1024;
`app_sidebar.dart` (логотип, поиск, 5 пунктов, реальный остаток повторений),
`app_top_header.dart` (крошки, «Новая карточка» с реальным выбором колоды,
настройки). `NavigationBar`/`NavigationRail` удалены (ADR-038); все
19 маршрутов доступны. Новые провайдеры: `allDeckSummariesProvider`,
`totalDueCardsProvider`, `decksSortProvider`, `decksViewModeProvider`.
Тест `pump_app.dart` проецирует M3E-тему из Material, как production.

**Сделано (этап C — колоды):** `decks_screen.dart` переписан: шапка с
реальными счётчиками, 4 KPI, панель поиска/фильтров/сортировки/вида
(сетка/список), карточки колод (статус, прогресс «Изучено», дата, CTA),
архив свайпом и из меню с undo, создание/переименование/экспорт/импорт/
удаление. Тесты `decks_screen_test.dart` обновлены под новую оболочку
(прокрутка, счётчики в чипах, ключи вместо M3ECard), все сценарии
сохранены; `shell_test.dart` переписан под панель/Drawer.

**Гейты этапов A–C (baseline):** `dart format` — применён; `analyze` — 0 issues;
`test/widget` — **335 passed**; `test/unit` — **1722 passed**;
`test/guards/no_secrets_test.dart` — зелёный (9/9).
Каталог `journal/redesign/` заведён: `00_REFERENCE_AUDIT.md`,
`01_SCREEN_MATRIX.md`, `02_DESIGN_SYSTEM.md`,
`03_IMPLEMENTATION_PLAN.md`.

**Известные ограничения этапа:** визуальный QA по скриншотам (1440×900,
1024×768, 390×844) — на этапе H; остальные экраны (обучение, генерация,
статистика, настройки, карточки, конструктор) ещё на старой визуальной
системе и в этапах D–G.

## REDESIGN 2 — этапы D–H и приёмка (2026-11-19)

**Задача:** завершить перенос макета Gemini/Stitch v2 на все экраны, провести
визуальную проверку реального приложения и финальные гейты.

**Сделано (этап D — обучение):** общий каркас сессии (шапка 56 px, полоса
прогресса с подписью, карточка r16 с раскрытием ответа, панель оценок 2/4
колонки с прогнозом интервалов и цветами ролей) применён к классике, ленте,
тренировке, тесту, вводу, парам, верно/неверно и плановым сессиям; итоги и
состояния пусто/ошибка — общие компоненты. Логика FSRS, лимитов, таймеров,
undo, LaTeX/cloze/occlusion/медиа не менялась. Цвета оценок переведены на
роли макета (тест обновлён), форма карточки ленты — r16→pill при свайпе.

**Сделано (этап E — генерация):** три нумерованные секции в панелях,
пунктирная зона загрузки (`AppDashedBorder`), файлы/параметры/провайдеры на
общих поверхностях, sticky-панель запуска с верхней границей; предпросмотр —
те же поверхности и нижняя панель импорта. Пайплайн, провайдеры, обработка
файлов, план и частичный успех не менялись.

**Сделано (этап F — статистика/настройки):** KPI из реальных данных (серия из
карты, удержание 30 дней и цель из настроек, повторения за год, активные дни),
годовая карта с легендой и краткими месяцами, удержание, прогноз, слабые темы,
неделя; настройки — двухколоночный макет с поднавигацией по секциям и пятью
карточками, все переключатели/слайдеры/поля сохранены. Экран провайдеров —
панели аккаунтов, общие пустые/ошибочные состояния.

**Сделано (этап G — колода/карточки/конструктор):** экран колоды (чипы
счётчиков, прогресс, панель запуска, список карточек), форма карточки и
конструктор (ширина контента, нижние панели с границей и центрированием,
секции-панели).

**Сделано (этап H — QA и документация):**8 компонентных тестов дизайн-системы
(включая регрессию правила диалогов ADR-036 — закрытие маршрута из
`dialogContext`); визуальная проверка реального Windows release на логических
1440×900 и 390×844 с исправлениями V1–V6 (`journal/redesign/04_VISUAL_QA.md`,
снимки в `journal/redesign/screenshots/`); ADR-038 дополнен отступлениями;
`docs/dependencies.md` — Inter (OFL); `KNOWN_LIMITATIONS` L149–L153; матрица
экранов, дизайн-система, план и приёмка обновлены. Guard-тесты исправлены без
ослабления: `shellVersion` без латинской «v», чип FSRS и крошки — через ARB,
числовые подписи — через локализованные строки.

**Финальные гейты (2026-11-19):**
- `fvm flutter test --no-pub --coverage --exclude-tags golden` → **2193 passed
  + 16 skipped, 0 failed** (baseline был 2176+16+1; +11 тестов, guard
  `no_secrets` починен очисткой неотслеживаемого снимка дизайна).
- Покрытие: **92.0 % рукописного кода (17710/19254)**, все файлы 82.9 %.
- `fvm flutter analyze --no-pub` → **No issues found**.
- `fvm dart format --set-exit-if-changed lib test integration_test` →
  **504 файла, 0 changed**.
- `fvm flutter build windows --release --no-pub` → `cardflow.exe` (103,2 с).
- Реальное приложение: снимки десктопа/мобильного, тёмная/светлая тема через
  настройки (тема проверена тестами применения).

**Коммиты этапов:** `8c0d544` (A), `cc84ba8` (B), `2bfea53` (C), `9ae3b93` (D),
`a3f8048` (E), `cd7af12` (F), `0f205a2` (G), финальный docs/test-коммит (H).
Push не выполнялся.

## TASK 04 — готовность к реальной генерации и управляемые испытания (2026-11-19)

**Задача:** после TASK 01/02A/02B-FINAL/03 установить фактическую готовность
к реальной генерации: аудит провайдеров/адаптеров/моделей/ключей, безопасная
инфраструктура live-тестов, предварительная стоимость, тестовые сценарии,
калибровка токенов. **Платные API-запросы запрещены** — только подготовка.

**Факты старта:** `git status --porcelain` → только `?? redesign/` (каталог
владельца не тронут); `HEAD = dba80ec`, ветка `main`, коммиты TASK 03 на
месте. Baseline — **2110 passed + 8 skipped**, `analyze` 0. Прогоны — только
с `--no-pub` (L64).

**Аудит (по коду и официальным страницам, `journal/task04/audit.md`):**
- 9 пресетов-провайдеров обслуживаются 4 адаптерами (OpenAI,
  OpenAI-compatible, Anthropic, Gemini); streaming не реализован; OpenAI не
  передаёт `max_tokens`; Vision/PDF/JSON/usage — по протоколам.
- **Каталог моделей устарел/не подтверждён:** официальная страница DeepSeek
  (2026-11-19) перечисляет `deepseek-flash` (1M контекст, вывод до 384K,
  Vision ✓) и `deepseek-v4-pro`; `deepseek-chat`/`deepseek-reasoner` в ней
  отсутствуют; `claude-3-5-*` нет в актуальной таблице тарифов Anthropic;
  страница тарифов Gemini из окружения недоступна.
- **Тарифы подтверждены только для 4 моделей** (`deepseek-flash`,
  `deepseek-v4-pro`, `gpt-4o`, `gpt-4o-mini`); у остальных цена неизвестна.
- **Ключи/безопасность:** только secure storage, read-back, логи без
  заголовков/тел; `DioException.toString()` (dio 5.11.1) не печатает URI и
  заголовки. Найдено расхождение санитайзеров (диагностика vs
  `providerReason`) — устранено.
- **Дефект:** битый JSON провайдера классифицировался как `network` и
  **повторялся** (лишние платные запросы до 4 на фрагмент).

**Сделано:**
- **Транспорт:** `GenerationHttpClient` запрашивает `ResponseType.plain` и
  разбирает тело сам — битый JSON → `invalidResponse` без повторов;
  подтверждено локальным HTTP-тестом на реальном сокете.
- **Безопасность:** единый `redactSecretsInText` (`log_redaction.dart`) для
  диагностики и `providerReason`: заголовки `Authorization`/`x-api-key`/
  `x-goog-api-key`, `Bearer`, `sk-`/`AIza`/`gsk_`/`xai-`/`nvapi-`, секретные
  query-параметры (`?key=`, `&api_key=`).
- **Инфраструктура live-тестов (`test/live/support/`):** конфигурация по
  окружению с безопасными умолчаниями (`enabled=false`, `maxRequests=0`,
  `maxCost=0`), тарифы с URL/датой проверки, предварительная стоимость
  (неизвестно → `null` + блокировка), бюджет логических запросов + лимит
  HTTP-попыток, план сценариев Test A–E, фикстуры, качество карточек,
  `LiveRunRecord` (провайдер/модель/версия оценщика/оценки и факты токенов/
  байты/изображения/время/статус/recovery), harness на production-адаптерах.
- **Управляемый набор:** `test/live/adaptive_generation_live_test.dart` —
  Test A–E, все пропускаются без `CARDFLOW_LIVE_TESTS=1` + бюджета + ключа.
- **Test F без оплаты:** `local_provider_server.dart` +
  `test/integration/generation_recovery_http_test.dart` (11 тестов: 413, 429 +
  `Retry-After`, таймаут, context overflow, битый JSON, `truncated`, 5xx, 401).
- **Легаси live-тесты** (DeepSeek, метрики картинок, Wikimedia) переведены на
  общий opt-in; обычный прогон стал полностью офлайновым (три Wikimedia-теста
  раньше выполнялись в нём).
- **Список адаптеров** вынесен в `lib/api/providers/generation_adapters.dart`
  (production и live-тесты — один набор).
- **Документация:** раздел S `docs/adaptive-generation-architecture.md`;
  `docs/generation-pipeline.md` (§5 разбор тела ответа, §9 управляемые
  испытания); `journal/KNOWN_LIMITATIONS.md` L137–L142; правило live-тестов в
  `AGENTS.md`; `journal/task04/{audit.md,live-test-plan.md,report.md}`.

**Гейты:** `fvm flutter test --no-pub --exclude-tags golden` →
**2157 passed + 16 skipped** (`All tests passed!`; baseline 2110 + 8,
+47 passed / +8 skipped); `fvm flutter test --no-pub --coverage
--exclude-tags golden` → **2157 passed + 16 skipped**, покрытие рукописного
кода **92.4 % (16200/17535)**; `fvm flutter analyze --no-pub` → **No issues
found!**; `fvm dart format --set-exit-if-changed lib test integration_test
tool` → **499 файлов / 0 changed**; `fvm flutter build windows --release
--no-pub` → **`cardflow.exe`** (63,0 с).

**Остатки (L137–L142):** устаревшие/непроверенные id моделей каталога;
неизвестные тарифы большинства моделей; Vision-флаг пресета DeepSeek неверен
для `deepseek-flash`; 404/402/422 не имеют отдельных кодов; live-тесты не в
CI и требуют ручного запуска; живых платных запросов не было (L142).
Негативные живые контракты по-прежнему не проверяются (ADR-014).

**Стоимость безопасной проверки (оценка):** Test A–C — 5 запросов,
≈ $0.031; A–E — 11 запросов, ≈ $0.072; рекомендуемый бюджет TASK 05 —
15 запросов, $0.12 (`journal/task04/live-test-plan.md` §3).

## TASK 03 — надёжность адаптивной генерации (2026-11-19)

**Задача:** после TASK 02B-FINAL провести аудит по фактическому коду и довести
адаптивную генерацию до надёжного состояния: единая оценка токенов и
калибровка по `usage`, честные возможности модели/fallback, согласованность
prompt-only запросов, восстановление без потери успешного, прозрачный статус
изображений, распределение 1…1000 карточек, UI-диагностика и числовое поле
карточек. Без новой архитектуры и без ослабления тестов.

**Факты старта:** `git status --porcelain` → `?? redesign/` (каталог владельца
не тронут); `HEAD = e0f8e4b` (`docs(journal): note windows build gate for TASK
02B-FINAL`), ветка `main`. Baseline — **2000 passed + 8 skipped**, `analyze` 0.
Прогоны — только с `--no-pub` (L64). Схема БД и `format_version` не менялись.

**Аудит (только по коду, `journal/task03/audit.md`):** подтверждено 27 дефектов
D1–D27. Критичные: prompt-only план в production считался без обвязки
(`GenerationPipeline` вызывал планировщик без `overhead`); сервис повторно
отбирал image-части и мог разойтись с планом; документные изображения уходили
частями без Vision; `truncated` дробил вход раньше сокращения вывода; бюджет
восстановления считался по числу детей, а не дополнительных запросов;
`Retry-After` терялся; не было калибровки; не было compact-состояния
prompt-only; D.5-план занижал `achievableCards` при большом заказе; UI не
показывал частичный успех/fatal/статус изображений и не имел поля количества.

**Сделано:**
- **Оценка и калибровка:** `TokenValue` (`exact|estimate|reserve|unknown`) и
  `TokenCalibrationSample/Report` (`token_accounting.dart`);
  `GenerationRequestEstimator` считает фактически собранный `userContent`
  системный промпт, каноническую схему, каталог, image-части и continuation тем
  же `ContentTokenEstimator`; `GenerationResult` несёт
  `estimatedInputTokens/estimatedOutputTokens/estimatorVersion`;
  `GenerationRunResult.calibration` + `GenerationDiagnostics.tokenCalibration`
  (debug) сравнивают план/запрос/`usage`; отсутствие `usage` фиксируется явно.
- **Возможности/лимиты:** `GenerationRequestLimits` +
  `resolveGenerationRequestLimits` — единый источник лимитов image-частей/байт/
  тела с источником `user|preset|unknown`; планировщик, сервис и UI используют
  его. Fallback 8 частей/10/24/32 МБ остаётся явным конфигурационным
  допущением (`assumedImageLimits`, `assumptionFields`), а не фактом модели.
  `ModelCapabilities.sources`/`GenerationPlan.capabilitySources` — карта
  источников для диагностики. Изображения без поддержки модели больше не
  попадают в `imageParts` (status `unsupportedModel`, предупреждение
  `imagesWithoutVision`).
- **Изображения:** `GenerationPlan.images` (`PlannedImage`) со статусами
  `sentToModel|catalogOnly|unsupportedModel|omittedBudget|omittedPayload`;
  `GenerationRequest.documentImageParts` — префикс каталога, сервис отправляет
  ровно его; дедуп одинаковых байтов перенесён в план
  (`documentImageDigest`), `skippedDocumentImageIds` — в диагностику;
  предпросмотр показывает «передано/только каталог/без поддержки/исключено».
- **Prompt-only:** `GenerationPipeline` строит план через
  `GenerationPlanBuilder.buildPromptOnly` (обвязка не нулевая);
  `GenerationContinuityState` — компактная сводка принятых карточек (до 1200
  токенов, 40 карточек/40 тегов) после исходных `<wishes>`; резерв сводки
  учтён в `PromptOnlyPlanner` и `GenerationEstimate.continuationReserveTokens`;
  при повторе состояние восстанавливается из успешных карточек.
- **Восстановление:** порядок F.4 — лимит → резерв вывода → дробление;
  `GenerationPlanSplitter.withContext` получает оценщик плана и
  `imageTokens`; последняя попытка при `limit == 1` делит на две части
  (`allowLimitOverflow`, заказ не меняется); бюджет — `max(configured,
  fragments/8)` до 64, списание по дополнительным запросам, поля
  `recoveryRequestsUsed/recoveryBudget/recoveryBudgetExhausted`;
  `Retry-After` — в `GenerationChunkFailure.retryAfter` и в предпросмотре.
- **Распределение:** `_tuneSoftTarget` учитывает заказ (цель
  `ceil(requested/cap)`, 80 % среднего, не ниже 512 токенов) — план больше не
  занижает `achievableCards`, когда материала хватает; D.5-укрупнение и
  распределение лимитов сохранены.
- **UI:** числовое поле `generation-cards-count` с валидацией (положительное
  целое, технический предел `int`) и передачей в
  `GenerationRunRequest.requestedCards`; предпросмотр плана до запуска тем же
  builder-ом (фрагменты/запросы/запрошено/достижимо + причины ограничений),
  невалидный план блокирует запуск; в предпросмотре результата — постоянные
  баннеры частичного успеха/fatal, сводка изображений, число запросов
  восстановления.
- **Тесты:** новые файлы `token_accounting_test`, `generation_request_limits_test`,
  `generation_continuity_test`, `generation_recovery_budget_test`,
  `generation_request_estimator_test`, `generation_plan_images_test`,
  `generation_distribution_test`, `generation_pipeline_reliability_test`,
  `test/widget/generation` (поле, предпросмотр плана, баннеры). Обновлены
  устаревшие ожидания: `truncated` теперь уменьшает лимит/резерв до дробления;
  план большого заказа достигает заказ; изображения без Vision — каталог, а не
  части; D.5-тест 26 проверяет реальный запас материала. Каждое изменение
  ожидания объяснено в тесте/отчёте.
- **Документация:** раздел R `docs/adaptive-generation-architecture.md`;
  `docs/generation-pipeline.md` (бюджет/план/восстановление/UI);
  `journal/KNOWN_LIMITATIONS.md` L122–L136; этот раздел; 
  `journal/task03/audit.md`.

**Гейты:** `fvm flutter test --no-pub --exclude-tags golden` →
**2110 passed + 8 skipped** (`All tests passed!`; baseline 2000 + 8, +110 net);
`fvm flutter test --no-pub --coverage --exclude-tags golden` → **2110 passed +
8 skipped**, покрытие рукописного кода **92.4 % (16193/17529)**;
`fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**484 файла / 0 changed**; `fvm flutter build windows --release --no-pub` →
**`cardflow.exe`** (60,8 с).

**Остатки (L122–L136):** эвристика/калибровка без токенизатора (L122),
бюджет восстановления — предохранитель (L128), приближённый recovery-пересчёт
(L129), prompt-only сводка без семантического дедупа (L130/L136), парсерные
пределы (L131), возможности/цены не вводятся в UI (L133), отброшенные
парсером изображения не отчитываются (L134), `usage` упавших/обрезанных
ответов недоступен (L135). Реальные платные API не вызывались; `redesign/`
не тронут.

## TASK 02B-FINAL — адаптивный план в production, D.5, prompt-only, снятие лимитов (2026-11-19)

**Задача:** TASK 02B-FINAL — полностью закрыть три незавершённых вопроса после
TASK 02B: второй проход D.5 (укрупнение фрагментов при заказе меньше числа
фрагментов), production-поддержка prompt-only через новую архитектуру и снятие
старых искусственных ограничений (20 карточек/фрагмент, кламп 200, бюджеты
8192/16000/8000/2000/512, 8 image-частей, 1000 токенов/изображение, старый
чанкинг), с интеграцией плана в реальный `GenerationPipeline`.

**Факты старта:** `git status --porcelain` → `?? redesign/` (каталог владельца не
тронут); `HEAD = c01b6fa` (`docs(journal): record TASK 02B adaptive planner`),
ветка `main`; коммиты TASK 01/02A/02B на месте: `8e90618`, `007fcc4`, `a7a89a8`,
`d7d0154`, `c01b6fa`. Baseline — **1965 passed + 8 skipped**, `analyze` 0.
Прогоны — только с `--no-pub` (L64). Схема БД и `format_version` не менялись.

**Сделано:**
- **D.5 (второй проход):** `GenerationChunkPlanner._mergeToRequested/_mergePass/
  _mergePair` — соседние фрагменты укрупняются (сначала с общим документом),
  пока их число больше `requestedCards`; заново проверяются `GenerationBudget`
  (окно/`maxInputTokens`/`maxRequestBytes`), image-лимиты и байты, `bodyBytes`,
  выходной резерв. `UnitSpan` сдвигаются, `unitIds`/порядок сохраняются,
  изображения/вложения дедуплицируются, текст не теряется; при невозможности —
  безопасное число фрагментов + `cardsAboveRequested`; лимиты перераспределяются
  (сумма ≤ заказа, каждый ≥ 1). Тесты: 5/12, 10/25, 1/6, 50/10, невозможность
  по бюджету/изображениям/телу, порядок/покрытие/дубли, 1–100 карточек.
- **Prompt-only:** `lib/domain/generation/prompt_only_request.dart` +
  `prompt_only_planner.dart` (`GenerationMode.promptOnly`, `ChunkKind.promptOnly`):
  нет фиктивных `ContentUnit`; учитываются промпт/схема/обёртка, токены темы в
  каждом запросе, output budget, тело; число запросов =
  `ceil(requested / cardsByOutputCap)`, сумма лимитов = заказ; превышение
  `maxChunks` — явная невыполнимость. `GenerationPlanBuilder.buildPromptOnly`.
- **Снятие лимитов:** `generation_model.dart` удалён (нет клампов 2000/16000/
  8000/8192; `GenerationBudget.compute` — единственный расчёт; `512` — явный
  порог валидности); `kMaxCardsPerChunk`, `kImageTokenEstimate`,
  `distributeCardLimits`, `kMaxRequestedCards` удалены; `requestedCardCount`
  без клампа (BigInt/int.max); лимит карточек — `budgetCardsPerRequestCap` из
  output budget/`maxCardsPerRequest`; `PlannedChunk.limit ≥ 1`, фрагменты не
  пропускаются; UI-оценка без 1000/8, предупреждение — по бюджету модели.
- **Production-интеграция:** `GenerationPipeline` строит `GenerationPlan` до
  первого запроса (материалы — `GenerationPlanBuilder`, тема — `PromptOnlyPlanner`),
  валидирует его (невалидный — ошибка ARB без сети) и исполняет `PlannedChunk`
  последовательно; `GenerationRequest.maxOutputTokens` из плана;
  `GenerationChunkFailure.plannedChunk` для точного повтора; `retryFailed` не
  пересобирает план и не дробит заново. `GenerationRunResult` несёт `plan`,
  `requestedCards`/`achievableCards`/`promptOnly`; предпросмотр показывает
  «запрошено/достижимо» и omitted.
- **Восстановление:** `GenerationPlanSplitter` (F.3) дробит только проблемный
  фрагмент по единицам/страницам с сохранением unitIds/порядка/лимитов;
  `truncated` сначала дробит по единицам, если нечего — сокращает вывод (F.4);
  `contextOverflow` (400 по тексту ошибки/невалидный план) и `payloadTooLarge`
  (413) дробятся; `rateLimited`/сеть/auth/refusal — нет; без повторов для
  auth/refusal/исчерпанного дробления. Бюджет восстановления 12 запросов,
  глубина ≤ 3.
- **Изображения:** `CardGenerationService` берёт число частей/байты из аккаунта
  (`maxImagesPerRequest`, `maxImageBytes`), 8/10/24 МБ — только явные допущения
  при неизвестности; `max_tokens` из плана/аккаунта; не вошедшие изображения
  остаются в каталоге.
- **Тесты (+35 net, старые обновлены):** `generation_plan_merge_test` (11),
  `prompt_only_planner_test` (11), `generation_plan_splitter_test` (5),
  `test/integration/adaptive_generation_flow_test.dart` (10) — small/large/
  prompt-only/partial/retry/429/auth/overflow/invalid plan; HTTP 413/400-context (3);
  сервисные лимиты аккаунта (4); UI-предупреждения плана (2, «достижимо меньше/
  больше запрошенного»); заказы 20/21/50/100/200/201/500/1000 и изображения
  1/8/20/50/100. Обновлены устаревшие ожидания: truncated теперь
  сокращает вывод/дробит по единицам; 1 карточка на 3 фрагмента больше не
  пропускает контент (D.5/L-26); распределение заказа переехало в планировщик;
  `generation_model_test` удалён вместе с удалённым старым бюджетом (его роль
  покрывает `generation_budget_test`).
- **Документация:** раздел Q в `docs/adaptive-generation-architecture.md`
  (production-путь, D.5, prompt-only, таблица всех 44 ограничений со статусами);
  `docs/generation-pipeline.md` (бюджет/планирование/восстановление/ошибки);
  `journal/KNOWN_LIMITATIONS.md` L121–L126 сняты, L127–L133 актуальны.

**Гейты:** `fvm flutter test --no-pub --exclude-tags golden` →
**2000 passed + 8 skipped** (`All tests passed!`; baseline 1965 + 8, +35 net);
`fvm flutter test --no-pub --coverage --exclude-tags golden` → **2000 passed +
8 skipped**, покрытие рукописного кода **91.9 % (15585/16958)** (сгенерированные
`*.g.dart`/локализации исключены; новые файлы: `generation_plan_splitter`
92.9 %, `prompt_only_planner` 95.6 %, `generation_plan` 96.1 %,
`generation_pipeline` 93.1 %, `generation_chunk_planner` 90.0 %);
`fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**471 файл / 0 changed**; `fvm flutter gen-l10n` — новые строки ARB;
`fvm flutter build windows --release --no-pub` → **`cardflow.exe`** (62,2 с).

**Остатки/известные ограничения (L128–L133):** бюджет восстановления 12
запросов; приближённый пересчёт токенов при recovery; prompt-only большие
заказы не разделяют факты между запросами (дедуп только по контенту);
парсерные пределы L-05…L-11/L-32/L-33; UI-поле числа карточек не добавлено
(L-44); реальные пределы провайдеров частично неизвестны (допущения явные);
оценка токенов — эвристика (L122). `GenerationChunker` остался совместимым
фасадом, production его не вызывает.

**Следующий шаг:** TASK 02C — оценщик G (калибровка по `usage`), диалог
стоимости/подтверждения, числовое поле карточек и UI-возможности провайдера
(`ProviderCapabilitiesDialog`).

## TASK 02B — адаптивный планировщик фрагментов (2026-11-18)

**Задача:** TASK 02B — планировщик по разделам D.4–D.7 аудита: бюджет модели,
семантическое дробление текста, изображения как единицы содержимого,
распределение карточек без «универсального 20», отсутствие потерь и дублей.
Интеграция `GenerationPipeline`/`CardGenerationService`/адаптеров/UI/БД **не
выполнялась** (условие этапа), реальные API-запросы не запускались.

**Факты старта:** `git status --porcelain` → `?? redesign/` (каталог владельца
не тронут); `HEAD = a7a89a8` (`docs(journal): record TASK 01 audit and TASK 02A
foundation`), ветка `main`; коммиты предыдущих этапов на месте: `8e90618`
(TASK 01, аудит), `007fcc4` (TASK 02A, контракты), `a7a89a8` (журнал).
Baseline 02A — 1899 passed + 8 skipped, `analyze` 0, `format` 459/0. Прогоны —
только с `--no-pub` (L64).

**Сделано (новые файлы + совместимое расширение старых; production-путь прежний):**
- `lib/domain/generation/content_token_estimator.dart` — минимальный контракт
  оценки единиц (`ContentTokenEstimator`: `version`, `charsPerToken`,
  `estimateText`, `estimateImage`) и `ImageTokenEstimate` с источником и
  пометкой допущения. Эвристика: текст — существующий `TokenEstimator` (2,5
  симв./токен); изображение — `ImageTokenModel` модели, если он есть, иначе
  размерная (750 px/токен) или байтовая (256 байт/токен) эвристика с
  `isAssumption`; универсальных 1000 токенов и `length/3.5` нет. Заменяется
  `GenerationEstimator` этапа G без смены контракта.
- `lib/domain/generation/generation_chunk_planner.dart` — `GenerationChunkPlanner`,
  `GenerationChunkPlannerConfig` (мягкая цель 6000 материала/карточку,
  `maxChunks = 512`, глубина дробления 3, допущения лимитов изображений/тела),
  `GenerationOverheadTokens`, `GenerationPlanCoverage`. Бюджет — по D.1 через
  существующий `GenerationBudget` (`окно − резерв вывода − обвязка − запас
  5 %/≥256`), отдельно `maxInputTokens`/`maxRequestBytes` (base64);
  неизвестное окно — 6000/2048 с `BudgetSource.assumption`; при нехватке
  бюджета план `invalid` (`contextWindowTooSmall`), а не «всё равно 2000».
  Упаковка жадная по единицам, дробление `раздел → абзац → предложение →
  строка → руна`, жёсткое деление не рвёт суррогатную пару; прогресс
  гарантирован (нет зацикливания на пограничном фрагменте — бюджет дробления
  вычитает заголовок файла, повтор без прогресса → `unitTooLarge`).
  Изображения: части с сохранением `img:`-id и каталога документа, остальные —
  `catalogOnly`; подгруппы по лимитам модели, orphan-изображения — отдельные
  фрагменты; всё, что не влезло, — в `omitted` с причиной. Лимит карточек —
  из бюджета вывода и `maxCardsPerRequest`; заказ распределяется без нулей и
  без молчаливого среза (предупреждения `requestedAbovePlan`/
  `cardsAboveRequested`).
- `lib/api/generation/generation_plan_builder.dart` — `ContentInventory` из
  `ParsedDocument`/`GenerationAttachment`/`DocumentImage`: стабильные id,
  непрерывное покрытие текста раздела абзацами (конкатенация = текст раздела),
  каталог документа, страницы вложений по `groupKey`, orphan-изображения;
  фиксированная обвязка (системный промпт `gen-ru-v7`, каноническая JSON-схема,
  обёртка через существующий `buildGenerationUserContent`), пожелания и заказ
  карточек; строка каталога — существующий `imageCatalogLine` (без второй
  реализации формата).
- `lib/domain/generation/generation_plan.dart` — аддитивно: `PlannedChunk.
  materialsText` (in-memory, в БД не пишется), `imagePartIds`/`catalogOnlyIds`
  для проверяемого покрытия, `PlanWarningCode.omittedUnits`,
  `PlanInvalidReason.tooManyChunks`.
- `lib/domain/generation/generation_chunker.dart` — совместимый фасад: новые
  поля `GenerationChunk` (`unitIds`, `splitDepth`, `imageParts`,
  `catalogOnly`) с умолчаниями, методы `planChunks`/`chunksFromPlan`; старые
  `chunkDocuments`/`chunkAll`/`splitInHalf` не изменили поведение
  (`splitInHalf` очищает новые поля и увеличивает глубину).
- Тесты (+66): `generation_chunk_planner_test` (сценарии 1–30, параметризованные
  объёмы 1/3/12/40 абзацев × 0/1/8/20 изображений, линейность, отсутствие
  `kMaxCardsPerChunk`/`kImageTokenEstimate`), `content_token_estimator_test`,
  `generation_plan_builder_test`. Проверяются: покрытие (нет потерь), отсутствие
  дублей частей/страниц, исходный порядок, сохранение `image_id` и связей
  изображение↔раздел после дробления, 1/8/20/50/100 изображений, разные лимиты
  моделей, payload, неизвестное окно, окна 8000/128000/200000/1M,
  недостаточный бюджет, очень большой документ, заказ карточек,
  совместимость старого `GenerationChunker`.

**Гейты:** `fvm flutter test --no-pub --coverage --exclude-tags golden` →
**1965 passed + 8 skipped** (`All tests passed!`; baseline 1899 + 8, +66);
покрытие рукописного кода **92.1 % (15066/16361)**; новые файлы —
`generation_plan_builder` **100 % (135/135)**, `content_token_estimator`
**100 % (24/24)**, `generation_chunk_planner` **90.0 % (812/902)**,
`generation_plan` **96.8 % (90/93)**, `generation_chunker` **95.2 % (237/249)**;
`fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**465 файлов / 0 changed**.

**Ограничения/долги (осознанно вне TASK 02B; L121–L127 в
`journal/KNOWN_LIMITATIONS.md`):** планировщик не подключён к пайплайну
(production-путь — прежний чанкер с 2000-клампом и 20 карточками); оценка
токенов — эвристика без калибровки по `usage`; заказ из пожеланий по-прежнему
режется парсером до 200 (политика L-24, не планировщика); второй проход D.5
(заказ меньше числа фрагментов) не реализован — план предупреждает
`cardsAboveRequested`; prompt-only фрагмент создаёт пайплайн (пустой
`PlannedChunk` запрещён контрактом 02A); дедуп одинаковых байтов изображений
остаётся в сервисе.

**Следующий шаг:** TASK 02C — интеграция плана в `GenerationPipeline`
(план → запросы, восстановление/дробление по единицам, `retryable`), затем
оценщик G, UI/стоимость и БД K1. На TASK 02B работа остановлена.

## TASK 02A — фундамент адаптивной генерации: доменные контракты (2026-11-18)

**Задача:** TASK 02A — только фундамент архитектуры из
`docs/adaptive-generation-architecture.md` (раздел P, шаг 1): возможности
модели, цены, бюджет, единицы содержимого, план. Планировщик, пайплайн, сервис,
адаптеры, UI и БД не менялись.

**Факты старта:** `git status --porcelain` → `M journal/STATE.md`,
`?? docs/adaptive-generation-architecture.md`, `?? redesign/` (TASK 01 сохранён,
каталог владельца не тронут); `HEAD = af3172a`, ветка `main`. Baseline L76 —
1822 passed + 8 skipped (TASK 01 был AUDIT-ONLY, код не менялся).
Прогоны — только с `--no-pub` (L64).

**Сделано (домен + JSON аккаунтов; production-путь прежний):**
- `lib/domain/generation/model_capabilities.dart` — `CapabilitySource`
  (`verified|preset|user|inferred|unknown`), `TokenizerKind`, `ImageTokenModel`
  (E.4), `ModelCapabilities` (nullable-значения + источники групп),
  `resolveModelCapabilities`: аккаунт (user) → каталог пресета (preset) →
  unknown. Окно пользовательской модели **не** подставляется из
  `ProviderAccount.contextTokens` (16 000 — заглушка приложения, L-18),
  `maxOutputTokens` — не 8192 сервиса, strict-схема и image-токены — `null`
  (подтверждённых данных в репозитории нет).
- `generation_pricing.dart` — `GenerationPricing` (nullable цены/валюта),
  `PricingState` (`complete|incomplete|unknown`), `GenerationCost`;
  `costFor` → `null` при неполных ценах и 0 только при явно нулевой цене;
  JSON `input_per_mtok|output_per_mtok|currency`.
- `generation_budget.dart` — `GenerationBudget.compute` по D.1:
  окно − резерв вывода − фиксированная обвязка − запас (5 %, ≥ 256);
  лимиты `maxInputTokens`/`maxRequestBytes` (base64); unknown-стратегия
  6000/2048 с `BudgetSource.assumption`; клампинга 2000 нет —
  `isWorkable`/`shortfallTokens`; `BudgetTrace` (формула, слагаемые,
  источники, `unknownFields`), `GenerationBudgetConfig` (калибруемые
  допущения, не факты модели), `base64EncodedByteLength`.
- `content_unit.dart` — `ContentInventory`, `DocumentUnit`, `SectionUnit`,
  `TextPiece`, `ImageRef` (обёртка над `DocumentImage`), `DocumentCatalog`,
  `AttachmentUnit`/`PageUnit`, `OrphanImageUnit`, `PageRange`; стабильные id
  `doc:<файл>#<раздел>#<фрагмент>`, `img:<файл>#<n>`, `att:<ключ>[#pN]`;
  каталог документа объединяется с изображениями разделов (изображение не
  выпадает), orphan-изображение — отдельная единица.
- `generation_plan.dart` — `GenerationPlan`, `PlannedChunk`, `UnitSpan`,
  `OmittedUnit`/`OmittedReason` (`budget|providerImageCap|payload|unsupported`),
  `PlanValidity` (+ `PlanWarningCode`, `PlanInvalidReason`), `GenerationEstimate`
  (G.6; стоимость nullable). Пустой фрагмент и `limit < 1` запрещены assert-ом;
  `plannedCards`/`plannedRequests` вычисляются из фрагментов (без дубля полей).
  JSON плана не пишется: `plan_json` в БД не добавляется (K.2), материалы в БД
  запрещены (SPEC 3.4), поэтому план — in-memory.
- `provider_account.dart` — JSON аккаунтов v2
  (`ProviderAccounts.version = 2`): nullable `max_output_tokens`,
  `max_images_per_request`, `max_image_bytes`, `max_request_bytes`, `pricing`,
  `capabilities_source`; чтение v1 (поля отсутствуют → неизвестны),
  нулевые/битые значения → `null`, неизвестные ключи игнорируются.

**Решения по nullable/неизвестности:** неизвестная характеристика — `null` +
`CapabilitySource.unknown` (никогда 0); каталог пресета — источник `preset`
(не `verified`: подтверждённой документации в репозитории нет); пользовательские
значения — `user` (явное значение в JSON без источника подписывается `user`
в резолвере — одна логика, без дубля в `fromJson`); цены при неполных данных
дают `null`/`incomplete`, не 0; бюджет при неизвестном окне — консервативное
допущение с явной пометкой source/unknownFields.

**Тесты (+77):** новые `generation_pricing_test` (12),
`model_capabilities_test` (12), `generation_budget_test` (13),
`content_unit_test` (16), `generation_plan_test` (17) и 7 новых в
`provider_account_test` (v2 round-trip, legacy v1, битые/нулевые значения,
pricing с null, copyWith): известные/неизвестные характеристики, сериализация
и десериализация, совместимость старых JSON-конфигураций, отсутствующие
nullable-поля, «unknown ≠ 0», пользовательские значения, валидность
плана/бюджета, «нет потерь» в каталоге изображений.

**Гейты:** `fvm flutter test --no-pub --coverage --exclude-tags golden` →
**1899 passed + 8 skipped** (`All tests passed!`; baseline 1822 + 8, +77);
покрытие рукописного кода **92.7 % (14055/15166)**; новые доменные файлы
**100 %** (`model_capabilities` 48/48, `generation_pricing` 59/59,
`generation_budget` 57/57, `content_unit` 132/132, `generation_plan` 91/91),
`provider_account` 87.4 %; `fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**459 файлов / 0 changed**.

**Ограничения/долги (осознанно вне TASK 02A):**
- планировщик (`generation_chunk_planner`/`generation_plan_builder`), оценщик
  (`generation_estimator`), пайплайн, сервис, адаптеры, UI, классификатор
  ошибок и БД K1 — следующие шаги; старый путь генерации новые контракты ещё
  не использует;
- `ProviderAccount.contextTokens` пока не считается пользовательским окном
  (UI-поля нет); после появления поля источник `user` должен включать его явно;
- редактирование аккаунта в текущем UI создаёт аккаунт без новых полей —
  сохранение возможностей/цен появится с `ProviderCapabilitiesDialog` (I23);
  до этого новые поля UI не заполняет;
- `GenerationPlan`/`ContentInventory` — in-memory: токены единиц считает
  будущий оценщик, собственной оценки в фундаменте нет.

**Следующий шаг:** TASK 02B — планировщик по D.4–D.7 и
`generation_plan_builder`, фасад `generation_chunker`, тесты инвариантов и
«нет потерь»; затем оценщик (G) и пайплайн (F). На TASK 02A работа остановлена.

## TASK 01 — аудит пайплайна генерации и план адаптивной архитектуры (2026-11-18, AUDIT-ONLY)

**Задача:** отдельный трек по запросу владельца (не итерация продукта):
исследовать путь «контент → карточки» и подготовить план адаптивного
токен-осознанного чанкинга, снятия искусственных лимитов, мультимодальной
обработки, бюджетирования контекста/вывода, восстановления после переполнений,
оценки токенов и стоимости, предупреждений перед генерацией.

**Факты старта:** `git status --porcelain` → `?? redesign/` (только каталог
владельца), `HEAD = af3172a` (`docs(journal): table of L76 CI runs and runner
capacity cancellations`), ветка `main`; baseline из L76 — **1822 passed +
8 skipped** (не перепроверялся: код не менялся). Расхождения со STATE, найденные
при сверке: последний зафиксированный в L76 хеш — `bdc5336`, фактический HEAD на
два docs-коммита новее (`9e4bb0f`, `af3172a`); `lib/ui.rar` в дереве отсутствует
(остался только `redesign/`). Исторические записи не переписывались.

**Сделано (только документы; production-код, лимиты, модели, схема БД не менялись):**
- `docs/adaptive-generation-architecture.md` — полный аудит и проект: диаграмма
  пайплайна, реестр **44** ограничений с классификацией A/B/C/D, архитектура
  возможностей модели (`ModelCapabilities`, nullable + источник), адаптивный
  планировщик (формула `effectiveInputBudget`, резерв вывода, мягкая цель,
  инварианты, `GenerationPlan`), мультимодальные единицы контента (ассоциации
  секция↔страница↔изображение), восстановление (категории ошибок, рекурсивное
  дробление, отдельная стратегия для output truncation, бюджеты попыток),
  оценщик токенов/стоимости (unknown ≠ 0), поток предупреждения о стоимости,
  точный список изменяемых/новых файлов с критериями приёмки, изменения модели
  данных (JSON аккаунтов v2; `generation_jobs` + 5 nullable-колонок, K1),
  миграция/совместимость, 30 тест-кейсов по п.10 задания, производительность/память,
  риски и порядок реализации.
- Эта запись в STATE (по конвенции журнала). Других файлов не касались.

**Ключевые дефекты, подтверждённые кодом (входят в план):**
1. Переполнение контекста не обрабатывается: 400/413 сводятся к `badRequest`
   (`generation_http_client.dart:194-281`), дробится только `truncated`
   (`generation_pipeline.dart:406-416`) — большие документы на малом окне
   гарантированно падают.
2. Малое окно ломается формулой: `inputTokenBudget` клампится в 2000
   (`generation_model.dart:19,38`); для `moonshot-v1-8k` (8000) 2000 + системный
   промпт (~6566) + вывод > окна.
3. Молчаливая потеря контента: фрагменты с `limit == 0` пропускаются
   (`generation_pipeline.dart:368-371`), заказ карточек режется 200
   (`generation_card_limit.dart:12,44`) и `maxPerChunk × chunks` (`:62-63`).
4. `splitInHalf` запрещён для фрагментов с картинками и теряет каталог
   (`generation_chunker.dart:320,341-354`).
5. Совокупный размер запроса не ограничен: 3 страницы скана по ≤ 10 МБ + до 8
   image-частей (≤ 24 МБ) → тело до ~54 МБ (base64 ~72 МБ) без проверки.
6. `retryable` всегда `true` (`generation_run.dart:105`) — повтор
   детерминированных ошибок (vision/PDF/размер).
7. Цен и модели стоимости нет вообще; оценка токенов расходится между UI и
   пайплайном, не включает схему, каталог `<images>`, image-части, ретраи.

**Гейты:** не запускались — задача AUDIT-ONLY, `lib/`, `test/`, `pubspec.yaml`
не изменялись; проверка свелась к чтению кода и сверке путей документа
(144 извлечённые ссылки, несуществующих «старых» путей нет; новые пути — план
реализации). `docs/generation-pipeline.md` устарел (≤ 4 страницы вместо 3,
`GenerationModel.contextTokens`, Openverse как единственный поиск) — обновляется
в итерации реализации.

**Следующий шаг:** итерация реализации по разделу P документа (контракты →
планировщик → пайплайн → сервис/адаптеры → UI → БД K1 → документация → live).

## Итерация L76 — PDF Visual Intelligence (2026-11-18, ADR-037)

**Факты старта:** `git status --porcelain` → пусто,
`HEAD = origin/main = 4d6b992` (`docs(cleanup): record green CI for cleanup-1`);
baseline **1775 passed + 8 skipped**, `analyze` 0, `format` 0. Прогоны — только
с `--no-pub` (L64).

**Аудит (факты, не предположения):** `pdfrx 2.12.0`/`pdfrx_engine 0.9.1` даёт
только текст и рендер страниц — API объектов страницы в нём нет (grep
`FPDFPage_GetObject`/`FPDFImageObj_*`/`FPDFFormObj_*` — 0). `FPDFImageObj_GetRenderedBitmap`
отдаёт растр **в размере на странице** (спайк: 300×200 px при выводе 150×100 pt →
150×100). OCR-подсистемы в проекте нет. `DocumentImage` из DOCX отправлялся
модели только строкой каталога — байты не уходили (пробел). Промпт в коде —
`gen-ru-v6`, файла `gen-ru-v7` не было. `syncfusion_flutter_pdf` отклонён
(коммерческая/community-лицензия Syncfusion, pub.dev `unknown`), `pdfx` не нужен.

**Спайки (кодом, три гипотезы):** (1) прямые FFI-вызовы `pdfium_dart` из
изолята после `pdfrxInitialize()` падают — `Cannot invoke native callback from a
different isolate`; (2) в воркер-изоляте `pdfrx`
(`PdfrxEntryFunctions.instance.compute`) извлечение работает, результат
(`Uint8List` + метаданные) передаётся между изолятами; (3) рендер **области**
страницы с масштабом «пиксели изображения / размер на странице» возвращает
исходное разрешение (300×200), маски/цветовые пространства обрабатывает PDFium.

**Сделано:**
- `PdfImageExtractor` (`lib/api/parsers/pdf_image_extractor.dart`) — Image и
  Form XObject, метаданные (`width`/`height`/bpp/colorspace), положение
  (`FPDFPageObj_GetBounds` + матрица формы), порядок на странице, PNG в исходном
  разрешении (резерв — растр PDFium в размере отображения); guard-лимиты
  (≥ 32 px, ≤ 16 млн пикселей, ≤ 60 изображений, ≤ 2600 px сторона).
- `PdfPageClassifier` — постранично `textLayer`/`scanned`/`blank` (порог 50
  символов): смешанный PDF обрабатывается страница за страницей.
- `PdfPageRegionDetector` — сетка «чернил», дилатация, связные компоненты,
  склейка, отсев строк текста/тонких линий, вырезка из полного рендера без
  масштабирования; «одна большая схема» → страница целиком.
- `PdfScanPageExtractor`/`PdfScanDocument` — страницы скана (рендер PDFium,
  номера страниц) + области → `DocumentImage(source: renderedPage/croppedRegion)`.
- `PdfParser` — текст + изображения + рендеры/области; привязка к разделу
  (`ParsedDocumentBuilder.addImageToSection`), страница сохраняется; полностью
  сканированный PDF по-прежнему `scannedPdf` (страницы уходят image-частями).
- `DocumentImage` расширен обратно совместимо: `source`, `rect` (доли 0..1),
  `order`; DOCX/PPTX/ODT без изменений поведения.
- Фильтр `PdfImageFilter` (иконки, тонкие линии, однотонные плашки; повторы по
  SHA-256; небольшие формулы на странице с подписью рисунка сохраняются).
- Vision: `CardGenerationService` добавляет image-части документов для моделей
  с Vision (`selectVisionDocumentImages`: приоритет подпись → область/встроенное
  → площадь; ≤ 8 частей и ≤ 24 МБ, дедуп по SHA-256); перед каждой частью —
  подпись каталога (`GenerationAttachment.label`) во всех трёх протоколах,
  поэтому `image_id` сопоставим однозначно; каталог `<images>` полный, не
  вошедшие изображения разрешаются по `image_id` при импорте.
- `GenerationRunRequest.documentImages` → чанкер кладёт области скана во
  фрагмент своего файла; экран генерации разбирает скан `PdfScanPageExtractor`.
- Промпт `gen-ru-v7` = `gen-ru-v6` дословно + блок «ИЗОБРАЖЕНИЯ ИЗ PDF И
  СКАНОВ» (текст задания + правила каталога/частей/усечения); копия
  `docs/prompts/gen-ru-v7.txt` (тест сверяет байты); v5/v6 сохранены.
- `MediaStore`: парсер не пишет файлы (как DOCX), карточка при импорте пишет
  файл и строку `media` — сквозной путь покрыт интеграционным тестом.

**Гейты итерации:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **1822 passed + 8 skipped** (`All tests passed!`; baseline 1775 + 47 новых);
**набор CI (`--exclude-tags golden,live`) → 1819 passed** (офлайновый прогон);
покрытие рукописного кода **92.5 % (13638/14746)**, новые файлы:
`pdf_image_extractor` 87.3 %, `pdf_page_regions` 93.8 %, `pdf_parser` 91.3 %,
`pdf_scan_pages` 100 %, `document_image` 93.4 %; `fvm flutter analyze --no-pub`
→ **No issues found!**; `fvm dart format --set-exit-if-changed lib test
integration_test tool` → **449 файлов / 0 changed**;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (64,9 с).

**Тесты (47 новых):** `pdf_document_images_test` (10: обычный PDF, Form
XObject, без изображений, повторы, иконка, формула с подписью, скан →
`scannedPdf`, смешанный PDF, битое изображение), `pdf_page_classifier_test` (6),
`pdf_page_regions_test` (6), `pdf_scan_pages_test` (5, реальный PDFium),
`pdf_document_images_vision_test` (6: байты в запросе + подпись, без Vision,
лимит 8/каталог, дедуп, чужой `image_id`, страница скана),
`document_image_test` (7), `generation_chunker` (2: области скана в свой
фрагмент, сироты), `prompt_test` v7 (4: байты, v6 внутри, текст задания, JSON),
`test/integration/pdf_image_flow_test.dart` (1: PDF → изображение → image-part в
запросе → `image_id` → импорт → файл в `MediaStore` байт-в-байт).

**Живая проверка (DeepSeek, `deepseek-chat`, настоящий API):** `fvm flutter test
test/live/openai_compatible_deepseek_live_test.dart --tags live --no-pub` →
**7 passed** с промптом `gen-ru-v7`: `cards=3, tokens=5509`; fallback
`strict=400 → tolerant=200`; prompt-only `cards=3, image_query=3, prompt=gen-ru-v7`;
PDF-скан страницами (`pages=3, cards=2`); статика 20 карточек (пометок 4/20,
`rejected=0`); DOCX с рисунком (`images=1, image_id=4, with_image=4`).
Заодно исправлена устаревшая live-проверка: она ждала в сыром ответе
`image_query` (схема v4/v5), теперь принимает объект `image` (v6+) — тест
остался строгим, но соответствует действующей схеме.

**Ограничения итерации:** L115–L120 (нет локального OCR — текст скана
распознаёт vision-модель; геометрический детектор областей; векторные схемы на
страницах с длинным текстом не вырезаются; координаты вложенных форм — в
системе формы; лимиты 60/24/3 страницы/8 частей/24 МБ; отмена парсинга не
поддерживается). L76 **снято** в объёме «встроенные изображения PDF
извлекаются и используются».

**Красный CI и его причина (разобрано по фактам).** Прогон `481f2cb` дал по
одному падению в `test` на Ubuntu и Windows (остальные 7 job'ов зелёные).
Первая гипотеза — сетевой live-тест (L92) — не подтвердилась: после
`--exclude-tags golden,live` падение повторилось, **и воспроизвелось локально**
тем же фильтром: `test/widget/study/study_modes_test.dart: «карточка с due в
будущем пишется как тренировка»`. Причина — **тест-бомба с датой**: виджет
сравнивает `due` с реальными часами (`isDueForStudy(card, DateTime.now)`), а
фикстура задавала `due = DateTime.utc(2026, 11, 16, 12) + 2 дня`
= 2026-11-18 12:00 UTC — после этого момента due оказывается в прошлом и FSRS
пишется вместо тренировки. Подтверждено прогоном на **базовом коммите
`4d6b992`** (та же ошибка ⇒ дефект не внесён этой итерацией). Исправление:
due считается от текущего момента (`DateTime.now().toUtc() + 30 дней`), тест
по-прежнему проверяет «будущая due → тренировка». Заодно закрыто **L92**:
job `test` теперь `--exclude-tags golden,live` (обычный прогон офлайновый и
детерминированный; live-проверки — по тегу), аннотация падений публикует
строки `Failing tests`/`[E]`, guard `ci_pdfium_test` обновлён. После фикса
(`9cf28a2`) прогон
[`44349211802`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44349211802):
`format + analyze` ✅, `test` Ubuntu ✅, `test` Windows ✅, 6 сборок ✅;
`test` macOS **отменён раннером** — «The job was not acquired by Runner of type
hosted even after multiple attempts» (capacity constraints macOS arm64), шагов
не было, т.е. инфраструктура, а не ошибка кода → итоговый conclusion прогона
`failure` только из-за этого; повторный прогон — после docs-коммита.
Прогон [`44352510436`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44352510436)
(`19b2c3a`): `test` Ubuntu ✅, `test` Windows ✅, `format + analyze` ✅,
`build` android/windows/linux/ios ✅; `test (macos)` и `build macos` снова
**отменены раннером** — 0 шагов, «not acquired by Runner … capacity constraints
macOS arm64» (инфраструктура GitHub; так же было в итерации 7.16).

**Push/CI итерации L76:** `4d6b992..bdc5336`. Финальный прогон
[`44355509340`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44355509340)
(`bdc5336`) — **9/9 job success**: `format + analyze`, `test` × 3 ОС
(Ubuntu/Windows/macOS), `build` desktop × 3 + Android + iOS. Коммиты:
`77dca82` (извлечение PDF-изображений, vision, промпт v7, тесты),
`c21d753` (ADR-037/parsers/dependencies/STATE/limitations), `481f2cb`
(live-проверка схемы v6+), `553a3e6` (CI: `golden,live`, диагностика падений,
L92), `9cf28a2` (тест-бомба с датой), `19b2c3a`/`bdc5336` (STATE: факты
прогонов, инфраструктурные отмены macOS). Рабочее дерево: остались
**неотслеживаемые** файлы владельца (`lib/ui.rar`, `redesign/`) — в коммиты не
попали.

## Итерация cleanup-1 — отказ от «Nocturne» и фикс «Создать колоду» (2026-11-18, ADR-036)

**Факты старта:** `git status --porcelain` → пусто, `HEAD = 4ca8e00`
(этап 3 Nocturne, 43 коммита впереди `origin/main = 8e9db8a`); baseline
**2121 passed + 8 skipped**. Прогоны — только с `--no-pub` (L64).

**Решение владельца:** дизайн-система провалилась (скорость и стабильность);
полное удаление наследия, чистый Material 3, Indigo `#4F46E5`. ADR-035 →
**отменён** ADR-036.

**Критический баг «Создать колоду» (белый экран) — найдена корневая причина:**
`showNcDialog` собирал `actions` диалога во внешнем `BuildContext` экрана, а
`DecksScreen` живёт в ветке `StatefulShellRoute` со **своим навигатором**.
`Navigator.of(context).pop()` выталкивал из ветки **экран** вместо маршрута
диалога: `You have popped the last page off of the stack`
(`go_router/src/delegate.dart:178`), белый экран, незавершённый фьючер
`showDialog`, `!debugLocked` на финализации. Воспроизведено на
production-проводке (`CardFlowApp` + `createAppRouter`) — 0 виджетов
`DecksScreen` после закрытия диалога. Исправление: диалог снова
самодостаточный `_DeckNameDialog`, закрывающий себя из собственного `context`;
проверены все 12 мест `showDialog`. Ограждение —
`test/widget/decks/create_deck_dialog_test.dart` (3 случая: открыть/закрыть,
создать, пустое имя).

**Удалено (511 файлов, −28 059 строк):** `lib/ui/design/**` (56 файлов:
`NcAmbientBackground` + Aurora, `NcGlass`/`NcGlassGroup` и все
`BackdropFilter`, 37 компонентов с `rim light` и градиентами, токены
`nc_colors/typography/spacing/radii/depth`, `nc_theme`, `motion_scope`,
`haptics`, Nocturne-переходы), `test/golden/**` (346 PNG), `tool/screenshots/**`
+ `tool/extract_ui_keys.dart` (51), Nocturne-тесты (43), 7 ассетов шрифтов и
зерна, пакет `redesign/`. Восстановлено из `7458346` 46 файлов: экраны этапа 3,
оболочка, тема, `app.dart`, `main.dart`, ARB (88 Nocturne-строк), `pubspec.yaml`
(+`material_color_utilities`, `cupertino_ui` — удалены), `.gitignore`, `docs`.
Ни одна строка `lib/{domain,data,api}` не изменилась.

**Что стало вместо:** `AppTheme` — `ColorScheme.fromSeed` +
`ThemeData(useMaterial3: true)`, акцент Indigo `#4F46E5`; экраны — простые
Material/M3E-виджеты; фон статичен (кадры только по событиям).

**Гейты итерации:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **1775 passed + 8 skipped** (`All tests passed!`; 1771 baseline + 1 сетевой
live + 3 новых); покрытие рукописного кода **92.5 % (12948/13996)**
(`AppTheme` 100 %); `fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**438 файлов / 0 changed**; `fvm flutter build windows --release --no-pub` →
`cardflow.exe` (65,2 с). **Windows-смоук на реальном процессе**
(`integration_test/session_smoke_windows_test.dart -d windows --no-pub`) →
**All tests passed!** (10 с; debug-сборка 30,4 с) — в смоук добавлен шаг 0:
«Создать колоду» на боевой оболочке открывает и закрывает диалог, экран ветки
остаётся; дальше прежний сквозной сценарий (картинка Basic, дневной лимит,
генерация с настоящим Wikimedia) зелёный.

**Историческое наследие:** журналы `journal/redesign-1..3/` (146 файлов,
29,3 МБ) и ADR-035 сохранены со статусом «отменён» — причины закрытого
направления не переписываются. Новые ограничения — L111–L114 (L-seкция
`KNOWN_LIMITATIONS.md`).

**Коммиты итерации (5):** `ac3f109` — удаление Nocturne и возврат экранов
(+511 файлов удалено), `6de6eca` — Indigo-сид темы, `493f732` — тест диалога
«Создать колоду» на production-проводке, `500c9aa` — шаг диалога в Windows-смоуке,
`ae9227a` — ADR-036/STATE/journal/limitations.

**Push/CI:** `8e9db8a..ae9227a` (44 коммита: этапы 1–3 Nocturne + cleanup-1);
CI run [`44184233645`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44184233645)
— **9/9 job success** (`format + analyze`, `test` × 3 ОС, `build` desktop × 3 +
Android + iOS).

## Редизайн «Nocturne» — этап 2 «Компоненты» (2026-11-17, ADR-035) — ОТМЕНЁН

**Факты старта:** `git status --porcelain` → пусто, `HEAD = origin/main =
8e9db8a` (`docs: confirm 9/9 CI for docs commit 734c120`). Baseline этапа 1 —
1924 passed + 8 skipped. Прогоны — только с `--no-pub` (L64).

**Гейты этапа 2:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **2036 passed + 8 skipped** (+112 к baseline); покрытие `lib/ui/design/`
**93,8 % (2672/2848)**, `components/` **93,1 % (2116/2272)**, рукописный код
**92,8 % (15825/17047)**; `fvm flutter test --no-pub test/golden` →
**298 passed** (298 PNG, 4,25 МБ); `analyze` **0**; `dart format
--set-exit-if-changed lib test integration_test tool` → **530 / 0 changed**;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (60,0 с).
Красная зона и экраны: `git diff --stat 8e9db8a..HEAD` пуст (19 файлов
Красной зоны, `*_screen.dart`, `app_shell.dart`, `review_chrome.dart`).

**Сделано (шаги 2.1–2.8):** библиотека `lib/ui/design/components/` — 37
компонентов + 7 внутренних примитивов (`NcTappable`, `NcPressScale`,
`NcFocusRing`, `NcSpringBuilder`, `NcStagger`, `NcScrollCollapseScope`,
`NcButtonAppearance`) по REDESIGN-SPEC §8: примитивы, действия, ввод,
структура, оверлеи, прогресс, сессионные. Каждый компонент — на токенах
`NcTheme.of`, пружинах `NcMotion.of` и `NcHaptics`; экспорт — `design.dart`;
ни один не импортирует Riverpod/роутер/домен (guard расширен).
**Глобальный переход тостов:** `showAppMessage` и `showArchivedUndoSnackbar`
в `deck_actions.dart` показывают `NcToast` при прежних сигнатурах, текстах,
«Отменить» и поведении undo; старые экранные тесты зелёные, добавлены два
теста проводки (`test/widget/design/toast_wiring_test.dart`).
**Golden-инфраструктура:** `test/helpers/nc_golden.dart` (8 вариантов:
dark/light × обычный/high-contrast × textScale 1,0/2,0), `nc_harness.dart`,
`glass_budget.dart`; каталог-полотно —
`journal/redesign-2/screenshots/components-catalog-{dark,light}.png`.

**Коммиты этапа (13):** red/green по группам — `9da7782`/`0446cc6` (2.1),
`e207be2`/`60164b9` (2.2), `507a49d`/`b59b672` (2.3), `7adf028`/`6107531`
(2.4), `82363c7` (2.5), `535ffe2`/`20dff64` (2.6), `5f33d0a`/`44e0c41` (2.7)
+ финальный verify/docs-коммит.

**Отклонения/решения (ADR-035, раздел «Этап 2»):** зерно стекла — процедурный
painter (детерминизм golden); `NcIcon3D`-резерв без `BackdropFilter` (бюджет
§4.4); `NcToast` не перехватывает указатель и обновляет полосу шагом 200 мс
(совместимость с `pumpAndSettle` старых тестов); AI-блик одноразовый;
neighbor-squish — доли `flex`; `NcFlip` при `disableAnimations` — кроссфейд
120 мс; golden сняты на Windows.

**Новые ограничения:** L98 (golden на Windows, CI без тега golden),
L99 (squish долями), L100 (NcTopBar/NcFab подключаются на этапе 3),
L101 (3D-ассетов нет — резерв), L102 (бюджет стекла на компонентах, не на
экранах), L103 (ступенчатая полоса тоста).

**Push/CI:** коммиты этапа 2 не пушились — push и прогон 9/9 job — по команде
владельца (AGENTS.md).

**Следующий шаг:** этап 3 «Каталог» — `NcNavDock`/`NcNavRail` и перевод
экранов вне сессии (оболочка, «Мои колоды», экран колоды, форма карточки,
конструктор, статистика, настройки, провайдеры) с сохранением ключей §9 и
бюджетом стекла ≤ 2 групп на экран.

## Редизайн «Nocturne» — этап 3 «Каталог» (2026-11-17)

**Факты старта:** `git status --porcelain` → пусто, `HEAD = 4b4cc21`
(этап 2 принят; на 15 коммитов впереди `origin/main = 8e9db8a` — push этапа 2
в remote не ушёл, выполняется владельцем). Baseline — 2036 passed + 8 skipped.

**Гейты этапа 3:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **2121 passed + 8 skipped** (+85 к baseline); покрытие рукописного кода
**93,1 % (16799/18043)**, порог 80 % пройден; `--tags golden` → **336 passed**
(экраны этапа 3 + библиотека этапа 2); `analyze` **0**; `dart format
--set-exit-if-changed lib test integration_test` → **541 / 0 changed**;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (67,2 с);
Windows-смоук `integration_test/session_smoke_windows_test.dart -d windows
--no-pub` → **All tests passed!** (39 с) — смоук переведён на фиксированные
кадры (`settle`), потому что в реальном процессе фон Aurora дрейфует
бесконечно и `pumpAndSettle` не завершается.

**Сделано (шаги 3.1–3.8):** оболочка `NcNavDock`/`NcNavRail`/сайдбар 248
(ключи `shell-nav-*`), «Мои колоды» с сеткой 1/2/3, сводкой и Hero-тегами,
экран колоды (hero-CTA, стат-пилюли, сетка режимов 2×4/4×2, парящий тулбар),
форма карточки + стили контента §9.20, конструктор с пронумерованными
секциями и `NcStepper`, статистика на токенах (`NcColors.heat`), настройки
(`NcSection`/`NcSlider`/`NcChip`/`NcStepper`) и провайдеры (карточки,
`NcDropdown`, проверка ключа бейджем). Guard миграции расширен на 13 файлов,
`ui_keys.txt` — **238 ключей**, Красная зона: `git diff --stat
4b4cc21..HEAD -- <19 файлов>` пуст. Скриншоты — 48 PNG (8 экранов × 2 темы ×
3 ширины), golden экранов — 16 PNG.

**Отклонения (журнал `journal/redesign-3/README.md`):** плитка колоды 92 px
вместо 88 (вмещение двух строк), аватар в конструкторе 40 px (NcIcon3D
запрещает < 40), миниатюры карточек в списке колоды не загружаются,
предпросмотр полей формы свёрнут по умолчанию, fade-out occlusion-маски
заменён мгновенным раскрытием (тесты контента ждут исчезновения после одного
`pump`), подсказка ⌘K в сайдбаре — этап 5.

## Редизайн «Nocturne» — этап 1 «Фундамент» (2026-11-17, ADR-035)

**Факты старта:** `git status --porcelain` → только `?? redesign/` (пакет
документации), `HEAD = origin/main = 7458346` (`docs: record green CI for
7.17`). Baseline: **1771 passed + 8 skipped**, одно падение — живой Wikimedia
(сеть, L92); в STATE 7.17 записано 1772 + 8 (расхождение — тот же live-тест).
Прогоны — только с `--no-pub` (L64).

**Гейты этапа 1:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **1924 passed + 8 skipped** (+152 к baseline); покрытие рукописного кода
**92.8 % (13706/14775)** (`tool/coverage_check.dart --min=80`); `analyze` **0**;
`dart format --set-exit-if-changed lib test integration_test tool` → **0
changed**; `fvm flutter build windows --release --no-pub` → `cardflow.exe`
(61,1 с). Скриншоты: `journal/redesign-1/screenshots/` — 60 PNG (15 экранов ×
2 темы × 390×844 и 1440×900). Красная зона и экраны: `git diff --stat` пуст
(`journal/redesign-1/red-zone.md`).

**Сделано (шаги 1.0–1.7):** ADR-035 (замена SPEC A4 в визуальном слое) и
спайки (`journal/redesign-1/spikes.md`); guard-тесты (`tool/extract_ui_keys.dart`
+ снимок 219 ключей, `design_tokens_test`, `no_network_fonts_test`,
`haptics_test`, изоляция `design/` в `architecture_test`); токены
`lib/ui/design/tokens/` (Nocturne/Porcelain/high-contrast/dynamic HCT,
типографика, сетка, радиусы, глубина, стекло); шрифты Onest/Literata/
JetBrains Mono (переменные, OFL, `LicenseRegistry`) и растровый тест
кириллицы; `NcTheme` (ThemeExtension) + ручной `ColorScheme` §1.5 в
`AppTheme` (публичный API прежний, elevation 0, прозрачный `scaffold`,
18 тем компонентов, шрифт дислексии во всех ролях); движение
(press/snap/gentle/celebrate, длительности, кривые) и `NcMotion`/
`NcHaptics` (throttle 40 мс); `NcAmbientBackground` (Aurora + зерно) и
`NcPageTransitionsBuilder`; подключение в `builder` `MaterialApp.router`
(`NcMotionScope → NcHapticsScope → NcAmbientBackground → M3ETheme`).

**Коммиты этапа:** `8158fc6` (ADR/спайки), `1daef8c` (guard-тесты),
`3559557` (токены), `bed3196` (шрифты), `1787097` (NcTheme/AppTheme),
`42f13df` + `e4fb90f` (движение/отклик), `a4a5e4c` (фон/переходы/проводка),
далее — журнал/verify.

**Отклонения (в ADR-035):** light-акценты Porcelain затемнены минимально
(4,38 → 4,77 : 1) до нормы AA §10; iOS/macOS делегируют Cupertino-переходом
(жест «назад»), `cupertino_ui` запинен 1.1.6; зерно — тайловый PNG, не
`grain.frag` (детерминизм golden/CI); `TextTheme.bodyLarge` — роль `bodyL`
(Onest 16/24), Literata-роль `answer` живёт в `NcTypography`; дрейф Aurora
выключен под `FLUTTER_TEST`.

**Новые ограничения:** L93 (M3E-виджеты не подчиняются теме), L94 (поля
ввода без superellipse), L95 (дрейф Aurora не виден в тестах), L96 (бюджет
стекла не измерен — нет Android SDK), L97 (guard-долг: 29 литералов цвета +
7 файлов с `HapticFeedback.`, burn-down в этапах 3–4).

**Push и CI этапа 1:** `7458346..9a19d97` (9 коммитов + пакет
`redesign/`). CI run
[`43970683883`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43970683883)
— **9/9 job success** (`format + analyze`, `test` × Ubuntu/Windows/macOS,
`build` desktop × Linux/Windows/macOS, `build` mobile Android/iOS). Проверочный
docs-коммит `734c120` (`docs: record green CI for Nocturne stage 1`) — CI run
[`43973443414`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43973443414)
— **9/9 job success** (проверено через GitHub API по SHA, jobs: тот же набор).

**Следующий шаг:** этап 2 «Компоненты» — `lib/ui/design/components/` по
REDESIGN-SPEC §8 (примитивы → действия → ввод → структура → оверлеи →
прогресс → сессионные), golden-тесты, счётчик групп `BackdropFilter`.

## Итерация 7.17 — где остановились (до редизайна)

**Дата:** 2026-11-16 · **Этап:** итерация **7.17** «Глобальный рендер LaTeX и
cloze во всех режимах» (ADR-034) — завершена.

**Факты старта 7.17 (сверено командами):** `git status --porcelain` → пусто,
`HEAD = origin/main = 4dfe10c` (`docs: note cancelled macos/ios jobs and rerun
CI`) — в STATE 7.16 последним записан `aad938f`, после него был docs-коммит,
исправлено. Baseline — **1742 passed + 8 skipped**
(`flutter test --no-pub --exclude-tags golden`), `analyze` **0**, `format` **0**.
Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode нет (L2).
Прогоны — только с `--no-pub` (L64).

## Сверка STATE с кодом (7.17, старт)

Проверено по файлам, расхождения исправлены:

- **Режимы:** `classic`, `feed`, `practice`, `constructor` (`_SessionModeAction`
  в `lib/ui/decks/deck_screen.dart`) + новые `test`, `typing`, `match`,
  `true_false` (7.15/7.16). Маршруты — `/decks/:deckId/{study,feed,practice,
  test,typing,match,true-false}` и `/constructor`. Подтверждено.
- **Рендер карточки:** единая точка — `lib/ui/cards/content/`
  (`CardContentView`, `LatexText`, `ClozeText`, `InlineLatexText`). До 7.17
  новые режимы использовали `CardContentView` только для вопроса.
- **Факты приложения:** копия `%APPDATA%\ru.example\cardflow\cardflow\
  cardflow.sqlite` — 175 карточек, 61 с LaTeX (61 формула в ответах, часть в
  вопросах), 6 cloze; все 78 уникальных формул парсятся `flutter_math_fork`.

## Сверка STATE с кодом (7.14, старт)

Проверено по файлам, расхождения исправлены:

- **Режимы:** реально четыре — `classic`, `feed`, `practice`, `constructor`
  (`_SessionModeAction` в `lib/ui/decks/deck_screen.dart`; маршруты
  `/decks/:deckId/{study,feed,practice}` и `/constructor`). В истории STATE
  конструктор упоминался только в итерации 6 — здесь зафиксировано явно.
- **Промпты генерации:** `gen-ru-v5` — сырой литерал
  `lib/api/prompts/system_prompt.dart`, дословная копия
  `docs/prompts/gen-ru-v5.txt`; механизм версии — константы +
  `CardGenerationService.promptVersion`. Подтверждено.
- **ImageSearchService:** до 7.14 это **Openverse**
  (`lib/api/images/image_search_service.dart`), а цепочка —
  `CompositeCardImageFinder` (Commons → Wikipedia → Openverse). В 7.14
  `ImageSearchService` стал цепочкой провайдеров (ADR-031), старые сервисы
  заменены на `ImageProvider`-реализации.
- **MediaStore:** был только файловый (байты по пути); метаданных
  провайдера/лицензии/isPlaceholder не было, `media` их не хранит. В 7.14
  добавлены побочные `<путь>.meta.json` (`MediaMetadata`), схема БД не менялась.
- **FSRS:** `FsrsScheduler` (`lib/domain/scheduling/scheduler.dart`), маппер
  `fsrs_mapper.dart`, начальное состояние `CardSchedulingMapper.initialScheduling`.
  Подтверждено.
- **Лист режимов:** `showModalBottomSheet` в `_startSession`
  (`lib/ui/decks/deck_screen.dart`), ключи `review-mode-*`. Подтверждено.
- **ARB:** один файл `lib/l10n/app_ru.arb`; `supportedLocales` — только `ru`,
  `app_en.arb` нет. Требование задания «ARB (ru, en)» конфликтует с жёстким
  правилом AGENTS/SPEC (локаль только `ru`) и guard-тестом `ru_strings_test`:
  новые строки добавлялись в `app_ru.arb`; английская локаль не вводилась
  (продуктовое решение, не самовольное изменение).
- **Правило «абстрактные понятия без картинки»** было в валидаторе
  (`_isAbstractCard` + `CardIssueCode.abstractImageQuery`) — удалено в 7.14
  вместе с промптом v6.

## Итерация 7.14 — итог (ADR-031)

**Гейты 7.14:** `test --no-pub --coverage --exclude-tags golden` → **1660
passed + 8 skipped** · покрытие рукописного кода **92.0 % (12159/13218)** ·
`analyze` **0** · `format` **0 changed** · `build windows --release --no-pub` →
`cardflow.exe` (84,4 с) · Windows-смоук
`integration_test/session_smoke_windows_test.dart -d windows --no-pub` →
**All tests passed!** (9 с) — форма+картинка, лимит, сессия, генерация с картинкой.

**Сделано:**
- Промпт `gen-ru-v6` (сырой литерал + `docs/prompts/gen-ru-v6.txt`, тест
  байт-в-байт); v5 сохранён. Обязательный объект `image` у каждой карточки
  (`query`, `fallback_query`, `kind`), канонические якоря схем
  (`free body diagram …`, `force couple diagram …`), запреты (русские слова,
  «image/photo of», имена файлов, LaTeX, одно слово, повторы в колоде).
- Схема: строгая v6 для провайдера; локальная терпимая `localCardItemSchema`
  принимает и v5 (`image_query` строкой/`null`), и карточку без `image`.
- Нормализация `image_query_normalizer.dart`: чистка запрещённых слов,
  не-латиницы, имён файлов и LaTeX; обрезка до 7 слов; сборка из fallback;
  дополнение вида; legacy-вывод kind. Правка → `imageQueryAdjusted`, карточка
  не отбрасывается.
- Цепочка `ImageSearchService` + интерфейс `ImageProvider`
  (`wikimedia`, `wikipedia`, `openverse`, `pixabay`, `pexels`): таймаут 6 с на
  провайдера, бюджет 20 с на карточку, основной запрос → fallback, скачивание
  с лимитом 4 параллельно, фильтры JPEG/PNG/WebP + короткая сторона ≥ 400 px +
  пропорции ≤ 3:1 + безопасный поиск, кэш LRU 32, дедупликация URL, ретрай
  одного 429/5xx с backoff, затем следующий провайдер. Ключи Pixabay/Pexels —
  только `--dart-define`/env; без ключа провайдера нет.
- Заглушки: `PlaceholderImageGenerator` (8 палитр, градиент+паттерн+иконка
  вида, детерминированно от хэша содержимого), PNG 800×450/800×600, флаг
  `isPlaceholder`, провайдер `placeholder`. Метаданные атрибуции
  (`provider`, `sourceUrl`, `author`, `license`, `query`, `fallbackQuery`,
  `kind`) — в `MediaStore` рядом с файлом; GC чистит их вместе с медиа.
- «Найти картинку заново» в редакторе карточки (`CardImageRefresher`) и
  фоновый ретрай заглушек на старте (`main.dart`, ≤ 5 за запуск, ошибки глушатся).
- UI: `CardImageView` (16:9, схема 4:3, cover/contain, скругление 16, fade-in,
  скелетон, max-height 220), полноэкранный просмотр с зумом и атрибуцией;
  картинки в предпросмотре, Классике, Ленте, Тренировке, редакторе; живой
  список карточек во время генерации (`GenerationProgress.cards`).
- Тесты: нормализация, схема/совместимость v5, провайдеры (включая
  Pixabay/Pexels на мок-клиенте), цепочка (приоритет/таймаут/фильтры/ретраи/
  кэш/лимит параллелизма/дедуп), заглушки (детерминизм/флаги), `MediaStore`
  и GC, `CardImageRefresher` (замена заглушки, лимит, ошибки), pipeline
  (заглушка, дедуп URL, fallback/kind), виджеты (фото/схема/заглушка/без
  картинки, overflow 360×640 и 1280×800, fullscreen+атрибуция, «Найти заново»,
  живые карточки).

**Живая проверка (2026-11-16, `deepseek-chat`, настоящая сеть):** две колоды по
18 карточек (`test/live/images_v6_live_test.dart`, отчёт
`journal/iteration-7.14/live-metrics.{md,json}`, картинки в
`journal/iteration-7.14/images/`):

| Колода | Карточек | Настоящих | Заглушек | Провайдеры | Ср. догрузка |
|---|---|---|---|---|---|
| Статика | 18 | 18 (100 %) | 0 | wikipedia 14, wikimedia 4 | 3,5 с |
| Биология | 18 | 18 (100 %) | 0 | wikipedia 10, wikimedia 8 | 1,9 с |

Ручная оценка 10 случайных карточек (`journal/iteration-7.14/relevance.md`):
**Биология 8/10** — цель достигнута; **Статика 1/10** — цель ≥ 7/10 не
достигнута. Выполнена одна итерация правки промпта (канонические якоря схем),
повторный замер: настоящих картинок 100 %, уместность «Статики» осталась низкой
(2/18 по всей колоде), «Биология» — 13/18. Причина — полнотекстовый поиск
Commons/Wikipedia для абстрактных механик совпадает с посторонними статьями
(фазовые диаграммы, карты, портреты); фильтры формата/размера их пропускают.
Ограничение — L84; рекомендация — семантическая проверка релевантности
(vision/LLM) или курируемый источник схем. Заглушка в этих случаях не
включается, т.к. картинка формально найдена.

**Долги 7.14:** L81 (Pixabay/Pexels без ключей), L82 (метаданные вне БД),
L83 (seed заглушки — хэш содержимого), L84 (семантическая релевантность),
L85 (метрики на одной модели), L86 (дедуп URL в пределах запуска).

## Итерация 7.15 — итог (ADR-032)

**Гейты 7.15:** `test --no-pub --coverage --exclude-tags golden` → **1715
passed + 8 skipped** · покрытие рукописного кода **91.7 % (12974/14143)** ·
`analyze` **0** · `format` 0 changed · `build windows --release --no-pub` →
`cardflow.exe` (см. отчёт о прогоне) · Windows-смоук — после 7.16.

**Сделано:**
- Домен: `StudyMode` (`test`, `typing`, `match`, `true_false`; wire-значения для
  `review_logs.mode`), политика FSRS (`isDueForStudy`: новая карточка тоже
  «due» — первая оценка создаёт расписание; будущая `due` — тренировка),
  очередь (`buildStudyQueue`: due/новые, затем будущие), `AnswerType`
  (`short_text|number|formula|long_text`; для ввода — ≤ 60 символов, ≤ 6 слов,
  без LaTeX/переносов), нормализация (NFC через `unorm_dart`, регистр, ё/е,
  пробелы, пунктуация, ответы через `/`/`;`), `AnswerMatcher`
  (`exact|almost|wrong`, Левенштейн 1/2, diff missing/extra), `DistractorGenerator`
  (3 ответа из колоды того же типа, близкой длины; числа — та же единица; без
  дублей; позиция правильного по seed; `aiDistractors` как вход).
- `StudySessionController`: общая очередь/прогресс/итоги/undo/«Повторить
  ошибки»; due → `Scheduler`+`ReviewRepository` (`mode`), будущие →
  `PracticeRepository` (`mode`; undo фильтруется по mode, классический журнал
  не удаляется). Порт тренировки расширен необязательным `mode`.
- Экраны: `MultipleChoiceScreen` (4 варианта, зелёный/красный, автопереход 1,2 с
  кроме reduce motion, пружина+haptics, клавиши 1–4/Enter, итоги и повтор
  ошибок), `TypingScreen` (exact/almost/wrong, diff, «Я был прав» = undo +
  Good, «Показать ответ» = Again, Enter); маршруты
  `/decks/:deckId/{test,typing}`; лист режимов с числом доступных карточек и
  неактивными пунктами при их нехватке; ARB (ru).
- Тесты: 9 domain (тип/матчер/дистракторы/очередь/политика), 8 controller,
  16 widget (Тест/Ввод), 3 листа режимов, mode-scoped undo; полный прогон —
  зелёный.

**Решения/отклонения:** ИИ-дистракторы (batch-запрос на колоду и кэш) в этой
итерации не подключены: генератор принимает `aiDistractors`, но production-
источника ИИ и кэша нет — карточки, для которых в колоде меньше 4 подходящих
ответов, пропускаются в Тесте (L87). Дневные лимиты новые режимы не учитывают
(L88) — FSRS пишется только для due, но лимит новых/повторов может быть
превышен; это осознанное упрощение до обсуждения владельцем.

## Итерация 7.14 — CI

Push `cc88e0c..bf28359`; CI run
[`43901313115`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43901313115)
— **9/9 job success** (format+analyze, test ×3, build desktop ×3, mobile 2).

## Итерация 7.15 — CI

Push `bf28359..df0e873`; CI run
[`43904903386`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43904903386)
— **9/9 job success** (format+analyze, test ×3, build desktop ×3, mobile 2).

## Итерация 7.17 — итог (ADR-034)

**Гейты 7.17:** `test --no-pub --coverage --exclude-tags golden` → **1772
passed + 8 skipped** (baseline 1742 + 8; первый прогон дал 1771 + 8 и одно
падение живого Wikimedia-теста — сеть/rate-limit, повторный зелёный, L92) ·
покрытие рукописного кода **91.9 % (12947/14085)** · `analyze` **0** ·
`format` 0 changed · `build windows --release --no-pub` → `cardflow.exe`
(60,8 с).

**Причина по фактам:** вопрос новых режимов уже рендерился через
`CardContentView`, а остальной текст — сырым `Text`: варианты «Теста», плитки
«Подбора пар» (все 12), утверждение и пояснение «Верно/Неверно», строка
правильного ответа и diff «Ввода ответа», список ошибок на итогах. ЛаТеХ в БД
корректен (78/78 формул парсятся) — ломался только рендер.

**Сделано:**
- `latexTextSpans()` (`lib/ui/cards/content/latex_spans.dart`) — единый inline-
  рендер текста с формулами (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`): текст —
  `TextSpan`, формулы — `WidgetSpan(Math.tex)`, все сразу; стиль наследует
  родителя, `fontSize`/`color` дозаполняются из темы.
- `CardText` (`lib/ui/cards/content/card_text.dart`) — «текст карточки вне
  карточки»: cloze → `ClozeText`, формулы → `InlineLatexText`, plain → `Text`;
  `style/textAlign/maxLines/overflow/revealed`. `InlineLatexText` переписан на
  общий хелпер (plain-текст остаётся `Text` с `data` — тесты не ломаются).
- `CardContentView.showAllFormulas` — вопрос режимов показывает все формулы
  сразу (пошаговое раскрытие — механика «Классики»); cloze-пропуски скрыты.
- Семантика вариантов «Теста» — без `$` (`plainTextOfLatex` в
  `latex_markup.dart`).
- `AnswerDiffView` (публичный) собирает фрагменты через `latexTextSpans`:
  полная формула рендерится, обрывок остаётся текстом (без падения).
- Домен (ADR-034): `AnswerType.isChoice` + `AnswerTypes.isChoice` (короткий/
  число/**формула**, ≤ 120 символов); `DistractorGenerator`, лист режимов и
  дистракторы «Верно/Неверно» используют `isChoice`; «Ввод ответа» остаётся на
  `isTypable`. `classifyAnswer` относит `\(…\)`/`\[…\]` к `formula`.
- Скриншоты `journal/iteration-7.17/screenshots/` (Тест с формулами в вопросе и
  четырёх вариантах, Пары, Ввод, Верно/Неверно); `tool/screenshots` грузит
  KaTeX-шрифты `packages/flutter_math_fork/KaTeX_*`.
- Тесты: +30 (10 `study_mode_latex_test`, 11 `card_text_test`, 6 доменных,
  1 лист режимов, 2 в существующих наборах). Отчёт —
  `journal/iteration-7.17/README.md`.

**Решения/долги:** формульный ответ теперь допустим в «Тесте» (выбор) и как
дистрактор «Верно/Неверно», но не в «Вводе ответа»: контракт 7.15 «формулы не
строят вопрос» заменён осознанно (ADR-034). L87/L88 не менялись. Схема БД и
`format_version` не менялись.

## Итерация 7.17 — CI

Push `4dfe10c..b199dbc`; CI run
[`43935245725`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43935245725)
— **9/9 job success** (format+analyze, test ×3, build desktop ×3, mobile 2).

## Итерация 7.16 — итог (ADR-033)

**Гейты 7.16:** `test --no-pub --coverage --exclude-tags golden` → **1742
passed + 8 skipped** · покрытие рук��писного кода **91.7 % (13521/14743)** ·
`analyze` 0 · `format` 0 changed · `build windows --release --no-pub` →
`cardflow.exe` (52,4 с).

**Сделано:**
- «Подбор пар»: домен `MatchGame` (6 пар, 12 плиток, перемешивание по seed,
  selected/matched/mismatch/moves, `select → selected|matched|mismatch|ignored`),
  экран `MatchScreen` (сетка 3/4 колонки, таймер с первого тапа, встряхивание
  несовпавшей пары, исчезновение найденной, итог + лучшее время, «Ещё раз»,
  «Готово»); `MatchBestStore` + `DriftMatchBestStore` — JSON v1 в `app_settings`
  (`study.match.best`), схема БД не менялась. FSRS не пишется.
- «Верно/Неверно»: домен `TrueFalseQuestion` (50/50 из правильного ответа или
  дистрактора колоды, seed), экран `TrueFalseScreen` (утверждение, кнопки ✓/✗,
  свайп вправо/влево, плашка результата с правильным ответом, авто-переход 0,9 с
  кроме reduce motion, итоги/повтор ошибок) на общем `StudySessionController`
  (`mode='true_false'`, FSRS только для due, остальные — тренировка).
- Маршруты `/decks/:deckId/{match,true-false}`, пункты листа режимов с числом
  доступных карточек и неактивным состоянием, ARB (ru). Тесты: домен
  (MatchGame/TrueFalse), хранилище на реальной drift-БД, widget (9 сценариев),
  лист режимов, роутер (17 маршрутов).

**Скриншоты (7.14–7.16):** `journal/iteration-7.15/screenshots/` — карточка с
фото/схемой/заглушкой, «Тест» (светлая/тёмная), «Ввод ответа», «Подбор пар»,
«Верно/Неверно» (тёмная); сняты golden-рендером реальных экранов
(`tool/screenshots/screens_test.dart`), README — рядом.

**Решения/долги:** лучшие результаты «Пар» — локальный кэш, не входят в
статистику/экспорт; таймер игры — `Timer.periodic` экрана (L33/L88);
ИИ-дистракторы по-прежнему не подключены (L87).

## Итерация 7.16 — CI

Первый push (`8eedd84`) — CI run
[`43909148956`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43909148956)
**упал только на `format + analyze`** (неиспользуемые импорты в новом
test/tool), все test/build job'ы зелёные. Фикс `ed83795` → CI run
[`43913907014`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43913907014)
— **9/9 job success**. Push 7.16: `ed83795..b58895a` (фикс analyze, скриншоты `3aac099`,
STATE/AGENTS `b58895a`); финальный CI run
[`43915833682`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43915833682)
— **9/9 job success**. Docs-коммит `aad938f` (run
[`43918913669`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43918913669)):
все выполнявшиеся job'ы зелёные, `build macos`/`build ios` **отменены раннером**
(инфраструктура, не ошибка шага) — повторный прогон после docs-правки.

## Итерация fix-gen — итог (архив, v5)

**Причины (диагностика `journal/iteration-fix-gen/diagnosis.md`):**
- Д4/Д6: модель пишет LaTeX одним `\` в JSON → `\frac`→form feed, `\alpha`→
  `FormatException`; фрагмент падал `invalidResponse`, формула молча портилась.
- Д6: все схема- и структурно-невалидные карточки роняли фрагмент; предпросмотр
  не импортировал пак из-за одной невалидной карточки.
- Д3: изображения файлов не извлекались (парсеры читали только текст).
- Д2: производный `image_query` из текста вопроса давал случайные картинки.

**Сделано:**
- Промпт `gen-ru-v5` дословно (`lib/api/prompts/system_prompt.dart` +
  `docs/prompts/gen-ru-v5.txt`, тест байт-в-байт); блоки `<materials>`,
  `<wishes>`, `<limit>`, `<images>`; `Файл: <имя>`; лимит карточек из пожеланий
  делится по фрагментам пропорционально (`generation_card_limit.dart`).
- Схема A8.4 + `image_id`, поштучная проверка, проекции OpenAI/Gemini/Anthropic
  (ADR-029); валидатор: `image_id` вне каталога → null; `image_query` — латиница
  ≤ 7 слов; абстрактные понятия без картинки; tags ≤ 3.
- LaTeX: `latex_escape_repair.dart` (до/после JSON), `\(\)`/`\[\]` → `$…$`,
  `\$` не формула; `LatexText`/`ClozeText`/`InlineLatexText` через `Math.tex`.
- Изображения DOCX/PPTX/ODT (`DocumentImage` + контекст, фильтры мусора) →
  `<images>` фрагмента → `image_id` → байты файла; предпросмотр: убрать/заменить.
- Причины сбоя фрагмента (`GenerationFailureReason`, 13 кодов) в
  `generation_jobs.error_code` и debug-лог; частичный импорт; кнопка неактивна
  только без выбранных карточек; ошибки «Фрагмент K из M: причина».
- Д5: мягкие проверки качества (7 пометок) + eval-набор 3 сценария + live-метрика.
- Д1: кнопка неактивна без файлов/темы, подсказка ARB, имя колоды из темы,
  `source_excerpt` при пустых материалах → null.

**Доказательства:** `journal/iteration-fix-gen/{diagnosis,red-output,review,verify,summary}.md`;
тесты `latex_escape_repair_test`, `latex_render_fix_test`, `document_images_test`,
`card_generation_images_test`, `generation_fix_gen_test`, `card_quality_test`,
`quality_eval_test`, `generation_preview_partial_test`, `failure_reasons_test`,
`generation_failure_message_test`, `prompt_test` (байты).

## Известные ограничения (актуальные)

L1, L2, L4–L8, L10–L16, L18–L20, L23–L25, L27, L28 (только Windows), L30,
L31–L34, L35, L36, L37–L44, L46–L52, L53 (живой PDF-part), L54, L55, L56,
L57–L59 (≤ 3 страниц), L60 (снято 7.12; предпросмотр — fix-gen), L61, L62–L64,
L65, L66 (обновлено L80), L67, L68, L69, L70, L71–L75,
**L76** (изображения внутри PDF не извлекаются), **L77** (только JPEG/PNG из
документов), **L78** (ручные клики/скриншоты владельца), **L79** (причины
сбоя перечнем в `error_code`), **L80** (поштучный отброс карточек моделей,
не следующих strict-схеме), **L81** (Pixabay/Pexels без ключей), **L82**
(атрибуция в побочном JSON, не в БД), **L83** (seed заглушки — хэш
содержимого), **L84** (семантическая релевантность картинок не проверяется),
**L85** (метрики на `deepseek-chat`), **L86** (дедуп URL в пределах запуска),
**L87** (ИИ-дистракторы не подключены: мало ответов → карточка пропускается в
Тесте), **L88** (новые режимы не учитывают дневные лимиты), **L89** (семантика
формул — текст без `$`), **L90** (посимвольный diff для формул не показывается),
**L91** (KaTeX-шрифты в скриншот-харнессе грузятся вручную), **L92** (live-тесты
поиска картинок идут в общем прогоне и зависят от сети).

## История

- 7.17 «Глобальный рендер LaTeX и cloze во всех режимах» (2026-11-16) — ADR-034,
  гейты выше.
- 7.16 «Подбор пар» и «Верно/Неверно» (2026-11-16) — ADR-033, гейты выше.
- 7.15 «Тест» и «Ввод ответа» (2026-11-16) — ADR-032, гейты выше.
- 7.14 «Картинка у каждой карточки» (2026-11-16) — ADR-031, CI run `43901313115` 9/9.
- fix-gen «Исправление генерации» (2026-11-16) — ADR-029/030.
- 7.12 «Фикс UX картинок, лимитов и поиска ИИ» — CI run `43750931989` 9/9.
- 7.11 «FSRS новых карточек, картинки, сканы и Practice Mode» — CI run
  `43742161910` 9/9.
- 7.10 «Prompt-only, PDF и картинки» — CI run `43728048903` 9/9.
- 7.9 «PDF-сканы, иллюстрации и occlusion» — CI run `43703387395` 9/9.
- 7.8 «Вложения и Vision» — ADR-022, CI run `43650756271` 9/9.
- 7.6 «Пустой ответ LLM» — CI runs `43637919516`/`43639479927` 9/9.
- 7.5 «Провайдеры и ключи» — ADR-020, CI run `43632334916` 9/9.

## TASK 05 — Controlled Live Generation Validation, подготовка A–C (2026-11-19)

**Старт:** `git status --porcelain` → только `?? redesign/`; `HEAD = 6bdf3e4`;
baseline **2157 passed + 16 skipped**, `analyze` 0.

**Сделано (без единого платного запроса):**
- каталог DeepSeek приведён к официальной странице 2026-11-19:
  добавлены `deepseek-flash` (default, 1M, Vision) и `deepseek-v4-pro` (1M),
  legacy `deepseek-chat`/`deepseek-reasoner` оставлены для сохранённых
  аккаунтов; это убрало «1 карточку на запрос» у unknown-модели (L137/L139
  обновлены, L147);
- live-инфраструктура: logical/HTTP/attempts/retries разделены, бюджеты общие
  на файл (`LiveRecordingCaller`, `LiveProbeTransport`, `LiveAttemptLimiter`),
  `LiveCostGuard` резервирует стоимость каждой физической попытки до отправки,
  strict-400 освобождает резерв; отчёт содержит цены, estimated/actual cost,
  `requestCosts[]`, latency; `note` редактируется;
- сценарии A–C: A = 5 карточек (1 запрос), B = 40 (6 запросов, continuity),
  C = DOCX с 3 Heading1 через production `DocxParser`; importability
  проверяется `CardDraft.validate()`;
- `CARDFLOW_LIVE_SCENARIOS` — явный список id, чтобы A–C не задевали Test D;
- ручная рубрика 8 критериев 0/1/2 + `LiveDocumentAssessment` для Test C;
- артефакты: `journal/task05/{audit,test-plan,budget,readiness-report}.md`,
  `journal/task05/results/README.md`; `docs/generation-pipeline.md` §9.

**Гейты:** `test --no-pub --exclude-tags golden` → **2177 passed + 16 skipped**;
`test/unit/live` → **48 passed**; Test F (`generation_recovery_http_test`) →
**11 passed**; `test/live --tags live` → **16 skipped, 0 запросов**; `analyze`
0; `format` **500 файлов / 0 changed**; `build windows --release --no-pub` →
`cardflow.exe` (62,1 с); `--coverage` → **92.4 % (16202/17535)**.

**Коммиты:** `4e385ff` (каталог DeepSeek), `e401c69` (live-инфраструктура и
A–C), docs-коммит `docs(journal): record TASK 05 live readiness` (аудит, план,
бюджет, отчёт). Push не выполнялся.

**Платные запросы:** не выполнялись. `DEEPSEEK_API_KEY` present в Windows
User scope, значение не выводилось. Готовность A–C — YES, запуск только по
отдельному разрешению (`journal/task05/readiness-report.md`). Ограничения:
L143–L148 (биллинг 400/повторов, thinking mode, live-импорт в БД, legacy
DeepSeek, ручная приёмка).

## Итерация «аудит 1.0 → исправления → повторный аудит» (2026-11-22/23)

**Вход.** Независимый аудит `review/REPORT.md` (снимок `53ead19`): вердикт
«НЕ ГОТОВО», 2 blocker (F1, N1), 5 critical (N2, D1, D2, D3, D5, F3, D15/A1),
~30 major/minor.

**Выход.** `review/FIXED.md` — статус каждой находки с доказательством;
`review/screenshots/after/` — скриншоты живого приложения; `design/PROGRESS.md` —
этапы, гейты, ограничения.

**Гейты на финальном снимке:** `analyze` — 0; `format --set-exit-if-changed` — 0 changed;
полный `test --exclude-tags golden` — **2646 passed + 16 skipped**; `build windows --debug` — ок.

**Повторный аудит.** Аудитор v2 (`review/REPORT_v2.md`, снимок `820d095`):
«УСЛОВНО ГОТОВО», 0 blocker/critical, 2 major (A1 переполнение тулбара на 390×844;
D1 обрезка вопроса на 800×600) и 5 minor. Все major и 4 minor закрыты
(`ac4ba2d`), N2 (sticky-якоря настроек) принят как minor. Аудитор v3
(`review/REPORT_v3.md`, снимок `ac4ba2d`): **«ГОТОВО»**, 0 blocker/critical,
main-сценарии пройдены, данные профиля не изменены; новая находка — косметический
minor D4 (подпись первого поля формы), запас прокрутки увеличен (`1a7f074`).

**Ограничения:** реальный платный ИИ-прогон не запускался; Android-специфика
(нет SDK) и screen-reader не проверялись; golden-тесты — Linux CI.

## Итерация «визуальный аудит v7 → исправления → аудиты v8/v9» (2026-11-23)

**Вход.** Независимый аудит `review_visual/GATES.md` (снимок `a087ee4`): вердикт
«НЕ ГОТОВО», 11 FAIL из 12 (G1 оценки до ответа, G3 карточка 24–54 % ширины и
81–90 % пустоты, G4 cover-обрезка 25–61 %, G5 серые оценки и undo, G2 кнопки
48–53 px и кегль 14,4, G6/G7/G9/G10/G11).

**Работа.** Коммиты `0701f12`, `b29b621`, `9240306`, `eb43817`:
оценки живут только после раскрытия (внутри карточки), карточка считается от
окна (≥60 % ширины) и принимает высоту содержимого с минимумом 430 × множитель,
панель оценок 56–67 px с кеглем 18 и зазором ≥12, изображения всегда contain и
по пропорциям файла, предпросмотр формы получает метаданные, экраны проверки —
единая карточка вопроса и центрирование, ширины детальных страниц адаптивны,
анимации из единой шкалы (панель оценок fade+slide 220 мс, reduced motion),
контекстное меню карточки — popup.

**Гейты на финальном снимке:** `analyze lib test` — 0; полный
`test --exclude-tags golden` — **2678 passed + 16 skipped**; `build windows
--debug` — ок; `dart format` — 0 changed.

**Аудиты.**
- v8 (`review_visual/GATES_V2.md`, снимок `9240306`): 9 PASS, 3 FAIL — G3/G8
  (сплошная пустая полоса 452 px = 37,2 % высоты, чернила 7–11 %) и G10
  (живое окно 844×390 физических px = 562×260 лог.: «BOTTOM OVERFLOWED BY
  62 PIXELS», 2 из 4 оценок недоступны). Вердикт «НЕ ГОТОВО».
- Исправления по v8: карточка больше не растягивается (полоса 37,2 → 25,9–29,9 %,
  чернила 2,6–7,1 → 11,3–28,0 %), в низком окне панель оценок — один ряд,
  скрыты надзаголовок/повтор вопроса/прогресс, содержимое прокручивается;
  G10-тесты на 562×260 и 533×400.
- v9 (`GATES_V3.md`): 9 PASS / 3 FAIL (G3/G8 полоса 30,1–30,4 %, короткие 33–35 %, лента 45,2 %; G10 — лента схлопывалась в 0 на 562×260).
- v10 (`GATES_V4.md`): 10 PASS / 2 FAIL (G8 лента 33–34 %; регрессия G5 — дубль подписи «ВОПРОС»).
- v11 (`GATES_V5.md`): 11 PASS / 1 FAIL (G8 лента 32,6–33,5 %; причина — невидимый `SizedBox` в `spaceEvenly`).
- v12 (`GATES_V6.md`): **12 PASS / 0 FAIL — «ГОТОВО»** (лента 18,9–21,6 % на 8 живых карточках, медианный вопрос 20,7 %).

**Ограничения.** Высота карточки на «логических» 2K@100 %/4K — 29–37 % окна
(на живых 2K/FullHD — 56–59 %): «≥60 % высоты» и «≤30 % пустоты» для вопроса в
1–2 строки несовместимы; выбран второй критерий. Лента/тренировка живьём не
сняты в финале. Тёмная тема, контраст, дислексия, dynamic color, screen reader —
не перепроверялись.

## Итерация «UI/UX-редизайн v3: лента, оценки, фильтры, поиск» (2026-11-24)

**Старт.** `git rev-parse --abbrev-ref HEAD` → `main`; `HEAD = 36f8738`
(`docs(review): зафиксировать внешний сбой macOS-раннера в CI`); рабочее дерево
содержало только прежние журналы/аудиты (`review_visual/`, `review_final/`).
Baseline: `fvm flutter analyze --no-pub` — 0 issues; полный
`fvm flutter test --no-pub --exclude-tags golden` — **2654 passed + 16 skipped**
(до новых тестов).

**Сделано (ADR-044/045).**
- **Лента — свободный просмотр, без FSRS.** `FeedSessionEngine` переписан: нет
  `Scheduler`/`ReviewRepository`/`clock`/`rate`/`undo`/лимитов; очередь
  `buildBrowseQueue` (все, кроме `suspended`, `createdAt` ASC, тай-брек `id`);
  план конструктора — `prebuilt`. `feed_session_screen.dart`: вертикальный
  `PageView`, колесо через `Listener` + `pointerSignalResolver` **внутри
  страницы**, клавиатура `feed_keyboard.dart` (↓/PageDown/→, ↑/PageUp/←,
  Home/End, Space/Enter, Esc), шевроны и кликабельный прогресс; тап раскрывает
  ответ, раскрытие хранится по карточке. Длинный текст не прокручивается в
  странице: «Открыть полностью» (`feed-read-full`) → лист. Карточка —
  отдельный дизайн (`feed_card_view.dart`), 72 % ширины/78 % высоты на
  десктопе, вся полезная область на телефоне. `feed_progress_bar.dart` без
  пульсации. `feedPath` без `?limits=ignore`; лента не показывает диалог
  дневного лимита. Интеграционный тест на реальной drift-БД подтверждает:
  после листания/раскрытия `review_logs` пуст, `due`/`fsrs_json`/`state` не
  изменились.
- **Кнопки оценки.** `review_toolbar.dart` — только `Не знаю / Затрудняюсь /
  Знаю / Легко` (ARB `ratingHard` = «Затрудняюсь»), без цифр и интервалов;
  высота 56–70 (compact тоже 56), кегль 18–22, центр, состояния
  hover/pressed/focused/disabled, иерархия «одна залитая» (primary) + три
  тонировки. `preview` продолжает считаться движком и применяться FSRS;
  клавиши 1–4 работают. UI-хелпер `review_interval_format.dart` и его тест
  удалены (показ интервалов больше не существует); интервалы проверяются
  тестами `Scheduler.previewIntervals`.
- **Поиск колоды.** `decksSearchFocusProvider` + `FocusNode` в
  `_DecksSearchField`; `open()`/`toggle()` показывают поле и просят фокус;
  рамка фокуса видна. Тесты на десктопе и в мобильном `Drawer`: поле в фокусе,
  ввод сразу фильтрует, пустой результат объясняется.
- **Фильтры.** Новый `AppFilterChip`: высота 36 + цель 44, `Row` по центру,
  счётчик отдельным бейджем (`tabularFigures`), `Flexible` + ellipsis, состояния
  selected/unselected/danger/hover/pressed/focus/disabled. ARB:
  `decksFilterAll/New/InProgress/Due` + `decksFilterMenuItem`. Ряд фильтров
  колод переведён на компонент (ключи `decks-filter-*`); Material `FilterChip`
  конструктора остаётся с темой приложения (две строки названия колоды).
- **Палитра.** «Кобальт на графите»: primary `#1E4FD8`/`#7FA5FF`, нейтральные
  поверхности `#F6F7F9…#D8DCE2` и `#0B0E13…#2A3140`, secondary teal, tertiary
  amber; indigo `#3525CD` и голубые фоны убраны. Guard контраста проходит:
  primary/onPrimary 6,63:1, onSurface 16,6:1, onSurfaceVariant 7,35:1, outline
  4,28:1; тёмная — 7,47/16,04/10,56/7,60.
- **Анимации.** Удалены пульс Stories и авто-продвижение 3/5/8 с; переход
  ленты 240 мс, переворот 300 мс, панель 220 мс, чипы 120–160 мс; reduced
  motion → `jumpToPage`/`Duration.zero`. Постоянных анимаций нет.
- **Тексты.** Подсказка на обороте классики — «1–4 — оценка · ← — отменить»
  (раньше обещала «Пробел — показать ответ» уже после ответа); описание ленты
  в листе режимов — «Свободный просмотр: вертикальная лента без оценки и
  влияния на расписание».
- **Визуальная приёмка.** `journal/ui-ux-redesign/tools/render_v3_test.dart`:
  25 production-кадров (2K light/dark, FullHD, 390×844, 360×800, 768×1024, 260×562);
  `tools/live_check.ps1` — живой Release (старт без ошибок, колоды, лист
  режимов). По кадрам исправлено: ширина карточки ленты (72 %), высота (78 %
  рабочего поля), шевроны в жёлобе; мобильная классика 2×2; на 360 px поиск перестал сжиматься до «ктр» (сортировка/вид — в overflow-меню при <420 px).
- **Документация.** `journal/ui-ux-redesign/{audit,report}.md`,
  `docs/decisions/ADR-044-feed-browse-mode.md`, `ADR-045-design-system-v3.md`,
  обновлён `AGENTS.md` (разделы ленты и дизайн-системы).

**Гейты.** `fvm flutter analyze --no-pub` — 0 issues;
`fvm dart format --set-exit-if-changed lib test integration_test tool` — 0
changed; `fvm flutter test --no-pub --exclude-tags golden` —
**2660 passed + 16 skipped**; покрытие — **90,9 % рукописного кода (22 360/24 607)**, всего 83,6 % (24 119/28 860);
`fvm flutter build windows --release --no-pub` — `cardflow.exe` (76,4 с; финальная после правки — 81,2 с);
живой Release — старт без ошибок (только строка Impeller в stderr).
Независимый reviewer в сессии недоступен (L35): ревью Lead по чек-листу на
снимке рабочего дерева.

**Ограничения.** Stitch/Mobbin/Figma Make/Uizard недоступны из агента (нет
сессии/UI; см. audit §3.4); Android/iOS-девайса нет (L2); screen reader — только
семантика widget-тестов (L46); `SessionCard` содержит неиспользуемую
свайп-механику (включается только `enableSwipe`, экраны его не передают);
живой кадр ленты не снят из-за сжатия окна на рабочем столе (лента проверена
production-рендерами и widget-тестами). Push не выполнялся.
