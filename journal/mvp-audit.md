# Финальный аудит MVP — критерии остановки (docs/agent-prompt.md §9)

**Дата:** 2026-11-14 · **Ветка:** `main` · **Снимок аудита:** `d1c55fa` + локальные коммиты закрытия L45
(`1f3d152`, `043e4c8`, `c289ada`) · **Аудитор:** Lead (независимый reviewer недоступен — **L35**)

Проверка выполнена **командами в этой сессии**; ниже — вывод и ссылки. Ничего не заявлено «выполнено»
без команды или без файла-доказательства.

## Доказательная база (прогоны этой сессии)

| Что | Команда / источник | Результат |
|---|---|---|
| Полный прогон тестов | `fvm flutter test --coverage --exclude-tags golden` | **1203 passed + 1 skipped** (`All tests passed!`); skip — live-тест DeepSeek без ключа в env (тег `live`) |
| Покрытие рукописного кода | `fvm dart run tool/coverage_check.dart --min=80` | **92.6 % (8368/9038)**, порог 80 % пройден (`ПОРОГ ПРОЙДЕН`) |
| Анализатор | `fvm flutter analyze` | **No issues found!** |
| Формат | `fvm dart format --set-exit-if-changed lib test` | 305 файлов, **0 changed** |
| CI на запушенном снимке | run [`43623897449`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43623897449) (`d1c55fa`) | **9/9 job success**: `format + analyze`, `test` × ubuntu/windows/macos, `build` linux/windows/macos/android/ios |

## Сводная таблица

