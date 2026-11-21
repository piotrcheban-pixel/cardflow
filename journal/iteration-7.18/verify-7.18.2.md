# Итерация 7.18.2 — ворота качества (§6)

**Дата:** 2026-11-21. **HEAD на момент прогонов:** `4642bf1` (+ правка
`generation_payload_bytes_test.dart` перед финальным прогоном, см. ниже).
Окружение: Windows 11, FVM 4.3.2, Flutter 3.47.9 (Dart 3.13.7).

## Baseline (до правок)

```
fvm flutter test --no-pub --exclude-tags golden
→ 03:51 +2302 ~16: All tests passed!   (exit 0)
```
Лог: `journal/iteration-7.18/baseline-7.18.2.log`.

## Красная фаза

`journal/iteration-7.18/red-7.18.2.log` — 30 passed · 15 failed, все падения
уровня assertion (ожидаемое/фактическое). Разбор: `red-7.18.2.md`.

## Финальные ворота

| Команда | Результат |
|---|---|
| `fvm flutter gen-l10n` | ок (обновлены `settingsCapabilitiesImageInput*`, `generationPlanDetailsCatalogTokens`, `generationPlanDetailsReasoningReserve`) |
| `fvm dart format lib test integration_test` | `Formatted 546 files (1 changed)` (финальный проход) |
| `fvm dart format --set-exit-if-changed lib test integration_test` | `Formatted 546 files (0 changed)` |
| `fvm flutter analyze --no-pub` | `No issues found!` (после последней правки тестов) |
| `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2340 passed + 16 skipped, 0 failed** (exit 0; baseline 2302+16, +38 тестов) |
| `fvm dart run tool/coverage_check.dart --min=80` | **92.0 % (19581/21286)**, порог пройден |
| `fvm flutter build windows --release --no-pub` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (69,6 с) |
| `fvm flutter test integration_test/session_smoke_windows_test.dart -d windows --no-pub` | **All tests passed!** (11 с) |

Логи: `journal/iteration-7.18/full-7.18.2.log` (2339+16, до добавления
Anthropic-теста payload), `full-final-7.18.2.log` (2340+16, финальный прогон на
итоговом снимке), `smoke-7.18.2.log`.

## Затронутые проверки (по ходу итерации)

| Прогон | Результат |
|---|---|
| `test/unit/api/generation/image_catalog_budget_test.dart` | 6/6 |
| `test/unit/api/generation/generation_payload_bytes_test.dart` | 7/7 |
| `test/unit/domain/generation/reasoning_reserve_test.dart` | 5/5 |
| `test/unit/api/models/model_discovery_errors_test.dart` | 14/14 (зелёные до правок) |
| `test/integration/generation_exact_tokens_test.dart` | 6/6 |
| `test/unit/api/generation/card_generation_service_test.dart` + `test/unit/domain/generation` | 380/380 |
| `test/widget/settings/*` + `test/widget/generation/*` | 56/56 + 15/15 |
| `test/integration/*` | 737/737 |
| `test/unit/api/models/*`, `test/unit/domain/generation/model_capability_settings_test.dart` | зелёные |

## Что не запускалось

- **Живые API-запросы запрещены** (§0.6 задания): `test/live` остаются под
  тегом `live` и без `CARDFLOW_LIVE_TESTS=1` скипаются; обычный прогон
  офлайновый.
- Golden-тесты исключены (`--exclude-tags golden`), как в CI-профиле проекта и
  в предыдущих итерациях; они генерируются/прогоняются на Linux CI.

## Инфраструктурные замечания

- Прогоны только с `--no-pub` (L64: `pub get --example` виснет); `analyze`
  с `--no-pub`.
- Полный прогон шёл 4 мин 20 с; во время прогона `lib/`/`test/` не менялись.
