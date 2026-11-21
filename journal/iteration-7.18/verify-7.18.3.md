# Итерация 7.18.3 — ворота качества (§6)

**Дата:** 2026-11-21. **HEAD на момент прогонов:** `8332df2` + коммиты
итерации `cac4586`, `ee135b8`, `3f80f6d`, `cf3a741`, `72d8e3e` (исходники
тестов не менялись во время финального прогона). Окружение: Windows 11,
FVM 4.3.2, Flutter 3.47.9 (Dart 3.13.7).

## Baseline (до правок)

```
fvm flutter test --no-pub --exclude-tags golden
→ 03:51 +2302 ~16: All tests passed!   (логи 7.18.2)
```
Фактический baseline итерации 7.18.3: **2340 passed + 16 skipped** (снимок
`8332df2`).

## Красная фаза

`journal/iteration-7.18/red-7.18.3.log` — 16 assertion-level падений;
разбор `red-7.18.3.md`. Отдельный прогон Vision/лимитов —
`red-7.18.3-unknown-vision.log` (4 падения).

## Финальные ворота

| Команда | Результат |
|---|---|
| `fvm flutter gen-l10n` | ок (новые ключи состава бюджета/предупреждений сгенерированы) |
| `fvm dart format --set-exit-if-changed lib test integration_test` | `Formatted 550 files (0 changed)` |
| `fvm flutter analyze --no-pub` | `No issues found!` |
| `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2365 passed + 16 skipped, 0 failed** (exit 0; 4 мин 07 с) |
| `fvm dart run tool/coverage_check.dart --min=80` | **92.1 % (19743/21437)**, порог пройден |
| `fvm flutter build windows --release --no-pub` | `√ Built build\x64\runner\Release\cardflow.exe` (66,2 с) |
| `fvm flutter test integration_test/session_smoke_windows_test.dart -d windows --no-pub` | **All tests passed!** (11 с) |
| CI GitHub Actions (push `8332df2..1e32ee6`) | run [`44909643704`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44909643704) — **9/9 job success** (`format + analyze`, `test` × 3 ОС, `build desktop` × 3, `build mobile` Android + iOS) |

Логи: `full-final-7.18.3.log`, `build-windows-7.18.3.log`, `smoke-7.18.3.log`,
`full-7.18.3-a.log` (первый прогон полного набора после зелёной фазы, без
покрытия — 2364+16 до добавления теста вложений без текста).

## Затронутые проверки (по ходу итерации)

| Прогон | Результат |
|---|---|
| `test/unit/api/generation/request_token_counter_multimodal_test.dart` | 5/5 |
| `test/unit/api/generation/request_token_counter_test.dart` | 6/6 |
| `test/unit/domain/generation/token_breakdown_test.dart` | 5/5 |
| `test/unit/domain/generation/unknown_vision_and_limits_test.dart` | 8/8 |
| `test/integration/generation_exact_tokens_test.dart` | 10/10 |
| `test/unit/domain/generation` + `test/unit/api/generation` + `test/unit/api/models` | 705/705 |
| `test/widget` + `test/integration` | 456/456 |
| полный набор | 2365 + 16 skipped |

## Что не запускалось

- **Живые API-запросы** запрещены §0.6/§6 задания: `test/live` под тегом
  `live`, без `CARDFLOW_LIVE_TESTS=1` скипаются; обычный прогон офлайновый.
  Ключей OpenAI/Gemini/Anthropic в окружении нет (L1).
- Golden-тесты исключены (`--exclude-tags golden`), как в CI-профиле проекта.

## Инфраструктурные замечания

- Прогоны только с `--no-pub` (L64: `pub get --example` виснет).
- Первый фоновый прогон покрытия был остановлен: во время него правились
  `lib/`/`test/` (ревью-находки), поэтому его результат не засчитан; финальный
  прогон выполнен после последней правки исходников (только docs после него).
