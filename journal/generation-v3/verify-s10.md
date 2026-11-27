# Verify — срез 10: сквозное включение v3 и правки по решениям владельца

**Дата:** 2026-11-28 · **Ветка:** `main` · **Старт:** `HEAD = 23766df`
(docs среза 9) · **Срез:** `TASK.txt` «Срез 10».
**Толкования:** `journal/QUESTIONS.md` Q22 (решения владельца по Q5, Q13, Q16,
Q17 и «Ограничениям» приоритетнее прежних).

Baseline старта: `flutter test --no-pub --exclude-tags golden` —
**3155 passed + 17 skipped**; `analyze` 0; `dart format` 0 changed.

## 1. Что сделано (по пунктам TASK)

| Пункт | Что | Где | Чем подтверждено |
|---|---|---|---|
| 1 | `ShortfallKind.duplicates` — шестой класс: долг только из-за дублей даёт `duplicates`, а не `validationRejects`; приоритет прогона дополнен | `lib/domain/generation/generation_ledger.dart` | `generation_ledger_test` (6 wire-имён, приоритет), `generation_report_test` («только дубли — duplicates») |
| 2 | `CardVerdict.blocked` + `CardReasonCode.isBlocking` для пяти жёстких кодов; блокированная карточка не удаляется, а живёт в `CardValidationReport.blocked/blockedCards`; в `cards` (импорт) её нет | `lib/api/generation/validation/card_validator.dart` | `card_validator_test` ×6: каждый жёсткий код → `blocked` + вне `cards`, «остальные — warning», отчёт (`blockedCount`) |
| 3 | `quote_ref == null` + единица без якорей → `quoteUnverified` («без источника», warning); `KnowledgeUnitKind.topic` и единица без якорей только для prompt-only; `KnowledgeMap.unanchoredUnitIds` | `card_validator.dart`, `knowledge_map.dart` | `card_validator_test` (2), `generation_v3_facade_flow_test` (prompt-only), `knowledge_map_test` |
| 4 | `ReplenishPolicy.wallClock = max(10 мин, 2 с × requested)`; `ReplenishGuards` (фактические пределы + сработавший) в `ReplenishOutcome.guards` и `GenerationReport.guards` | `replenish_stage.dart`, `generation_report.dart` | `replenish_stage_test` (формула, срабатывание, guards), `generation_report_test` (guards в отчёте) |
| 5 | `GenerationReport.shortfallReasons` — `Map<ShortfallKind,int>`: дубли и валидация своими числами, остаток — причиной остановки; полностью объяснённый остаток не дублируется | `generation_report.dart` | `generation_report_test` ×4 (дубли, валидация+дубли, материал, успех) |
| 6 | Тонкий фасад `GenerationV3Facade`: этапы из портов (Understanding → Allocation → Generation → Validation → Replenish → журнал/импорт → отчёт), без бюджетов/калибровок/recovery | `lib/api/generation/generation_v3_facade.dart` | сквозные тесты §2; `analyze` 0 |
| 7 | Два (и ещё два) сквозных теста без сети: «40 из 40» и «12 из 40 exhausted_material» — от материала до записи в журнал/импорта и `GenerationReport` | `test/integration/generation_v3_facade_flow_test.dart` | 4/4 зелёные |
| 8 | UI: пометка «Без источника» (`generation-mark-no-source`), ARB `generationMarkNoSource`, причина недобора `duplicates` (`generationShortfallDuplicates`) | `generation_preview_screen.dart`, `lib/l10n/app_ru.arb` | `generation_preview_screen_test` (файл зелёный), `analyze` 0, guard `ru_strings_test` |

## 2. Сквозные тесты фасада (п. 7)

`test/integration/generation_v3_facade_flow_test.dart` — без сети, фейковый
`LlmPort`; материал собирается `ContentModelBuilder` из текстового файла:

1. **happy-path «40 из 40»** — заказ 40, 12 единиц материала: `report.requested
   = 40`, `report.accepted = 40`, `report.isComplete`, `shortfallReasons`
   пуст, 40 записей в журнале, `imported = 40`, предохранители в отчёте.
2. **partial «12 из 40 exhausted_material»** — модель отдаёт только основные
   карточки: `accepted = 12`, `reason = exhausted_material`,
   `shortfallReasons = {exhausted_material: 28}`, `isComplete = false`.
3. **blocked-карточка** — английская карточка первого ответа: `blockedCards`
   содержит её, в журнале/колоде её **нет** (`deck.accepted` не содержит
   «moment of force»), добор ставит замену, `report.invalid = 1`.
4. **prompt-only** — тема без файлов: карта из одной `KnowledgeUnit
   kind=topic` без якорей, `unanchoredUnitIds = {ku:prompt#0}`, карточки
   помечены «без источника» и всё равно приняты.

## 3. Красная и зелёная фазы

