# Verify — срез 3 «Understanding: KnowledgeMap» (2026-11-27)

**Срез:** `TASK.txt` «Срез 3. Understanding: KnowledgeMap». План этапов —
`docs/generation/ARCH.md`, BACKLOG, ADR-050. Расхождение с BACKLOG S2
(детерминированная карта) и толкования полей — `journal/QUESTIONS.md` Q8/Q9.
**Старт:** ветка `main`, `HEAD = 74ec413` (docs среза 2); baseline
`flutter test --no-pub --exclude-tags golden` — **2863 passed + 17 skipped**.

## Что сделано

| Файл | Назначение |
|---|---|
| `lib/domain/generation/knowledge_map.dart` | `KnowledgeUnit` (`id`, `sectionId`, `topic`, `kind`, `statement`, `anchors`, `salience`, `splittable`), `KnowledgeAnchor`, `KnowledgeMap` (индекс по id O(1), `unitsOfSection`, `splittableUnits`), `KnowledgeUnitKind` (5 wire-значений), каноническая JSON-схема `gen-map-v1` по образцу A8.4 |
| `lib/api/prompts/understanding_prompt.dart` | версия `gen-map-v1`, системный промпт (только извлечение атомарных единиц, без правил карточек), `buildUnderstandingUserContent` (раздел + блоки с id) |
| `docs/prompts/gen-map-v1.txt` | дословная копия промпта; тест сверяет байты |
| `lib/api/generation/knowledge_map_caller.dart` | узкий контракт вызова модели (`KnowledgeMapRequest`, `KnowledgeMapRawResponse` с `usage`/`truncated`), по образцу `GenerationCaller` |
| `lib/api/generation/knowledge_map_parser.dart` | разбор ответа: id присваивает приложение, `section_id` — подсказка, поштучная проверка единиц, причины `json_parse`/`schema_invalid` |
| `lib/api/generation/understanding_service.dart` | этап Understanding: последовательные вызовы по разделам, пометка невалидного фрагмента без остановки прогона, кэш по «документ + хеш содержимого и версии промпта», фактический `usage` |
| `lib/data/generation/in_memory_knowledge_map_cache.dart` | in-memory реализация порта `KnowledgeMapCache<KnowledgeMap>` (БД — срез 7) |
| `test/fixtures/understanding/gen-map-v1-response.json` | golden-фикстура ответа модели (3 единицы, 5 якорей, `section_id = null`) |

Старый конвейер, UI, схема БД и публичные типы провайдеров **не менялись**.

## DoD из TASK.txt

1. **Golden-фикстура ответа модели** — `test/fixtures/understanding/gen-map-v1-response.json`,
   тест `knowledge_map_parser_test.dart` → 3 единицы, id/якоря/виды/`splittable`.
2. **Валидный/битый/пустой ответ** — `knowledge_map_parser_test.dart`: фикстура;
   `jsonParse` для `{"units": [`, `''`, `'   '`, текста без JSON; `schemaInvalid`
   для `[]`, `{"cards": []}`, `{"units": {}}`, `{"units": null}`; `{"units": []}` —
   валидный пустой ответ; поштучно отброшенные единицы (salience вне 0..1,
   неизвестный `kind`, нет обязательного поля, нет валидных якорей).
3. **Фолбэк: фрагмент помечен, остальные обрабатываются** —
   `understanding_service_test.dart`: битый JSON первого раздела → `failed`
   (`json_parse`), второй раздел даёт единицы, `hasFailures == true`, неполная
   карта **не** кэшируется; сбой провайдера → `provider_error`; обрезанный ответ
   → `truncated`; отмена пробрасывается наружу.
4. **Кэш: второй вызов не идёт в LLM** — `understanding_service_test.dart`
   (второй `build` → `fromCache == true`, `callCount` не растёт, `usage` пуст) и
   `in_memory_knowledge_map_cache_test.dart` (ключ документа и хеша, замена,
   очистка). Правка документа даёт новый ключ.

