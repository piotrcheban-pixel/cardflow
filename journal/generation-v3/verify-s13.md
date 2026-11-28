# Verify — срез 13: Dedup в цепи, стоимость Understanding, честная база сравнения

**Срез:** `TASK.txt` «Срез 13. Dedup в цепи, стоимость Understanding, честная
база сравнения». Толкования — `journal/QUESTIONS.md` Q25; пересчёт матрицы —
`journal/generation-v3/live-s12/matrix-s13.md` (из существующего `matrix.jsonl`,
без платных прогонов).

**Факты старта:** ветка `main`, `HEAD = 92943da`; baseline (срез 12) —
3214 passed + 18 skipped, покрытие 90,4 %, схема БД v2, флаг
`generationPipelineV3` выключен.

## 1. Что сделано (по пунктам TASK)

| Пункт | Сделано | Где | Чем подтверждено |
|---|---|---|---|
| 1.1 Dedup в фасаде | Этап Dedup между валидацией/добором и отчётом/импортом: существующий `SemanticMatcher` (каскад S6) по принятым прогона **и** целевой колоде. Новых правил нет | `generation_v3_facade.dart` (`_dedup`), `dedup_mark.dart` (порт загрузки колоды/записи пометок), `generation_v3_path.dart`, `app_providers.dart` (`deckCards` из `DriftCardRepository.cardsByDeck`) | `generation_v3_facade_flow_test`: «3 известные пары помечены своими уровнями, не удалены», «пара „уже в колоде“ ловится до импорта» (`events == ['dedup', 'import']`) |
| 1.2 Дубль не удаляется | Карточка получает `CardIssueCode.possibleDuplicate` (чип предпросмотра «Возможный дубль») и `CardReasonCode.possibleDuplicate` (отчёт/`cleanRate`/ARB-текст); `DedupReport` — в итоге прогона, `duplicatesByLevel` — в отчёте, `duplicateRate` — в `MetricsCollector` | `generated_card.dart`, `card_reason_code.dart`, `generation_report.dart`, `generation_preview_screen.dart`, `app_ru.arb` (`generationReasonPossibleDuplicate`) | `generation_v3_facade_flow_test`: принято 8 из 8, помечено 6, `duplicateRate = 6/8`, `cleanRate = 2/8`, уровни exact/normalized/semantic по 1 паре; `previewMarks` показывает чип |
| 1.3 Персист `DedupReport` (L219) | Схема **v3**: `card_drafts.is_duplicate_of` + `dedup_level` (nullable), миграция 2 → 3 (`addColumn`), `DriftGenerationRunStore.saveDedupMarks` (UPDATE по `run_id + content_hash`), `GenerationRunSnapshot.dedup` восстанавливает пары, импорт пометки не теряет | `tables.dart`, `app_database.dart`, `drift_generation_run_store.dart`, `generation_run_snapshot.dart` | `schema_migration_v2_test` (1 → 3 и 2 → 3, данные и NULL-пометки), `migration_test` (dump v3, onCreate/dump v3), `schema_test` (колонки и schemaVersion = 3), `drift_generation_run_store_test` (2 теста: перезапуск, одинаковое содержимое), `drift_run_import_test` («импорт не теряет пометки») |
| 2.5 Probe один раз на прогон | `SchemaCompatProfile` (ключ провайдер + модель + схема): первая `400` на strict-схему запоминается, следующие разделы идут сразу без strict | `schema_compat_profile.dart`, `http_knowledge_map_caller.dart`, `cards_batch_port.dart`, `generation_v3_path.dart` (один профиль на `run`) | `http_knowledge_map_caller_test`: **12 разделов → 13 запросов** (было 24), strict-вариант ровно 1; `schema_compat_profile_test` |
| 2.6 Та же проба для батчей карточек | `AdapterCardsBatchPort` принимает общий профиль; probe — один раз на прогон | `cards_batch_port.dart` | `cards_batch_port_test`: **10 батчей → 11 запросов** (было 20), strict ровно 1 |
| 3.8 Честная база | `cleanRate` = принято без пометок / **произведено**; `duplicateRate` — тоже к произведённому; `duplicateMarked` в отчёте; чистые правила ячеек — `matrix_comparison.dart` (20/40 нерешающие, 80/150/300 решающие) | `generation_report.dart`, `metrics_collector.dart`, `matrix_comparison.dart` | `generation_report_test` (1/2), `metrics_collector_test` (8/14 вместо 10/10), `matrix_comparison_test` (9) |
| 3.9 Пересчёт матрицы | Скрипт читает существующий `live-s12/matrix.jsonl`, пишет `matrix-s13.md`: cleanRate по новой базе, колонка «было», метки «нерешающая», вердикт только по 80/150/300, разбор partial | `tool/recompute_matrix_s13.dart`, `live-s12/matrix-s13.md` | запуск `dart run tool/recompute_matrix_s13.dart` — файл создан из существующих run-файлов (новых платных прогонов 0) |
| 4.10 188/300 на статье | Ответ числом: остановка `complete`, не `max_passes` и не `exhausted_material` — 188 различимых слотов (`unit_id + angle`), ещё 112 карточек плана повторяют занятые; при полном наборе углов 188 / 4 = 47 единиц | `matrix-s13.md` §«Разбор partial», L229 | cell матрицы: `stage = ready`, `accepted = 188`, `generated = 189`; `_stageOf` даёт `ready` только при `reason == complete` |

## 2. Стоимость Understanding: числа «до → после»

Офлайн-измерение транспорта (счётчик HTTP-обменов в тестах, без платных
вызовов). «До» — лестница ADR-021 на каждом запросе; «после» — проба один раз
на прогон.

