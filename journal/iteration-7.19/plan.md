# План 7.19 — независимые изображения вопроса и ответа, отказ от заглушек

**Дата:** 2026-11-21. **Снимок:** `16766f8`. **Вход:** `audit.md` (фаза 0).

## 1. Решения (ADR-041, ADR-042)

### ADR-041 — «Никаких синтезированных изображений в данных карточки»

- Генератор заглушек `PlaceholderImageGenerator` **удаляется** из кодовой
  базы; `GenerationPipeline` никогда не создаёт изображение.
- Неудачи привязки изображения — **явные состояния**:
  `imageIdUnknown` (id вне каталога фрагмента), `imageNotFound` (поиск не дал
  результата), отсутствующий файл (id есть, строки/файла нет), повреждённые
  байты/неверный MIME. Карточка остаётся без изображения, а не с картинкой.
- Плейсхолдер допустим **только** как визуальная подсказка пустого слота в
  редакторе: нейтральная иконка + текст, не PNG, не сохраняется, не
  экспортируется.
- Существующие заглушки в БД удаляются при старте
  (`PlaceholderMediaPurger`): строка `media`, файл, `<path>.meta.json` и id из
  `media_json`; настоящие изображения не трогаются.
- `main.dart` больше не вызывает `retryPlaceholders()`.
- Целостность: `MediaIntegrityChecker` сверяет
  `source → catalog → stored asset → card media`; отчёт без бинарных данных,
  `tool/media_integrity_report.dart` печатает таблицу по фактической БД.

### ADR-042 — «Сторона изображения в `media_json` v2, схема ответа v9»

- `cards.media_json` получает **версию 2**:
  `{"version":2,"question":["id…"],"answer":["id…"]}`.
  Старый формат `["id…"]` читается как **сторона вопроса** (совместимость:
  до 7.19 единственная иллюстрация показывалась на лицевой стороне).
  Схема БД (`schemaVersion`) **не меняется** — миграции нет.
- Домен: `Card.questionMediaIds` / `Card.answerMediaIds`; `mediaIds` —
  производное объединение (для GC, экспорта, загрузки медиа).
  `CardDraft` — независимые коллекции и независимые загрузки файлов.
- Схема ответа модели `gen-ru-v9`:

```json
{
  "front": "…", "back": "…", "card_type": "basic",
  "tags": ["…"], "hint": null, "source_excerpt": null, "source_file": null,
  "section_id": null,
  "question_image_ids": ["img3"],
  "answer_image_ids": ["img7"],
  "image": {"query": "…", "fallback_query": "…", "kind": "diagram",
            "side": "question"} | null
}
```

- `question_image_ids` / `answer_image_ids` — только id из `<images>`
  **текущего фрагмента**; неизвестный id → пометка `imageIdUnknown`, id
  отбрасывается. Один и тот же id в обеих коллекциях → остаётся на стороне
  вопроса, из ответа удаляется (пометка `imageDuplicatedSide`).
- `image` — **необязательный** объект для настоящей фотографии из внешнего
  поиска; `side` = `question` | `answer` | `none`. `none` и `null` — поиск не
  выполняется. `side` учитывает, раскрывает ли изображение ответ.
- Локальная терпимая схема принимает v9, а также v5 (`image_query`),
  v6–v8 (`image_id`, `image` без `side`): `image_id` → сторона вопроса,
  `image` без `side` → `question`. Старые ответы не отбрасываются.

## 2. Карта изменений по слоям

