# TASK 05 — план управляемых испытаний A–C

**Дата:** 2026-11-19. **Статус:** подготовлено, **не запускалось**.
Любой запуск — только после отдельного подтверждения владельца.

## 1. Условия запуска

По умолчанию запросы запрещены: тег `live`, `CARDFLOW_LIVE_TESTS` не задан,
`maxRequests = 0`, `maxCost = 0`. Обычный `flutter test` и CI остаются
офлайновыми (проверено: `test/live --tags live` → 16 skipped, 0 запросов).

Точная команда для PowerShell (ключ читается из Windows User scope и
передаётся только дочернему процессу; значение не печатать — L30):

```powershell
$key = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY','User')
if ([string]::IsNullOrWhiteSpace($key)) { throw 'DEEPSEEK_API_KEY отсутствует' }

$env:CARDFLOW_LIVE_TESTS = '1'
$env:CARDFLOW_LIVE_PROVIDER = 'deepseek'
$env:CARDFLOW_LIVE_MODEL = 'deepseek-flash'
$env:CARDFLOW_LIVE_MAX_REQUESTS = '20'
$env:CARDFLOW_LIVE_MAX_COST_USD = '0.12'
$env:CARDFLOW_LIVE_ENABLE_PROMPT_ONLY = '1'
$env:CARDFLOW_LIVE_ENABLE_MATERIALS = '1'
$env:CARDFLOW_LIVE_SCENARIOS = 'prompt_only_short,prompt_only_many_40,small_document'
$env:CARDFLOW_LIVE_REPORT = 'build/live/task05-a-c.jsonl'
$env:DEEPSEEK_API_KEY = $key

fvm flutter test test/live/adaptive_generation_live_test.dart --tags live --no-pub

Remove-Item Env:DEEPSEEK_API_KEY
```

Запускаются только включённые сценарии: A и B (`ENABLE_PROMPT_ONLY`), C
(`ENABLE_MATERIALS`). D/E не включаются, `ENABLE_IMAGES`/`ENABLE_RECOVERY`
не задаются. Бюджеты **общие на файл**: A+B+C делят 20 логических запросов,
40 HTTP-обменов, 160 физических попыток и $0.12.

Остановка: `Ctrl+C`; повторный запуск — новые бюджеты (новый процесс), это
учитывать вручную.

## 2. TEST A — простая prompt-only генерация (5 карточек)

**Вход:** тема «Круговорот воды в природе…» (`kLiveTopicShort`), короткие
пожелания, `requestedCards = 5`, стандартная схема A8.4 / промпт `gen-ru-v7`.
**Ожидаемо:** 1 логический запрос, 2 HTTP-обмена (strict 400 → tolerant 200),
5 карточек или меньше; `status = done`; `usage` есть; `plan.isPromptOnly`.

Проверяется:

1. `PromptOnlyPlanner`/`GenerationPlanBuilder.buildPromptOnly` — план до
   первого запроса, 1 фрагмент, лимит 5.
2. Бюджет: `plan.estimate`, logical/HTTP/cost guard.
3. Production `OpenAiCompatibleAdapter` + `CardGenerationService` +
   `GenerationPipeline` (не тестовая упрощённая реализация).
4. HTTP-ответ, `usage`, разбор JSON, локальная схема A8.4, контентные правила.
5. `result.status`, `failures`, `rejectedCards`, дедуп.
6. Preview: `result.cards` — те же данные, что показывает предпросмотр.
7. Importability: каждая карточка проходит `CardDraft.validate()` (та же
   проверка, что в предпросмотре перед импортом). Фактическая запись в
   drift-БД — офлайновый `generation_flow_test.dart`; live-тест БД не трогает.
8. Качество: авто-метрики (`LiveCardQualityReport`) + ручная рубрика 8
   критериев из §5.

**Частичный успех:** если карточек меньше 5 — это не автоматически «ошибка
HTTP», а результат провайдера/парсинга. Тест печатает `shortfall`; причина
разбирается по `result.failures`, `rejectedCards`, `status`. `status = partial`
и непустые `failures` не считаются успехом.

## 3. TEST B — prompt-only continuity (40 карточек)

**Вход:** одна тема статики, `requestedCards = 40`, пожелания «без повторов».
**Ожидаемо:** 6 логических запросов по 7 карточек, 12 HTTP-обменов,
`plan.chunks.length = 6`, сумма лимитов = 40, continuity-блок со второго
запроса.

Проверяется:

1. План делит заказ на 6 фрагментов без клампа и без потери лимитов.
2. `GenerationContinuityState`: `harness.calls.first.hasContinuation == false`,
   у всех последующих `hasContinuation == true` (тексты не сохраняются —
   только длины/факт блока).
