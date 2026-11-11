# Итерация 0 — Каркас. План

**Дата:** 2026-11-11 · **Автономность:** `ИТЕРАЦИИ` · **org_id:** `ru.example`
**Цель итерации (SPEC B2):** Flutter-проект под 5 платформ, FVM, локализация `ru`, ADR по зависимостям и M3E, guard-тесты, CI-матрица, первый тест FSRS, минимальный `Scheduler`.

## 0. Факты о текущем состоянии (предъявлены перед первой правкой)

Рабочее дерево на момент старта:
- `C:\Users\piotr\OneDrive\Desktop\CardFlow` содержал только папку `work/` (комплект: `SPEC.md`, `START-PROMPT.md`, `CONTINUE-PROMPT.md`, `README.md`). Git-репозитория не было.
- `SPEC.md` в корне отсутствовал → скопирован из `work/SPEC.md` (итерация 0, шаг 0).
- `docs/agent-prompt.md` создан из `work/START-PROMPT.md` (разделы 0–14).
- Инициализирован git (`main`), локальные user.name/user.email заданы (глобального gitconfig на хосте нет).

Тулчейн (проверено `Get-Command`/`vswhere`/`winget list`):
- **Flutter/Dart/FVM — отсутствовали.** Установлены в итерации 0: Flutter **3.47.9 stable** (Dart **3.13.7**, релиз 2026-10-29, sha256 сверен) → FVM.
- git 2.55.0, node есть, pnpm есть, curl/tar есть. Visual Studio Build Tools 2026 (VC tools) — есть.
- Android SDK/JDK — **нет** → сборка Android локально недоступна.
- Xcode/macOS/Linux — **нет** → iOS/macOS/Linux сборки локально недоступны.
- Windows desktop: предположительно возможен (VS Build Tools 2026); проверяется в шаге 5.

Хуки/навыки:
- В конфигурации DSH (`~/.dsh/profiles/desktop`) хуки `block-hardcoded-secret`, `block-destructive-command`, `confirm-git-push`, GateGuard **не подключены** → smoke-тест хуков невозможен, фиксируется как известное ограничение (хуки не отключаем и не создаём себе сами).
- Навыки `tdd-workflow`, `dart-flutter-patterns`, `flutter-dart-code-review`, `material-3-skill`, `api-design`, `security-review`, `verification-loop`, `coding-standards` в каталоге сессии **отсутствуют** → работаем по правилам `docs/agent-prompt.md`, отсутствие фиксируется в `STATE.md`.
- API-ключей в окружении нет (present: нет) → live-тесты API не запускаются, генерация проверяется моками.

## 1. Задачи итерации, файлы, проверка

| # | Задача | Файлы | Проверка |
|---|---|---|---|
| 0.1 | Спайк зависимостей, ADR-001 (M3E), ADR-002 (state mgmt), ADR-003 (.doc/.xls) | `docs/dependencies.md`, `docs/decisions/ADR-00*.md`, `journal/iteration-0/dependency-spike.md` | все пакеты существуют на pub.dev, версии/лицензии/платформы указаны, вердикты |
| 0.2 | Сохранить промпт | `docs/agent-prompt.md` | файл совпадает по содержанию с `work/START-PROMPT.md` (разделы 0–14) |
| 0.3 | Flutter 3.47.9 + FVM, `flutter create` 5 платформ, `--org ru.example` | `pubspec.yaml`, `pubspec.lock`, `android/ ios/ linux/ macos/ windows/`, `.fvmrc`, `analysis_options.yaml` | `fvm flutter --version`, `fvm flutter analyze` = 0 issues, все 5 каталогов платформ |
| 0.4 | Локализация `ru` через gen-l10n, `flutter_localizations`, `supportedLocales: [Locale('ru')]` | `l10n.yaml`, `lib/l10n/app_ru.arb`, `lib/l10n/app_localizations*.dart` (ген.), `lib/main.dart` | тест: `Localizations` отдаёт русские системные строки, `supportedLocales == [ru]` |
| 0.5 | `AGENTS.md` — устойчивые правила | `AGENTS.md` | файл ≤ ~80 строк, покрывает TDD/секреты/архитектуру/русский UI |
| 0.6 | Guard-тесты: no_webview (pubspec.lock+pubspec.yaml, включая транзитивные), ru_strings, no_secrets | `test/guards/*.dart` | тесты зелёные; no_webview проверен на подставленном фейковом lock (smoke в самом тесте) |
| 0.7 | CI-матрица ubuntu/windows/macos + iOS/macOS сборка без подписи | `.github/workflows/ci.yml` | YAML валиден (разбор в тесте/локально), remote отсутствует → запуск в CI не проверен (KNOWN_LIMITATIONS) |
| 0.8 | Первый падающий тест: маппинг Again/Hard/Good/Easy → FSRS + минимальный `Scheduler` | `test/unit/domain/scheduler_rating_test.dart`, `lib/domain/...` | красный прогон зафиксирован до реализации; затем зелёный |
| 0.9 | Каркас архитектуры `lib/{domain,data,api,ui}` (+ `lib/ui/m3e/`, `lib/ui/motion.dart` — токены движения) | файлы-заглушки без мёртвого UI | `flutter analyze` чистый; нет WebView; нет литералов в UI |
| 0.10 | Покрытие ≥80% рукописного кода | `coverage/lcov.info` | `fvm flutter test --coverage` + расчёт по рукописным файлам |
| 0.11 | Журнал, ADR, известные ограничения, verify/review/summary, checkpoint-коммит | `journal/STATE.md`, `KNOWN_LIMITATIONS.md`, `journal/iteration-0/*`, коммит | артефакты существуют, доказательства в журнале — только реальные команды этой сессии |

