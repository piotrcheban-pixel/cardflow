# AGENTS.md — устойчивые правила CardFlow

CardFlow — кроссплатформенное нативное Flutter-приложение для интервального повторения (FSRS). Единственный источник правды о продукте — `SPEC.md` в корне; процесс — `docs/agent-prompt.md`. Этот файл — краткие постоянные соглашения, не журнал.

## Окружение и команды

- Flutter закреплён через **FVM** (`.fvmrc`), версия — в `docs/dependencies.md`.
- Все команды — только через FVM: `fvm flutter pub get`, `fvm flutter test`, `fvm flutter analyze`, `fvm dart format .`, `fvm flutter gen-l10n`, `fvm flutter test --coverage`.
- Новые зависимости — только после проверки на pub.dev и записи в `docs/dependencies.md`; запрещённые WebView/HTML-пакеты — стоп.
- `docs/decisions/ADR-*.md` — принятые решения; при конфликте SPEC с реальностью — ADR, а не правка SPEC.

## Архитектура (`lib/`)

- `domain/` — сущности, оценки `Rating` (Again/Hard/Good/Easy), FSRS-адаптер, бизнес-правила. **Без импортов Flutter.**
- `data/` — drift, репозитории, импорт/экспорт.
- `api/` — провайдеры, DTO, валидация, промпты, парсеры файлов.
- **Парсеры документов** — `lib/api/parsers/` (SPEC A8.3, ADR-010): результат всегда `ParsedDocument`
  (`lib/domain/text/`) — нормализованный текст + границы разделов `start/end` + метаданные; между разделами
  ровно пустая строка. ZIP-форматы (DOCX/PPTX/ODT/**XLSX**) проходят `SecureZip` с лимитами (10 000 записей /
  32 МБ запись / 120 МБ сумма) до разбора; ошибки — только `ParserErrorCode` → строка ARB
  (`lib/ui/generation/parser_error_message.dart`), `details`/сырые исключения в UI не попадают. `.doc/.xls`
  не поддерживаются (ADR-003). Парсинг — в `Isolate.run`; ошибка файла не блокирует остальные.
- **API-слой генерации** (SPEC A8.1/A8.2/A8.4–A8.6, ADR-011/ADR-012/ADR-013/ADR-015):
  канон-схема ответа и её проекции — `lib/api/generation/` (`card_json_schema.dart`, `provider_schema.dart`);
  адаптеры провайдеров — `lib/api/providers/` (OpenAI, Gemini, Anthropic и OpenAI-compatible; чистые
  `buildRequest`/`parseResponse`, без сети и UI). Пайплайн генерации — `lib/api/generation/generation_pipeline.dart`
  (`GenerationPipeline`: `GenerationPlan` до первого запроса, последовательные вызовы по `PlannedChunk`,
  восстановление context overflow/413/truncated, прогресс/отмена, дедуп, `generation_jobs`, partial/retry);
  чистые правила — `lib/domain/generation/` (`generation_budget.dart`, `generation_chunk_planner.dart`,
  `generation_plan.dart`, `generation_plan_entry.dart`, `generation_plan_splitter.dart`,
  `content_token_estimator.dart`, `generation_job.dart`, `generation_run.dart`).
  **Провайдеры — аккаунты, а не enum** (SPEC A6.6/A6.8/A8.6, ADR-020): статический каталог
  `lib/domain/generation/provider_preset.dart` (DeepSeek, OpenAI, Anthropic, Gemini, OpenRouter,
  Moonshot, MiniMax, Groq, Ollama), `ProviderProtocol` → существующий адаптер, `ProviderAccount`
  (`id`, протокол, `base_url`, модель, контекст) + `ProviderAccounts` — JSON v1 в `app_settings`
  (`generation.providers`), схема БД не меняется. Ключ — по `ProviderAccount.id` в `ApiKeyStore`
  (контракт строковый), значения не показываются; после записи — read-back, и только затем
  сохранение аккаунта. Legacy-настройки/ключи мигрирует `DriftProviderAccountsStore`. Адрес
  запроса — `lib/api/providers/provider_endpoint.dart` (все адаптеры уважают `baseUrl` аккаунта).
  `GenerationRequest`/`GenerationRunRequest` несут аккаунт, `generation_jobs.provider` = id аккаунта.
  Экран — `lib/ui/settings/generation_settings_screen.dart` (+ `provider_account_dialogs.dart`),
  блок API в настройках — сводка и переход. strict `response_format` — лестница совместимости
  OpenAI-совместимого протокола (ADR-021): strict+`max_tokens` → без схемы+`max_tokens` →
  без схемы и `max_tokens`, не больше трёх запросов, только по `badRequest`; разбор текста ответа —
  `lib/api/generation/cards_json_extractor.dart` (BOM, markdown-ограждение, текст вокруг JSON —
  только для compatible-протокола); пустой `cards` — не ошибка ответа: в UI отдельная строка
  `generationNoCardsFound`. Промпт `gen-ru-v5` скрыт в коде
  (`lib/api/prompts/system_prompt.dart`, сырой литерал; дословная копия —
  `docs/prompts/gen-ru-v5.txt`, тест сверяет байты), пользовательское сообщение —
  `generation_prompt.dart`: стабильный префикс `<materials>` → `<images>` →
  `<outline>` → `<wishes>` и изменяемый хвост `<task>` (`<part>`, `<focus>`,
  `<cards>`, `<context_only>`, `<already_created>`), промпт `gen-ru-v8`;
  каждый файл в `<materials>` начинается со строки `Файл: <имя>`.
  **Планирование (ADR-039/040, итерация 7.18):** характеристики модели —
  `Sourced<T>` (`lib/domain/generation/sourced.dart`), `ModelLimits`, слоистый
  `resolveModelLimits` (пользователь > API > каталог > допущение > неизвестно);
  discovery — `lib/api/models/model_discovery.dart`, кэш JSON v1
  `generation.model_capabilities` (TTL 7 дней), сервис — `model_capability_service.dart`.
  Три независимых решения — `input_planner.dart`, `card_allocator.dart`,
  `output_batch_planner.dart`; фасад — `generation_chunk_planner.dart`; конвейер
  шлёт focus/part/already_created, обрабатывает исчерпание и калибрует
  `tokensPerCard` (`generation.calibration` v1). **Заказ карточек не ограничен
  бюджетом одного ответа (7.20, ADR-043):** мягкая ёмкость материала —
  предпочтение распределения (`Σ planned == requested`), партии заполняются до
  `cardsPerBatch` (`OutputBatchPlanner.batchCount/batchSizes`), нехватка
  материала показывается отдельно (`PlanWarningCode.materialCapacityBelowRequested`),
  технический предел — число партий (`maxChunks`). Prompt-only строится той же
  машинерией (7.18.1). Нативный `count_tokens` (Anthropic/Gemini) —
  `request_token_counter.dart` + `exact_token_cache.dart`: один подсчёт на план,
  ошибка → оценка, точность/источник в `InputPlan`. 413 или подтверждённый 400
  перепланируют часть с бюджетом ×0.8 (`GenerationPlanSplitter.splitToBudget`),
  wholeDocument → fragmented, ≤3 операций на запрос; прочие 400/401/403 — без
  перепланирования. Предпросмотр и конвейер строят план через
  `generation_plan_entry.dart`; «Подробнее» —
  `lib/ui/generation/generation_plan_details.dart`; ручные характеристики —
  `ProviderAccount.withConfiguredCapabilities` + `model_capability_section.dart`.
  Документация — `docs/generation-planning.md`; сверка discovery 2026-11-21 —
  ADR-039 §6a. Схема A8.4 v9 содержит независимые изображения сторон —
  `question_image_ids`/`answer_image_ids` и необязательный `image` со `side`
  (ADR-042); `image_id`/`image_query` — только legacy v5–v8; проверка схемы — поштучно (`CardResponseSchema.splitValid`): одна плохая
  карточка не отбрасывает фрагмент. Контентные правила и мягкие проверки качества A8.4/A8.1 —
  `card_content_validator.dart` (пометки `CardIssueCode`, карточка не отбрасывается);
  LaTeX-экранирование ответа восстанавливается до/после разбора JSON
  (`latex_escape_repair.dart`: `\frac`/`\alpha`, `\(\)`/`\[\]`). HTTP — только через
  `GenerationTransport` (`lib/api/http/generation_http_client.dart`) с `RetryPolicy` и
  `RedactingLogInterceptor`. Ошибки — только `GenerationErrorCode` → строка ARB
  (`lib/ui/generation/generation_error_message.dart`); причина сбоя фрагмента —
  `GenerationFailureReason` (`json_parse`, `schema_invalid`, `validator_rejected`,
  `truncated`, `refusal`, `safety`, `network`, `http_4xx/5xx`, …) пишется в
  `generation_jobs.error_code` и debug-лог `GenerationDiagnostics.fragmentFailure`.
  Ключи — только `ApiKeyStore` (secure storage). LaTeX-проверка `flutter_math_fork` допустима только в
  `lib/api/generation/latex_checker.dart` и инжектируется в валидатор; остальной `lib/api/` от Flutter не зависит.
  **Изображения из документов (fix-gen, Д3):** парсеры DOCX (`word/media` + `r:embed`), PPTX
  (`ppt/media` + слайд), ODT (`Pictures/`) отдают `DocumentImage` (`lib/domain/generation/document_image.dart`)
  с подписью/контекстом/номером страницы; мусор (< 4 КБ, < 64 px, повторы по SHA-256, не JPEG/PNG)
  отбрасывается. Изображения раздела входят в каталог `<images>` только своего фрагмента
  (`id | файл | подпись | окружающий текст`); `image_id` разрешается в байты до внешнего поиска.
  Приоритет: файл → внешний поиск по `image_query` модели; производного запроса из текста вопроса нет.
  Общий заказ карточек (`GenerationPlan.requestedCards`) распределяется планировщиком без клампа 200
  и без универсального «20 на фрагмент»; лимит фрагмента — из output budget/`maxCardsPerRequest`
  (`generation_card_limit.dart` только разбирает число). Предпросмотр импортирует успешные карточки при
  упавших фрагментах, невалидные карточки пропускает, картинку можно убрать/заменить; ошибки фрагментов —
  списком «Фрагмент K из M: причина» + «Повторить неудавшиеся»; при невыполнимом заказе видно
  «запрошено/достижимо».
  **Prompt-only и диагностика (ADR-024, TASK 02B-FINAL):** файлы необязательны — без вложений, но с темой
  план строит `PromptOnlyPlanner` (`ChunkKind.promptOnly`, `GenerationMode.promptOnly`) без фиктивных
  `ContentUnit`; сервис шлёт пустой `<materials>`, тема — в `<wishes>`; большие заказы делятся на
  несколько запросов по output budget. `buildGenerationUserContent` допускает пустые материалы;
  `noMaterials` — только когда нет ни текста, ни вложений, ни пожеланий. `GenerationDiagnostics` (`lib/api/generation/generation_diagnostics.dart`,
  `enabled = !dart.vm.product`, sink инжектируется) — debug-only тело ошибки провайдера, сырой ответ
  модели (`image_query`) и итог поиска картинки; в release — no-op, секреты редактируются.
  **Текст документов (ADR-024):** `TextSanitizer` удаляет Unicode Cc/Cf (включая C1 `U+0080–U+009F`),
  BOM/zero-width/bidi и одиночные суррогаты, `U+2028/2029` → `\n`; `PdfTextQuality` (порог 5 замен / 5 %)
  поднимает `ParserErrorCode.garbledText` — «PDF содержит нечитаемый текст».
  **Вложения (ADR-022, итерация 7.8):** `TextSanitizer` (`lib/domain/text/text_sanitizer.dart`) — единый
  санитайзер локального текста, `normalizeDocumentText` делегирует в него; пустой текст без вложений и
  пожеланий → `noMaterials` (с 7.10 пожелания-тема тоже вход, ADR-024).
  Картинки JPG/PNG и PDF-сканы — `GenerationAttachment` (`lib/domain/generation/generation_attachment.dart`),
  передаются inline только при `ProviderAccount.supportsVision`; PDF — только Anthropic/Gemini
  (`ProviderProtocol.supportsPdfAttachments`), OpenAI/совместимые получают `image_url`, тела собирает
  `lib/api/providers/attachment_parts.dart`. Каталог `ProviderPresetModel.supportsVision`, JSON аккаунта
  `supports_vision`; старые записи — пресет или инференс по имени модели. `providerReason` для 400 —
  очищенная причина провайдера (ARB `generationErrorBadRequestReason`), тела не логируются.
  **PDF-сканы, иллюстрации и occlusion (ADR-023, итерации 7.9/7.11):** PDF с текстом < 50 символов
  (или `scannedPdf`) рендерится `PdfScanRenderer` (`lib/api/parsers/pdf_scan_renderer.dart`, pdfrx
  + `image`, `Isolate.run`) в первые **≤ 3 PNG** (ADR-027); страницы одного PDF — один фрагмент
  (`groupKey`). Модель без Vision → `pdfScanVisionRequired`; при сбое рендера — fallback на PDF для
  Anthropic/Gemini. `image_query` (схема `gen-ru-v5`), только если `image_id` не задан, → доменный порт
  `CardImageFinder` → `CompositeCardImageFinder` (`lib/api/images/`): **Wikimedia Commons**, затем
  **Wikipedia pageimages** (ru → en; ADR-028, итерация 7.12), Openverse резервом (CC0/PDM/CC BY/CC BY-SA,
  таймаут 5 с); бюджет `GenerationPipeline.imageSearchBudget` = 90 с **суммарного времени поиска**
  (ожидание модели не считается), после бюджета карточки импортируются без картинок.
  Если модель не дала ни `image_id`, ни `image_query`, карточка остаётся без картинки;
  `wishesForbidImages` отключает поиск, неудачный поиск ставит `CardIssueCode.imageNotFound`
  и предупреждение в предпросмотре, а не теряется. Debug-диагностика ADR-024 пишет сырой ответ модели
  в консоль `flutter run` (`generationDiagnosticsProvider`, sink `debugPrint` в debug).
  Байты `GeneratedCard.questionImages`/`answerImages` пишутся в `MediaStore` + `media`
  только при импорте (`DriftGenerationCardStore`); `cards.media_json` v2 хранит стороны
  (`{"version":2,"question":[…],"answer":[…]}`), `schemaVersion` не менялся (ADR-042). `card_type: "occlusion"` — wire-формат ответа модели: в БД/экспорте
  `basic` + `occlusion_json` + media (SPEC A5); без найденной картинки — `basic` +
  `CardIssueCode.occlusionImageMissing`, с картинкой — базовая маска
  `defaultOcclusionDocumentJson()`. Basic-карточка с media показывает иллюстрацию в
  `CardContentView`; ошибка поиска не отменяет карточку.
- **Новые карточки и очередь (ADR-026/ADR-028, итерации 7.11/7.12):** `DriftCardRepository.createCards` и
  `DriftGenerationCardStore` пишут `due = now` и валидный `fsrs_json` начального состояния
  (`CardSchedulingMapper.initialScheduling`, state `new`, шаг 0) — «новизну» определяет
  `state`, а не `due IS NULL`; счётчик «к повторению» (`DriftDeckRepository`) исключает
  `state='new'`, `SessionBuilder._baseOrder` делит по `state`. `ReviewQueue.build` **всегда**
  включает новые карточки, созданные в текущий локальный день (границы — `DailyLimits.localDayUtc`),
  лимит новых действует для более ранних. Пустая сессия из-за лимита объясняет причину
  (`reviewDailyLimitTitle`) и предлагает «Продолжить без лимита» (`?limits=ignore`, ADR-028) или
  тренировку; экран колоды проверяет очередь тем же остатком лимитов (`lib/ui/state/review_limits.dart`)
  и показывает предупреждение с теми же действиями.
- **Режим «Тренировка» (ADR-025, итерация 7.11):** домен — `PracticeQueue` (все карточки, кроме
  `suspended`) и порт `PracticeRepository`; данные — `DriftPracticeRepository` пишет
  `review_logs` с `mode='practice'` (`scheduled_days`/`actual_days` = NULL) и **не** меняет
  `cards.state`/`fsrs_json`/`due`; дневные лимиты (`DriftDailyUsageRepository`) тренировку не
  считают. UI — `PracticeSessionEngine` + `PracticeSessionScreen` (каркас `ReviewChrome`, без
  прогноза интервалов), маршрут `/decks/:deckId/practice`, пункт «Тренировка» в листе режимов.
- `ui/` — экраны, виджеты, локализация. Компоненты M3 Expressive — только через слой `lib/ui/m3e/` (библиотеку можно заменить). Токены движения — `lib/ui/motion.dart`.
- **Режим «Лента» — свободный просмотр** (ADR-044, заменяет пользовательский сценарий ADR-016):
  движок `lib/ui/review/feed_session_engine.dart` **не знает FSRS**: нет `scheduler`/`ReviewRepository`/
  `clock`, нет `rate`/`undo`/авто-продвижения; очередь — все карточки, кроме `suspended`
  (`buildBrowseQueue`, `createdAt` ASC, тай-брек `id`), план конструктора принимается `prebuilt`.
  Свайп/колесо/клавиши — только навигация; тап раскрывает ответ, раскрытие хранится по карточке.
  UI — `feed_session_screen.dart` (вертикальный `PageView`, колесо перехватывается `Listener` +
  `pointerSignalResolver` **внутри страницы**, клавиатура `feed_keyboard.dart`, рейка
  `feed-previous/next`), `feed_card_view.dart` (отдельный дизайн, без вложенной прокрутки:
  длинный текст → «Открыть полностью»), `feed_progress_bar.dart` (компактные кликабельные
  сегменты, без пульсации). Маршруты `/decks/:deckId/feed` и `/session/feed` сохранены;
  `feedPath` без `?limits=ignore`, дневные лимиты к ленте не применяются. **Свайп не пишет
  `review_logs` и не меняет `due`/`fsrs_json`** — инвариант держит
  `test/integration/feed_session_flow_test.dart`. Старая свайп-политика `feed_swipe.dart`
  остаётся только внутри `SessionCard` (классика её не включает) и в unit-тесте.
- **Дизайн-система v3** (ADR-045; уточняет ADR-038): палитра «кобальт на графите» в
  `lib/ui/theme/app_tokens.dart` (primary `#1E4FD8`/`#7FA5FF`, поверхности нейтральные без
  сине-фиолетового сдвига), guard `test/guards/contrast_test.dart` (≥4,5:1 текст, ≥3:1 границы).
  Кнопки оценки (`review_toolbar.dart`) — **только названия действий** (`Не знаю / Затрудняюсь /
  Знаю / Легко`), без номеров клавиш и интервалов; прогноз `preview` остаётся в движке и FSRS,
  клавиши `1–4` работают, но не печатаются. Единый чип фильтра — `lib/ui/components/app_filter_chip.dart`
  (высота 36 + цель 44, центр, счётчик отдельным бейджем; ключи `decks-filter-*`).
  Анимации — одна шкала (`AppDurations`, `AppMotion.reduce`), постоянных (пульс/авто-таймер)
  анимаций в приложении нет. «Найти колоду» в оболочке обязана передавать фокус полю
  (`decksSearchFocusProvider` + `FocusNode`), а не только показывать его.
- **Типы/разметка карточек** (SPEC A7.8–A7.10, ADR-017): чистая разметка — `lib/domain/cards/`
  (`occlusion.dart`, `cloze_markup.dart`, `latex_markup.dart`); общий рендер — `lib/ui/cards/content/`
  (`CardContentView`, `cloze_text.dart`, `latex_text.dart`, `occlusion_image_view.dart`), редактор масок —
  `lib/ui/cards/occlusion_mask_editor.dart`. Изображение occlusion — первый `media_json`, маски — 
  `occlusion_json` v1 (нормализованные 0..1); запись файла/строк `media` транзакционная
  (`DriftCardRepository` + `MediaStore`), чтение сессий — `CardMediaRepository`, GC — 
  `MediaGarbageCollector` при старте. LaTeX-рендер — только UI, проверка — `latex_checker.dart`.
  **Единый inline-рендер (ADR-034, 7.17):** любой текст карточки вне карточки (варианты «Теста»,
  плитки «Пар», утверждение/пояснение «Верно/Неверно», правильный ответ и diff «Ввода», список
  ошибок итогов) идёт через `CardText` (`card_text.dart`) → `InlineLatexText` +
  `latex_spans.dart` (`latexTextSpans`: текст → `TextSpan`, формула → `WidgetSpan(Math.tex)`,
  все формулы сразу, стиль наследует родителя); cloze-разметка — `ClozeText`. Сырой `Text(card.front/
  back/option)` в новых режимах запрещён — guard-тесты `test/widget/study/study_mode_latex_test.dart`
  и `test/widget/cards/card_text_test.dart` проверяют отсутствие `$…$`/`{{` в дереве. Вопрос
  режимов рендерится `CardContentView(showAllFormulas: true)` (пошаговое раскрытие — только
  «Классика»); `plainTextOfLatex` даёт текст без разделителей для семантики.
- **Конструктор сессии** (SPEC A6.7/A7.19–A7.20, ADR-018): домен — `lib/domain/session/`
  (`session_config.dart` — конфиг + JSON `version=1` для `session_presets.config_json`;
  `session_builder.dart` — фильтры OR, базовый порядок ADR-008, разминка ≤4 выученных по stability,
  перемешивание по seed, интерливинг round-robin **после** перемешивания, лимит карточек/минут;
  `session_plan.dart`). Порты `SessionPresetRepository` и `LeechRepository` (порог 8, A7.17) —
  реализации `lib/data/session/`, `lib/data/review/`. Экран — `lib/ui/session/session_constructor_screen.dart`;
  маршруты `/constructor` (`?deck=`), `/session/classic`, `/session/feed` (план через `GoRouter.extra`),
  пункт «Конструктор» в листе режимов колоды. Движки классики/ленты принимают `prebuilt` (план не
  пересобирается `ReviewQueue`); лимит минут — `Timer` экрана, по истечении «Время сессии истекло»,
  непройденные карточки не трогаются. Схема БД не менялась: таблица `session_presets` есть с schemaVersion=1.
- **Статистика и настройки** (SPEC A6.1/A6.5/A6.6, ADR-019/ADR-038): оболочка — `lib/ui/shell/app_shell.dart`
  (боковая панель 240 px + шапка 56 px ≥1024 px, `Drawer` <1024 px; ветки `/`, `/statistics`,
  `/settings`; «Сессия» скрыта без активной сессии; `NavigationBar`/`NavigationRail` удалены). Настройки — `lib/domain/settings/` (`AppSettings`, JSON
  `version=1` в `app_settings` ключ `app.settings`, клампы), `AppSettingsStore` + drift-реализация,
  `AppSettingsController` (`save`, откат при ошибке), `appSettingsProvider`/`effectiveAppSettingsProvider`
  в `app_providers.dart`; экран `lib/ui/settings/settings_screen.dart`; проверка ключа —
  `lib/api/generation/api_key_verifier.dart` (минимальный запрос существующими адаптерами, наружу только
  `ApiKeyCheckStatus`). Статистика — `lib/domain/statistics/` (`StatisticsCalculator`: удержание 30 дней,
  карта 365, слабые темы ≥5 повторов и ≥20 % Again, прогноз 7 дней), `DriftStatisticsRepository`
  (только чтение), `lib/ui/statistics/`. Применение — `lib/ui/app.dart` (тема/контраст/dynamic color/
  OpenDyslexic/масштаб, `M3EThemeData.fromMaterial`), `schedulerProvider` (retention/шаги),
  `ReviewQueue.build` (лимиты), экраны сессий (haptics/motion), генерация (модель по умолчанию).
  Шрифт дислексии — `assets/fonts/OpenDyslexic-Regular.otf` (SIL OFL); политика — `docs/privacy.md`.
- **Дневные лимиты — по календарному дню** (ADR-019 §8, L45 снят): расход дня читается из `review_logs`
  (`lib/domain/review/daily_limits.dart` — `DailyReviewUsage`/`RemainingReviewLimits`/`DailyLimits`;
  порт `daily_usage_repository.dart`; drift-реализация `DriftDailyUsageRepository`, провайдер
  `dailyUsageRepositoryProvider`). «Новая» карточка = запись с `actual_days IS NULL` (до оценки не
  планировалась), иначе повторная; день — локальный календарный, схема БД не меняется. Экраны классики и
  ленты передают **остаток** в движок: `int?` в `ReviewQueue.build`/движках — `null` без лимита, `0`
  исчерпан. Конструктор (A6.7) не ограничивается (`prebuilt`).
- Модели immutable (`freezed`/`const`), роутинг `GoRouter` (см. ADR), HTTP `Dio`. Состояние — Riverpod 3 без кодогенерации (ADR-002).
- **Material-виджеты — только `package:material_ui/material_ui.dart`** (ADR-001), `package:flutter/material.dart` в `lib/` запрещён. M3E-компоненты — только через `lib/ui/m3e/`, библиотека `material_3_expressive` больше нигде не импортируется.
- Никаких литералов пользовательского текста в виджетах: только `AppLocalizations` из `lib/l10n/app_ru.arb`.

## Жёсткие запреты

- Локаль только `ru`; `supportedLocales: [Locale('ru')]`; системные строки Flutter — через `GlobalMaterialLocalizations`.
- Никаких WebView/HTML-обёрток, включая транзитивные зависимости (guard-тест по `pubspec.lock`). LaTeX — только `flutter_math_fork`.
- Ключи API — только `flutter_secure_storage` (контракт `ApiKeyStore`); вне кода, логов, БД, экспорта, git. В логах редактировать `Authorization`, `x-api-key`, `x-goog-api-key` (и query `key`/`api_key`) через `lib/api/http/log_redaction.dart`; **тела запросов генерации не логируются вообще**; тела ответов — только debug-диагностикой `GenerationDiagnostics` (ADR-024: `enabled = !dart.vm.product`, редакция секретов, лимит длины, no-op в release), перехватчик — только debug. Значения ключей не выводить в терминал; проверка — present/absent.
- Сырые ошибки API/исключения пользователю не показывать — только сообщения из ARB.
- Никаких мёртвых кнопок и заглушек: функция либо работает, либо её нет (фича-флаг выключен).
- Нельзя ослаблять/удалять тесты, отключать анализатор, ставить `// ignore:` без ADR, понижать порог покрытия.

## Тесты и качество

- TDD: падающий тест → минимальная реализация → зелёный. Покрытие рукописного кода ≥80% (сгенерированное не считается).
- Guard-тесты: `test/guards/no_webview_test.dart`, `ru_strings_test.dart`, `no_secrets_test.dart`, `architecture_test.dart` (framework-Material в `lib/` запрещён, M3E — только в `lib/ui/m3e/`, domain без Flutter).
- Golden-тесты — под тегом `golden`, шрифты с кириллицей подкладываются явно; генерируются/прогоняются на Linux CI.
- **Фикстуры документов — программные** (`test/unit/api/parsers/fixtures/`): DOCX/PPTX/ODT/XLSX/PDF/RTF
  и тексты в кодировках собираются кодом, бинарные файлы в репозиторий не коммитятся; PDF-фикстуры включают
  скан и запароленный PDF (V1/R2 RC4 40-bit).
- Live-тесты API — под тегом `live` и **только по явному разрешению** `CARDFLOW_LIVE_TESTS=1` (+ бюджет `CARDFLOW_LIVE_MAX_REQUESTS`/`_MAX_COST_USD`); без разрешения или без ключа — skip, обычный `flutter test` и CI остаются офлайновыми. Инфраструктура — `test/live/support/` (бюджет, тарифы, отчёт калибровки), управляемый набор — `test/live/adaptive_generation_live_test.dart`; восстановление после ошибок проверяется офлайн на локальном endpoint (`test/integration/generation_recovery_http_test.dart`).
- `flutter analyze` — 0 issues; `dart format` применён.

## Процесс

- Цикл итерации: plan → test → implement → review → verify → remember → improve. После каждого шага — обновить `journal/STATE.md`.
- Коммит после каждого зелёного шага (conventional commit: английский префикс, тело по-русски). Push — только в конце итерации по подтверждению.
- Внешний блокер (нет ключа, нет платформы, нет CI) — известное ограничение в `journal/KNOWN_LIMITATIONS.md` + mock-тест, а не остановка.
- Одна и та же ошибка пережила 3 попытки — стоп, гипотезы в журнал, смена подхода.
- Не заявлять «готово» без команды и её вывода в текущей сессии.
- **Ретроспектива итерации 0 (улучшение процесса с итерации 1):** красная фаза должна сохранять фрагмент вывода с *ожидаемым* поведением (assertion-level, «ожидалось: X, получено: Y»), а не только ошибку компиляции; и — отдельный коммит на каждый зелёный шаг (red / green / verify / docs), а не один коммит на итерацию.
- **Ретроспектива итерации 1:** фикс-итерация findings ревью — отдельный шаг до verify; каждый фикс слоя обязан подтверждаться интеграционным тестом на production-проводке (`app_providers`/`main`/роутер), иначе unit-тесты слоя зелёные, а фикс в приложении не работает (урок M5).
- **Ретроспектива итерации 2:** независимое ревью запускается только на неизменяемом снимке (после коммита зелёной фазы), Lead не правит код до его завершения — иначе findings устаревают; стыки слоёв (импорт/экспорт `.zip` ↔ планировщик/сессия) подтверждаются интеграционным тестом на стыке (export → import → сессия), а не только unit-тестами каждого слоя (урок H1).
- **Ретроспектива итерации 3a:** каждый high/medium из ревью закрывается отдельным fix-коммитом и **новым тестом**
  (или программной фикстурой — например, запароленный PDF/архив с >10 000 записей), а не только правкой кода;
  главные риски парсеров снимаются спайком до плана (pdfrx в изоляте, `cachedValue`, `innerText`).
- **Ретроспектива итерации 3b:** гейт формата — `fvm dart format lib test` (пишет файлы) + проверка
  `fvm dart format --set-exit-if-changed lib test` **без** `--output=none` (он не пишет и маскирует расхождение —
  ложное «0 changed» нашлось на ревью); параллельные слои — тесты-спецификация red-фазы как неизменяемый
  контракт и исполнители с непересекающимися write-scope (адаптеры; HTTP/безопасность), Lead — ядро и проводка.
- **Ретроспектива итерации 3c:** первичные действия длинного экрана — в `bottomNavigationBar`, а не в конце
  `ListView`: иначе widget-тест не находит кнопку без `scrollUntilVisible`, а пользователь — без прокрутки.
  Все high/medium ревью закрывать одним fix-коммитом с отдельным тестом на каждую находку; ошибки
  инфраструктуры (БД) не маскировать под ошибки фрагментов/адаптеров.
- **Ретроспектива итерации 4:** в widget-тестах анимаций после тапа/жеста — сначала `pump()` (старт тика),
  затем `pump(duration)`; PopupMenu/диалоги — `pump()` + `pump(300 ms)`; экраны с повторяющейся
  анимацией (пульс Stories) прогонять `pump(Duration)`, не `pumpAndSettle`; не редактировать `lib/`/`test/`
  во время полного прогона (иначе `loading … [E]`). Независимый reviewer в сессии недоступен (L35):
  ревью Lead по чек-листу на неизменяемом снимке, findings — fix-коммитом с тестами.
- **Ретроспектива итерации 5:** ARB не содержит сырых `{}`-шаблонов (ICU) — синтаксис разметки проверяется
  тестами/ADR, UI-сообщение остаётся коротким. Интерактивный рисующий canvas внутри прокрутки забирает
  pointer eager-распознавателем и имеет vertical-first widget-тест; medium ревью воспроизводится тестом
  до фикса, а `analyze` прогоняется после последней правки тестов, не только кода.
- **Ретроспектива итерации 6:** в widget-тестах экрана с `ListView` сразу заводить helper
  `scrollTo(finder)` (`scrollUntilVisible`) для элементов ниже fold — иначе `find` даёт 0 и «дефект»
  оказывается тестом; блокировку действий во время загрузки проверять гейтом (`Completer`) в фейковом
  репозитории, а не полагаться на «быстрые» фейки; домен и его тесты писать до UI — тогда порядок
  фильтров/сборки не отлаживается в виджетах.
- **Ретроспектива итерации 7:** настройка считается сделанной только с тестом **применения** (корень
  приложения/планировщик/очередь/экран), а не только записи в store; в widget-тестах длинного списка
  настроек идти сверху вниз (`scrollUntilVisible` не ищет выше текущей позиции); ряд провайдеров API
  проверять на узкой ширине (`Wrap`/перенос вместо `Row` с двумя кнопками); M3E-тему проецировать из
  Material-темы (`M3EThemeData.fromMaterial`), иначе M3E перекрывает шрифт дислексии и dynamic color.
- **Ретроспектива итерации 7.5:** сохраняемые сущности с несколькими полями валидировать и писать
  **независимо** — ранний `return` по одному полю не должен «съедать» другое (баг D1: ключ не
  сохранялся из-за пустого адреса); результат read-back хранилища обязан влиять на сообщение об
  успехе (D3); платформенный плагин без `flutter test`-регистрации проверять
  `integration_test`-ом на десктопе (`-d windows`), а не только моками; при breaking-рефакторинге
  контрактов сначала обновлять общие тестовые фейки (`test/helpers/`), затем точечно тесты.
- **Ретроспектива итерации 7.6:** owner-note «ошибка при генерации» диагностировать сначала по
  **фактическим данным приложения** — `generation_jobs` (`status`, `error_code`, `cards_count`, модель)
  и разбор приложенных файлов тем же парсером, — и лишь затем живыми вызовами API: в 7.6 живой ответ был
  корректен (`finish_reason=stop`), а причину дали запись `done` + `cards_count=0` и PDF-бланки без
  текста. UI-строку ошибки нельзя переиспользовать для другого исхода: валидный пустой `cards` — не
  `emptyResponse`, для него отдельная строка ARB. CI с `concurrency` отменяет незавершённый прогон при
  новом push — сначала пушить все коммиты итерации, затем ждать один прогон.
- **Ретроспектива итерации 7.8:** поля-возможности провайдера (`supportsVision`) добавлять в JSON с
  обратной совместимостью (инференс для старых записей и переключатель в UI), а «сырую» диагностику
  провайдера (причина 400) — отдельным безопасным полем `providerReason`, не через `details`; проверять
  сквозной путь HTTP → ARB → UI и приоритет ошибок (vision раньше размера/PDF-протокола).
- **Ретроспектива итерации 7.9:** wire-значение, конфликтующее со SPEC (occlusion), проецировать в
  существующий тип + ADR, а не менять публичный контракт; при добавлении обязательного поля strict-схемы
  (`image_query`) обновлять одну общую JSON-фикстуру карточки, а не три копии; при привязке провайдера к
  новому обязательному platform-зависимому сервису (MediaStore в `generationCardStoreProvider`) сразу
  прогонять production-интеграционный тест — он ловит `UnimplementedError` в проводке, который unit-тесты
  слоёв не видят; риск «тяжёлый PDFium в изоляте» снимать реальным тестом (`Isolate.run`) до UI.
- **Ретроспектива итерации 7.10:** owner-note «PDF → неожиданный ответ» разбирать спайком **до** плана
  (PDFium отдаёт C1-управляющие и одиночные суррогаты — видно на программной фикстуре), а не догадками;
  для молчаливых сервисов с `null`-контрактом (поиск картинок) добавлять debug-диагностику **вместе** с
  фиксом, иначе «модель не дала image_query» и «не удалось скачать» неразличимы; `fvm flutter test` без
  `--no-pub` в сессии агента зависает на `pub get --example` — прогоны только с `--no-pub`.
- **Ретроспектива итерации «Фикс мобильного Empty State» (1.0.1):** блок `Row` из
  «иконка + `Expanded(Text)` + `TextButton`» на телефоне отдаёт кнопке её неделимую ширину, а тексту —
  остаток: на 390 px оставалось 36,8 px (42 строки), на 360 px — 6,8 px (по одной букве). Горизонтальные
  блоки с неделимым действием проверять на мобильной ширине `Column`-ом (`< AppSizes.mobileBreakpoint`),
  а не только на десктопе. Widget-тесты шрифтом по умолчанию **скрывают** переполнения реального
  Inter: измерять геометрию на реальных шрифтах/кегле 150 % (`textScaleFactorTestValue`) и проверять
  относительное положение (`action.top >= note.bottom`), а не только `takeException()`. Скриншот без
  устройства — `RepaintBoundary.toImage(pixelRatio: 2)` в `tester.runAsync` (вне fake-async зоны `toImage`
  не завершается) + `FontLoader` из `assets/fonts` и `materialicons-regular.otf` из SDK
  (`$FLUTTER_ROOT/bin/cache/artifacts/material_fonts`); `setSurfaceSize` **не** меняет `MediaQuery` —
  размер задавать через `tester.view.physicalSize` + `devicePixelRatio: 1`.

## Факты хоста (обновлять при изменении)

- Windows 11; Android SDK/JDK/Xcode отсутствуют → локально проверяем `flutter test/analyze` и `flutter build windows`; остальные сборки — CI/известное ограничение.
- FVM 4.3.2; Flutter 3.47.9 (Dart 3.13.7). Все команды — через `fvm` (`fvm flutter …`).
- **Windows-сборка CardFlow работает локально (итерация 1, 2026-11-12):** `fvm flutter build windows --release` → `√ Built build\windows\x64\runner\Release\cardflow.exe` (VS BuildTools 18.12/MSVC 14.52; прежняя ошибка ATL снята, устаревший `build/windows` удалён). Если сборка падает на компиляторе — сначала очистить `build/windows` (stale CMakeCache).
- **API-слой генерации проверен локально (итерация 3b + ADR-013, 2026-11-13):**
  `fvm flutter test --exclude-tags golden` → **800 тестов зелёные + 1 live skipped**; покрытие
  **95.1% (4071/4279)**; `analyze` 0; `dart format` 0 changed; `fvm flutter build windows --release` — ок.
  CI: 3b — run [`43501572437`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43501572437),
  OpenAI-compatible — run [`43505863077`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43505863077),
  оба 9/9 job success. Спайки: `json_schema 5.2.2` валидирует A8.4 (S1), проверка LaTeX —
  `Math.tex(...).parseError` без рендера (S2), fake `HttpClientAdapter` Dio 5.11.1 для retry/429/5xx/отмены
  без сети (S3) — `journal/iteration-3b/spikes.md`.
- **Живой DeepSeek проверен (2026-11-14, L30 частично закрыт):** `DEEPSEEK_API_KEY` задан в Windows
  **User scope**, но в унаследованном env процесса агента его нет (absent) — ключ читается из реестра
  (`[Environment]::GetEnvironmentVariable(...,'User')`) и передаётся **дочернему** процессу; значение не печатать.
  `fvm flutter test test/live --tags live` → **1 passed** (`deepseek-chat`, 3 карточки, 1231 токен): живой
  `/chat/completions`, Bearer, разбор ответа, валидация A8.4 и контентные правила. Детали —
  `journal/iteration-3b/live-l30.md`. Негативные live-контракты (401/403/429/`Retry-After`) не проверяются —
  ADR-014. OpenAI/Gemini/Anthropic живьём не проверялись (L1).
- **Экран генерации проверен локально (итерация 3c, 2026-11-14):** `fvm flutter test --exclude-tags golden`
  → **897 passed + 1 skipped**; покрытие **93.2% (5219/5597)**; `analyze` 0; `dart format` 0 changed;
  `fvm flutter build windows --release` — ок. Ревью 3c: 2 high, 12 medium, 11 low, H/M закрыты
  fix-коммитом `9db83ab` с новыми тестами. Пайплайн: `GenerationPipeline` (оценка/чанкинг,
  последовательные вызовы, split-once, дедуп, partial/retry, `generation_jobs`); UI A6.8:
  `lib/ui/generation/`; входы — Split-меню «Колод» и Toolbar «Колоды». DnD — `desktop_drop 0.8.4`,
  файлы — `file_picker 13.3.3`; реальный DnD-жест на ОС не проверялся (L33). CI 3c — run
  [`43583803312`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43583803312) (`e5f64c4`), 9/9 success.
- GitHub-remote: `origin` → `piotrcheban-pixel/cardflow` (**Public** с 2026-11-14, биллинг GitHub починен);
  CI — GitHub Actions (`.github/workflows/ci.yml`). Push выполняется по команде владельца (хука `confirm-git-push` нет).
- **PDF-тесты и PDFium в CI (L26, с 2026-11-13):** job `test` скачивает pinned PDFium
  (`bblanchon/pdfium-binaries` `chromium/8125` — тот же релиз, что build-hook `pdfium_dart` 0.4.1) на всех трёх ОС,
  сверяет sha256 и экспортирует `PDFIUM_PATH`; PDF-тесты не скипаются/не тегируются, инварианты защищает
  `test/guards/ci_pdfium_test.dart`. При обновлении `pdfium_dart`/`pdfrx` синхронно обновлять пин, ассеты и sha256
  в `.github/workflows/ci.yml` (ADR-010 §11). В корне `.gitattributes` `* text=auto eol=lf`: guard-тесты сверяют
  точные маркеры файлов, CRLF из checkout-а ломал L26-guard на Windows.
- **CI и диск раннера (с 2026-11-13):** перед `flutter pub get` все job'ы выполняют шаг `Free disk space` (Linux: dotnet/android SDK/ghc/boost/CodeQL + `docker image prune --all`; macOS: Android SDK/Homebrew cache/dotnet) с `df -h` до/после; Android-сборка дополнительно чистит `~/.gradle/caches` перед сборкой. Android SDK в android-job сохраняется (`KEEP_ANDROID_SDK`) — без него `flutter build apk` не работает. Прогоны docs-коммитов live-верификации L30 (`a2568ea`, `384ca43`) — 9/9 job success
(`43510331361`, `43511718280`); актуальный статус — вкладка Actions репозитория.
- **Лента проверена локально (итерация 4, 2026-11-14):** `fvm flutter test --coverage --exclude-tags golden`
  → **959 passed + 1 skipped**; покрытие **93.6% (5788/6181)** (feed-файлы 95.8–100%); `analyze` 0;
  `dart format` 229 files 0 changed; `fvm flutter build windows --release` → `cardflow.exe` (51,9 s).
  Ревью Lead (независимый reviewer недоступен — L35), fix `1857589`; push 2026-11-14: `origin/main` =
  `e90f660`, CI runs [`43587472135`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43587472135)
  и [`43588247850`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43588247850) — оба **9/9 success**.
  После них run [`43589108294`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43589108294) (`490eb80`) —
  9 job'ов failure без единого шага (GitHub billing/spending limit — внешний блокер владельца; снят 2026-11-14
  переводом репозитория в Public и починкой биллинга). Ограничения: L36 (таймер при покрытии маршрутом), L37 (реальные жесты).
- **Occlusion / Cloze / LaTeX проверены локально (итерация 5, 2026-11-14):** `fvm flutter test --coverage
  --exclude-tags golden` → **1020 passed + 1 skipped**; покрытие **93.1% (6468/6946)**; `analyze` 0;
  `dart format` 253 files 0 changed; `fvm flutter build windows --release` → `cardflow.exe` (56,2 с).
  Ревью Lead снимка `5af8f70` (L35), M1–M4 закрыты `0e4e11b` с тестами; L17 снят startup-GC, добавлены
  L38/L39. Схема БД/`format_version` не менялись, create → export → import покрыт интеграционным тестом.
  Push 2026-11-14: `origin/main = 9bd09ad` (7 коммитов итерации 5); CI run
  [`43612309379`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43612309379) — **9/9 job success**
  (`format + analyze`, `test` × 3 ОС, `build desktop` × 3, `build mobile` Android + iOS). Реальные picker/рисование — L11/L38.
- **Конструктор сессии проверен локально (итерация 6, 2026-11-14):** `fvm flutter test --coverage
  --exclude-tags golden` → **1102 passed + 1 skipped**; покрытие **93.1% (7236/7772)** (экран конструктора
  94.8%); `analyze` 0; `dart format` 269 files 0 changed; `fvm flutter build windows --release` →
  `cardflow.exe` (51,9 с). Ревью Lead снимка `70b1d97` (L35): high нет, M1–M3 и L1–L2 закрыты `0bdc0ab`
  с тестами (порядок «перемешивание → интерливинг», блокировка старта при недогруженных карточках, тест
  переключения режима). Схема БД/`format_version` не менялись (пресеты — в существующей `session_presets`),
  стык domain → сессии покрыт интеграционным тестом на production-графе и реальной drift-БД. Лимит минут —
  `Timer` экрана (L40), загрузка карточек конструктором — L41, ручная приёмка — L42. CI финального снимка —
  после push по команде владельца.
- **Статистика и настройки проверены локально (итерация 7, 2026-11-14):** `fvm flutter test --coverage
  --exclude-tags golden` → **1175 passed + 1 skipped**; покрытие **92.7% (8322/8977)**; `analyze` 0;
  `dart format` 299 files 0 changed; `fvm flutter build windows --release` → `cardflow.exe` (61,7 с).
  Ревью Lead снимка `85afff3` (L35): high/critical нет, M1–M2 закрыты `6a40180` с тестами (подписи месяцев
  карты, нулевой столбик прогноза), M3 — L45. `dynamic_color` впервые задействован; OpenDyslexic (SIL OFL) —
  `assets/fonts/`; политика приватности — `docs/privacy.md`. Схема БД/`format_version` не менялись
  (`app.settings` — строка существующей `app_settings`), стык settings → scheduler/ReviewQueue/статистика
  покрыт интеграционным тестом на production-графе и реальной drift-БД. Ограничения: L43 (dynamic color/
  шрифт/размеры на ОС), L44 (объём статистики), L46 (screen-reader карты).
  **Push итерации 7 (2026-11-14):** `b2293cc..d1c55fa`; CI run
  [`43623897449`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43623897449) — **9/9 job success**.
  **Долг L45 снят в той же сессии** (ADR-019 §8): полный прогон **1203 passed + 1 skipped**, покрытие
  **92.6% (8368/9038)**, `analyze` 0, `format` 305/0. **Финальный аудит MVP** — `journal/mvp-audit.md`,
  8/8 критериев §9 «выполнено»; добавлен отсутствовавший `docs/m3e-tokens.md` (требование SPEC B4).
- **Провайдеры и ключи проверены локально (итерация 7.5, 2026-11-14, ADR-020):** `fvm flutter test
  --coverage --exclude-tags golden` → **1254 passed + 1 skipped**; покрытие рукописного кода
  **92.6 % (8759/9457)**; `analyze` 0; `dart format` 317/0; `fvm flutter build windows --release` →
  `cardflow.exe` (54,7 с). **Реальное secure storage (Windows, DPAPI):**
  `fvm flutter test integration_test/secure_api_key_store_windows_test.dart -d windows` →
  `All tests passed!` (write → read → delete; L28 сужен). **Живой DeepSeek на аккаунтном пути:**
  `fvm flutter test test/live --tags live` → `LIVE DeepSeek OK: model=deepseek-chat, cards=3,
  tokens=1138` (ключ из Windows User scope, значение не выводилось). Интеграционный тест
  «DeepSeek-аккаунт → `https://api.deepseek.com/chat/completions` + Bearer + job.provider=deepseek».
  Каталог: 9 провайдеров, миграция legacy-настроек и ключей, экран «Провайдеры», проверка
  подключения. Схема БД/`schemaVersion` не менялись; `AppSettings.defaultProvider/defaultModelId`
  удалены (роль — `activeAccountId`). Ограничения: L28 (только Windows), L47, L48, L49.
  **Push итерации 7.5:** `7892b08..a20cd5e`; CI run
  [`43632334916`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43632334916) —
  **9/9 job success**.
- **PDF-сканы, иллюстрации и occlusion проверены локально (итерация 7.9, 2026-11-15, ADR-023):**
  `fvm flutter test --coverage --exclude-tags golden` → **1369 passed + 2 skipped**; покрытие
  **92.8 % (9277/9994)**; `analyze` 0; `dart format` 331 файл / 0 changed;
  `fvm flutter build windows --release` → `cardflow.exe` (80,5 с). Рендер PDF-страниц в `Isolate.run`
  проверен на реальном PDFium (`pdf_scan_renderer_test.dart`); production-граф
  «occlusion + image_query → поиск → drift-БД → MediaStore → media/маска» — в
  `test/integration/generation_flow_test.dart`. **Живой DeepSeek с `gen-ru-v3`:** 2 live-теста
  passed (`cards=3, tokens=1351`; fallback strict=400 → tolerant=200, `max_tokens=8192`).
  Схема БД/`schemaVersion` и `format_version` не менялись; `card_type: occlusion` — wire-формат,
  в БД `basic` + `occlusion_json`. Ограничения: L57–L60.
  **Push итерации 7.9:** `31a5999..63330da`; CI run
  [`43703387395`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43703387395) —
  **9/9 job success**.

- **Prompt-only, PDF и картинки проверены локально (итерация 7.10, 2026-11-15, ADR-024):**
  старт: `git status --porcelain` → пусто, `HEAD = origin/main = bdb0bd1` (в STATE 7.9 было `31a5999` —
  исправлено); baseline **1369 passed + 2 skipped**. Спайк PDFium: C1 `U+0080–U+009F` и `U+FFFD`/
  одиночные суррогаты из Type0/ToUnicode-PDF подтверждены программной фикстурой. Гейты:
  `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1409 passed + 3 skipped**; покрытие
  **92.9 % (9393/10114)**; `analyze` 0; `dart format` 334 файла / 0 changed;
  `fvm flutter build windows --release --no-pub` → `cardflow.exe` (63,9 с). **Живой DeepSeek:** 3 live-теста
  passed — `cards=3, tokens=1467`; fallback `strict=400 → tolerant=200`; **prompt-only без файлов:
  `cards=3, image_query=3, prompt=gen-ru-v4, tokens=1502`** (промпт v4 действительно возвращает
  `image_query`). Живой Openverse с хоста агента не завершается (L61), проводка проверена
  интеграционным тестом с реальным `ImageSearchService` и fake-Dio (media + файл). Ограничения: L61–L64.
  Замечание окружения: `fvm flutter test` без `--no-pub` зависает на `pub get --example` — все прогоны
  итерации с `--no-pub`. **Push итерации 7.10:** `bdb0bd1..5cbb653`; CI run
  [`43728048903`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43728048903) —
  **9/9 job success**.

- **FSRS новых карточек, картинки, сканы и «Тренировка» проверены локально (итерация 7.11, 2026-11-15,
  ADR-025/026/027):** старт: `git status --porcelain` → пусто, `HEAD = origin/main = 14b1a71`
  (в STATE 7.10 было `5cbb653` — исправлено); baseline **1409 passed + 3 skipped**.
  Диагностика owner-note по **фактической БД приложения** (копия `%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite`):
  43 новые карточки с `due`/`fsrs_json` = NULL; за день 30 оценок «новых» при `daily_new_limit=20`;
  экран колоды проверял очередь без лимитов → пустая сессия. Openverse с хоста таймаутил (первый GET 200,
  дальше > 30 с), Wikimedia Commons по русским запросам — 1–2 с. Гейты:
  `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1458 passed + 4 skipped**; покрытие
  рукописного кода **92.9 % (9804/10557)**; `analyze` 0; `dart format --set-exit-if-changed lib test`
  → 349/0; `fvm flutter build windows --release --no-pub` → `cardflow.exe` (79,3 с);
  `fvm flutter run -d windows --no-pub` → окно открылось, ошибок старта нет.
  **Windows-смоук на реальном процессе:** `fvm flutter test integration_test/session_smoke_windows_test.dart
  -d windows` → `All tests passed!` (генерация с картинкой → файловая drift-БД + MediaStore → лимит →
  тренировка → видимая иллюстрация → practice-оценка). **Живые тесты (deepseek-chat):** 5 passed —
  `cards=3, tokens=1601`; `strict=400 → tolerant=200`; prompt-only `image_query=3`;
  **PDF-скан: `pages=3, cards=2, tokens=2905`**; **живой Wikimedia: JPEG 97 КБ, CC BY-SA 4.0**.
  `deepseek-flash` дал 2/5 `invalidResponse` (strict-схема) — L66. Ограничения: L65–L70.
  Замечание: `flutter test -d windows` собирает Debug-приложение и требует десктоп-дисплея (в CI нет).
  **Push итерации 7.11:** `14b1a71..8925e99`; CI run
  [`43742161910`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43742161910) —
  **9/9 job success**.

- **Картинки без масок, дневной лимит и поиск иллюстраций проверены локально (итерация 7.12,
  2026-11-15, ADR-028):** старт: `git status --porcelain` → пусто, `HEAD = origin/main = e9ea08b`
  (в STATE 7.11 было `8925e99` — исправлено); baseline **1458 passed + 4 skipped**.
  Диагностика owner-note по фактической БД: `daily_new_limit=20`, за день 30 «новых» оценок,
  затем создан пак 13 карточек → пустая сессия; задание `deepseek-flash` (13 карточек) —
  `media_json = []`. Живой зонд: `image_query: null` на определениях, Commons по русским
  словоформам — 0 файлов, Openverse таймаутит, ошибка поиска не видна; DDG — bot-challenge (202),
  Pexels/Pixabay нужен ключ. Гейты: `fvm flutter test --no-pub --coverage --exclude-tags golden`
  → **1512 passed + 5 skipped**; покрытие рукописного кода **92.4 % (10085/10914)**; `analyze` 0;
  `dart format --set-exit-if-changed lib test integration_test` → 355/0;
  `fvm flutter build windows --release --no-pub` → `cardflow.exe` (64,3 с);
  `fvm flutter run -d windows --no-pub` → окно открылось, ошибок старта нет.
  **Windows-смоук:** `integration_test/session_smoke_windows_test.dart -d windows` →
  `All tests passed!` (Basic+картинка без масок через реальную форму → media+файл; исчерпанный
  лимит не блокирует сегодняшнюю карточку, иллюстрация видна; старая карточка → предупреждение →
  «Продолжить без лимита»; генерация с `image_query` → картинка в предпросмотре и media).
  **Живые тесты (deepseek-chat):** 7 passed — Wikimedia JPEG 97 КБ; Wikipedia JPEG 239 КБ;
  composite «спайность минерала»: Commons 0 → Wikipedia «Минерал»; prompt-only
  `image_query=3, tokens=1602`; PDF-скан `pages=3, cards=2`; fallback strict=400 → tolerant=200.
  **`deepseek-flash` (модель владельца):** prompt-only `image_query=3, tokens=2421`;
  production-пайплайн → **3 карточки, 3 картинки** (218 670 / 458 295 / 134 919 Б JPEG).
  Ограничения: L71–L75; L60/L70 обновлены.
  **Push итерации 7.12:** `e9ea08b..c6dd64e`; CI run [`43750931989`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43750931989) — **9/9 job success**.

- **Генерация: промпт v5, картинки из файлов, LaTeX и частичный импорт проверены локально (итерация
  fix-gen, 2026-11-15/16, ADR-029/ADR-030):** старт: `git status --porcelain` → пусто,
  `HEAD = origin/main = c95e5a9` (в STATE 7.12 было `c6dd64e` — исправлено); baseline
  **1512 passed + 5 skipped**. Диагностика подтвердила JSON-экранирование LaTeX (`\frac`→form feed,
  `\alpha`→FormatException) и отбрасывание фрагмента из-за одной карточки; причина «Не удалось
  обработать фрагмент» разобрана по `generation_jobs`. Гейты:
  `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1597 passed + 7 skipped**;
  покрытие **92.3 % (10814/11720)**; `analyze` 0; `dart format --set-exit-if-changed lib test
  integration_test` → 378/0; `fvm flutter build windows --release --no-pub` → `cardflow.exe`
  (70,5 с); Windows-смоук `integration_test/session_smoke_windows_test.dart -d windows` →
  **All tests passed!** (10 с). **Живые тесты (deepseek-chat):** 10 passed — prompt-only v5
  `cards=3, image_query=3, rejected=0`; **статика 20 карточек, доля пометок 0.0 %**;
  **DOCX с рисунком: `images=1, cards=9, image_id=1, with_image=1`**; PDF-скан `pages=3,
  cards=2`; картинки 3/3. Схема БД/`schemaVersion` не менялись (`image_id` — wire-поле до
  импорта в `media`). Ограничения: L76–L80. **Push итерации fix-gen:** `c95e5a9..08b42d8`;
  CI run [`43764143830`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43764143830) —
  **9/9 job success**.

- **Картинки у всех карточек проверены локально (итерация 7.14, 2026-11-16, ADR-031):**
  старт: `git status --porcelain` → пусто, `HEAD = origin/main = cc88e0c` (в STATE fix-gen было
  `08b42d8` — исправлено); baseline **1597 passed + 7 skipped**, `analyze` 0, `format` 378/0.
  Промпт `gen-ru-v6` (v5 сохранён): у каждой карточки обязательный объект
  `image {query, fallback_query, kind}`; локальная терпимая схема принимает и v5 `image_query`.
  Цепочка `ImageSearchService` + `ImageProvider` (Wikimedia Commons → Wikipedia → Openverse →
  Pixabay/Pexels по ключу): таймаут провайдера 6 с, бюджет карточки 20 с, фильтры JPEG/PNG/WebP,
  короткая сторона ≥ 400 px, пропорции ≤ 3:1, кэш, дедуп URL, ретрай 429/5xx, ≤ 4 загрузки.
  Метаданные атрибуции — в `<путь>.meta.json` (схема БД не менялась), «Найти картинку
  заново» для настоящих изображений; фоновый ретрай и заглушки удалены в 7.19 (ADR-041).
  UI: `CardImageView` 16:9/4:3, fade-in, скелетон, полноэкранный зум с атрибуцией; карточки
  появляются до догрузки картинок (`GenerationProgress.cards`). Гейты:
  `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1660 passed + 8 skipped**;
  покрытие рукописного кода **92.0 % (12159/13218)**; `analyze` 0; `format` 0 changed;
  `fvm flutter build windows --release --no-pub` → `cardflow.exe` (84,4 с); Windows-смоук
  `integration_test/session_smoke_windows_test.dart -d windows --no-pub` → **All tests passed!**
  (9 с; debug-сборка 28,6 с) — форма+картинка, лимит, сессия, генерация с настоящей картинкой.
  **Живые колоды (`deepseek-chat`, настоящая сеть):** «Статика» 18 карточек —
  **18/18 настоящих картинок (100 %)**, wikipedia 14/wikimedia 4, среднее 3,5 с;
  «Биология» 18 — **18/18 (100 %)**, wikipedia 10/wikimedia 8, среднее 1,9 с; заглушек 0.
  **Ручная уместность 10 случайных:** «Биология» **8/10** (цель достигнута), «Статика»
  **1/10** (цель ≥ 7/10 не достигнута). Одна итерация правки промпта (канонические якоря схем)
  не исправила полнотекстовый матчинг Commons/Wikipedia — ограничение L84 (рекомендация:
  семантическая проверка релевантности/курируемые схемы). Отчёт:
  `journal/iteration-7.14/{live-metrics.md,relevance.md}`. Ограничения: L81–L86.

- **Режимы «Тест» и «Ввод ответа» проверены локально (итерация 7.15, 2026-11-16, ADR-032):**
  старт: `git status --porcelain` → пусто, `HEAD = origin/main = bf28359` (CI 7.14 — run
  [`43901313115`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43901313115) 9/9);
  baseline **1660 passed + 8 skipped**, `analyze` 0, `format` 0. Домен: `StudyMode`,
  `StudyFsrsPolicy` (due → FSRS, будущая due → тренировка, новая — как due), `StudyQueue`,
  `AnswerType` (short_text/number/formula/long_text; для ввода ≤ 60 символов/6 слов без LaTeX),
  `AnswerMatcher` (NFC через `unorm_dart`, exact/almost/wrong, Левенштейн 1/2, diff), `DistractorGenerator`
  (3 из колоды того же типа/длины, числа той же единицы, seed-позиция). Общий
  `StudySessionController` (очередь/прогресс/итоги/undo/повтор ошибок; `review_logs.mode`,
  undo фильтруется по mode). Экраны `MultipleChoiceScreen`/`TypingScreen`, маршруты
  `/decks/:deckId/{test,typing}`, лист режимов с числом карточек, ARB (ru). Гейты:
  `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1715 passed + 8 skipped**;
  покрытие рукописного кода **91.7 % (12974/14143)**; `analyze` 0; `format` 0 changed;
  `fvm flutter build windows --release --no-pub` → `cardflow.exe` (56,4 с); CI run
  [`43904903386`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43904903386) — 9/9.
  Новая зависимость `unorm_dart ^0.3.3` (чистый Dart, MIT) — в `docs/dependencies.md`. Ограничения: L87
  (ИИ-дистракторы не подключены), L88 (новые режимы не учитывают дневные лимиты).

- **Режимы «Подбор пар» и «Верно/Неверно» проверены локально (итерация 7.16, 2026-11-16, ADR-033):**
  домен `MatchGame` (6 пар/12 плиток, seed, selected/matched/mismatch), `MatchScreen` (таймер,
  встряхивание, лучшее время), `MatchBestStore` + `DriftMatchBestStore` (JSON v1 в `app_settings`,
  ключ `study.match.best`, схема БД не менялась); `TrueFalseQuestion` 50/50 и `TrueFalseScreen`
  (кнопки ✓/✗, свайпы, общий `StudySessionController`, `mode='true_false'`, FSRS только для due).
  Маршруты `/decks/:deckId/{match,true-false}`, лист режимов, ARB (ru). Гейты:
  `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1742 passed + 8 skipped**;
  покрытие рукописного кода **91.7 % (13521/14743)**; `analyze` 0; `format` 0 changed;
  `fvm flutter build windows --release --no-pub` → `cardflow.exe` (52,4 с);
  CI run [`43913907014`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43913907014) — 9/9
  (первый прогон `43909148956` упал на analyze из-за импортов test/tool, фикс `ed83795`);
  финальный run [`43915833682`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43915833682) — 9/9.
  Скриншоты — `journal/iteration-7.15/screenshots/`. Ограничения: L87/L88.

- **Рендер LaTeX/cloze во всех режимах проверен локально (итерация 7.17, 2026-11-16, ADR-034):**
  старт: `git status --porcelain` → пусто, `HEAD = origin/main = 4dfe10c` (в STATE 7.16 было
  `aad938f` — исправлено); baseline **1742 passed + 8 skipped**, `analyze` 0, `format` 0.
  Диагностика owner-note по фактической БД (`cardflow.sqlite`: 175 карточек, 61 с LaTeX, 6 cloze;
  78/78 формул парсятся `flutter_math_fork`) + зонд widget-тестами: вопрос уже шёл через
  `CardContentView`, сырой `Text` остался в вариантах «Теста», плитках «Пар» (все 12), утверждении/
  пояснении «Верно/Неверно», строке ответа и diff «Ввода», списке ошибок итогов. Решение:
  `CardText` + `latexTextSpans` (единый inline-рендер, все формулы сразу), `CardContentView(showAllFormulas: true)`
  для вопроса, `AnswerDiffView` на общем хелпере, `plainTextOfLatex` для семантики; домен —
  `AnswerType.isChoice` (Тест: короткий/число/формула ≤ 120 символов; Ввод — по-прежнему `isTypable`),
  дистракторы «Верно/Неверно» из `isChoice`, `\(…\)`/`\[…\]` → `formula`. Гейты:
  `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1772 passed + 8 skipped**;
  покрытие рукописного кода **91.9 % (12948/14086)**; `analyze` 0; `format` 0 changed;
  `fvm flutter build windows --release --no-pub` → `cardflow.exe` (60,8 с); скриншоты
  `journal/iteration-7.17/screenshots/` (Тест с формулами в вопросе и четырёх вариантах, Пары,
  Ввод, Верно/Неверно; KaTeX-шрифты в харнессе грузятся вручную — L91); первый полный прогон упал
  на живом Wikimedia-тесте (сеть, повторный зелёный — L92). Ограничения: L89–L92.
  **Push итерации 7.17:** `4dfe10c..b199dbc`; CI run
  [`43935245725`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43935245725) — **9/9 job success**.

- **Изображения: стороны и отказ от заглушек (итерация 7.19, 2026-11-21, ADR-041/042):**
  первопричина повторяющейся картинки — `PlaceholderImageGenerator` (рисованный PNG,
  80/207 медиа фактической БД, 68 `diagram`); генератор удалён, pipeline не создаёт изображения,
  `PlaceholderMediaPurger` удаляет старые заглушки при старте, байты проверяются по сигнатуре
  (`image_bytes.dart`). Стороны: `cards.media_json` v2 `{"version":2,"question":[…],"answer":[…]}`,
  схема ответа `gen-ru-v9` (`question_image_ids`/`answer_image_ids`/`image.side`, legacy v5–v8
  принимается), промпт v9 (v8 дословно), редактор двух сторон, `CardContentView` по стороне,
  явные состояния ошибок с повтором (`onRetryMedia`, `reloadSessionMedia`). Legacy-массив без
  стороны: occlusion/cloze — вопрос, остальное — ответ (безопасная политика). Гейты:
  2425 passed + 16 skipped, покрытие 91.5 %, `cardflow.exe` 61,8 с, Windows smoke passed;
  CI run [`44924253292`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44924253292) — 9/9.
  Ограничения L186–L193.
