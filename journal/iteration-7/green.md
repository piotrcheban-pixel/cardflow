# Итерация 7 — зелёная фаза

**Дата:** 2026-11-14 · **Снимок:** `1d591f4` + рабочее дерево
**Команды:** `fvm flutter analyze` → **No issues found**;
`fvm flutter test --exclude-tags golden` → **1171 passed + 1 skipped**;
`fvm flutter test test/integration/settings_statistics_flow_test.dart` → **2 passed**.

## Что реализовано

1. **Настройки (A6.6, ADR-019 §1–2).**
   `lib/domain/settings/app_settings.dart` — `AppSettings` (тема, dynamic color, motion, шрифт дислексии,
   масштаб 0.8–1.4, контраст, haptics, retention 0.70–0.95, шаги 1–5×1–60 мин, дневные лимиты 0–999,
   модель по умолчанию), JSON `version=1`, клампы, `FormatException` на битые типы.
   `DriftAppSettingsStore` — одна строка `app_settings` с ключом `app.settings`, битый JSON → дефолты.
   `AppSettingsController` (Riverpod `AsyncNotifier.save`) — состояние сразу, ошибка записи откатывает
   состояние и уходит в UI; `effectiveAppSettingsProvider` — синхронный снимок для планировщика.
2. **Статистика (A6.5, ADR-019 §4).**
   `StatisticsCalculator` — удержание 30 дней (`rating > 1`), карта 365 локальных дней, неделя 7 дней,
   слабые темы (≥5 повторов и ≥20 % Again, топ-5), прогноз 7 дней с просроченными в «сегодня».
   `DriftStatisticsRepository` — чтение `review_logs`/`cards`/`generation_jobs`, терпимость к битому
   `tags_json`; `tokensUsedSince` для недельного счётчика.
   UI: `StatisticsScreen` (loading/error/empty/data), waveform/heatmap/forecast на `CustomPainter`
   без новых зависимостей; «Тренировать» → `/constructor?tag=…`.
3. **Оболочка A6.1.** `AppShell` (`NavigationBar` < 600 px, `NavigationRail` ≥ 600 px), три ветки
   `StatefulShellRoute`: `/`, `/statistics`, `/settings`; «Сессия» скрыта (ADR-019 §3).
   Иконка настроек на «Колодах» ведёт в `/settings`; настройки генерации открываются из блока «API».
4. **Настройки применяются.**
   `CardFlowApp` — ConsumerStatefulWidget с одноразовым router (смена темы не сбрасывает навигацию),
   `themeMode`, `contrastLevel`, dynamic color (`DynamicColorBuilder`), шрифт OpenDyslexic
   (`AppTheme` + проекция `M3EThemeData.fromMaterial` — иначе M3E перекрывал textTheme), масштаб текста
   через `MediaQuery`.
   `schedulerProvider` собирает `FsrsScheduler` из retention/шагов; `ReviewQueue.build` принимает
   дневные лимиты; классика и лента читают настройки до старта движка; haptics и motion (стандартная
   пружина, без пульса) учитываются экранами; модель по умолчанию предвыбирается на экране генерации.
5. **Проверка ключа (A6.6, ADR-019 §5).** `ApiKeyVerifier` — минимальный запрос через существующие
   адаптеры/транспорт, наружу только `ApiKeyCheckStatus` → ARB; ключи не логируются, `generation_jobs`
   не пишется.
6. **О приложении.** Версия (тест сверяет с `pubspec.yaml`), `showLicensePage`, политика приватности
   `docs/privacy.md` через `ExternalLinkLauncher` (системный браузер, тест с фейком).
   OpenDyslexic Regular + OFL добавлены в `assets/fonts/`.

## Тесты

- Домен/данные: `app_settings_test` (9), `drift_app_settings_store_test` (6), `statistics_calculator_test`
  (9), `drift_statistics_repository_test` (6) — красная фаза зафиксирована `red.md`.
- Проводка: `app_settings_controller_test` (5: store, откат, шаги→планировщик, retention→интервал),
  `review_queue_limits_test` (3), `api_key_verifier_test` (7), `about_links_test` (2), `app_theme_test` (3).
- Widget: `statistics_screen_test` (4), `settings_screen_test` (5), `shell_test` (2),
  `app_settings_applied_test` (2), `feed_progress_bar_test` (2), дополнены тесты сессии (лимит, haptics off),
  конструктора (?tag=), генерации (модель по умолчанию), app/router/localization (оболочка, ветки).
- Integration: `settings_statistics_flow_test` (2) на реальной drift-БД и production-провайдерах.

## Оговорка процесса

Красная фаза снята отдельным прогоном для домена/данных; UI-тесты писались после появления ARB-строк и
виджетов (иначе они не компилируются), поэтому assertion-level red для UI отдельным снимком не зафиксирован.
Это ограничение процесса итерации 7, зафиксировано в summary; покрытие и ревью — отдельными шагами.
