# Итерация 2 — «Классический режим». План (шаг 1)

**Дата:** 2026-11-13 · **Режим:** `ИТЕРАЦИИ` · **Ветка:** `main` (рабочее дерево clean, HEAD `68b1c1b`)
**Цель SPEC B2:** ReviewSessionScaffold (A6.4), 4 кнопки с прогнозом (A7.2), undo, `review_logs` + обновление `due`/`fsrs_json` в одной транзакции (A5), создание/редактирование карточек (A6.3).

## Критерии приёмки итерации (SPEC)

| # | Критерий | Источник | Проверка |
|---|---|---|---|
| C1 | Каркас сессии: линейный прогресс, undo, выход с диалогом, «Почему?» (неактивна без `source_excerpt`), центр — карточка, низ — панель оценок | A6.4 | widget-тесты экрана сессии |
| C2 | 4 кнопки «Не знаю / Сложно / Знаю / Легко»: роли цветов `errorContainer / secondaryContainer / primary / tertiaryContainer`, клавиши 1–4, haptics `heavyImpact / lightImpact / lightImpact / selectionClick` | A7.2 | widget-тест клавиш/кликов; unit-тест маппинга haptics |
| C3 | Прогноз над каждой кнопкой вычислен тем же планировщиком, что и оценка (`previewIntervals` == фактический `due`) | A7.2 | тест на реальном `FsrsScheduler` (расширение существующего: learning/relearning) |
| C4 | Тап по карточке/пробел → 3D-flip с Expressive-пружиной, вторая сторона — `back` | A7.2 | widget-тест: до тапа только `front`, после — `back` |
| C5 | Undo откатывает последнюю оценку (лог удалён, `due`/`fsrs_json`/`state` карточки восстановлены) | A6.4 | unit-тест data-слоя + widget-тест + интеграционный прогон |
| C6 | Запись `review_logs` и обновление `due`/`fsrs_json` — атомарно (одна транзакция; расхождение — баг) | A5 | data-тест: успех — обе записи; ошибка — ни одной; интеграционный тест производственной проводки |
| C7 | `review_logs` заполняет `rating` (1–4), `reviewed_at`, `mode`, `scheduled_days`, `actual_days`, `elapsed_ms` | A5, A7.2 | data-тест полей лога |
| C8 | Сессия запускается с экрана колоды: «Начать сессию» → выбор режима (в итерации 2 виден только «Классический»), пустая очередь — понятное сообщение, не пустой экран | A6.3 | widget-тест экрана колоды |
| C9 | Создание карточки: форма с front/back/hint/теги/тип; `basic_reversed` создаёт две строки с взаимными `sibling_id`; `content_hash` пересчитывается | A5, A6.3, A8.4 | unit data-тест + widget-тест формы |
| C10 | Редактирование: тап по карточке в списке колоды → форма с заполненными полями; сохранение обновляет поля и `content_hash`; удаление — с подтверждением | A6.3 | widget-тест + unit data-тест |
| C11 | Валидация ручного создания: front не пуст, ≤500; back не пуст для basic/basic_reversed, ≤2000; теги ≤3, без `#`; сообщения из ARB | A8.4, L14 | unit-тест `CardDraft` + widget-тест ошибок формы |
| C12 | Тексты только из ARB, локаль ru; guard-тесты зелёные | 3.1, B6 | guard-тесты |

## Задачи (TDD: red → green на каждую)

