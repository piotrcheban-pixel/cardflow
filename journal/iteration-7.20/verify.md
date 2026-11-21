# Verify 7.20 — гейты CardFlow

**Дата:** 2026-11-21 · **Снимок:** `6bf7889` + docs (ADR-043, planning, L194–L196)
**Живых API-запросов нет.** Все прогоны — локально на Windows, `--no-pub`.

## 1. Генерация локализаций

```
fvm flutter gen-l10n
```

без изменений (`git status --porcelain` пуст после генерации): ARB и
сгенерированные `app_localizations*.dart` согласованы.

## 2. Формат

```
fvm dart format lib test integration_test
```

— применён; проверка расхождений:

```
fvm dart format --set-exit-if-changed lib test integration_test
```

(результат — в §7 после последнего docs-коммита).

## 3. Анализатор

```
fvm flutter analyze --no-pub
→ No issues found!
```

## 4. Полный набор тестов

```
fvm flutter test --no-pub --exclude-tags golden
```

→ **2532 passed + 16 skipped + 0 failed** (лог: `full-run-1.txt`; прогон до
fix-коммита ревью).

```
fvm flutter test --no-pub --coverage --exclude-tags golden
```

→ **2534 passed + 16 skipped + 0 failed** (лог: `coverage-run.txt`; финальный
снимок с тестами ревью R1/R2 — +2 теста).

## 5. Покрытие рукописного кода

```
fvm dart run tool/coverage_check.dart --min=80
→ Итого: 91.5% (20294/22174), порог 80.0%
→ ПОРОГ ПРОЙДЕН
```

## 6. Сборка Windows Release

```
fvm flutter build windows --release --no-pub
```

→ `build\windows\x64\runner\Release\cardflow.exe` (лог: `windows-build.txt`).

## 7. Windows Smoke Test

```
fvm flutter test integration_test/session_smoke_windows_test.dart -d windows
```

→ `All tests passed!` (лог: `windows-smoke.txt`).

## 8. Живые API

Не выполнялись (запрет задания): ни одного платного/сетевого запроса; все
проверки — на fake-вызове модели и локальном плане.

## 9. Финальный CI

Push `0d3c35b..02bf726` → run
[`44936474031`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44936474031)
(`02bf726`) — **9/9 job success**: `format + analyze (ubuntu)`,
`test` × 3 ОС (ubuntu/windows/macos), `build desktop` × 3 (windows/linux/macos),
`build mobile` Android + iOS. Живых API-запросов в CI нет (live-тесты под
тегом `live` и opt-in).
