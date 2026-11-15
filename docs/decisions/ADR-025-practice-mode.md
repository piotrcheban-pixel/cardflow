# ADR-025 — Режим «Тренировка» (practice) без влияния на FSRS

**Дата:** 2026-11-15 · **Итерация:** 7.11 · **Статус:** принято

## Контекст

Owner note 7.11: «Нужен режим "Тренировка" (Practice), чтобы проходить любые карточки
независимо от FSRS». Причина — тупик: дневной лимит новых карточек исчерпан, `due` у
новых карточек нет, и после импорта сгенерированных карточек «Начать сессию» показывает
«Нет карточек к повторению», хотя карточки в колоде есть.

Требования:

1. В тренировку входят **любые** карточки колоды — независимо от `due`, `state` и
   дневных лимитов.
2. Оценки тренировки **не ломают** реальное расписание FSRS (`state`, `fsrs_json`, `due`
   не меняются).
3. Схема БД и `format_version` в этой итерации не меняются.

## Варианты

| Вариант | Оценка |
|---|---|
| **A. Отдельная таблица `practice_logs`** | таблица есть в SPEC A5, но в ней нет `rating`; оценку пришлось бы кодировать в `mode`, а схему менять нельзя |
| **B. Отдельный столбец/таблица оценки** | миграция схемы и `format_version` ради тренировки — противоречит ограничению итерации |
| **C. Строка `review_logs` с `mode = 'practice'` (выбрано)** | схема не меняется, `rating` сохраняется, `scheduled_days`/`actual_days` = NULL; расход лимитов и FSRS-статистика явно исключают `mode = 'practice'` |
| **D. Оценки тренировки вообще не писать** | теряется история и undo; «нет мёртвых кнопок» — журнал лучше |

## Решение

1. **Домен.** `PracticeQueue.build(cards)` — все карточки, кроме `suspended`; порядок
   `createdAt ASC`, тай-брейк `id ASC`. Порт `PracticeRepository`
   (`recordPractice` → id строки, `undoPractice`).
2. **Данные.** `DriftPracticeRepository` пишет одну строку `review_logs`:
   `rating` = оценка, `mode = 'practice'`, `scheduled_days = NULL`,
   `actual_days = NULL`, `elapsed_ms` — время ответа. Карточка не обновляется
   (никакой транзакции с `cards`), undo удаляет строку с проверкой
   `mode = 'practice'`.
3. **Лимиты.** `DriftDailyUsageRepository.usageOnDay` исключает `mode = 'practice'`:
   тренировка не расходует дневной лимит новых/повторных, потому что не планирует
   карточку и не «вводит» её в FSRS.
4. **Движок и UI.** `PracticeSessionEngine` (раскрытие, оценка, undo, busy) и
   `PracticeSessionScreen`: тот же каркас A6.4 (`ReviewChrome`), но без прогноза
   интервалов (кнопки оценок без чисел). Маршрут `/decks/:deckId/practice`, пункт
   «Тренировка» в листе режимов колоды. Пустая сессия из-за дневного лимита
   показывает причину и кнопку «Тренировать» (`ReviewEmptyView` с `onPractice`).
5. **Тексты** — только ARB (`reviewModePractice`, `practiceTitle`, `practiceSubtitle`,
   `practiceEmptyTitle`, `practiceCompletedMessage`, `practiceRatedLabel`,
   `reviewDailyLimitTitle`, `reviewDailyLimitMessage`,
   `reviewStartEmptyLimitedMessage`, `practiceStartAction`).

## Последствия

- Тренировка не меняет прогноз и не «съедает» лимиты; статистика удержания и
  прогноз (`due` из `cards`) остаются честными.
- Строки `mode = 'practice'` видны в `review_logs`; счётчики активности по журналу
  (карта 365) их учитывают как факт работы — это осознанно.
- `practice_logs` (SPEC A5) остаётся неиспользуемой таблицей: без `rating` она не
  покрывает сценарий. Перенос тренировочных записей туда — при изменении схемы.
- Ограничение: тренировка не учитывает признак «показать ответ» для статистики
  узнавания (`recognition_flag` всегда 0) — вне рамок задачи.

## Ссылки

- SPEC A5, A6.3, A6.4, A6.6, A7.2; ADR-008, ADR-019 §8.
- `lib/domain/review/practice_queue.dart`, `lib/domain/review/practice_repository.dart`,
  `lib/data/review/drift_practice_repository.dart`,
  `lib/ui/review/practice_session_*.dart`, `lib/ui/state/review_limits.dart`.