3. Ранее созданные карточки остаются в `result.cards`; при падении фрагмента
   успешные не теряются (`partial`).
4. Дедуп `contentHashOf`: 0 дублей; смысловые повторы — ручная проверка.
5. Общий бюджет: 6 логических ≤ 20, 12 HTTP ≤ 40, cost guard ≤ $0.12.
6. Partial: если часть фрагментов упала, `status = partial`, `failures`
   перечислены; тест не должен выдавать это за `done`.
7. Preview/importability — как в Test A.

**Критерий:** ≥ 20 карточек (половина заказа) как технический health-check;
целевые 40 — предмет ручной оценки. Меньшее число фиксируется как shortfall,
а не маскируется.

## 4. TEST C — небольшой текстовый документ (6 карточек)

**Вход:** `liveSmallDocumentParsed()` — программная DOCX-фикстура проходит
production `DocxParser` (реальное извлечение текста и заголовков), 3 раздела
(Heading1): испарение, конденсация, осадки; `requestedCards = 6`.

Проверяется:

1. Извлечение текста `DocxParser` и границы 3 разделов.
2. `ContentInventory`: документ → разделы → единицы.
3. `GenerationPlan`: `isPromptOnly = false`, 1 фрагмент, `omitted` пуст.
4. Adaptive chunk planning и input/output budgets.
5. Связи `doc:<файл>#<раздел>#<номер>` в `PlannedChunk.units`; `materialsText`
   содержит все три смысловых блока.
6. Запрос по `PlannedChunk`, ответ, парсинг, схема, валидатор.
7. Соответствие карточек материалу — вручную по рубрике §5, включая
   покрытие документа, сохранение важных фактов, корректность связей,
   отсутствие неподтверждённых утверждений.
8. Preview/importability — как в Test A.

**Критерий:** карточки опираются на факты документа, не теряют
систематически важные сведения и не выдумывают отсутствующее. Один успешный
HTTP 200 не считается доказательством.

## 5. Ручная оценка качества (не подменяется JSON-валидом)

Для каждой карточки — 0/1/2 по 8 критериям (`LiveCardCriterion`):

| Критерий | Что означает |
|---|---|
| фактическая корректность | утверждения верны |
| релевантность | соответствует теме/материалу |
| полнота | покрывает существенную часть факта |
| ясность | формулировка понятна |
| образовательная ценность | карточка учит, а не пересказывает |
| отвечаемость | на вопрос есть однозначный ответ |
| отсутствие дублей | нет смыслового повтора |
| привязка к источнику | для Test C — факт из документа |

Для Test C дополнительно (`LiveDocumentAssessment`): покрытие документа,
сохранение важных фактов, корректность связей с разделами, наличие
неподтверждённых утверждений. `null` — критерий не оценён (не 0).

Итог: `LiveScenarioAssessment.toMarkdown()` → файл в
`journal/task05/results/`; вердикт «принято / доработка» ставит человек.

Отдельно фиксируются:

- **технический успех** — HTTP, парсинг, схема, `status`;
- **структурная корректность** — обязательные поля, лимиты, дедуп;
- **содержательное качество** — рубрика выше.

## 6. Что проверяется офлайн, а что живым прогоном

| Проверка | Где |
|---|---|
| Планы A/B/C, число запросов, лимиты, стоимость | `test/unit/live/live_task05_readiness_test.dart` (офлайн) |
| Бюджеты logical/HTTP/attempts/cost guard | `test/unit/live/live_infrastructure_test.dart` (офлайн) |
| Секреты/редакция | `live_infrastructure_test.dart`, `test/unit/api/http/redaction_test.dart` |
| Recovery 413/429/400/5xx/битый JSON/truncated | `test/integration/generation_recovery_http_test.dart` (loopback) |
| Preview/import в drift-БД | `test/integration/generation_flow_test.dart` (офлайн) |
| Реальный endpoint, usage, карточки, continuity, документ | только A–C live после разрешения |

## 7. Артефакты прогона

- `build/live/task05-a-c.jsonl` — числа, цены, стоимость, счётчики, ошибки
  (без материалов/ключей);
- `journal/task05/results/<date>-<scenario>.md` — таблицы авто-метрик и
  ручной рубрики, вердикт, найденные дефекты;
- при сбое — `status`, `failures`, `providerReason` (очищенная причина),
  `Retry-After`, счётчики бюджета; тела запросов не сохраняются.

## 8. Границы

- Test D/E в TASK 05 **не запускаются** (отдельное разрешение и смета).
- Негативные живые контракты (401/403/429) на реальном ключе не
  провоцируются — ADR-014; транспорт покрыт офлайн Test F.
- Ручная приёмка GUI (клики/скриншоты) остаётся за владельцем (L78).
