# Итерация 4 — «Лента». План (шаг 1)

**Дата:** 2026-11-14 · **Режим:** `ИТЕРАЦИИ` · **Ветка:** `main` · **HEAD на старте:** `e5f64c4`
(`origin/main` = `e5f64c4`, дерево clean — сверено `git status`/`git log`/`git ls-remote`).
**Baseline (эта сессия):** `fvm flutter test --exclude-tags golden --reporter compact` → **897 passed
+ 1 skipped**, exit 0; `fvm flutter analyze` → **No issues found!**; `fvm dart format
--set-exit-if-changed lib test` → **218 files, 0 changed**. Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2),
Windows 11.
**Цель SPEC B2/A7.3:** вертикальный срез «Лента» поверх готовой классической сессии (итерация 2):
полноэкранный `PageView.builder`, жесты оценок с порогами, Stories-прогресс, авто-продвижение 3/5/8 с,
«Пауза», haptics, возврат карточки пружиной, форма карточки 28→16→pill (A4.3), запись `review_logs`
с `mode = 'feed'`, запуск из листа режимов колоды (A6.3), каркас A6.4 (undo/«Почему?»/выход).

Граница с итерацией 2: `ReviewQueue`, `Scheduler`, `ReviewRepository`, `ReviewUndo`, haptics-маппинг
и транзакционная запись **не переписываются**; лента использует их как есть. Классический экран
сохраняет поведение; его каркасные элементы выносятся в общие виджеты без изменения ARB/семантики.

## Критерии приёмки итерации (SPEC)

| # | Критерий | Источник | Проверка |
|---|---|---|---|
| C1 | Полноэкранный вертикальный `PageView.builder`: одна карточка на страницу; свайп вверх/вниз — навигация; листание без оценки не пишет `review_logs` | A7.3 | unit-тест движка (`visit` без записи) + widget-тест PageView/fling |
| C2 | Тап раскрывает/скрывает ответ; тап по раскрытой карточке скрывает ответ; раскрытие — `selectionClick` | A7.3, A4.4 | widget-тест: front→back→front; haptic-канал |
| C3 | Свайп вправо — «Знаю», влево — «Не знаю»; долгий вправо (>60% ширины) — «Легко», влево — «Сложно» | A7.3 | unit-тесты чистой политики жеста + widget-тесты fling/drag |
| C4 | Защита от случайных свайпов: короткий свайп засчитывается только при ≥80 px **и** минимальной скорости; иначе карточка возвращается Elastic-пружиной | A7.3, A4.4 | unit-тесты границ 80 px/300 px·с⁻¹; widget-тест spring-back (смещение 0, оценок нет) |
| C5 | Stories-прогресс сверху: сегменты по карточкам, оценённые заполнены, текущий сегмент пульсирует; семантическая подпись на русском | A7.3 | widget-тест сегментов/пульсации (два кадра) и семантики |
| C6 | Авто-продвижение (опция) 3/5/8 с после раскрытия; «Пауза» останавливает и возобновляет; авто-продвижение не ставит оценку | A7.3 | widget-тесты таймера (`pump(3 c)`), паузы и отсутствия записи в `review_logs` |
| C7 | Снизу — колода, счётчик и «Пауза»; выбор интервала авто-продвижения доступен и не является мёртвой кнопкой | A7.3 | widget-тест нижней панели/меню 3-5-8 с |
| C8 | Оценка свайпом — haptic по таблице A7.2 (Again heavy, Hard light, Good light, Easy selectionClick); завершение — `mediumImpact`; раскрытие — `selectionClick` | A7.3, A7.2, A4.4 | widget-тест haptic-канала (4 оценки) |
| C9 | Форма карточки: `extraLarge` (28) в покое → `large` (16) при свайпе → pill при подтверждении; движение — токены `AppMotion` | A4.3, A4.4 | widget-тест `borderRadius` при drag/commit + unit-тест токенов (существующий) |
| C10 | Запись оценки: та же транзакция, `review_logs.mode = 'feed'`; один ответ на карточку; undo возвращает карточку с раскрытым ответом | A5, A6.4, ADR-008 | unit-тесты движка + интеграционный тест на in-memory drift |
| C11 | Сессия завершается, когда оценены все карточки (не когда пролистан последний экран); пустая очередь — пустое состояние; завершение — `mediumImpact` | A7.3, A6.4 | unit- и widget-тесты завершения/пустой очереди |
| C12 | Лист режимов колоды содержит «Классический» и «Лента» (A6.3); маршрут ленты работает на production-роутере | A6.3 | widget-тест листа/перехода + тест `createAppRouter` |
| C13 | Только ARB/ru, без сырых исключений; ошибка БД не теряет карточку и показывает сообщение из ARB | 3.1, A8.6 | widget-тесты ошибок; guard `ru_strings`; `no_secrets` |
| C14 | Качество: полный прогон зелёный, `analyze` 0, `format` 0 changed, покрытие ≥80%, Windows-сборка | B6 | `fvm flutter test --coverage`, `analyze`, `format`, `build windows --release` |
| C15 | Ревью: blocker/critical/high закрыты fix-коммитом с новыми тестами (в этой сессии независимый reviewer недоступен — L35) | процесс, шаг 4 | `journal/iteration-4/review.md`, `review-fixes.md` |
| C16 | Документация: ADR-016, `STATE.md`, `AGENTS.md`, `KNOWN_LIMITATIONS.md`, summary, retrospective | §11 | ревью файлов |