### Домен
- **T1. Единый `CardState`.** Убрать дубликат enum из `domain/scheduling/scheduling_card.dart`, канон — `domain/cards/card.dart` (значения `newCard/learning/review/relearning`). Обновить `scheduler.dart`, `fsrs_mapper.dart`, существующий FSRS-тест (только переименование значения, поведение не меняется — зафиксировать в журнале). Файлы: `lib/domain/scheduling/*`, `lib/domain/cards/card.dart`, `test/unit/domain/fsrs_scheduler_test.dart`.
- **T2. `CardDraft` + валидация** (`lib/domain/cards/card_draft.dart`): immutable-черновик, `normalized()` (trim, теги: убрать `#`/пустые/дубли, ≤3), `validate()` → `Map<CardDraftField, CardValidationError>`; пороги 500/2000/3 (A8.4). Тест: `test/unit/domain/card_draft_test.dart`.
- **T3. Маппинг `Card` ↔ `SchedulingCard`** (`lib/domain/cards/card_scheduling.dart`): из `fsrsJson` (если есть) или `SchedulingCard.newCard`; `applyOutcome` → карточка с `state`, `fsrsJson`, `due`, `updatedAt`. Тест: `test/unit/domain/card_scheduling_test.dart`.
- **T4. Очередь сессии** (`lib/domain/review/review_queue.dart`): исключить `suspended` и `buriedUntil > now`; включить `state == newCard` и `due <= now`; порядок: сначала просроченные (`due` asc), затем новые (`createdAt` asc); будущие `due` не входят. Тест: `test/unit/domain/review_queue_test.dart`.
- **T5. Контракты повторения** (`lib/domain/review/review.dart`, `review_repository.dart`): `reviewModeClassic`, `ReviewUndo{logId, previousCard}`, порт `ReviewRepository.recordReview/undoReview`; расширить `CardRepository`: `cardById`, `createCards(deckId, draft, now)`, `updateCard(card, draft, now)`, `deleteCard(id)`.

### Данные
- **T6. Общий маппер строк** (`lib/data/cards/card_row_mapper.dart`): `Card` ↔ `CardsCompanion`/`CardRow` (вынести из `drift_card_repository.dart`, переиспользовать в review-репозитории).
- **T7. CRUD карточек** (`lib/data/cards/drift_card_repository.dart`): uuid v4, `content_hash`, `basic_reversed` — две строки с взаимными `sibling_id` в одной транзакции, `cardType` при редактировании не меняется, удаление чистит `sibling_id` у пары. Тест: `test/unit/data/cards/card_crud_test.dart`.
- **T8. `DriftReviewRepository`** (`lib/data/review/drift_review_repository.dart`): транзакция «обновить карточку → вставить лог», откат при ошибке; `scheduled_days` = `(after.due - reviewedAt)/сутки`, `actual_days` = `(reviewedAt - lastReview)/сутки` (null при первом повторении), `elapsed_ms`; undo — компенсирующая транзакция. Тест: `test/unit/data/review/review_repository_test.dart` (in-memory drift: успех/поля/undo/откат при отсутствующей карточке/пустой лог).

### UI и состояние
- **T9. Провайдеры** (`lib/ui/state/app_providers.dart`): `reviewRepositoryProvider`, `schedulerProvider`; интеграционный тест графа.
- **T10. Движок сессии** (`lib/ui/review/review_session_engine.dart`): `ChangeNotifier`; состояние (очередь, индекс, revealed, busy, undo-стек, превью); `reveal()`, `rate()` (elapsed от показа карточки, haptics-маппинг отдельно), `undo()`, завершение. Тесты: `test/unit/ui/review_session_engine_test.dart`, `test/unit/ui/review_haptics_test.dart`.
- **T11. Форматирование прогноза** (`lib/ui/review/review_interval_format.dart`): `<1 мин` / `N мин` / `N ч` / `N д`; unit-тест.
- **T12. Экран сессии** (`lib/ui/review/review_session_screen.dart`, `review_card_view.dart`, `review_toolbar.dart`): scaffold A6.4, flip-анимация на `AppMotion.expressiveSpring()`, кнопки с прогнозом и цветами A7.2, клавиши 1–4/Space, haptics, undo/«Почему?»/выход, пустое и завершённое состояния. Widget-тест с реальной in-memory drift-БД: `test/widget/review/review_session_screen_test.dart`.
- **T13. Форма карточки** (`lib/ui/cards/card_form_screen.dart`): создание/редактирование/удаление, валидация, тип `basic|basic_reversed`, подсказка про парную карточку, `source_excerpt`. Widget-тест: `test/widget/cards/card_form_screen_test.dart`.
- **T14. Экран колоды** (`lib/ui/decks/deck_screen.dart`): Expressive Card «Начать сессию» (bottom sheet режима: только «Классический»), FAB «Добавить», тап по карточке → редактирование, сообщения после сохранения/удаления, пустая очередь → snackbar. Обновить `test/widget/decks/deck_screen_test.dart`.
- **T15. Роутер и ARB**: маршруты `/decks/:deckId/study`, `/decks/:deckId/cards/new`, `/decks/:deckId/cards/:cardId/edit` (`app_router.dart`, `pump_app.dart`, `app_router_test.dart`); ключи ARB + `fvm flutter gen-l10n`; `test/widget/app_test.dart` и guard-тесты.

