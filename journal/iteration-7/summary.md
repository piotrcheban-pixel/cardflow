# Итерация 7 — summary

**Дата:** 2026-11-14 · **Итерация:** 7 «Статистика + настройки» · **Статус:** завершена (шаги 1–7)
**Снимок финальных гейтов:** `6a40180` · **Режим:** ИТЕРАЦИИ · **Push:** не выполнялся

## Сделано

1. **Настройки (A6.6, ADR-019).** Домен `lib/domain/settings/`: `AppSettings` (тема, dynamic color,
   motion, шрифт дислексии, масштаб текста 0.8–1.4, контраст, haptics, retention 0.70–0.95, шаги
   обучения 1–5 × 1–60 мин, дневные лимиты 0–999, провайдер/модель по умолчанию), JSON `version=1`,
   клампы, `FormatException` на неверные типы; `AppSettingsStore` + `DriftAppSettingsStore`
   (строка `app.settings` в существующей `app_settings`, битый JSON → дефолты); `AppSettingsController`
   (`AsyncNotifier.save`, откат при ошибке записи); `effectiveAppSettingsProvider`.
2. **Статистика (A6.5, ADR-019).** `StatisticsCalculator`: удержание за 30 дней (`rating > 1`), карта
   года (365 локальных дней), неделя 7 дней, слабые темы (≥5 повторов и ≥20 % Again, топ-5), прогноз
   7 дней (просроченные → сегодня), токены за неделю. `DriftStatisticsRepository` на `review_logs`,
   `cards.tags_json`, `cards.due`, `generation_jobs`; битый `tags_json` не ломает загрузку.
   UI `lib/ui/statistics/`: блоки, waveform/heatmap/forecast на `CustomPainter`, состояния
   loading/error/empty/data, «Тренировать» → `/constructor?tag=`.
3. **Оболочка A6.1.** `lib/ui/shell/app_shell.dart`: `NavigationBar` (<600 px) / `NavigationRail`
   (≥600 px), ветки `/`, `/statistics`, `/settings` (`StatefulShellRoute.indexedStack`); «Сессия»
   скрыта (нет активной сессии вне полноэкранного маршрута, ADR-019 §3). Иконка настроек на «Колодах»
   ведёт в `/settings`; настройки генерации — из блока «API».
4. **Применение настроек.** `CardFlowApp` — ConsumerStatefulWidget с одноразовым router; тема,
   `contrastLevel`, dynamic color (`DynamicColorBuilder`), OpenDyslexic, `MediaQuery.textScaler`;
   `M3EThemeData.fromMaterial` (M3E перекрывал textTheme). `schedulerProvider` собирает `FsrsScheduler`
   из retention/шагов; `ReviewQueue.build` получил `newLimit/reviewLimit`; классика и лента читают
   настройки до старта движка; haptics и motion учитываются; модель по умолчанию предвыбирается на
   экране генерации.
5. **API.** `ApiKeyVerifier` — минимальный запрос через существующие адаптеры/транспорт, наружу только
   `ApiKeyCheckStatus` → ARB; ключи не логируются, `generation_jobs` не создаётся. Блок API в настройках:
   провайдеры со статусом, «Добавить ключ» → настройки генерации, «Проверить», модель по умолчанию,
   токены за неделю.
6. **О приложении.** Версия (тест сверяет с `pubspec.yaml`), `showLicensePage`, политика приватности
   `docs/privacy.md` через системный браузер (`ExternalLinkLauncher`). Шрифт `OpenDyslexic-Regular.otf`
   (SIL OFL, `assets/fonts/OFL.txt`).
7. **Ревью.** `journal/iteration-7/review.md` на снимке `85afff3` (Lead, L35): high/critical нет;
   M1 (наложение подписей месяцев карты) и M2 (столбик прогноза при нуле) закрыты `6a40180` с тестами;
   M3 (дневные лимиты) — L45, критерий A6.6 «частично».

## Доказательства

- Красная фаза домена/данных: `journal/iteration-7/red.md` — 24 падения `UnimplementedError` на
  заглушках, 1 зелёный; после реализации 30 тестов зелёные.
- Итерация: полный прогон — **1175 passed + 1 skipped**; покрытие **92.7 % (8322/8977)**;
  `analyze` 0; `format` 299 files 0 changed; `fvm flutter build windows --release` → `cardflow.exe`
  (61,7 с); integration `settings_statistics_flow_test` — 2 passed на реальной drift-БД.
- Гейты и статусы критериев — `journal/iteration-7/verify.md`.

## ADR итерации

- **ADR-019** — статистика и настройки: хранение одним JSON `app.settings` (без миграций), что именно
  меняет каждая настройка, семантика статистики (окна/пороги/просроченные), оболочка A6.1, проверка ключа
  минимальным запросом, вложенный шрифт SIL OFL, ограничения L43–L46.

## Что осталось / не проверено

- **L45:** дневные лимиты — к очереди сессии, не накопление за день (критерий A6.6 «частично»).
- **L6c/L43:** dynamic color и рендер OpenDyslexic/размеры на реальных ОС; контраст+dynamic color.
- **L44:** объём/память статистики на больших БД; **L46:** screen-reader дней тепловой карты.
- **L35:** независимый reviewer; ручная приёмка устройства (L11/L12/L37/L38/L42).
- **L2:** сборки Android/iOS/Linux/macOS и CI — после push (команда владельца).
- Процесс: UI-тесты писались после появления ARB/виджетов, assertion-level red для UI отдельным
  прогоном не зафиксирован (оговорка в `green.md`).

## Следующее действие

Push коммитов итерации 7 и проверка CI — только по команде владельца; затем итерация 8 (post-MVP)
или закрытие L45 — по отдельной команде.