## Задачи (TDD: red → green на каждую)

### Домен/UI-политика
- **T1. `lib/domain/review/review.dart`:** константа `reviewModeFeed = 'feed'`.
- **T2. `lib/ui/review/feed_swipe.dart`:** чистая политика `feedSwipeRating(dx, velocity, width)`;
  константы 80 px / 300 px·с⁻¹ / 60%; длинный свайп не зависит от скорости, короткий — зависит.
- **T3. `lib/ui/review/feed_session_engine.dart`:** `FeedSessionItem`/`FeedSessionState`/`FeedSessionEngine`:
  очередь `ReviewQueue`, `visit` (без записи), `reveal`, `rate` (mode `feed`, elapsed, next unrated),
  `advance` (авто-продвижение без оценки), `undo` (возвращает карточку раскрытой), busy/dispose-защиты,
  завершение «все оценены», пустая очередь.

### UI
- **T4. `lib/ui/review/review_chrome.dart`:** общие для классики и ленты: AppBar (undo/«Почему?»/выход),
  диалог выхода, bottom sheet «Почему?», состояния «пусто/завершено/ошибка загрузки». Классический экран
  переводится на них без изменения поведения (существующие тесты — контракт).
- **T5. `lib/ui/review/feed_progress_bar.dart`:** Stories-сегменты, пульсация текущего, семантика.
- **T6. `lib/ui/review/feed_card_view.dart`:** горизонтальный drag, пороги, spring-back, fly-out,
  морфинг радиуса 28→16→pill, 3D-flip по тапу, тонировка роли оценки, rated-состояние, семантика.
- **T7. `lib/ui/review/feed_session_screen.dart`:** PageView.builder, синхронизация индекса, таймер
  авто-продвижения (3/5/8, пауза), нижняя панель (колода/счётчик/пауза/интервал), undo/why/exit,
  клавиши Space и 1–4 (desktop-паритет), состояния загрузки/ошибки/пусто/завершено.
- **T8. Роутер и вход:** `AppRoutes.feed`/`feedPath`, маршрут `/decks/:deckId/feed`, лист режимов на
  экране колоды (Классический/Лента), `test/helpers/pump_app.dart` — маршрут ленты.
- **T9. ARB:** `reviewModeFeed`, `feedPause`, `feedResume`, `feedSeconds`, `feedAutoAdvanceTooltip`,
  `feedCounter`, `feedRatedLabel`, `feedProgressSemantics`, `feedSwipeHint`; `fvm flutter gen-l10n`.
- **T10. Проводка:** `FeedSessionScreen` использует `cardRepositoryProvider`, `deckRepositoryProvider`,
  `reviewRepositoryProvider`, `schedulerProvider`; production-роутер `createAppRouter` содержит ленту.

