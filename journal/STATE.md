# STATE — текущее состояние CardFlow

**Дата:** 2026-11-15 · **Этап:** итерация **7.11** «FSRS новых карточек, картинки,
сканы и Practice Mode» (ADR-025/026/027) — завершена локально, verify зелёный;
**push выполнен, CI ожидается/зелёный по факту прогона** · **Режим:** ИТЕРАЦИИ
**Факты (сверено командами в этой сессии):** на старте `git status --porcelain` → пусто,
`HEAD = origin/main = 14b1a71` (`docs: record green CI for prompt-only iteration`;
в STATE 7.10 было записано `5cbb653` — исправлено). Baseline — **1409 passed + 3 skipped**.
Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode нет (L2).
Прогоны — только с `--no-pub`: `fvm flutter test`/`build` без него зависают на
`dart pub get --example` (сеть pub в сессии агента).

## Следующее действие

1. **Стоп:** итерация 7.11 принята локальными гейтами; ждать команды владельца.
2. Приёмка владельцем: (а) сгенерировать карточки — предпросмотр показывает
   иллюстрацию (Wikimedia); (б) «Начать сессию» при исчерпанном дневном лимите —
   объяснение причины + кнопка «Тренировать»; (в) тренировка проходит любые
   карточки, оценки не меняют интервалы; (г) PDF-скан уходит страницами PNG.
3. Дизайн (стекло, тени, анимации) — отдельная задача, не начиналась.

## Итерация 7.11 — итог

**Диагностика owner-note по фактической БД приложения (не по догадкам):**
43 новые карточки имели `due IS NULL`/`fsrs_json IS NULL`; за 15.11 — 30 «новых»
оценок при `daily_new_limit = 20`; экран колоды проверял очередь **без** лимитов,
а сессия — с лимитами → пустая сессия «Нет карточек к повторению». Openverse с хоста
таймаутил (L61), поэтому картинок не было вовсе.

**Сделано:**
- **ADR-026 (критический хаб):** новая карточка (ручная и сгенерированная) сразу
  сохраняется с `due = now` и валидным `fsrs_json` (`CardSchedulingMapper.initialScheduling`);
  счётчик «к повторению» исключает `state='new'`; базовый порядок конструктора
  различает запланированные/новые по `state`, а не по `due IS NULL`.
  Интеграционный тест: генерация с медиа → drift-БД → `ReviewQueue.build` содержит
  карточку, `due`/`fsrs_json` валидны, media читается production-репозиторием.
- **ADR-025 «Тренировка»:** `PracticeQueue` (все карточки, кроме suspended),
  `DriftPracticeRepository` (`review_logs.mode='practice'`, `scheduled_days`/`actual_days`
  = NULL, карточка не меняется), `PracticeSessionEngine` + `PracticeSessionScreen`,
  маршрут `/decks/:deckId/practice`, пункт «Тренировка» в листе режимов; пустая
  сессия из-за лимита показывает причину и ведёт в тренировку; экран колоды
  проверяет очередь тем же остатком лимитов (`readRemainingReviewLimits`).
  Дневные лимиты не расходуются тренировкой.
- **ADR-027 картинки/сканы:** `WikimediaImageSearchService` (Commons, русские
  запросы, JPEG/PNG ≤ 5 МБ, атрибуция) — основной источник; Openverse — резерв;
  `CompositeCardImageFinder`; таймауты 8 с; бюджет 45 с **суммарного времени поиска**
  в `GenerationPipeline` (ожидание модели не считается). PDF-скан — первые **3**
  страницы PNG (`PdfScanRenderer.maxPages = 3`).
- **Живые проверки:** 5/5 live-тестов на `deepseek-chat`, включая **PDF-скан
  (3 страницы → 2 карточки)** и **живой Wikimedia** (JPEG 97 КБ, CC BY-SA 4.0).
  Windows-смоук `integration_test/session_smoke_windows_test.dart -d windows`:
  генерация → импорт → лимит → тренировка → видимая картинка → practice-оценка.

**Доказательства:** `fvm flutter test --no-pub --coverage --exclude-tags golden` →
**1458 passed + 4 skipped**; покрытие рукописного кода **92.0 % (10316/11216)**;
`analyze` 0; `dart format --set-exit-if-changed lib test` → 349/0; `build windows
--release` → `cardflow.exe` (79,3 с); `flutter run -d windows` — окно открылось,
ошибок старта нет. Детали — `journal/iteration-7.11/{plan,red-output,review,verify}.md`.

## Известные ограничения (актуальные)

L1, L2, L4–L8, L10–L16, L18–L20, L23–L25, L27, L28 (только Windows), L30, L31–L34,
L35, L36, L37–L44, L46–L52, L53 (живой PDF-part), L54, L55, L56, L57, L58,
**L59** (≤ 3 страниц; PNG-страницы живьём — да, PDF-part — нет), L60, L61 (Openverse
резерв), L62–L64, **L65** (Openverse нестабилен), **L66** (`deepseek-flash` —
нарушение strict-схемы), **L67** (ручные клики владельца), **L68** (живой PDF-part
Anthropic/Gemini), **L69** (recognition_flag тренировки), **L70** (дневной лимит —
продуктовое правило).

## История

- 7.10 «Prompt-only, PDF и картинки» — CI run `43728048903` 9/9; summary —
  `journal/iteration-7.10/summary.md`.
- 7.9 «PDF-сканы, иллюстрации и occlusion» — CI run `43703387395` 9/9;
  summary — `journal/iteration-7.9/summary.md`.
- 7.8 «Вложения и Vision» — ADR-022, CI run `43650756271` 9/9.
- 7.6 «Пустой ответ LLM» — CI runs `43637919516`/`43639479927` 9/9.
- 7.5 «Провайдеры и ключи» — ADR-020, CI run `43632334916` 9/9.
