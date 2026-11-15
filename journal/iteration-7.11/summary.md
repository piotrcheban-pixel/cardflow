# Итерация 7.11 — итог: FSRS новых карточек, картинки, сканы, Practice Mode

**Дата:** 2026-11-15 · **ADRs:** 025 (тренировка), 026 (инвариант новой карточки),
027 (источники иллюстраций и 3 страницы скана) · **Коммиты:** `d6d68f2`, `17bb65a`,
`7861c82` (+ docs)

## Что было в owner-note и что оказалось на самом деле

| Owner-note | Диагноз по фактическим данным | Что сделано |
|---|---|---|
| «Сгенерировал 10 карточек — "Нет карточек к повторению"» | В БД: 43 новые карточки с `due/fsrs_json = NULL`; за день **30** «новых» оценок при `daily_new_limit = 20`; сессия получала `newLimit = 0`, экран колоды проверял очередь **без** лимитов | Инвариант новых карточек (`due/fsrs_json`, ADR-026); пустая сессия объясняет лимит и ведёт в тренировку; экран колоды проверяет очередь тем же остатком лимитов |
| «Картинки не отображаются в предпросмотре» | Рендер предпросмотра работает (тест на `Image` + байты, после импорта файл/`media` целы); **поиск не давал картинку**: Openverse таймаутил (первый GET 200, дальше > 30 с), Wikimedia по-русски — 1–2 с | Wikimedia Commons — основной источник, Openverse — резерв, композит + бюджет 45 с поиска (ADR-027); тесты предпросмотра/импорта/сессии |
| «Сканы PDF не отправляются» | Механика 7.9 на месте; подтверждено живьём: DeepSeek принимает `image_url` и вернул карточки по 3 PNG-страницам | 3 страницы по умолчанию (было 4), живой тест `pages=3 → cards=2`; для модели без Vision — `pdfScanVisionRequired` |
| «Нужен режим "Тренировка"» | — | `PracticeQueue`/`PracticeRepository`/`DriftPracticeRepository`/`PracticeSessionEngine`/экран/маршрут/пункт в листе; оценки `mode='practice'` без изменения FSRS и без расхода лимитов |

## Ключевые артефакты

- `lib/domain/cards/card_scheduling.dart` — `initialScheduling`.
- `lib/domain/review/practice_queue.dart`, `practice_repository.dart`;
  `lib/data/review/drift_practice_repository.dart`.
- `lib/ui/review/practice_session_{engine,screen}.dart`, `lib/ui/state/review_limits.dart`.
- `lib/api/images/wikimedia_image_search_service.dart`,
  `composite_card_image_finder.dart`; бюджет в `generation_pipeline.dart`.
- `lib/api/parsers/pdf_scan_renderer.dart` — `maxPages = 3`.
- Тесты: +48 (всего 1458 passed + 4 skipped); Windows-смоук
  `integration_test/session_smoke_windows_test.dart`.

## Доказательства (полные — `verify.md`)

- `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1458 passed + 4 skipped**;
  покрытие рукописного кода **92.0 % (10316/11216)**.
- `analyze` 0; `dart format --set-exit-if-changed lib test` → 349/0.
- `fvm flutter build windows --release --no-pub` → `cardflow.exe` (79,3 с).
- `fvm flutter run -d windows --no-pub` → приложение запущено (окно, Impeller, VM Service).
- Windows-смоук на реальном процессе → `All tests passed!`.
- Живые тесты: **5 passed** (`deepseek-chat`), в т.ч. PDF-скан и Wikimedia; `deepseek-flash` — 3/5
  (2 × `invalidResponse` strict-схемы, L66).

## Риски и ограничения

L65 (Openverse нестабилен — резерв), L66 (`deepseek-flash`/strict-схема), L67 (ручные клики
владельца), L68 (живой PDF-part Anthropic/Gemini), L69 (`recognition_flag` тренировки),
L70 (дневной лимит — продуктовое правило). Схема БД и `format_version` не менялись.

## Ретроспектива (для следующих итераций)

1. Owner-note «карточек нет» надо проверять **на данных приложения** (лимиты/`state`/`due`),
   а не только в коде очереди: причина была в дневном лимите, а не в FSRS-фильтре.
2. Дублирующий расчёт (экран колоды vs сессия) — источник «зелёной» проверки с пустым
   результатом: один helper `readRemainingReviewLimits` для обоих экранов.
3. `autoDispose`-провайдер с асинхронными зависимостями нельзя читать через `ref.read(...future)`
   из экрана: provider освобождается до завершения будущего (Riverpod 3) — использовать helper.
4. Бюджет внешнего сервиса должен считать **своё** время, а не время всей операции: иначе
   медленная модель «съедает» бюджет картинок.
5. Внешний источник без ключа — проверять живьём **до** выбора: Openverse был нерабочим,
   Wikimedia закрыл потребность в 10× быстрее.