### Тесты
- **T11. Unit:** `test/unit/ui/feed_swipe_test.dart`.
- **T12. Unit:** `test/unit/ui/feed_session_engine_test.dart`.
- **T13. Widget:** `test/widget/review/feed_session_screen_test.dart` — навигация, тап/раскрытие,
  4 свайпа, spring-back, PageView без оценки, Stories/пульс, авто-продвижение/пауза/интервал,
  haptics, undo, ошибки, пусто/завершено, «Почему?», выход.
- **T14. Widget:** `test/widget/review/feed_entry_test.dart` — лист режимов и production-роутер
  `/decks/:deckId/feed` через `CardFlowApp(router: createAppRouter(...))`.
- **T15. Integration:** `test/integration/feed_session_flow_test.dart` — реальная in-memory drift-БД:
  `FeedSessionEngine` → `review_logs.mode='feed'` → undo; production-провайдеры.
- **T16. Существующие тесты:** `app_router_test` (9 маршрутов), `review_session_screen_test` (лист
  режимов), guard `ru_strings`, haptics — обновить только под новое поведение (лист режимов).

### Ревью, проверка, память
- **T17. Ревью** (Lead, независимый агент в сессии недоступен — L35): чек-лист архитектуры, жестов,
  таймеров, утечек, ARB, семантики; `journal/iteration-4/review.md`; fix-коммит с тестами.
- **T18. Verify:** полный прогон с покрытием, `analyze`, `format`, `build windows`, сверка C1–C16 →
  `journal/iteration-4/verify.md`; `KNOWN_LIMITATIONS.md` (L35).
- **T19. Память:** ADR-016, `journal/iteration-4/summary.md`, `STATE.md`, `AGENTS.md` (устойчивые
  факты), ретроспектива шага 7 с одним улучшением процесса.

## Вне объёма итерации 4 (осознанно)

- Настройки сессии A6.4 (лимит/перемешивание/интерливинг) — итерация 6; в ленте их нет.
- Requeue learning-карточек (L20) и neighbor-squish (L18) — без изменений.
- Персистентность интервала авто-продвижения — итерация 7 (экран настроек); сейчас опция живёт в сессии.
- Deep accessibility pass (screen reader, golden) — итерация 7; сейчас семантические метки и клавиатура.
- Post-MVP режимы (аудио/ввод/выбор) — не отрисовываются.

## Риски

| Риск | Митигация |
|---|---|
| Конфликт горизонтального свайпа с вертикальным PageView | чистый `GestureDetector` горизонтали внутри страницы; widget-тесты fling по обеим осям |
| Повторяющаяся пульсация ломает `pumpAndSettle` | тесты ленты — только `pump(Duration)`; пульсация `AnimationController.repeat`, останавливается при завершении/уходе |
| Таймер авто-продвижения переживает dispose/паузу | отмена в `dispose`, на смене карточки/оценке/паузе; widget-тесты паузы и ухода |
| Двойная оценка при свайпе и быстром PageView | busy-флаг движка, `enabled`, одна оценка на карточку, rated-состояние |
| Ошибка БД после fly-out оставляет карточку за экраном | `resetToken` возвращает карточку; сообщение из ARB; тест ошибки |
| Утечка `Timer`/`AnimationController`/`PageController` | отмена/`dispose` во всех владельцах; анализ + ревью |
| Рефакторинг каркаса классики ломает 19 тестов | поведение не меняется, тесты — контракт; рефакторинг отдельным коммитом до UI ленты |

## Порядок работы

1. План + ADR-016 + `STATE.md` → коммит `docs:`.
2. Красная фаза: T1–T16 на скелетах; фрагменты «ожидалось/получено» →
   `journal/iteration-4/red-feed.md` → коммит `test:`.
3. Зелёная фаза: политика/движок (T1–T3) → каркас (T4) → UI ленты (T5–T9) → роутер/проводка (T8/T10) →
   каждый слой зелёный + `analyze`/`format` → коммиты `feat:`.
4. Ревью T17 (снимок после зелёного/format-коммита), fix-коммит с тестами.
5. Verify T18; память T19; ретроспектива (шаг 7).
