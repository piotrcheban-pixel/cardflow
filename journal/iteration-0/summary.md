# Итерация 0 — Итог (шаг 6: память)

**Дата:** 2026-11-11 · **Автономность:** ИТЕРАЦИИ · **Статус:** завершена; независимое ревью пройдено (blocker/critical/high = 0), находки M1–M6 и документарные low закрыты
**Цель по SPEC B2:** Flutter-проект (5 платформ), FVM, локализация ru, ADR по зависимостям и M3E, guard-тесты, CI-матрица, первый тест FSRS, минимальный Scheduler.

## Сделано

1. **Репозиторий и документы.** `git init` (`main`, 3 коммита), `SPEC.md` в корне (sha256 сверен с комплектом), `docs/agent-prompt.md` (копия стартового промпта 0–14), `docs/continue-prompt.md`, `AGENTS.md`, `README.md`, `.gitignore`.
2. **Тулчейн и FVM.** Flutter **3.47.9 stable / Dart 3.13.7** (официальный release JSON, sha256 zip сверен), распакован в кэш FVM; FVM **4.3.2** standalone; `.fvmrc`; `.fvm/versions/3.47.9` — junction (симлинки Windows без admin не создаются); `fvm flutter --version` проверен.
3. **Проект 5 платформ.** `flutter create --org ru.example --project-name cardflow --platforms=android,ios,linux,macos,windows .` — 123 файла; каталоги всех платформ закоммичены.
4. **Локализация ru.** `l10n.yaml`, `lib/l10n/app_ru.arb`, gen-l10n (сгенерированные файлы закоммичены, генерация идемпотентна), `supportedLocales: [ru]`, `locale: ru`; Material-база — `material_ui` 1.11.0 (ADR-001), системные строки Material/Cupertino — из её делегатов; widget-тест: «Отмена», «Вставить», «ОК».
5. **Домен FSRS.** `Rating` (Again/Hard/Good/Easy, 1..4), `CardState` (new/learning/review/relearning по SPEC A5), `SchedulingCard` (иммутабельный снимок, JSON для `cards.fsrs_json`, assert UTC), `FsrsMapper` (единственная точка связи с пакетом `fsrs` 2.0.1), `Scheduler`/`FsrsScheduler` (FSRS-6, 21 вес, `previewIntervals` для 4 кнопок, `review`). ADR-004 фиксирует конфигурацию по умолчанию (retention 0.9, шаги 1/10 мин, fuzzing off для детерминированного прогноза).
6. **UI-каркас.** `CardFlowApp` на `material_ui`, `HomeShell` (без мёртвых кнопок), `AppTheme` (`ColorScheme.fromSeed`, без сырых hex в виджетах), `AppMotion` (380/0.8, 700/0.9, effects 1600/1.0 — совпадает с M3E-токенами), фасад `lib/ui/m3e/m3e.dart` (единственная точка импорта M3E-библиотеки, ADR-001).
7. **Guard-тесты.** `no_webview` (pubspec.yaml + pubspec.lock + импорты в lib, включая транзитивные, + самопроверки), `ru_strings` (ARB + латиница вне allow-list + литералы в `Text(...)` в lib/ui + самопроверки ICU), `no_secrets` (скан репозитория + самопроверки фейковых ключей).
8. **CI-матрица.** `.github/workflows/ci.yml`: quality (формат, анализатор, gen-l10n), test (ubuntu/windows/macos, покрытие ≥80%), build-desktop (linux/windows/macos), build-mobile (android debug, ios --no-codesign); YAML валиден (pyyaml). Прогон невозможен — нет GitHub-remote (L3).
9. **Покрытие и качество.** 75 тестов зелёные (34 guard-теста, включая architecture); `flutter analyze` — 0 issues; `dart format` применён; покрытие рукописного `lib/` — **100% (135/135)**, вне подсчёта — только `lib/main.dart` (entrypoint) и export-only `lib/ui/m3e/m3e.dart`; `tool/coverage_check.dart` — CI-проверка порога.

## Доказательства (в `journal/iteration-0/verify.md`)