Дополнительно: пустой документ не звонит в LLM; раздел из одного номера
страницы (мусор) не отправляется; `usage` суммируется только по факту из
ответов — отсутствующее поле делает сумму `null`, а не нулём (TASK: «не считать
токены на глаз»).

## Красная фаза

`journal/generation-v3/red-s3.txt` — тесты написаны до реализации, скелеты
падают **assertion-level**, а не только компиляцией: `Expected: <3>
Actual: <0>` (golden), `Expected: true Actual: <false>` (валидный ответ),
`Expected: 'gen-map-v1' Actual: 'gen-map-v0'` (версия промпта),
`Expected: <2> Actual: <0>` (вызовы LLM), `Expected: true Actual: <false>`
(кэш). Итог: 6 прошло / 29 упало.

## Гейты итогового снимка

- `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` →
  **No issues found!** (0 issues).
- `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` →
  **639 files, 0 changed**.
- `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
  --exclude-tags golden` → **2905 passed + 17 skipped**, `exit 0`
  (baseline 2863 + 17; +42 новых). Полный лог —
  `journal/generation-v3/green-s3-full.txt`.
- `.\.fvm\versions\3.47.9\bin\dart.bat run tool/coverage_check.dart --min=80` →
  **90.8 % (24082/26524)**, порог 80 % пройден.

Покрытие новых файлов: `knowledge_map_parser.dart` — 100 % (61/61),
`understanding_prompt.dart` — 100 % (8/8), `in_memory_knowledge_map_cache.dart` —
100 % (8/8), `understanding_service.dart` — 95.0 % (95/100, непокрыты
`toString` и `UnderstandingResult.unitCount`), `knowledge_map.dart` — 75.0 %
(48/64, непокрыты только `==`/`hashCode`/`toString` и `blockIds`),
`knowledge_map_caller.dart` — 33.3 % (2/6, объявления контракта и `toString`;
прецедент `ports.dart`/`api_key_store.dart`).

## Решения среза (полностью — Q8/Q9)

- Карта — доменный тип; модель — **источник кандидатов**, как разрешено
  ARCH.md §2. Детерминированные правила (salience по структуре, дедуп пунктов,
  покрытие) — следующие шаги.
- `kind`: `definition | fact | relation | formula | procedure`; `salience` —
  доля 0..1 (диапазон проверяет парсер: strict-схема OpenAI не поддерживает
  `minimum`/`maximum`); `splittable` — сигнал «утверждение составное».
- id единицы — `ku:<fragmentId>#<индекс ответа>`: модель не может подменить id
  и создать дубль; дубли id в `KnowledgeMap` — `ArgumentError`.
- Фрагмент = раздел `ContentModel`; в запрос идут только содержательные
  (не мусор, не пустые) блоки; `section_id` модели принимается только для
  известного раздела.
- Ключ кэша включает версию промпта: смена `gen-map-v1` не отдаёт старую карту.
- Кэшируется только **полная** карта (все фрагменты обработаны): иначе
  повторный прогон «запомнил» бы недобор как готовый результат.
- Отмена (`GenerationErrorCode.cancelled`) пробрасывается — прогон обязан
  остановиться, а не продолжиться без фрагмента.
- Ошибки модели не смешиваются с ошибками приложения: `json_parse` /
  `schema_invalid` / `truncated` / `provider_error` — машинные коды причин.

## Ограничения / что осталось

- HTTP-вызовы понимания не подключены: `KnowledgeMapCaller` — контракт; проекция
  схемы `gen-map-v1` в адаптеры провайдеров и `CardGenerationService` — отдельный
  шаг (схема уже strict-совместима, как A8.4).
- Кэш только в памяти; миграция БД — срез 7 (TASK.txt).
- Якоря не проверяются по offsets/тексту блока (только принадлежность блоку
  запроса) — это этап Validation (S5, `quote_offsets.dart`).
- Дедуп единиц нормализацией и пересчёт `salience` по структуре не делаются:
  следующий шаг Understanding (BACKLOG S2 целиком/ADR-050 §2).
- UI/ARB не затрагивались: пользовательских строк срез не добавляет.
