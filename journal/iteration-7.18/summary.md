# Итерация 7.18.1 — закрытие остатков 7.18 (2026-11-21)

**Задача:** не переписывать работающую архитектуру, а закрыть обязательные
требования `docs/prompts/iteration-7.18.md`, оставшиеся неизвестными: prompt-only
на общей машинерии (§0.11), нативный подсчёт токенов (§3.5), recovery ×0.8
(§3.9), ручные характеристики модели (§3.10), «Подробнее» плана (§3.10) и
сверка discovery (§3.3).

**Старт:** `git status --porcelain` → пусто; `HEAD = origin/main = d66b0ff`;
baseline `fvm flutter test --no-pub --exclude-tags golden` →
**2256 passed + 16 skipped**, `analyze` 0.

**Найдено при аудите (не отражено в отчёте 7.18):**
- production-сервис и builder по умолчанию слали **`gen-ru-v7`**, хотя версия
  задания/`generation_jobs` — `gen-ru-v8`: контракт `<focus>/<part>/<section_id>`
  модель не получала (high);
- `requestBytes` не включал текст каталога `<images>` (medium);
- recovery менял только ярлык стратегии: части/focus/`partCount` оставались от
  wholeDocument (medium);
- «Сбросить к автоматическому» терял явно заданный Vision пользовательской
  модели (medium);
- «Подробнее» брало лимиты исходного аккаунта, а не выбранной модели (medium).

## Сделано (сначала red-assertions, затем минимальная реализация)

| Пункт | Реализация | Коммит |
|---|---|---|
| 2.1 prompt-only на общей машинерии | `GenerationPlanBuilder.buildPromptOnly` → `GenerationChunkPlanner` (InputPlanner → OutputBatchPlanner); старый `PromptOnlyPlanner` удалён; тема — в обвязке каждого запроса, распределения по разделам нет; `GenerationPlan.partCount(prompt-only)=1` | `4072f4e` |
| v8 в production | `CardGenerationService` и builder по умолчанию — `systemPromptGenRuV8`; тест production-пути | `e30562a` |
| 2.2 нативный count_tokens | `RequestTokenCounter.supports` + `ProtocolRequestTokenCounter`; один подсчёт на план, `ExactTokenCountCache` по sha256 содержимого, ошибка → оценка; `InputAccuracy`/`inputTokenSource` в `InputPlan`; Anthropic `tools`, Gemini `generationConfig`; `<part>1 из 0</part>` убран | `c007328` |
| 2.3 recovery ×0.8 | `GenerationPlanSplitter.splitToBudget`; 413/подтверждённый 400 → части ≤ `min(0.8×бюджет, 0.8×фрагмент)`; whole→fragmented с реальными `InputPlan.parts`/focus; остальные партии части делятся заранее; ≤3 операций на запрос; прочие 400/401/403 — без переплана | `0e72b61`, `bd99ace` |
| 2.4 характеристики модели | `ProviderAccount.maxInputTokens`/`capabilitiesConfiguredAt` (JSON v2); `withConfiguredCapabilities` → `userConfigured` + дата; резолвер отдаёт дату сохранения; UI «Изменить» (контекст/вход/выход), пусто = авто, ошибка без обрезки; сброс | `c646c61` |
| 2.5 «Подробнее» и один план | `GenerationPlanDetails` (модель, источники/дата, точность входа, стратегия, части/партии/запросы, изображения, токены, стоимость, неизвестные лимиты); `buildRunPlan` — единая точка для конвейера и предпросмотра; `generationPlanBuilderFor` с калибровкой; лимиты предпросмотра из кэша discovery | `39ade40` |
| 3 discovery | Сверка по официальной документации 2026-11-21; DeepSeek `input_modalities`, Anthropic `capabilities.image_input/pdf_input`, Moonshot `supports_image_in/supports_reasoning`, Ollama семантика `unknown` (было ошибочно total); ADR-039 §6a, `docs/generation-planning.md` §9 | `0e42437`, `5c19856` |
| Ревью-фиксы | каталог в `requestBytes`/`bodyBytes`, реальные части recovery, Vision при сбросе, лимиты выбранной модели, ARB без латиницы | `6b374d7`, `419b625`, `9f42da6`, `bd99ace`, `50ca263` |

**Новые тесты (+46 net, 0 ослаблений):**

- `test/unit/domain/generation/prompt_only_unified_test.dart` (7) — общий
  контракт prompt-only.
- `test/integration/generation_exact_tokens_test.dart` (5) — один подсчёт,
  кэш, деградация к оценке, OpenAI без подсчёта, тела не в диагностике.
- `test/unit/api/generation/request_token_counter_test.dart` +3 (schema, supports/router).
- `test/unit/domain/generation/generation_plan_splitter_budget_test.dart` (4).
- `test/integration/generation_overflow_replan_test.dart` (6) — 413/400,
  обычные 400/401, сохранение карточек, лимит операций, реальные части/focus.
- `test/unit/domain/generation/model_capability_settings_test.dart` (6) —
  JSON, приоритет userConfigured, дата, сброс, Vision.
- `test/widget/settings/model_capability_section_test.dart` +3, экран
  провайдеров +1 (применение ручных значений).
- `test/widget/generation/generation_plan_details_test.dart` (3),
  `generation_screen_test.dart` +2 (кэшевые лимиты в предпросмотре/«Подробнее»,
  смена модели).
