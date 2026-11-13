# Итерация 2 — красная фаза: data-слой (шаг 2)

**Команда:** `fvm flutter test test/unit/data/cards/card_crud_test.dart test/unit/data/review/review_repository_test.dart`
**Итог:** 14 падений в новых тестах; существующие data-тесты (`card_repository_test`, `deck_repository_test`, `deck_transfer_service_test`, `zip_deck_archive_codec_test`) зелёные.

## Ожидаемое поведение, зашитое в тесты (до реализации)

### `DriftCardRepository.createCards/updateCard/deleteCard/cardById` (SPEC A5, A6.3, ADR-009)

- `basic` — одна строка: все поля из черновика, `state = new`, `due = null`, `fsrs_json = null`, `content_hash = sha256(normalize(front)+"\0"+normalize(back))`, `created_at = updated_at = now`; повторное чтение из БД равно возвращённой карточке.
- Черновик нормализуется перед записью (trim сторон, теги без `#`/пустых).
- `basic_reversed` — две строки с взаимными `sibling_id`, вторая с переставленными `front`/`back`, у каждой свой `content_hash`; обе видны в `watchCards`.
- `updateCard` — меняет front/back/hint/tags/source_excerpt и `content_hash`/`updated_at`, сохраняет id/deckId/cardType/createdAt/sibling; тип из черновика игнорируется (ADR-009); несуществующая карточка → `StateError`.
- `deleteCard` — удаляет строку; у парной обнуляет `sibling_id`; несуществующая — тихий no-op.

Причина красной фазы — заглушки `UnimplementedError`:

```
UnimplementedError: DriftCardRepository.createCards: красная фаза итерации 2
  package:cardflow/data/cards/drift_card_repository.dart 63:5  DriftCardRepository.createCards
  test\unit\data\cards\card_crud_test.dart 36:40               main.<fn>.<fn>
```

### `DriftReviewRepository.recordReview/undoReview` (SPEC A5 — одна транзакция; A6.4 undo)

- `recordReview`: `review_logs` (rating 1–4, reviewed_at epoch ms, mode, recognition_flag=0, scheduled_days = (after.due − reviewedAt)/сутки, actual_days = (reviewedAt − lastReview)/сутки или null, elapsed_ms) **и** `cards.state/fsrs_json/due/updated_at` пишутся вместе; возвращаемый undo-токен содержит id лога и снимок карточки до оценки.
- Несуществующая карточка → `StateError`, лог не пишется (атомарность).
- `undoReview`: удаляет лог и восстанавливает снимок карточки; отсутствующий лог → `StateError`, карточка не меняется.

Причина красной фазы — заглушки `UnimplementedError: DriftReviewRepository.recordReview: красная фаза итерации 2`.

## Почему это честная красная фаза

Тесты используют **реальную in-memory drift-БД** и боевую схему (посев через `test_support.dart`, чтение через сгенерированные drift-компанионы), а не фейки: проверяются и SQL-поля, и транзакционность. Зелёная фаза должна дать точные значения (`closeTo(10/1440, 1e-9)` и т.п.), а не «просто не упало».
