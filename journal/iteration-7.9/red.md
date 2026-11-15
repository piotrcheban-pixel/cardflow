# Итерация 7.9 — красная фаза

**Дата:** 2026-11-15 · Тесты писались до реализации; фрагменты вывода — assertion-level.

## 1. Лента: обратная сторона не должна зеркалиться

`test/widget/review/feed_card_view_test.dart` до фикса:

```
00:01 +0 -2: Some tests failed.
Failing tests:
  ...: обратная сторона при revealed=true не зеркалится
  ...: после анимации переворота текст не отзеркален
```

Ключа матрицы переворота не было (`Bad state: No element`), а после добавления ключа без
контр-поворота матрица дала бы `m00 = cos(pi) = -1` — зеркальный текст. После фикса оба теста
зелёные.

## 2. PDF-скан: рендер страниц

`test/unit/api/parsers/pdf_scan_renderer_test.dart` до реализации:

```
Expected: an object with length of <2>
  Actual: []
Which: has length of <0>
...
Expected: throws <Instance of 'ParserException'>
  Actual: <Instance of 'Future<List<Uint8List>>'>
  Which: emitted []
```

`test/unit/domain/generation/generation_chunker_test.dart` (groupKey):

```
Expected: an object with length of <2>
  Actual: [GenerationChunk(1...), GenerationChunk(2...), GenerationChunk(3...), GenerationChunk(4...)]
Which: has length of <4>
```

`test/widget/generation/generation_screen_test.dart` до проводки:

```
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Скан — страницы отправятся как изображения": []>
...
Expected: exactly one matching candidate
  Actual: Found 0 widgets with text "PDF-скан без текста. Выберите модель с поддержкой изображений"
```

## 3. Схема, промпт, occlusion и поиск картинок

- `card_schema_test`: свойств было 7 (не было `image_query`), enum — 3 значения.
- `prompt_test`: ожидалось `gen-ru-v3`, в коде был `gen-ru-v2`.
- `content_validator_test`: wire `occlusion` падал бы `CardType.fromWire` → `invalidResponse`.
- `generation_pipeline_test` (новые кейсы): карточка без картинки/маски; `imageFinder` ещё не был
  частью пайплайна.
- `image_search_service_test`: `findImage` возвращал `null` для валидного ответа Openverse:

```
Expected: not null
  Actual: <null>
Null check operator used on a null value
```

- `drift_generation_card_store_test`: `media`-строки/файла/`media_json` не появлялось (тесты
  компилировались на `GeneratedCard.image` и падали по ожидаемым полям после минимального скелета).

## 4. Полный прогон до фиксов

Первый полный прогон (`flutter test --exclude-tags golden`) — **7 failures**: 6 в
`test/integration/generation_flow_test.dart` из-за `UnimplementedError: mediaStoreProvider
должен быть переопределён` (production-граф после привязки MediaStore) и 1 в
`generation_pipeline_test` (`Expected: 'gen-ru-v2', Actual: 'gen-ru-v3'`). Исправлено
проводкой MediaStore в тестовый контейнер и обновлением ожидания версии промпта; это
подтверждает, что тесты проверяют production-проводку, а не только слои.