| Слой | Файлы | Изменение |
|---|---|---|
| domain/generation | `generated_card.dart`, `generated_card_image.dart` | `questionImages`/`answerImages`, `questionImageIds`/`answerImageIds`; нет «image»-заглушки |
| domain/cards | `card.dart`, `card_draft.dart`, `card_media_json.dart` (new) | коллекции по сторонам, JSON v2, совместимый разбор |
| api/generation | `card_json_schema.dart`, `card_content_validator.dart`, `generation_pipeline.dart`, `generation_images.dart` | схема v9, разбор массивов, разрешение id по сторонам, запрет дублей, нет генерации PNG |
| api/prompts | `system_prompt.dart`, `docs/prompts/gen-ru-v9.txt` (new) | `systemPromptVersion = 'gen-ru-v9'`, блок v9, v8 сохранён |
| data | `card_row_mapper.dart`, `drift_card_repository.dart`, `drift_generation_card_store.dart`, `media_store.dart`, `media_garbage_collector.dart`, `media_integrity_checker.dart` (new), `placeholder_media_purger.dart` (new), `drift_card_media_repository.dart`, export/import | запись/чтение v2, проверка MIME/пустых байтов, пурж заглушек, целостность, экспорт сторон |
| ui | `card_content_view.dart`, `card_image_view.dart`, `card_form_screen.dart`, `generation_preview_screen.dart`, `session_media.dart`, review/feed/study | изображения по стороне, явные состояния (нет файла/ошибка/повтор), редактор двух сторон, предпросмотр = будущий экран |
| l10n | `app_ru.arb` | строки состояний и редактора |
| tool | `media_integrity_report.dart` (new) | таблица диагностики §0.2 |

## 3. Шаги (TDD, каждый — отдельный коммит)

1. **red** — падающие тесты групп A/B/C (assertion-level), моделирующие все
   сценарии потери изображений; `red-7.19.md` с фрагментами «ожидалось/получено».
2. **green 1** — удаление заглушек из pipeline/провайдеров/main; явные пометки;
   пурж заглушек при старте; тесты A1–A12 (часть).
3. **green 2** — домен и хранилище: `media_json` v2, `Card`/`CardDraft`,
   репозитории, GC, экспорт/импорт, сессия; тесты A10, C28, группы C (кроме UI).
4. **green 3** — схема v9 и выбор сторон моделью: `GeneratedCard` коллекции,
   валидатор, pipeline, `question_image_ids`/`answer_image_ids`, дубли,
   неизвестные id; тесты B13–B21.
5. **green 4** — промпт `gen-ru-v9` + документация схемы; тесты байтов и версии.
6. **green 5** — UI: `CardContentView` по стороне, явные состояния,
   `CardImageView` (ошибка/повтор), редактор двух сторон, предпросмотр;
   тесты C22–C31, guard-тест «answerMedia не на лицевой».
7. **green 6** — целостность: `MediaIntegrityChecker`, MIME/пустые байты,
   `tool/media_integrity_report.dart`; тесты A4, A7, A8, D8.
8. **review** — независимый аудит снимка по чек-листу фазы 7 (в сессии
   reviewer недоступен → ревью Lead, L35), fix-коммиты с регрессионными тестами.
9. **verify** — ворота: `gen-l10n`, `dart format`, format check, `analyze`,
   полный набор тестов, покрытие ≥ 80 %, Windows Release Build, Windows Smoke.
10. **docs** — `audit.md`, `plan.md`, `review.md`, `verify.md`, `summary.md`,
    `STATE.md`, `KNOWN_LIMITATIONS.md`, `docs/api-schema.md`,
    `docs/prompts/gen-ru-v9.txt`, ADR-041/042.
11. **finish** — push, один финальный CI-прогон, 9/9 job success.

## 4. Критерии приёмки

- В сохранённых карточках нет `provider=placeholder`; ни один путь ошибки не
  создаёт изображение.
- `CardContentView` на лицевой стороне показывает **только** `questionMediaIds`,
  на обратной — только `answerMediaIds`.
- `question_image_ids`/`answer_image_ids` разбираются, дедуплицируются,
  неизвестные id безопасно отбрасываются; старые ответы читаются.
- Редактор: независимые списки, добавление/удаление/замена/просмотр/порядок/
  перенос на другую сторону; несколько изображений.
- Экспорт/импорт/backup сохраняют стороны; старые карточки открываются.
- Тесты групп A/B/C зелёные; покрытие ≥ 80 %; Windows Build и Smoke.
- CI 9/9.

## 5. Ограничения, которые остаются

- Автоматическая семантическая проверка «раскрывает ли изображение ответ»
  ограничена промптом и правилами нормализации: локально проверяется только
  назначение id/стороны, но не содержимое картинки (L186). Для изображений из
  документов содержимое читает модель (Vision), для остальных — человек в
  предпросмотре/редакторе.
- Реальный жест добавления файла (file_picker) в widget-тестах не
  воспроизводится — тесты через инжектированный `CardImageGateway`
  (L11 сохраняется).
