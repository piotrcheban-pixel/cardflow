# Итерация 0 — Верификация (шаг 5 цикла)

**Дата:** 2026-11-11 · **Среда:** Windows 11, Flutter 3.47.9 stable / Dart 3.13.7 (FVM 4.3.2), VS Build Tools 2026 18.9.2.
Все результаты ниже — вывод команд, выполненных в этой сессии в рабочем дереве `C:\Users\piotr\OneDrive\Desktop\CardFlow`.

## 1. Тулчейн

| Команда | Результат |
|---|---|
| `fvm --version` | `4.3.2` (standalone, `C:\Users\piotr\fvm`) |
| `fvm list` | `3.47.9 │ stable │ 3.47.9 │ 3.13.7 │ Oct 29, 2026` |
| `fvm flutter --version` | `Flutter 3.47.9 • channel stable • revision c197ca5199 • Dart 3.13.7 • DevTools 2.60.0` |
| `.fvmrc` | `{"flutter": "3.47.9"}`; `.fvm/versions/3.47.9` — junction на кэш FVM (симлинки FVM не создались: нет admin; junction создан вручную — версия резолвится, `fvm doctor` показывает Pinned Version 3.47.9) |
| `flutter create --org ru.example --project-name cardflow --platforms=android,ios,linux,macos,windows .` | exit 0, «Wrote 123 files», каталоги всех 5 платформ созданы |
| API-ключи в окружении | **absent** (OPENAI_API_KEY/GEMINI_API_KEY/GOOGLE_API_KEY/ANTHROPIC_API_KEY/API_KEY не заданы) — значения не выводились |

## 2. Красная фаза (шаг 2) — до реализации

```
fvm flutter test test/unit/domain/rating_test.dart test/unit/domain/fsrs_scheduler_test.dart \
  test/unit/ui/motion_test.dart test/widget/app_localization_test.dart
→ 00:00 +0 -4: Some tests failed.
  Error when reading 'lib/ui/app.dart': Не удается найти указанный файл
  Couldn't find constructor 'CardFlowApp'
  loading .../rating_test.dart [E] / fsrs_scheduler_test.dart [E] / motion_test.dart [E]
  EXIT test: 1
```
Причина падения — ожидаемая: тесты написаны до реализации (`lib/domain/scheduling/*`, `lib/ui/motion.dart`, `lib/ui/app.dart` отсутствовали).

> **Оговорка о типе красной фазы (найдено ревью, L3):** для новых модулей падение красной фазы — уровня компиляции (типы/файлы отсутствуют), assertion-level красный прогон до появления API невозможен. Для итераций 1+ красная фаза пишется на существующий код с проверкой поведения (assertion-level), это зафиксировано как процессное улучшение в `AGENTS.md`/журнале.

## 3. Зелёная фаза (шаг 3)

| Проверка | Команда | Результат |
|---|---|---|
| Полный прогон тестов | `fvm flutter test` | **75 passed**, 0 failed (EXIT 0) |
| Анализатор | `fvm flutter analyze` | **No issues found!** (ran in 11.2s), EXIT 0 |
| Форматирование | `fvm dart format .` | `Formatted 21 files (0 changed)` |
| Локализация | `fvm flutter gen-l10n` | EXIT 0, сгенерированы `lib/l10n/app_localizations.dart`, `app_localizations_ru.dart`; повторный `gen-l10n` идемпотентен (хеши не меняются), `dart format` на сгенерированных файлах — 0 изменений |
| pub get | `fvm flutter pub get` | `Got dependencies!`, EXIT 0 |
| Guard-тесты | `fvm flutter test test/guards` | 34 passed (architecture 6, no_webview 9, ru_strings 11, no_secrets 8) |
| Формат-детекторы guard-тестов | самопроверки внутри guard-файлов | ловят подставные нарушения (транзитивный `flutter_inappwebview_android`, английский текст, литерал в `Text(...)`, фейковый ключ) |

Состав тестов: домен FSRS (маппинг оценок/состояний, интервалы 4 оценок, совпадение прогноза с фактом, переходы learning/review/relearning, иммутабельность, сериализация, assert UTC, нормализация локального now→UTC, ошибки) — 30; motion/M3E-токены — 8; локализация — 3; guard-тесты (no_webview, ru_strings, no_secrets, architecture) — 34. Всего 75.

Найденный и исправленный в ходе verify дефект: guard `no_secrets` падал на бинарных артефактах сборки (`windows/flutter/ephemeral/*.dll.exp`, ошибка UTF-8). Исправлено: каталог `ephemeral` исключён, не декодирующиеся файлы пропускаются (с комментарием). Это доказывает, что guard-тест действительно работает на реальном дереве, а не только на синтетике.

## 4. Покрытие (шаг 5)