- `test/unit/api/models/model_discovery_test.dart` +5 (документированные поля,
  Ollama-семантика, `foo-128k`).
- `test/unit/domain/generation/input_plan_payload_bytes_test.dart` (3) —
  каталог в `requestBytes` и `bodyBytes`.
- В production-тест генерации добавлена проверка `gen-ru-v8`.

**Гейты (2026-11-21):** `gen-l10n` — ок; `dart format` **542/0**;
`analyze` — **No issues found**; полный набор
`fvm flutter test --no-pub --coverage --exclude-tags golden` →
**2302 passed + 16 skipped + 0 failed** (baseline 2256+16);
покрытие **91.7 % (19433/21185)**, порог 80 пройден;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (65,8 с);
`integration_test/session_smoke_windows_test.dart -d windows --no-pub` →
**All tests passed!** (11 с).

**Ограничения:** L154 (частично), L155, L158, L162–L173. Схема БД и
`schemaVersion` не менялись; `SPEC.md` не редактировался; живых API-запросов не
было.

---

# Итерация 7.18 — планирование генерации (7.18, историческая запись)

**Задача:** планировать генерацию по реальным характеристикам модели с
происхождением каждого числа, по фактическому размеру запроса и по заказанному
числу карточек; три решения независимы (вход / распределение / партии).

## Сделано

- **ADR-039 — происхождение характеристик и discovery.** `Sourced<T>` +
  `CapabilitySource` (пользователь/API/каталог/допущение/неизвестно),
  `ModelLimits`, слоистый `resolveModelLimits` с миграцией legacy (контекст
  пресета не считается пользовательским; `inferred` Vision → assumption;
  явный `vision_configured`). Discovery по протоколам (OpenAI-совместимые с
  политиками idsOnly/documented, OpenRouter min(context)/цены, Anthropic
  after_id, Gemini pageToken, Ollama tags+show) с машинными кодами ошибок и
  mock-тестами; кэш `generation.model_capabilities` v1 (TTL 7 дней,
  инвалидация, без ключей/хэшей); `ModelCapabilityService` (refresh не стирает
  последнее значение). Нативный `count_tokens` Anthropic/Gemini + exact-путь в
  `InputPlanner`/`RequestBudget` (подключение к конвейеру — L156).
- **ADR-040 — whole-document-first, распределение, партии.** `InputPlanner`
  (whole/fragmented/attachments, `Dmax`, границы T9, без зависимости от
  заказа), `CardAllocator` (плотность/вес/ёмкость, water-filling, largest
  remainder), `OutputBatchPlanner` (focus-группы, сбалансированные партии,
  `maxCardsPerRequest`). `GenerationChunkPlanner` — тонкий фасад;
  `GenerationPlan` получил `inputPlan`/`allocation`; `PlanValidity` —
  предупреждения `contextUnconfirmed`/`payloadLimited`.
- **`gen-ru-v8`** (v5–v7 сохранены): блок планирования, хвост `<task>`
  (`part/focus/cards/context_only/already_created`), `section_id`,
  `source_exhausted`; сообщение — стабильный префикс
  `materials → images → outline → wishes`; схема `{cards, source_exhausted}`
  с терпимым чтением v5–v7; display-id изображений и каталог стабильны между
  партиями.
- **Конвейер:** focus/part/already_created/outline в запросах; исчерпание
  разделов и однократное перераспределение недостачи; почти-дубли (триграммы
  ≥ 0.85); калибровка `generation.calibration` v1 (один замер на прогон, EMA
  после ≥2); `generation_jobs.chunk_count` = части входа; debug-сводка плана.
- **UI:** блок «Характеристики модели» у активного аккаунта — контекст/вывод/
  изображения с источником и датой, «Обновить характеристики» и «Сбросить к
  автоматическому» (ARB, widget-тесты). Сводка плана/предупреждения и итог
  прогона в предпросмотре существовали и сохранены.

## Доказательства

- Коммиты: `759ae31`, `2873957` (аудит), `bea6283` (ADR/план), `04534ba`
  (provenance), `f191375` (red-тесты), `5517c8e` (домен), `f729378`
  (discovery/кэш), `25ab407` (v8/схема), `efb5926` (конвейер), `7a3dcbd` (UI),
  `ddc0946` (fix id изображений/калибровка).
- Red-фаза с assertion-level выводом — `journal/iteration-7.18/red-output.md`.
- Гейты — `verify.md`: **2256 passed + 16 skipped**, analyze 0, format 533/0,
  покрытие **91.7 %**, Windows release — `cardflow.exe`.
- CI: push `ab57f17..f5f6fe1`, run [44819862886](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44819862886) — **9/9 job success**.`n- Ревью — `review.md` (чек-лист §11, 15 пунктов; high/critical нет, R1/R2
  закрыты с тестами, R3–R10 — L156–L161).

## Ограничения

L154–L161: неполная сверка документации discovery (Anthropic 404, Gemini
redirect, OpenAI/OpenRouter без таблицы), legacy `supports_vision` = assumption,
нативный подсчёт не подключён к конвейеру, UI характеристик только у активного
аккаунта и без ручного ввода лимитов, prompt-only — legacy-планировщик,
recovery без явного ×0.8, нет раскрывающейся «Подробнее» в предпросмотре.