- Красная фаза: 4 тест-файла падали с «Error when reading 'lib/ui/app.dart'», EXIT 1 — до реализации.
- Зелёная: `fvm flutter test` → 75 passed; `fvm flutter analyze` → No issues found; `dart format` → 0 changed.
- Покрытие: `fvm dart run tool/coverage_check.dart --min=80` → 100% (135/135), ПОРОГ ПРОЙДЕН.
- Windows: `fvm flutter build windows --release` для CardFlow падает на `atlstr.h` (нет ATL-компонента VS Build Tools, нужен admin); bare Flutter-проект собирается (`√ Built ... probe.exe`) — ограничение хоста L2b, не кода.
- Ключи API: present = нет (значения не выводились).

## ADR итерации

- **ADR-001** — M3E: официальная база `material_ui` + ровно одна community-библиотека `material_3_expressive` за `lib/ui/m3e/`; добавлен раздел «Статус реализации» (миграция выполнена, M3E-виджеты — итерация 1).
- **ADR-002** — управление состоянием: Riverpod 3 без кодогенерации (зависимость добавлена; первые провайдеры — итерация 1).
- **ADR-003** — `.doc`/`.xls`: известное ограничение с русским сообщением; спайк `.xls` — итерация 3a.
- **ADR-004** — конфигурация FSRS в MVP: детерминированный прогноз (fuzzing off), retention 0.9, шаги 1/10 мин, эталонные 21 вес.

## Отступления и известные ограничения

- `desktop_drop` зафиксирован на 0.8.4 (конфликт `cross_file` с `file_picker` 13.3.3) — `docs/dependencies.md` §7, L8.
- `drift_flutter`, `enough_convert`, `sqlite3_flutter_libs` не добавлены (EOL/поздние итерации) — обосновано в §7.
- `M3EMaterialApp`/M3E-виджеты не используются до первого экрана — итерация 1 (L6b).
- L1–L8 в `journal/KNOWN_LIMITATIONS.md` (ключи, платформы, ATL, CI, хуки, навыки, golden, .doc/.xls, DnD).

## Независимое ревью

- `journal/iteration-0/review.md` (ревьюер-тиммейт, read-only): **blocker / critical / high = 0**, 6 medium и 12 low. Вердикт: готово к приёмке.
- Все medium закрыты до финального коммита: M1 (latin1-фолбэк в `no_secrets` + расширенные binary-расширения), M2 (`architecture_test.dart` — запрет framework-Material, изоляция M3E, domain без Flutter), M3 (тесты «прогноз == факт» для 4 оценок), M4 (CI без `--no-fatal-infos`), M5 (синхронизация `docs/dependencies.md` + строка `dynamic_color`), M6 (тесты маппинга состояний, переходов и UTC-нормализации).
- Документарные low L1/L2/L11/L12 исправлены; L9 (Android label/allowBackup), L10 (dynamic color в ограничениях), L5 (мёртвая ветка удалена, assert-only задокументирован), L6 (предупреждение о файлах вне lcov), L7/L8 (детекторы расширены) — исправлены; L3/L4 — принятые отклонения, зафиксированы.

## Что осталось до приёмки итерации 0

- Финальный checkpoint-коммит и отчёт владельцу — выполнено в этой сессии (коммит с `summary.md`, `review.md`, `verify.md`).

## Следующее действие

Итерация 1 («Колоды + БД»): завершить спайки S2 (`M3EMaterialApp` + M3E-экран) и S3 (drift/sqlite3 native assets на Windows), открытие БД, drift-схема и миграции по SPEC A5, CRUD колод, экран «Колоды» (поиск/фильтр/архив с undo), импорт/экспорт `.zip` без потерь.

## CI на GitHub Actions (пост-приёмка)

- Репозиторий: https://github.com/piotrcheban-pixel/cardflow (private). Первый прогон (`43083107525`) упал: guard `no_secrets` на Ubuntu/macOS (баг: исключения по сегментам абсолютного пути, а CI-путь `/home/runner/work/...` содержит `work`) и `build linux` (нет `libsecret-1-dev`). Исправлено в коммите `018f6f8` (регрессионный тест red→green, относительные пути в guard-обходе, `libsecret-1-dev`, шаг-аннотация деталей падения).
- Второй прогон (`43098651759`, commit `018f6f8`): **9/9 job'ов success** — `format + analyze`, тесты на ubuntu/windows/macOS, сборки linux/windows/macOS/android/ios.
- Итог: критерий «сборки под 5 ОС» теперь подтверждён CI, ограничение L3 (CI не запускался) снято.
