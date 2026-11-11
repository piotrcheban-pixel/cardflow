# STATE — текущее состояние CardFlow

**Дата:** 2026-11-11 · **Итерация:** 0 (Каркас) · **Шаг цикла:** 7 (улучшение/отчёт) · **Режим:** ИТЕРАЦИИ (после отчёта — стоп)
**Факты:** Flutter 3.47.9 stable / Dart 3.13.7 через FVM 4.3.2 (`.fvmrc`); Windows 11; VS Build Tools 2026 (без ATL); Android SDK/JDK, Xcode, Linux — отсутствуют; ключей API нет (absent).

## Следующее действие

Принять находки независимого ревью (`journal/iteration-0/review.md`), исправить blocker/critical/high, выполнить финальный прогон тестов/анализатора/покрытия, сделать checkpoint-коммит и отчёт владельцу — затем стоп.

## Сделано в итерации 0 (проверено в сессии)

- Репозиторий: `git init`, SPEC.md в корне, docs/agent-prompt.md (копия промпта 0–14), AGENTS.md, .gitignore, README.
- Тулчейн: Flutter 3.47.9 (sha256 сверен) + FVM 4.3.2; `.fvmrc`; junction `.fvm/versions/3.47.9`.
- `flutter create --org ru.example` под 5 платформ (android/ios/linux/macos/windows), 123 файла.
- Локализация ru: `lib/l10n/app_ru.arb`, gen-l10n, `supportedLocales: [ru]`, Material-база `material_ui` + русские системные строки (widget-тест).
- Домен FSRS: `Rating`, `CardState`, `SchedulingCard` (JSON), `FsrsMapper`, `Scheduler`/`FsrsScheduler` — 17 тестов (интервалы 4 оценок, маппинг, иммутабельность, сериализация). ADR-004 — конфигурация по умолчанию.
- UI: `CardFlowApp`/`HomeShell` (без мёртвых кнопок), `AppTheme` (ColorScheme.fromSeed), токены `AppMotion` (380/0.8, 700/0.9, effects 1.0), фасад `lib/ui/m3e/m3e.dart` + сверка с `M3EMotion`.
- Guard-тесты: no_webview (по lock/yaml/импортам + самопроверки), ru_strings (ARB + `Text(...)` литералы + самопроверки ICU), no_secrets (репозиторий + самопроверки) — 24 теста.
- CI-матрица `.github/workflows/ci.yml` (quality/test/build-desktop/build-mobile), YAML валиден; прогон невозможен — нет remote.
- Документы: docs/dependencies.md (+§7 фактическое состояние), ADR-001 (+addendum статуса), ADR-002, ADR-003, ADR-004, dependency-spike.md, plan/verify/summary.
- Доказательства: `journal/iteration-0/verify.md` — 58 тестов зелёные, analyze 0 issues, coverage 99.3%, формат применён; Windows-сборка CardFlow блокирована ATL (L2b), bare-проект собирается.

## Открытые вопросы / риски

- Нет вопросов, требующих решения владельца: все развилки закрыты ADR-001…004.
- Известные ограничения: `journal/KNOWN_LIMITATIONS.md` (L1–L8: ключи, платформы, ATL, CI, хуки, навыки, M3E-runtime, .doc/.xls, DnD).
- Следующая итерация 1 (Колоды + drift): завершить спайк S2 (`M3EMaterialApp` + M3E-экран), S3 (drift/sqlite3 native assets на Windows), добавить `drift_flutter`/открытие БД, CRUD колод, миграции, .zip импорт/экспорт.
