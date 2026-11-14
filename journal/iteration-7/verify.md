# Итерация 7 — verify

**Дата:** 2026-11-14 · **Снимок:** `6a40180` (fix после ревью) · **Хост:** Windows 11, FVM/Flutter 3.47.9,
Dart 3.13.7. Android SDK/JDK/Xcode/Linux отсутствуют (L2), CI — после push.

## Команды и результаты

| Проверка | Команда | Результат |
|---|---|---|
| Формат | `fvm dart format --set-exit-if-changed lib test` | **299 files 0 changed**, exit 0 |
| Анализатор | `fvm flutter analyze` | **No issues found** |
| Полный прогон + покрытие | `fvm flutter test --coverage --exclude-tags golden` | **1175 passed + 1 skipped** |
| Покрытие рукописного кода | `fvm dart run tool/coverage_check.dart --min=80` | **92.7 % (8322/8977)**, порог 80 пройден |
| Сборка Windows | `fvm flutter build windows --release` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (61,7 с) |
| Guard-тесты | в полном прогоне (`test/guards/*`) | no_webview, ru_strings, no_secrets, architecture, ci_pdfium — зелёные |
| Интеграция настроек/статистики | `fvm flutter test test/integration/settings_statistics_flow_test.dart` | **2 passed** (production-граф на реальной drift-БД) |
| Ревью | `journal/iteration-7/review.md` | high/critical нет; M1/M2 закрыты `6a40180`, M3 — L45 |

Новые файлы покрытия (выборка): `app_settings.dart` — 100 %, `drift_app_settings_store.dart` — 100 %,
`statistics.dart` — 100 %, `drift_statistics_repository.dart` — 100 %, `api_key_verifier.dart` — 100 %,
`settings_screen.dart` — 89 %, `statistics_screen.dart` — 96 %, `app_shell.dart` — 100 %,
`app_theme.dart` — 100 %, `app.dart` — покрыт widget-тестами темы/масштаба.

## Критерии приёмки итерации

| # | Критерий (SPEC/план) | Статус | Доказательство |
|---|---|---|---|
| 1 | A6.1: `NavigationBar`/`NavigationRail`, пункты «Колоды/Статистика/Настройки», «Сессия» скрыта | **выполнено** | `shell_test` (узкая/широкая ширина, переключение веток, отсутствие «Сессии»), `app_router_test` (ветки/пути), app-тесты навигации |
| 2 | A6.5: удержание + waveform, карта года с месяцами, слабые темы + «Тренировать» с тегом, прогноз 7 дней, недельный прогресс | **выполнено** | `statistics_calculator_test` (9), `drift_statistics_repository_test` (6), `statistics_screen_test` (4+), `statistics_charts_test`; «Тренировать» → `/constructor?tag=` (widget + конструктор `?tag=`) |
| 3 | A6.6: внешний вид, API (ключи/«Проверить»/модель/токены), обучение, доступность, «О приложении»; нет мёртвых элементов | **частично** | Все блоки и элементы работают и покрыты `settings_screen_test`/`api_key_verifier_test`; **кроме:** дневные лимиты применяются к сессии, а не накапливаются за день — **L45** |
| 4 | Настройки реально влияют: тема/контраст/шрифт/размер, haptics, motion, retention, шаги, лимиты, модель | **выполнено** | `app_settings_applied_test`, `app_theme_test`, `app_settings_controller_test` (шаги→прогноз Again, retention→интервал), `review_queue_limits_test`, `review_session_screen_test` (лимит и haptics off), `feed_progress_bar_test`, `generation_screen_test` (модель по умолчанию) |
| 5 | API: «Проверить» — реальный запрос, ошибки → ARB, ключи не в БД/логах | **выполнено** | `api_key_verifier_test` (7: missing/valid/401/сеть/429/не настроен/совместимый без ключа), `no_secrets`; в `generation_jobs` проверка не пишет |
| 6 | Данные: схема БД не меняется, миграций нет | **выполнено** | `git diff` не трогает `lib/data/db/tables.dart`/`app_database.dart`; `schema_test`/`migration_test` зелёные; настройки — строка `app.settings` в существующей `app_settings` |
| 7 | Гейты: тесты/analyze/format/покрытие/сборка/guard-тесты | **выполнено** | таблица выше |

## Не проверено и почему

- **L6c/L43:** dynamic color и рендер OpenDyslexic на реальных ОС/экранах; `flutter test` не даёт плагин и
  не растеризует шрифт. Контраст+dynamic color совместно — L43.
- **L44:** объём/память статистики на больших БД (десятки тысяч повторов).
- **L45:** накопление дневных лимитов между сессиями — принятое ограничение, критерий 3 «частично».
- **L46:** screen-reader статистики — только сводка; детали тепловой карты не озвучиваются.
- **L35:** независимый reviewer недоступен; ревью Lead на неизменяемом снимке.
- **L2:** сборки Android/iOS/Linux/macOS — только CI после push; локально проверен Windows.
- **L11/L12/L37/L38/L42:** ручная приёмка устройства, реальные жесты/picker, screen-reader.

## Вывод

Итерация 7 завершена по шагам 1–6; гейты зелёные, критерий A6.6 — «частично» из-за L45 (разрыв с
формулировкой «дневные» лимиты), остальные критерии выполнены. Работа не называется «готово»
для MVP: пост-итерационное ограничение зафиксировано, push/CI — по команде владельца.