### Интеграция и доказательства
- **T16. Интеграционный срез** (`test/integration/review_session_flow_test.dart`): реальная drift-БД и производственный граф провайдеров: создать колоду/карточки через репозитории → очередь → оценки → проверить `review_logs`, `due`, `fsrs_json`, `state` → undo → снова проверить. Закрывает урок итерации 1 (фикс/фича должны быть подтверждены на production-проводке).
- **T17. Числа FSRS** (`tool/fsrs_intervals_probe.dart`): таблица прогнозов Again/Hard/Good/Easy для состояний new/learning/review/relearning (детерминированная конфигурация ADR-004) — в отчёт и `journal/iteration-2/verify.md`.
- **T18. Ревью** независимым reviewer (свежий контекст): отчёт `journal/iteration-2/review.md`, устранить blocker/critical/high, отдельный fix-коммит до verify.
- **T19. Verify/память**: полный `flutter test --coverage`, `analyze`, `format`, покрытие ≥80%, `build windows --release`, сверка C1–C12, `journal/iteration-2/{verify.md,summary.md}`, STATE/AGENTS, ретроспектива (шаг 7).

## Вне объёма итерации 2 (осознанно, без мёртвых кнопок)

- Настройки сессии (лимит/перемешивание/интерливинг, A6.4) и другие режимы (Лента, Конструктор) — **итерации 4/6**; в bottom sheet итерации 2 только «Классический» (остальные не отрисованы).
- Доп. кнопки A7.2 «Изменить»/«Отложить»/«Флаг» в сессии — скрыты (backlog итераций 5/6/7).
- Свайп-удаление/приостановка карточки в списке колоды (A6.3) — приостановка появится с фильтрами конструктора (итерация 6); создание `cloze` и редактор масок — итерации 5 (нужен редактор разметки).
- Повторное предъявление learning-карточек внутри сессии (requeue) — решение итерации 6 (конструктор) или отдельный ADR по обратной связи.
- `practice_logs`, интерливинг, дневные лимиты — итерации 6/7.

## Риски

| Риск | Митигация |
|---|---|
| FSRS-пакет 2.0.1 хранит состояние в `fsrs_json`; рассинхрон с колонками `state`/`due` | единый маппер T3, транзакция T8, интеграционный тест T16, undo-тест |
| Widget-тесты с реальной drift-БД могут быть медленными/флаки | точечный in-memory, `pumpAndSettle` только там, где нужна анимация; основной UI — на фейках |
| Flip-анимация на пружине усложняет детерминизм тестов | animation test: `pump` фиксированными шагами; проверить видимость `back` после settle |
| `M3ECard`/`M3ESnackbar` API 1.2.0 | сверять с существующим использованием (итерация 1), новых M3E-компонентов не вводить без спайка |
| Дубликат `CardState` мог «просочиться» в тесты | T1 отдельным red-коммитом: только переименование, поведение неизменно; зафиксировать в журнале |
| Undo после смены состояния карточки в другой сессии/экране | undo-стек только в памяти сессии; сессия — единственный писатель карточки, пока открыта; вне сессии undo недоступен |

## ADR итерации

- **ADR-008** — состав очереди классической сессии, порядок, одна оценка на карточку, немедленная персистентность, undo компенсирующей транзакцией, границы итерации 2.
- **ADR-009** — ручное создание/редактирование карточек: поля, типы (`basic`/`basic_reversed`), валидация (500/2000/3), неизменность типа при редактировании, семантика удаления парной карточки, `source_excerpt`, `cloze` — итерация 5.

## Порядок работы

1. План/ADR (этот файл) → коммит `docs:`.
2. Красная фаза: тесты T2–T5, T7, T8, T10, T11, T13–T16 с `UnimplementedError`-скелетами; прогон и фрагменты вывода с ожидаемым поведением → `journal/iteration-2/red-*.md` → коммит `test:`.
3. Зелёная фаза по слоям: домен → data → UI → маршруты/ARB; после каждого слоя тесты + `analyze`/`format` → коммиты `feat:`.
4. Ревью → fix → verify → память → улучшение (шаги 4–7).