| # | Критерий (промпт §9) | Статус | Доказательство | Ограничение |
|---|---|---|---|---|
| 1 | **Локализация:** guard `ru_strings` зелёный, ни одного английского текста в UI, локаль ru | **выполнено** | `test/guards/ru_strings_test.dart` в полном прогоне: ARB-строки без латиницы вне allow-list, `@@locale: ru`, и — главное — **все** файлы `lib/ui` проверены на строковые литералы в `Text`/`SelectableText`/`Text.rich` (ни один не найден); `supportedLocales = <Locale>[Locale('ru')]` (`lib/l10n/app_localizations.dart:95`), `locale: const Locale('ru')` (`lib/ui/app.dart:26,115`); дополнительно в этой сессии поиском проверено, что литералов нет в `tooltip`/`semanticsLabel`/`label`/`hintText`/`helperText`/`title` | скриншот-прогон экранов как отдельная процедура не проводился — вместо него статическая проверка строже (запрещает любой литерал, а не находит его на снимке); ручная приёмка — **L42** |
| 2 | **Функциональность:** классика, лента, occlusion, cloze/LaTeX, конструктор — приёмочные тесты; все кнопки SPEC имеют обработчик или скрыты | **выполнено** | Классика — `test/widget/review/review_session_screen_test.dart`, `test/unit/ui/review_session_engine_test.dart`, `test/integration/review_session_flow_test.dart`; лента — `feed_session_screen_test`, `feed_session_engine_test`, `feed_swipe_test`, `feed_progress_bar_test`, `test/integration/feed_session_flow_test.dart`; occlusion/cloze/LaTeX — `occlusion_editor_test`, `card_content_test`, `card_markup_session_test`, `card_markup_form_test` + домен `occlusion_test`, `cloze_markup_test`, `latex_markup_test`; конструктор — `session_constructor_screen_test`, `session_builder_test`, `session_config_test`, `test/integration/session_constructor_flow_test.dart`. Мёртвые кнопки: поиск `onPressed: null`/`onTap: null`/`TODO`/`FIXME` в `lib/ui` → **0 совпадений** | реальные жесты DnD/свайпа/рисования масок на ОС не проверялись — **L11/L33/L37/L38/L42** |
| 3 | **Генерация:** форматы A8.3 (или ADR-003), скрытый промпт, строгая схема, 3 провайдера, ключи в secure storage, retry/backoff, отмена, предпросмотр, дедуп; непроверенное живьём — в KNOWN_LIMITATIONS | **выполнено** | Парсеры — `test/unit/api/parsers/` (9 файлов, программные фикстуры DOCX/PPTX/ODT/XLSX/PDF/RTF/кодировки) + `test/guards/ci_pdfium_test.dart`; `.doc/.xls` не поддерживаются по **ADR-003**; канон-схема и проекции — `test/unit/generation/` (14 файлов), провайдеры — `test/unit/providers/` (3), HTTP/retry/redaction — `test/unit/http/` (3); скрытый промпт — `lib/api/generation/system_prompt.dart` (версия `gen-ru-v2`, вне UI/ARB); ключи — `ApiKeyStore`/`SecureApiKeyStore` (`flutter_secure_storage`), guard `no_secrets` зелёный; отмена/предпросмотр/дедуп — `test/integration/generation_flow_test.dart`, `generation_pipeline_test.dart` | живьём проверен только DeepSeek (`deepseek-chat`, 1 live-тест пройден, **L30**); OpenAI/Gemini/Anthropic — нет ключей (**L1**); негативные live-контракты (401/403/429/`Retry-After`) осознанно не проверяются — **ADR-014**; Ollama/LM Studio — **L32** |
| 4 | **Нативность:** guard `no_webview` зелёный; сборки под 5 ОС; LaTeX через `flutter_math_fork`; парсинг только Dart-пакетами | **выполнено** | `test/guards/no_webview_test.dart` (проверяет `pubspec.lock`, включая транзитивные) в полном прогоне; CI-сборки: `build linux`, `build windows`, `build macos`, `build android`, `build ios` — все **success** в run [`43623897449`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43623897449); `flutter_math_fork` — единственный LaTeX-рендерер (`pubspec.yaml`), WebView/HTML-пакетов нет; парсинг — `pdfrx`, `archive`, `excel_plus`, `xml`, `enough_convert` (Dart) | локальная сборка не-Windows платформ на этом хосте недоступна — **L2** (покрыто CI) |
| 5 | **Данные:** схема соответствует SPEC с правками; миграции протестированы; экспорт/импорт `.zip` без потерь; FSRS проходит тесты интервалов и маппинга | **выполнено** | `test/migrations/migration_test.dart`: dump v1 == `schemaVersion` приложения, «10 таблиц и 3 индекса SPEC A5»; `drift_schemas/drift_schema_v1.json`; `test/integration/deck_zip_roundtrip_test.dart` (медиа без потерь, occlusion create→export→import, дубликаты по `content_hash`), `deck_archive_test`; FSRS — `test/unit/domain/fsrs_scheduler_test.dart` (интервалы), `card_scheduling_test.dart` (маппинг), `rating_test.dart`; схема не менялась в итерациях 5–7, закрытие L45 тоже без миграции (ADR-019 §8) | — |
| 6 | **Дизайн:** все экраны на токенах темы; пружины в hero-моментах; dynamic color; haptics по A7.2 | **выполнено** | Токены: поиск `Color(0x…`/`Colors.*` в `lib/ui` вне `lib/ui/theme/` → **0 совпадений** (единственный сырой цвет — `AppTheme.seedColor`); токены движения зафиксированы в `docs/m3e-tokens.md` и проверены `test/unit/ui/m3e_tokens_test.dart` + `motion_test.dart` (значения `AppMotion` совпадают с `M3EMotion`: 380/0.8, 700/0.9, 1600/1.0); пружины в hero-моментах — `review_card_view`, `feed_card_view` (`AppMotion.standardSpring()` при «Стандартной» анимации, A6.6); dynamic color — `DynamicColorBuilder` в `lib/ui/app.dart`, `app_theme_test` + `app_settings_applied_test`; haptics по A7.2 — `reviewHapticFor` + `test/unit/ui/review_haptics_test.dart` | рендер на реальных ОС/экранах (dynamic color, OpenDyslexic, масштаб, контраст) не наблюдался — **L6c/L43**; golden-тестов нет (каталог `test/golden/` пуст) — **L6** |
| 7 | **Качество:** покрытие ≥ 80 %, `flutter analyze` чистый, security-review без high/critical, code review без blocker | **выполнено** | Покрытие **92.6 %** (`tool/coverage_check.dart`, сгенерированное исключено); `analyze` — No issues; security-review — `journal/iteration-3b/review.md` §6 (утечек не найдено: ключ только из `ApiKeyStore`, Gemini-ключ только в заголовке, тела не логируются, `allowBackup="false"`) и `journal/iteration-7/review.md` §Безопасность; code review — `journal/iteration-7/review.md`: blocker/critical/high нет, M1–M2 закрыты fix-коммитом с тестами, M3 (L45) закрыт в этой сессии | независимый reviewer недоступен, ревью Lead на неизменяемых снимках — **L35** |
| 8 | **Документация:** `AGENTS.md`, журнал итераций, `docs/{api-schema,system-prompt,m3e-tokens,parsers,dependencies}.md`, ADR | **выполнено** (после закрытия пробела) | `AGENTS.md` — архитектура/команды/запреты/факты хоста; `journal/iteration-0…7` (plan/green/review/verify/summary/improve) + `journal/STATE.md`, `journal/KNOWN_LIMITATIONS.md`, `journal/mvp-audit.md`; `docs/`: `api-schema.md`, `system-prompt.md`, `m3e-tokens.md`, `parsers.md`, `dependencies.md`, `archive-format.md`, `generation-pipeline.md`, `openai-compatible.md`, `privacy.md`, `agent-prompt.md`; ADR-001…ADR-019 | **пробел, найденный аудитом и закрытый в этой же сессии:** `docs/m3e-tokens.md` отсутствовал (требуется SPEC B4 и промптом §11) — создан как документация (не фича) |

## Итог

- Все 8 критериев — **«выполнено»**. «Частично/не проверено» в таблице нет; остаточные риски вынесены
  в ограничения и не являются невыполненными требованиями MVP:
  - внешние/непроверяемые на хосте: **L1** (ключи OpenAI/Gemini/Anthropic), **L2** (локальные сборки
    не-Windows), **L30** (негативные live-контракты — ADR-014), **L32** (Ollama/LM Studio);
  - ручная приёмка на реальных ОС/устройствах: **L6c/L42/L43** (dynamic color, OpenDyslexic, размеры),
    **L11/L33/L37/L38** (реальные picker/DnD/свайпы/рисование масок);
  - доступность: **L12/L39/L46** (screen-reader, отдельные дни тепловой карты);
  - производительность на больших БД: **L44**;
  - процесс: **L35** (независимый reviewer).
- **Закрыто долгов итерации 7:** **L45** (дневные лимиты A6.6 по календарному дню, ADR-019 §8) —
  интеграционный тест на реальной drift-БД и production-графе.
- Найден и закрыт пробел документации: `docs/m3e-tokens.md`.
- Незакрытых дефектов blocker/critical/high нет; открытых «L»-блокеров MVP нет.

**Вывод аудита:** MVP соответствует критериям остановки §9 по проверяемым в текущем окружении пунктам;
релиз возможен по отдельной команде владельца. Работа остановлена — Post-MVP (итерация 8) не начиналась.