```
fvm flutter test --coverage
fvm dart run tool/coverage_check.dart --min=80
→ 94.4% fsrs_mapper.dart, 100% rating.dart, 100% scheduler.dart, 100% scheduling_card.dart,
  100% app.dart, 100% motion.dart, 100% app_theme.dart
→ Итого: 100.0% (135/135), порог 80.0% — ПОРОГ ПРОЙДЕН
```
Сгенерированные файлы (`app_localizations*.dart`, `*.g.dart`, `*.freezed.dart`) из подсчёта исключены. Инструмент предупреждает о рукописных файлах вне lcov: `lib/main.dart` (точка входа `runApp`, не исполняется тестами) и `lib/ui/m3e/m3e.dart` (только `export`) — в процент не входят, т.к. не содержат исполняемых строк.

## 5. Сборки и платформы

| Платформа | Команда | Результат |
|---|---|---|
| Windows (CardFlow) | `fvm flutter build windows --release` | **FAILED**: `flutter_secure_storage_windows_plugin.cpp(6,10): error C1083: Не удается открыть файл включение: atlstr.h` — в VS Build Tools 2026 не установлен компонент ATL (`vswhere -requires Microsoft.VisualStudio.Component.VC.ATL` → пусто; `atlmfc/include/atlstr.h` отсутствует). Это ограничение хоста: установка компонента требует прав администратора (KNOWN_LIMITATIONS L2b) |
| Windows (тулчейн-проба) | `flutter create` + `flutter build windows --release` во временном bare-проекте | **exit 0**, `√ Built build\windows\x64\runner\Release\probe.exe` — MSVC-тулчейн и Developer Mode работают; блокирует только ATL у плагина secure storage |
| Android / iOS / macOS / Linux | — | **не проверено**: на хосте нет Android SDK/JDK, Xcode, Linux; сборки — в CI-матрице (не запущена: нет git-remote) |
| iOS без подписи | CI `flutter build ios --release --no-codesign` (macOS-раннер) | файл CI создан; прогон не выполнялся (L3) |

## 6. CI

```
python -c "yaml.safe_load('.github/workflows/ci.yml')" → jobs: quality, test, build-desktop, build-mobile; CI_YAML_OK
```
Матрица: `ubuntu/windows/macos` для тестов, desktop-сборки (linux/windows/macos), mobile (android debug / ios --no-codesign), coverage-порог через `tool/coverage_check.dart`, формат и анализатор в job `quality`. Фактический прогон невозможен — GitHub-remote отсутствует (L3).

## 7. Хуки (smoke-тест)

В конфигурации DSH-профиля хуки `block-hardcoded-secret`, `block-destructive-command`, `confirm-git-push`, GateGuard **не подключены** (проверено `~/.dsh/profiles/desktop/cordis.patch.yml` и отсутствие хуков в профиле). Smoke-тест невозможен; обход/создание хуков не выполнялись (запрещено). Известное ограничение L4.

## 8. Статус критериев приёмки итерации 0

| # | Критерий (README/SPEC B6) | Статус | Доказательство |
|---|---|---|---|
| 1 | `flutter --version` зафиксирована, FVM настроен | **выполнено** | §1: FVM 4.3.2, `.fvmrc`, `fvm flutter --version` = 3.47.9/3.13.7 |
| 2 | Проект под 5 платформ | **выполнено** | каталоги `android/ ios/ linux/ macos/ windows/` созданы и закоммичены |
| 3 | `SPEC.md` и `docs/agent-prompt.md` на месте | **выполнено** | `SPEC.md` в корне (sha256 = `work/SPEC.md`), `docs/agent-prompt.md` — копия разделов 0–14 |
| 4 | `docs/dependencies.md` + ADR-001/002/003 | **выполнено** | файлы на месте; ADR-004 (FSRS defaults) добавлен; `docs/dependencies.md` §7 — фактическое состояние |
| 5 | Локализация `ru`: ARB, `supportedLocales: [ru]`, `flutter_localizations` | **выполнено** | `lib/l10n/app_ru.arb`, gen-l10n, widget-тест: локаль `ru`, «Отмена»/«Вставить»/«ОК» из material_ui |
| 6 | Guard-тесты зелёные (WebView, ru-строки, секреты) | **выполнено** | `fvm flutter test test/guards` — 34 passed; дополнительно `architecture_test.dart` (запрет framework-Material, M3E только в lib/ui/m3e/, domain без Flutter) |
| 7 | CI-матрица ubuntu + windows + macos | **выполнено (файл), запуск не проверен** | `ci.yml` валиден (pyyaml), 4 job'а; прогон — L3 |
| 8 | Первый тест FSRS: красный → зелёный, `Scheduler`-адаптер | **выполнено** | §2 (красный: EXIT 1, нет `lib/`), §3 (75 passed); `lib/domain/scheduling/scheduler.dart` |
| 9 | `STATE.md` заполнен, checkpoint-коммит, отчёт | **выполнено** | `journal/STATE.md`; коммиты `20698fe`, `ba4f37a` (+ финальный); отчёт владельцу |
| 10 | `flutter analyze` 0 issues, `dart format`, тесты, покрытие ≥80% | **выполнено** | §3, §4 (100%) |
| 11 | M3E-слой `lib/ui/m3e/` + токены движения | **частично** | фасад и сверка токенов M3E↔SPEC есть (тест); M3E-виджеты и `M3EMaterialApp` — итерация 1 (спайк S2) |
| 12 | Сборки под доступные платформы | **частично** | Windows: тулчейн подтверждён bare-проектом, сборка CardFlow блокирована ATL (L2b); остальное — CI/не проверено |
| 13 | Хуки smoke-тест | **не проверено** | хуки не подключены (L4) |

