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
  (`GenerationPipeline`: оценка/чанкинг, последовательные вызовы, прогресс/отмена, split-once, дедуп,
  `generation_jobs`, partial/retry); чистые правила — `lib/domain/generation/` (`token_estimator.dart`,
  `generation_model.dart`, `generation_chunker.dart`, `generation_job.dart`, `generation_run.dart`).
  У OpenAI-compatible `base_url` и `model` — настройки в `app_settings` (`generation.openai_compatible`,
  `GenerationSettingsStore`), ключ опционален и только в `ApiKeyStore`; strict `response_format` — с одним
  fallback без схемы и локальной проверкой A8.4; промпт `gen-ru-v2` скрыт в коде (`system_prompt.dart`),
  пользовательское сообщение — `generation_prompt.dart`; контентные правила A8.4 — `card_content_validator.dart`
  (пометки `CardIssueCode`, карточка не отбрасывается); HTTP — только через `GenerationTransport`
  (`lib/api/http/generation_http_client.dart`) с `RetryPolicy` и `RedactingLogInterceptor`. Ошибки — только
  `GenerationErrorCode` → строка ARB (`lib/ui/generation/generation_error_message.dart`). Ключи — только
  `ApiKeyStore` (secure storage). LaTeX-проверка `flutter_math_fork` допустима только в
  `lib/api/generation/latex_checker.dart` и инжектируется в валидатор; остальной `lib/api/` от Flutter не зависит.
- `ui/` — экраны, виджеты, локализация. Компоненты M3 Expressive — только через слой `lib/ui/m3e/` (библиотеку можно заменить). Токены движения — `lib/ui/motion.dart`.
- **Режим «Лента»** (SPEC A7.3, ADR-016): движок `lib/ui/review/feed_session_engine.dart` (очередь
  `ReviewQueue`, по-карточные revealed/rated, `visit` без записи, `rate`/`undo` через тот же
  `ReviewRepository`, `mode='feed'`, авто-продвижение без оценки); политика свайпов —
  `feed_swipe.dart` (80 px + 300 px/с, >60% — Easy/Hard); UI — `feed_session_screen.dart`,
  `feed_card_view.dart`, `feed_progress_bar.dart`; общий каркас A6.4 — `review_chrome.dart`;
  маршрут `/decks/:deckId/feed` из листа режимов колоды. Пульсация Stories — повторяющаяся
  анимация: тесты только `pump(Duration)`, не `pumpAndSettle`.
- **Типы/разметка карточек** (SPEC A7.8–A7.10, ADR-017): чистая разметка — `lib/domain/cards/`
  (`occlusion.dart`, `cloze_markup.dart`, `latex_markup.dart`); общий рендер — `lib/ui/cards/content/`
  (`CardContentView`, `cloze_text.dart`, `latex_text.dart`, `occlusion_image_view.dart`), редактор масок —
  `lib/ui/cards/occlusion_mask_editor.dart`. Изображение occlusion — первый `media_json`, маски — 
  `occlusion_json` v1 (нормализованные 0..1); запись файла/строк `media` транзакционная
  (`DriftCardRepository` + `MediaStore`), чтение сессий — `CardMediaRepository`, GC — 
  `MediaGarbageCollector` при старте. LaTeX-рендер — только UI, проверка — `latex_checker.dart`.
- Модели immutable (`freezed`/`const`), роутинг `GoRouter` (см. ADR), HTTP `Dio`. Состояние — Riverpod 3 без кодогенерации (ADR-002).
- **Material-виджеты — только `package:material_ui/material_ui.dart`** (ADR-001), `package:flutter/material.dart` в `lib/` запрещён. M3E-компоненты — только через `lib/ui/m3e/`, библиотека `material_3_expressive` больше нигде не импортируется.
- Никаких литералов пользовательского текста в виджетах: только `AppLocalizations` из `lib/l10n/app_ru.arb`.

## Жёсткие запреты

- Локаль только `ru`; `supportedLocales: [Locale('ru')]`; системные строки Flutter — через `GlobalMaterialLocalizations`.
- Никаких WebView/HTML-обёрток, включая транзитивные зависимости (guard-тест по `pubspec.lock`). LaTeX — только `flutter_math_fork`.
- Ключи API — только `flutter_secure_storage` (контракт `ApiKeyStore`); вне кода, логов, БД, экспорта, git. В логах редактировать `Authorization`, `x-api-key`, `x-goog-api-key` (и query `key`/`api_key`) через `lib/api/http/log_redaction.dart`; **тела запросов/ответов генерации не логируются вообще** (материалы и ответ модели), перехватчик — только debug. Значения ключей не выводить в терминал; проверка — present/absent.
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
- Live-тесты API — под тегом `live`, только при наличии ключей в окружении (иначе skip).
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
  файлы — `file_picker 13.3.3`; реальный DnD-жест на ОС не проверялся (L33). CI-прогон 3c — после push.
- GitHub-remote: `origin` → `piotrcheban-pixel/cardflow` (private); CI — GitHub Actions (`.github/workflows/ci.yml`). Push выполняется по команде владельца (хука `confirm-git-push` нет).
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
  После них docs-only run `43589108294` (`490eb80`) не стартовал (GitHub billing/spending limit — внешний
  блокер владельца); код не выполнялся. Ограничения: L36 (таймер при покрытии маршрутом), L37 (реальные жесты).
- **Occlusion / Cloze / LaTeX проверены локально (итерация 5, 2026-11-14):** `fvm flutter test --coverage
  --exclude-tags golden` → **1020 passed + 1 skipped**; покрытие **93.1% (6468/6946)**; `analyze` 0;
  `dart format` 253 files 0 changed; `fvm flutter build windows --release` → `cardflow.exe` (56,2 с).
  Ревью Lead снимка `5af8f70` (L35), M1–M4 закрыты `0e4e11b` с тестами; L17 снят startup-GC, добавлены
  L38/L39. Схема БД/`format_version` не менялись, create → export → import покрыт интеграционным тестом.
  Локальные коммиты не запушены, CI итерации 5 не запускался; реальные picker/рисование — L11/L38.