## 2. Критерии приёмки итерации 0 (из README/SPEC B6)

- [ ] `flutter --version` зафиксирована, FVM настроен (`.fvmrc`, `docs/dependencies.md`).
- [ ] Проект создан под 5 платформ (android, ios, linux, macos, windows).
- [ ] `SPEC.md` и `docs/agent-prompt.md` на месте.
- [ ] `docs/dependencies.md` + ADR-001 (M3E), ADR-002 (state management), ADR-003 (.doc/.xls).
- [ ] Локализация `ru`: `app_ru.arb`, `supportedLocales: [ru]`, `flutter_localizations` подключён.
- [ ] Guard-тесты зелёные: нет WebView, русские строки, нет секретов.
- [ ] CI-матрица: ubuntu + windows + macos (файл; запуск — ограничение).
- [ ] Первый тест FSRS: красный → зелёный, `Scheduler`-адаптер существует.
- [ ] `journal/STATE.md` заполнен, checkpoint-коммит создан, отчёт с доказательствами предъявлен.
- [ ] `flutter analyze` — 0 issues; `dart format` применён; полный прогон тестов зелёный; покрытие ≥80%.

## 3. Риски

1. **Нет интернета/медленная сеть при установке SDK** → скачивание 1.8 ГБ уже идёт; при сбое — повтор с `curl --retry`, sha256-проверка.
2. **FVM + Windows-симлинки** → создать `.fvmrc` + `.fvm/flutter_sdk` junction/symlink; при неудаче — `fvm use --force`, зафиксировать версию в `docs/dependencies.md` и `STATE.md`.
3. **M3E-пакет может быть мёртвым/несовместимым** → официальные компоненты Flutter 3.47 принимаются как база, community-библиотека изолируется за `lib/ui/m3e/`; решение в ADR-001.
4. **`fsrs` API может отличаться от ожидаемого** → спайк исходников пакета до реализации; адаптер пишется по фактическому API, тест — по поведению (маппинг и интервалы), не по внутренностям.
5. **`flutter_math_fork` на Flutter 3.47** → проверить `pub get`; при несовместимости — спайк с `dependency_overrides`, иначе ADR/известное ограничение.
6. **Windows-сборка без Android SDK** → локально проверяем `flutter test`, `flutter analyze`, `flutter build windows` (если VS-тулчейн полноценный); остальное — CI/известное ограничение.
7. **Кириллица в golden-тестах** → в итерации 0 golden-тестов нет; при появлении — явный шрифт с кириллицей (OFL), тег `golden`.
8. **OneDrive-синхронизация рабочего дерева** → `.dart_tool/`, `build/` в `.gitignore`; возможные блокировки файлов при сборке фиксируем фактом.

## 4. Порядок исполнения

1. Спайк зависимостей (параллельно: deps-researcher) → ADR.
2. Установка Flutter 3.47.9 → FVM → `flutter create`.
3. Локализация ru + каркас `lib/` + `ui/m3e` изоляция.
4. Guard-тесты (красный→зелёный по TDD там, где применимо).
5. FSRS: красный тест маппинга → минимальный `Scheduler`.
6. CI, coverage, `flutter analyze`, формат.
7. verify.md, review.md, summary.md, STATE.md, KNOWN_LIMITATIONS.md, checkpoint-коммит.
8. Отчёт владельцу, стоп.
