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
| Покрытие рукописного кода | `fvm dart run tool/coverage_check.dart --min=80` | **91.7 % (18905/20608)**, `ПОРОГ ПРОЙДЕН` |
| Guard-тесты | в полном прогоне | `ru_strings`, `no_webview`, `no_secrets`, `architecture` — зелёные |
| Сборка Windows | `fvm flutter build windows --release --no-pub` | **√ Built build\windows\x64\runner\Release\cardflow.exe** (70,9 с) |
| Baseline до изменений | `fvm flutter test --no-pub --exclude-tags golden` | 2193 passed + 16 skipped (`baseline-test.txt`); итог +63 теста, 0 ослаблений |`n| Windows smoke (реальный процесс) | `fvm flutter test integration_test/session_smoke_windows_test.dart -d windows --no-pub` | **All tests passed!** (11 с; debug-сборка 33,7 с) — форма+картинка, лимит, сессия, генерация с картинкой. Найден и исправлен хрупкий finder: заголовок диалога искался по всему дереву и совпадал с кнопкой тулбара; теперь поиск ограничен `AlertDialog` (тест стал точнее, не слабее) |`n| CI после push | GitHub Actions run [44819862886](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44819862886) | **9/9 job success** (`format + analyze`, `test` ×3 ОС, `build` linux/windows/macos/android/ios), run completed success |

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


---

# Верификация итерации 7.18.1 (2026-11-21)

**Снимок:** `50ca263` (fix ARB-гварда) + документация этой фазы.
**Ветка:** `main` · **Живые API-запросы:** не выполнялись.

## Гейты §6 исходного задания

| Гейт | Команда | Результат |
|---|---|---|
| Локализация | `fvm flutter gen-l10n` | выполнено, ошибок нет |
| Формат (запись) | `fvm dart format lib test integration_test` | **542 файла, 0 changed** |
| Формат (проверка) | `fvm dart format --set-exit-if-changed lib test integration_test` | **0 changed** |
| Анализатор | `fvm flutter analyze --no-pub` | **No issues found** (5,1 с) |
| Полный набор + покрытие | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2302 passed + 16 skipped + 0 failed** (4:20; baseline 2256+16) |
| Покрытие рукописного кода | `fvm dart run tool/coverage_check.dart --min=80` | **91.7 % (19433/21185)**, `ПОРОГ ПРОЙДЕН` |
| Guard-тесты | в полном прогоне | `ru_strings`, `no_webview`, `no_secrets`, `architecture` — зелёные |
| Windows release | `fvm flutter build windows --release --no-pub` | **√ Built ...cardflow.exe** (65,8 с) |
| Windows smoke | `fvm flutter test integration_test/session_smoke_windows_test.dart -d windows --no-pub` | **All tests passed!** (11 с; форма+картинка, лимит, сессия, генерация с картинкой) |

## Инварианты

- Схема БД и `schemaVersion` **не менялись** (`git diff d66b0ff -- lib/data/db`
  пуст); `SPEC.md`, `analysis_options.yaml`, `tool/coverage_check.dart` не
  редактировались.
- Новые данные — JSON v2 аккаунта (`max_input_tokens`,
  `capabilities_configured_at`) и существующий JSON v1 кэша характеристик.
- Ключи API — только `ApiKeyStore`; тела запросов генерации не логируются,
  диагностика подсчёта пишет источник/код/число.
- Один `GenerationPlan` и один builder (`buildRunPlan`) у предпросмотра и
  конвейера; планировщик не ходит в сеть.
- Тесты не ослаблены: 16 файлов, +1849/−21 строк; удалены только вызовы
  удалённого старого планировщика и ожидание v7/одного «неизвестно»
  (заменено точными ожиданиями).

## Что проверено выборочно

- prompt-only: `buildPromptOnly` и общий планировщик дают одинаковые
  части/лимиты/бюджет; тема входит в каждый запрос; `<part>` не пишется при
  `partCount == 0`.
- exact: 1234 токена → `inputTokens = 1272` (запас 3 %), повторный запуск —
  без сети, ошибка `http_401` → `estimated` и код в диагностике.
- overflow: 413/400 → части меньше 80 % исходной (+512 Б на заголовки), план
  fragmented, `parts == chunks`, у всех `partCount`/`focus`; обычный 400 и 401
  — один запрос без переплана; 15 запросов при бесконечном overflow (≤16).
- ручные настройки: 65536/60000/8192 сохраняются в аккаунт с
  `userConfigured` и датой; пустая форма — авто; Vision явного выбора не
  теряется при сбросе.
- «Подробнее»: источник и дата, приблизительно/точно, стратегия, части,
  партии, запросы, изображения, неизвестные лимиты; при кэшевом лимите вывода
  1000 — 3 партии; после смены модели — контекст Flash 1 000 000.
- Discovery: документированные поля DeepSeek/Anthropic/Moonshot; Ollama —
  семантика `unknown`; `foo-128k` — все лимиты unknown.

## Ограничения (не блокируют приёмку)

L154 (частично), L155, L158, L162–L173 в `journal/KNOWN_LIMITATIONS.md`.