| Что | До (срез 12) | После (срез 13) | На 10 единиц |
|---|---:|---:|---:|
| Understanding, 12 разделов | 24 запроса (2 на раздел) | **13** (1 проба + 12) | 24 → **10,83** на 10 разделов |
| Generation, 10 батчей по 1 карточке | 20 запросов (2 на батч) | **11** (1 проба + 10) | 20 → **11** на 10 карточек |
| Формула на батч/раздел | 2 на каждый | 1 + одна проба на прогон | — |

Тесты-доказательства: `http_knowledge_map_caller_test` («12 разделов = 13
запросов»), `cards_batch_port_test` («10 батчей = 11 запросов»).
Цифры после лечения: `GenerationReport.understandingRequests` (считаются все
HTTP-обмены: `KnowledgeMapRawResponse.attempts`) и `requests` отчёта.

## 3. Пересчёт матрицы (часть 3)

`live-s12/matrix-s13.md`, источник — существующие 20 ячеек `matrix.jsonl`;
**новых платных прогонов для пересчёта 0**.

| Материал | Заказ | legacy cleanRate (к generated) | v3 cleanRate (к generated) | Решающая | Вердикт |
|---|---:|---:|---:|---|---|
| учебный текст | 80 | 100,0 % | 100,0 % | да | v3 не хуже |
| учебный текст | 150 | 100,0 % | 100,0 % | да | v3 не хуже |
| учебный текст | 300 | 98,6 % (73/74) | 97,3 % (292/300) | да | **v3 хуже** |
| статья | 80 | 100,0 % | 100,0 % | да | v3 не хуже |
| статья | 150 | 100,0 % | 100,0 % | да | v3 не хуже |
| статья | 300 | 100,0 % (15/15) | 97,9 % (185/189) | да | **v3 хуже** |

- Сравнено решающих пар: **6**, v3 хуже на **2** → строгий критерий cleanRate
  не выполнен, флаг остаётся выключенным.
- Ячейки 20 и 40 помечены «нерешающая (n мал)»: на базе к произведённым у
  legacy 40 учебного стало 97,6 % (40/41, один дубль), у v3 — 100 % (40/40);
  разница 2,4 п.п. при знаменателе 41 не решает ничего.
- Знаменатель у путей один по смыслу (`generated`), но не равен по величине:
  у legacy на больших заказах accepted 15–73, у v3 — 150–299; это исход
  выполнения заказа, а не качество карточки, и подписано в таблице.

## 4. Partial на 300 (часть 4)

**Статья, заказ 300, путь v3:** `stage = ready`, принято **188**, произведено
189, `unfilledSlots = 0`. В `ReplenishStage._stageOf` к `ready` ведёт только
`ReplenishStopReason.complete`, поэтому ответ: **ни `exhausted_material`, ни
`max_passes`** — остановка `complete` по слотам. Различимых слотов
(`unit_id + angle`) было **188**; заказ просил 300 карточек, и **112** заявок
плана указывали на уже занятые слоты (у единицы не больше 4 углов; 188 / 4 = 47
единиц при полном наборе). Это не «тугой предохранитель», а повтор слотов в
плане — зафиксировано L229; менять аллокацию/пороги в этом срезе TASK запретил.

Тот же эффект у учебного 300: 299 слотов, 1 карточка плана повторяет занятый
slot; у статьи 40: 35 слотов, 5 повторов.

## 5. Красная и зелёная фазы, гейты

Красная фаза — `journal/generation-v3/red-s13.txt`: падения assertion-level на
DoD-тестах до реализации (`Expected: <13> Actual: <12>`, `Expected: an object
with length of <5> Actual: [4 марки]`, миграция 2 → 3 «нет колонки»).

**Гейты (2026-11-28):**
- `flutter analyze --no-pub lib test tool` → **No issues found!**;
- `dart format --set-exit-if-changed lib test` → **0 changed** (725 files);
- `flutter test --no-pub --coverage --exclude-tags golden` →
  **3234 passed + 18 skipped**, `exit 0` (+20 к baseline 3214 + 18); guards
  (`ru_strings`, `architecture`, `no_webview`, `no_secrets`, `contrast`,
  `ci_pdfium`) — зелёные в полном прогоне;
- покрытие рукописного кода **90,9 % (27019/29740)** при пороге 80 %
  (`coverage-s13.txt`, `green-s13-full.txt`);
- миграция БД проверена `SchemaVerifier`: 1 → 3 и 2 → 3, данные и NULL-пометки
  (`schema_migration_v2_test`), dump v3 = onCreate (`migration_test`).

DoD среза по пунктам TASK: Dedup вызывается из фасада и доказан сквозным тестом
на фикстуре 3 пар; `duplicateRate` v3 непустой и разложен по уровням;
Understanding 12 разделов — 13 запросов вместо 24; пересчитанная таблица
(`matrix-s13.md`) использует один знаменатель и помечает нерешающие ячейки;
analyze 0, format 0 changed, полный набор зелёный, покрытие ≥80 %, guards
зелёные.

## 6. Остаточные ограничения (осознанные)

1. `SchemaCompatProfile` не персистится между запусками (L227): следующий
   прогон платит одну пробу, а не 12.
2. Dedup сверяет только стороны текста (L228): тип/разметка/картинки не
   участвуют — это следует из контракта `SemanticMatcher` S6.
3. План заказа допускает повтор слотов сверх 4 на единицу (L229) — отсюда
   `ready` при `accepted < requested`; честный `partial` ставит вердикт.
4. Живая матрица не перемерялась: пересчёт из существующих файлов (TASK п. 9).
   Все живые числа — про `deepseek / deepseek-flash` (L222).
5. Мультифайл и source_file по-прежнему не в матрице (S11, Q23).