> **Пометка (L12 ревью):** задачи плана 0.3/0.5/0.7 (проект/FVM, AGENTS.md, CI) закрыты файлами и командами, а не тестами — это конфигурационные артефакты; их проверка — команды из §1/§6 и статический разбор CI, что указано в таблице.

## 9. Не проверено и почему (см. `journal/KNOWN_LIMITATIONS.md`)

L1 — нет ключей API (живые вызовы не проверялись; важно для итераций 3b/3c).
L2 — нет Android SDK/JDK, Xcode, Linux: сборки этих платформ локально не выполнялись.
L2b — Windows-сборка CardFlow блокирована отсутствием ATL в VS Build Tools (нужны права администратора; CI windows-раннер содержит ATL).
L3 — CI не запускался (нет GitHub-remote).
L4 — хуки DSH не подключены, smoke-тест невозможен.
L5 — навыки Flutter из промпта отсутствуют в каталоге DSH.
L6 — golden-тестов в итерации 0 нет (по плану — с первыми экранами; тогда Linux CI + явный шрифт).
L6c — dynamic color (A4.1) ещё не подключён в UI (пакет `dynamic_color` добавлен; настройка — итерация 7).
L10 — `desktop_drop` 0.8.4 вместо 0.9.2 (конфликт `cross_file`), см. `docs/dependencies.md` §7.


## 10. Пост-приёмка: исправление CI на GitHub Actions (2026-11-11, 23:20–00:05 MSK)

Владелец создал репозиторий https://github.com/piotrcheban-pixel/cardflow (private) и запушил `main`. Первый прогон CI (run `43083107525`, commit `78c99be`) упал в 3 job'ах из 9:

| Job | Ошибка | Причина | Исправление |
|---|---|---|---|
| `test (ubuntu-latest)`, `test (macos-latest)` | `74 tests passed, 1 failed` — `no_secrets` (скан репозитория) | **Баг guard-теста:** исключения каталогов проверялись по сегментам **абсолютного** пути. На раннерах GitHub Actions репозиторий лежит в `/home/runner/work/<repo>/<repo>` (macOS: `/Users/runner/work/...`), т.е. абсолютный путь содержит сегмент `work` из `excludedScanDirs` → отфильтровывались **все** файлы → `expect(files, isNotEmpty)` падал. На Windows-раннере путь `D:\a\cardflow\cardflow` без `work` — job `test (windows-latest)` прошёл | `scannableFiles`: обход с исключением каталогов **по имени при рекурсивном обходе** (относительно корня проекта), а не по сегментам абсолютного пути. Тот же латентный дефект исправлен в `guard_utils.repoFiles` (architecture/no_webview/ru_strings) |
| `build linux` | `CMake: libsecret-1>=0.18.4 not found` (`flutter_secure_storage_linux`) | в CI-шаге установки Linux-зависимостей не было `libsecret-1-dev` | добавлен `libsecret-1-dev` в `apt-get install` |

**TDD-фиксация бага:** сначала написан регрессионный тест «корень проекта внутри каталога `work` не скрывает файлы (регрессия CI)» — красный (`Actual: Set: []`), затем реализовано исправление — зелёный. Тестов теперь **76**.

Дополнительно в CI добавлен шаг «Детали падения тестов (аннотация)»: при падении тестов хвост вывода публикуется как `::error`-аннотация check-run — причина видна через GitHub API/UI без полного лога (в первом прогоне лог падения приходилось восстанавливать по `check-runs`, т.к. endpoint `/jobs` отдавал 502).

**Локальные доказательства после фикса:** `fvm flutter test --no-pub --coverage` → **76 passed**; `fvm flutter analyze --no-pub` → No issues found; `dart format` → 0 changed; покрытие рукописного `lib/` → **100% (135/135)**; CI YAML валиден (4 job'а).
