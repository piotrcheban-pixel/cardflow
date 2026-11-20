# Верификация итерации 7.18 (снимок для гейтов)

**Снимок:** `ddc0946` (fix-коммит R1/R2) + документация этой фазы.
**Дата:** 2026-11-20/21 · **Ветка:** `main` · **Живые API-запросы:** не
выполнялись (запрет задания §0; discovery/counter проверены mock-HTTP и
фикстурами).

## Гейты

| Гейт | Команда | Результат |
|---|---|---|
| Тесты (полный набор, без golden) | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2256 passed + 16 skipped + 0 failed** (3:26; сводка `verify-full.log`) |
| Анализатор | `fvm flutter analyze --no-pub` | **No issues found** (6,1 с) |
| Формат | `fvm dart format --set-exit-if-changed lib test integration_test` | **533 files, 0 changed** |
| Покрытие рукописного кода | `fvm dart run tool/coverage_check.dart` | **91.7 % (18905/20608)**, порог 80 % пройден |
| Guard-тесты | в полном прогоне | `ru_strings`, `no_webview`, `no_secrets`, `architecture` — зелёные |
| Сборка Windows | `fvm flutter build windows --release --no-pub` | **√ Built build\windows\x64\runner\Release\cardflow.exe** (70,9 с) |
| Baseline до изменений | `fvm flutter test --no-pub --exclude-tags golden` | 2193 passed + 16 skipped (`baseline-test.txt`); итог +63 теста, 0 ослаблений |`n| CI после push | GitHub Actions run [44819862886](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44819862886) | **9/9 job success** (`format + analyze`, `test` ×3 ОС, `build` linux/windows/macos/android/ios), run completed success |

## Инварианты

- Схема БД и `schemaVersion` **не менялись**: кэш характеристик и калибровка —
  JSON v1 в `app_settings` (`generation.model_capabilities`,
  `generation.calibration`).
- Ключи API — только `ApiKeyStore`; discovery/refresh не логируют тела и ключи;
  `no_secrets`-guard зелёный.
- `SPEC.md` не редактировался; промпты v5–v7 сохранены (байтовые тесты), новый —
  `gen-ru-v8`.
- Один `GenerationPlan` и один builder сообщения на предпросмотр и production;
  планировщик не ходит в сеть.

## Что проверено выборочно

- Границы T9: `D=53363` → whole (input 62000/maxTokens 2000), `D=53364` →
  fragmented; inputOnly: input 113300/maxTokens 5530, партии 15×2+14×5;
  unknown context: 4 части по 5000 с `contextUnconfirmed`.
- Независимость: заказ 1/10/100/500 не меняет стратегию и части входа при том
  же материале (`planning_independence_test.dart`).
- Префикс сообщения (включая изображения) одинаков между партиями; display-id
  `img1…` стабильны (fix `ddc0946`).
- Исчерпание: `source_exhausted`/недобор < 50 % → focus сокращается, полностью
  исчерпанные партии не отправляются, одна доп. партия перераспределения.
- Калибровка: один агрегированный замер на прогон, EMA после ≥2 замеров,
  применяется в следующем плане; `generation_jobs.chunk_count` = число частей.

## Ограничения (не блокируют приёмку)

L154–L161 в `journal/KNOWN_LIMITATIONS.md`: неполная сверка документации
discovery, `supports_vision` legacy, нативный подсчёт не подключён к конвейеру,
UI характеристик только у активного аккаунта, prompt-only legacy-планировщик,
recovery без явного ×0.8, нет «Подробнее» со стратегией в предпросмотре.
