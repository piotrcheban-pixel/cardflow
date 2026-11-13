# STATE — текущее состояние CardFlow

**Дата:** 2026-11-13 · **Итерация:** 2 «Классический режим» — **в работе** · **Шаг цикла:** 1 (план) · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; локальная Windows-сборка работает; Android SDK/JDK, Xcode, Linux — отсутствуют; ключей API нет (absent). GitHub-remote `origin` → piotrcheban-pixel/cardflow; `main == origin/main == 052d2a2`, рабочее дерево clean. **CI итерации 1 — зелёный** (run `43436887755`, все job: quality, test×3, build-desktop×3, build-mobile Android+iOS) → L9/L9b закрыты 2026-11-13. Базовый прогон перед итерацией 2: `fvm flutter test` → 378 тестов зелёные.

## Следующее действие

Итерация 2, шаг 2 (красная фаза): падающие тесты на домен (маппинг `Card`↔`SchedulingCard`, очередь сессии, валидатор карточек), data (транзакция `review_logs`+`due`/`fsrs_json`, undo, CRUD карточек) и UI (ReviewSessionScaffold A6.4, 4 кнопки с прогнозом A7.2, undo, форма карточки).

## Итерация 2 — план (кратко)

1. Домен: `CardSchedulingMapper` (Card↔SchedulingCard), `ReviewQueue` (что учить: due+new, порядок), `CardDraft`+валидатор (front ≤500, back ≤2000, теги ≤3), `ReviewLog`/`ReviewUndo`.
2. Data: `DriftReviewRepository` — `recordReview` (одна транзакция: `review_logs` + `due`/`fsrs_json`/`state`/`updated_at`), `undo` (удаление лога + откат карточки), `cardsForReview`; `DriftCardRepository` — create/update/delete (+sibling для `basic_reversed`).
3. UI: экран сессии (`/decks/:deckId/study`) — линейный прогресс, undo, выход с диалогом, «Почему?», 3D-flip карточки, ReviewToolbar с 4 кнопками и прогнозами, клавиши 1–4, haptics по A7.2; форма карточки (`/decks/:deckId/cards/new`, `.../cards/:cardId/edit`), кнопка «Начать сессию» на экране колоды; M3E/тема-токены; ARB.
4. Ревью независимым reviewer, fix-итерация, verify (тесты/анализ/покрытие/Windows-сборка), summary/ADR/STATE, ретроспектива.

## Открытые вопросы к владельцу

Нет блокирующих. По ходу итерации могут возникнуть решения, требующие ADR (сессия без настроек A6.4 → итерация 6; `basic_reversed`/`cloze` в форме; requeue обучаемых карточек) — фиксируются как ADR, не как вопросы.

## Известные ограничения (актуальные)

L1 (ключи API), L4 (хуки), L5 (навыки), L6 (golden), L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (DnD-версия), L10 (устаревание due-счётчиков), L11 (живые диалоги file_picker/mobile), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины front/back при импорте — закрывается валидатором итерации 2), L15/L16/L17. **L9/L9b сняты 2026-11-13** (CI run `43436887755`).