- Существующие тесты обновлены **под новый контракт** (не ослаблены):

  | Файл | Было | Стало |
  |---|---|---|
  | `card_validator_test` | `latexBroken`, `languageNotRussian`, `quoteOutOfRange → warning` | `unparseableLatex`, `wrongLanguage`, `quoteOutOfRange → blocked` + 8 новых тестов срезa 10 |
  | `replenish_stage_test` | `policy.wallClock == 10 мин` | `wallClock == null` (auto), `wallClockFor(600) = 20 мин`, guards в итоге |
  | `generation_ledger_test` | 5 классов недобора | 6 (с `duplicates`) |
  | `knowledge_map_test` | 5 видов единиц | 6 (с `topic`) |
  | `generation_preview_screen_test` | `scrollTo` искал `find.byType(Scrollable).last` | скролл по ключу `generation-preview-list` (пометка «Без источника» добавила горизонтально прокручиваемую полосу — `.last` попадал в неё) |

- Красная фаза снята `analyze`-ошибками нового контракта
  (`non_exhaustive_switch_expression` для `ShortfallKind.duplicates` и
  `KnowledgeUnitKind.topic`) и падениями старых ожиданий
  (`Expected: warning, Actual: blocked`); затем зелёная.
- Полный прогон: `flutter test --no-pub --coverage --exclude-tags golden` →
  **3174 passed + 17 skipped**, exit 0 (+19 к baseline), покрытие рукописного
  кода **90.4 % (26354/29138)**; `analyze` — **No issues found**;
  `dart format --set-exit-if-changed lib test` — 0 changed (перед этим
  `dart format lib test` — 6 файлов). Лог —
  `journal/generation-v3/green-s10-full.txt`.

## 4. Остаточные ограничения и файлы > 300 строк

1. **Фасад не подключён к production-раннеру.** `GenerationV3Facade` —
   тонкая сборка этапов (§1 п. 6), но `GenerationRunner` по-прежнему
   `GenerationPipeline`: у Understanding нет HTTP-реализации
   `KnowledgeMapCaller`, флаг `generationPipelineV3` выключен, legacy —
   production (Q19/Q21/Q22). «GenerationPipeline = тонкий фасад» выполнено
   **созданием** фасада, а не переписыванием монолита: иначе пришлось бы
   менять путь по умолчанию (протокол §9).
2. **Файлы > 300 строк, оставшиеся осознанно:** `generation_pipeline.dart`
   (2440 — legacy production-путь, удаляется только после default-on флага);
   `replenish_stage.dart` (833 — исполнитель добора с проходами и журналом,
   без второго исполнителя дробить нечего); `card_validator.dart` (731 —
   правила и порядок кодов живут одним списком, это контракт отчёта);
   `generation_v3_facade.dart` — 384 строки: превышение на 28 строк — это
   `_cardJson`/`_validate`/`_persist` (конверт карточки в форму A8.4 и
   журнал запуска), вынесены бы в отдельные файлы при втором потребителе.
3. **Валидация в доборе.** Фасад проверяет и карточки добора, но
   `ReplenishStage` закрывает слот карточкой, которую валидация потом
   заблокирует: слот формально закрыт, а в колоду карточка не попадает
   (в тесте её заменяет следующий проход). Правильное место — `CardGate`
   внутри добора (отдельный срез).
4. **UI из `GenerationReport` (п. 8) — частично.** «Принято N из M» в
   предпросмотре берётся из `CompletionVerdict` (он тоже считается по журналу,
   а не по счётчикам экрана), но не из `GenerationReport`: отчёта нет в
   `GenerationRunResult`, пока фасад не подключён к раннеру. Готовы строки
   ARB, пометка «Без источника» и причина `duplicates`.
5. **Живые прогоны не выполнялись** (`CARDFLOW_LIVE_TESTS=1` — по отдельному
   разрешению владельца); p50/p95 и yield в отчёте — фейковые вызовы.
6. **`ReplenishPolicy.wallClock` — формула, а не измерение.** 2 с на карточку
   не откалиброваны живыми прогонами: константа консервативная.

## 5. Что из S9 работало и что нет

- **Работало:** флаг `generationPipelineV3` (выключен, переключатель в UI),
  `CompletionVerdict` по журналу, метрики, «Почему?» по блокам, пометки
  предпросмотра, общий набор тестов (3155 зелёных на старте).
- **Не работало / выяснилось:** «этапы v3 подключены» — нет, флаг переключал
  только слой завершения (Q19); поэтому срез 10 собирает **отдельный** фасад,
  а не подменяет раннер. `CardVerdict` не умел блокировать, `ShortfallKind` не
  различал дубли, у `wallClock` не было формулы от заказа, `GenerationReport`
  не показывал причины числами — всё это закрыто (§1).
- **Проверено числом:** blocked-карточка не попадает в колоду (тест §2.3:
  в журнале 40 записей, английской карточки нет; после добора `report.invalid
  = 1`); «40 из 40» — `done`/`isComplete`; «12 из 40» — `partial` с числом 28.
