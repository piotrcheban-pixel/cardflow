# Аудит итерации 7.18 — планирование генерации

**Статус:** фаза 0. Код не менялся: изменены только файлы журнала.
**Дата:** 2026-11-20. **База:** `main`, `HEAD = ab57f17`.
**Задание:** `docs/prompts/iteration-7.18.md`. Возобновление по §1: каталога
`journal/iteration-7.18/` не было → начата фаза 0.

---

## 1. Стартовые факты (вывод команд)

| Команда | Результат |
|---|---|
| `git status --porcelain` | `?? docs/prompts/iteration-7.18.md` (единственный файл — само задание владельца; чужих правок в `lib/`/`test/` нет) |
| `git branch --show-current` | `main` |
| `git log --oneline -5` | `ab57f17 docs(journal): record independent review fixes and dark/360 visual QA`, `5f4565d fix(ui): close independent redesign review findings`, `5af7dd4 refactor(ui): centralize answer feedback colors in theme tokens`, `afc53fc docs(journal): record redesign acceptance, visual QA and limitations`, `854fd82 fix(ui): polish session, statistics and upload-zone visuals` |
| Каталог `journal/iteration-7.18/` | отсутствовал (создан этим аудитом) |

**Сверка с `journal/STATE.md`.** В шапке STATE записана итерация `REDESIGN 2`
(2026-11-19) с фактом старта `HEAD = c50dafe` и коммитами этапов до `0f205a2`;
`HEAD = ab57f17` — на 5 коммитов новее (визуальный QA и независимое ревью
редизайна, `854fd82…ab57f17`). Код этих коммитов — UI/редизайн, планированием
генерации он не занимался. Расхождение зафиксировано здесь; запись в STATE
обновлена отдельной строкой (журнал, не код). Журнала 7.18 до сих пор не было —
итерация начинается с фазы 0.

---

## 2. Baseline

```
fvm flutter test --no-pub --exclude-tags golden
→ 03:55 +2193 ~16: All tests passed!
→ passed 2193 · skipped 16 · failed 0, exit code 0
```
Сводка вывода и хвост лога: `journal/iteration-7.18/baseline-test.txt`.

```
fvm flutter analyze --no-pub
→ No issues found! (ran in 95.3s), exit code 0
```

**Инцидент окружения (подтверждение L64).** Первый запуск
`fvm flutter analyze` (без `--no-pub`) завис: дочерний
`dart pub --directory . get --example` не завершался, `flutter` ждал
`startup lock`. После остановки зависших процессов (это наши процессы
анализа/паба, не чужие) `analyze --no-pub` прошёл за 95,3 с. Правило проекта
«прогоны только с `--no-pub`» действует и для `analyze`.

---

## 3. Что прочитано (по §2.3)

- `AGENTS.md` (полностью, 542 строки), `journal/STATE.md` (шапка + разделы
  REDESIGN 2 / TASK 01–05), `journal/KNOWN_LIMITATIONS.md` (L115–L153),
  `docs/agent-prompt.md`.
- ADR: `ADR-011…ADR-038` (файлы в `docs/decisions/`), в первую очередь
  генерационные ADR-011/012/013/015/020/021/022/023/024/027/029/030/031/037.
- `docs/generation-pipeline.md`, `docs/adaptive-generation-architecture.md`
  (разделы Q/R/S — фактическое состояние TASK 02B-FINAL/03/04).
- Код: `lib/domain/generation/*`, `lib/api/generation/*`,
  `lib/api/providers/*`, `lib/api/http/generation_http_client.dart`,
  `lib/ui/generation/*`, `lib/ui/settings/provider_account_dialogs.dart`,
  `lib/ui/state/app_providers.dart`, `lib/data/generation/*`,
  `test/unit/domain/generation/*`, `test/unit/api/generation/prompt_test.dart`,
  `lib/l10n/app_ru.arb`.

---

## 4. Карта текущей цепочки (с файлами)

```
экран генерации  lib/ui/generation/generation_screen.dart
  поле «Сколько карточек»  key `generation-cards-count` (:1088)
  getter _requestedCards :242–251, валидация :253–267
  предпросмотр плана  _currentPlanPreview :272–305 (тот же GenerationPlanBuilder)
  запуск _generate :548–631 → GenerationRunRequest(requestedCards) :622–631
  GenerationRunner (провайдер) lib/ui/state/app_providers.dart:442–451
    ↓
GenerationRunRequest  lib/domain/generation/generation_run.dart:19
  requestedCards :57; wishes; documents; images; documentImages; account
    ↓
GenerationPipeline.run  lib/api/generation/generation_pipeline.dart:180–262
  _buildPlan :265–292: requested = request.requestedCards ?? requestedCardCount(wishes)
  GenerationPlanBuilder  lib/api/generation/generation_plan_builder.dart:120–160
    overhead = системный промпт + канон-схема + обёртка (:138–151)
    inventoryOf → ContentInventory (:62–109)
      ↓ GenerationChunkPlanner.plan (materials) / PromptOnlyPlanner (prompt-only)
    lib/domain/generation/generation_chunk_planner.dart:167/190
      _prepareBudget :676–718  (GenerationBudget.compute, limit = _limitTarget)
      _tuneSoftTarget :732–757
      _pack :870, _splitToBudget/_hardSplit :1481/:1585
      _mergeToRequested :1816–1837, _mergePair :1904
      _distributeLimits :2092–2126
    lib/domain/generation/prompt_only_planner.dart (тема без материалов)
    lib/domain/generation/generation_budget.dart
      GenerationBudget.compute; budgetOutputCapTokens :43–52;
      budgetCardsPerRequestCap :60–72
    lib/domain/generation/content_token_estimator.dart (текст 2,5 симв./токен,
      изображения 750 px/токен или 256 байт/токен)
    ↓ GenerationPlan (chunks = PlannedChunk, budget, estimate, images, omitted)
    lib/domain/generation/generation_plan.dart:610
    ↓
CardGenerationService  lib/api/generation/card_generation_service.dart:157–193
  wishes + continuation → <wishes> (:160–161, :517–520)
  buildGenerationUserContent  lib/api/generation/generation_prompt.dart:12–54
  оценка собранного запроса  lib/api/generation/generation_request_estimator.dart
    ↓ адаптеры  lib/api/providers/{openai,openai_compatible,anthropic,gemini}_adapter.dart
    ↓ HTTP  lib/api/http/generation_http_client.dart (RetryPolicy, RedactingLogInterceptor)
    ↓ разбор  cards_json_extractor.dart → card_response_schema.dart (поштучно)
    ↓ валидатор  card_content_validator.dart (мягкие пометки)
    ↓ дедуп  generation_pipeline.dart:1217–1281 (contentHashOf, только точный)
    ↓ восстановление  generation_pipeline.dart:766–880 + generation_plan_splitter.dart
    ↓ generation_jobs (chunk_count/tokens_used/error_code), GenerationRunResult
    ↓ предпросмотр  lib/ui/generation/generation_preview_screen.dart (requested/achievable
      :438–465, изображения :395–402, повтор упавших :176–204)
    ↓ импорт  DriftGenerationCardStore (media + media_json)
```

---

## 5. Ответы на вопросы §2.5

### 5.1 Откуда сейчас берутся числа

| Величина | Источник в коде | Значение/поведение |
|---|---|---|
| окно контекста | **только** `ProviderPresetModel.contextTokens` через `resolveModelCapabilities` (`lib/domain/generation/model_capabilities.dart:242`); каталог — `provider_preset.dart:96–300` | 1 000 000 / 128 000 / 200 000 / 1 048 576 / 131 072 / 32 768 / 8 000 — статические числа пресетов **без `sourceRef` и даты**. У каталога нет полей «источник/дата проверки» (`ProviderPresetModel`, `provider_preset.dart:10–44`). `ProviderAccount.contextTokens` — legacy-поле JSON, по умолчанию `kCustomProviderContextTokens = 16000` (`provider_account.dart:21,37`), **окном не считается** (`model_capabilities.dart:230–234`); осталось ради обратной совместимости и копируется каталогом в `fromPreset` (`provider_account.dart:64`) и в `_requestAccount` (`generation_screen.dart:191–195`). |
| максимальный вход | `ModelCapabilities.maxInputTokens` (`model_capabilities.dart:120`) | **всегда `null`**: `resolveModelCapabilities` его не заполняет (нет поля в аккаунте/пресете) → ограничение не применяется. |
| максимальный выход | `account.maxOutputTokens` (JSON v2, `provider_account.dart:40,99`), иначе `budgetOutputCapTokens` (`generation_budget.dart:43–52`) | Известен лимит — он; иначе `kBudgetDefaultOutputCapTokens = 8192` (`:32`), но не больше половины окна; окно неизвестно → `kBudgetUnknownContextOutputCapTokens = 2048` (`:76`). Поле в UI не редактируется (в `provider_account_dialogs.dart` есть только Vision, :496–515). |
| лимит тела запроса | `account.maxRequestBytes` (JSON v2) через `resolveGenerationRequestLimits` (`generation_request_limits.dart:92–140`) | Иначе — допущения `GenerationChunkPlannerConfig` (`generation_chunk_planner.dart:70–73`): 8 image-частей, 10 МБ на изображение, 24 МБ изображений на запрос, 32 МБ тело. Источник помечается `CapabilitySource.unknown` → предупреждение `assumedImageLimits`. |
| `supportsVision` | `account.supportsVision` (JSON v2) → иначе пресет модели → иначе **инференс по имени** `inferSupportsVisionFromModelId` (`provider_account.dart:291–319`: `gpt-4o`, `gpt-4.1`, `gpt-5`, `claude`, `gemini`, `flash`, `vision`, `llava`, `vl`) | UI при смене модели сам ставит переключатель по имени (`provider_account_dialogs.dart:496–498`), а `_requestAccount` **перекрывает** сохранённый флаг флагом каталога (`generation_screen.dart:194`). |
| цены | `account.pricing` (JSON v2, `generation_pricing.dart:26–100`, USD за 1M input/output) | Иначе `null`; в каталоге пресетов цен нет. |
| запас/коэффициенты | `generation_budget.dart`: per-card output `1024` (:23), JSON-конверт `16` (:26), минимальный рабочий вход `512` (:79), запас `5 %` / мин `256` (:82,:85), байт тела на токен `4` (:93), вход при неизвестном окне `6000` (:73) | Все — **допущения приложения**, не подтверждённые характеристики провайдера. |

Discovery-эндпоинтов нет: каталога `lib/api/models/` не существует, `GET /models`
нигде не вызывается (`grep` по `lib/api` даёт только пути генерации
`/chat/completions`, `/v1/messages`, `/v1beta/models/{model}:generateContent`).
`ApiKeyVerifier` делает минимальный **генерационный** запрос, а не discovery.

### 5.2 Почему неизвестная модель получает число; где инференс по имени

- Окно неизвестно → `BudgetSource.assumption` (`generation_budget.dart:238`)
  и бюджет материалов `kBudgetUnknownContextInputTokens = 6000` (`:73`), вывод
  `2048` (`:76`). UI показывает общее предупреждение `unknownCapabilities`
  (`app_ru.arb:1359`), но не отдельное «размер контекста не подтверждён».
- Инференс по имени: `inferSupportsVisionFromModelId`
  (`provider_account.dart:304–319`) используется при чтении legacy-аккаунта
  (`:291–298`) и в UI-диалоге (`provider_account_dialogs.dart:496–498`); модель
  `foo-128k` контекст из имени не выводит (`resolveModelCapabilities` смотрит
  только каталог), но Vision — выводит. Это прямо противоречит §3.1 задания
  (инференс должен стать `assumption` с меткой в UI).

### 5.3 Что заставляет дробить и что искусственно уменьшает части

**Дробление (объективное):** бюджет входа `D.1`
(`generation_budget.dart`, `GenerationBudget.compute`):
`inputBudget = context − reservedOutput − fixedOverhead − safetyMargin`, где
`reservedOutput = min(outputCap, limit × 1024 + 16)`, `fixedOverhead =` промпт +
схема + обёртка + каталог + изображения, `safetyMargin = max(256, 5 % окна)`;
при неизвестном окне — плоские 6000. Плюс лимит тела (`bodyBytes`, см. 5.7) и
лимит image-частей/байт.

**Искусственные ограничения, уменьшающие части и/или зависящие от заказа:**

1. **Бюджет входа зависит от количества карточек.** `_limitTarget =
   max(1, min(requested, cardsByOutputCap))` (`generation_chunk_planner.dart:679–680`),
   и этот лимит передаётся в `GenerationBudget.compute(limit: _limitTarget)`
   (`:695–704`). Больше заказ → больше резерв вывода → меньше бюджет входа →
   больше фрагментов. Для нового требования T4 («разбиение не зависит от
   заказа») это прямое нарушение.
2. **Мягкая цель «6000 токенов материала на карточку»** —
   `softTargetMaterialTokensPerCard = 6000` (`generation_chunk_planner.dart:68`),
   `_softTarget = min(contentAllowance, _limitTarget × 6000)` (`:713–717`) и
   `_tuneSoftTarget` (`:732–757`), который пересчитывает цель от `requested`.
   Это продуктовое «не платить за 1M контекста», а не лимит модели; оно режет
   материал на части задолго до исчерпания окна.
3. **Пер-карточный резерв 1024 токена** (`generation_budget.dart:23`) —
   завышенный резерв вывода дополнительно уменьшает вход.
4. **`maxCardsPerRequest` никогда не заполняется** → потолок партии считается
   только из output cap (`budgetCardsPerRequestCap`, `:60–72`); лимит модели
   «сколько карточек в ответе» не используется.
5. **Предохранители** `maxChunks = 512`, `maxSplitDepth = 3`
   (`generation_chunk_planner.dart:75–76`) — технические, не лимиты модели.
6. **Один фрагмент = один запрос**: число запросов жёстко равно числу
   фрагментов; отдельного «сколько карточек просить в одном ответе» нет.
7. **`_mergeToRequested`** укрупняет фрагменты, пока их число больше **числа
   карточек** (`:1817–1818`) — сравнение карточек с фрагментами само по себе
   искусственно.

### 5.4 Как распределяются карточки; continuity/digest

- `_distributeLimits` (`generation_chunk_planner.dart:2092–2126`): каждому
  фрагменту минимум 1, остаток раздаётся по кругу в порядке убывания **объёма
  материала** фрагмента (`chunk.volume`), потолок — `_cardsByOutputCap`. Это
  water-filling по размеру текста, **не по смысловой насыщенности разделов**;
  единицы распределения — фрагменты, а не разделы.
- Разделов плана как сущности нет: `PlannedChunk.units` — плоские `UnitSpan`
  (`generation_plan.dart:52–78`), `section_id` в ответе модели отсутствует
  (схема `card_json_schema.dart` — поля `front/back/card_type/image/...`, без
  `section_id`; корень — `{cards}` без `source_exhausted`, `:23–79`).
- **Continuity/digest есть только для prompt-only**: `GenerationContinuityState`
  (`generation_continuity.dart:40`, ≤1200 токенов, 40 карточек, 40 тегов)
  добавляется в `<wishes>` (`generation_request.dart:57–59`;
  `card_generation_service.dart:160–161,517–520; generation_pipeline.dart:424–431,472`).
  Для материаловых запусков сводки уже созданных карточек нет, `<focus>` нет —
  модель не знает, что уже создано, и может повторять темы.
- Дедупликация — только точный `contentHashOf` прямой/обратный
  (`lib/domain/cards/content_hash.dart:15`; `generation_pipeline.dart:1217–1281`);
  почти-дублей по триграммам нет.

### 5.5 Поле количества карточек (до итерации)

| Свойство | Факт |
|---|---|
| Где | `generation_screen.dart:1088`, `key: ValueKey('generation-cards-count')` (TextField, цифровая клавиатура, подпись/подсказка из ARB `generationCardsCountLabel/Hint`) |
| Разбор | `_requestedCards` (`:242–251`): `BigInt.tryParse`, ≤0 и не-число → `null` (значит «не задано»), > `int.max` → `int.max` |
| Валидация | `_cardCountInvalid` (`:253–259`), `_cardCountTooLarge` (`:261–267`); в `_generate` блокируют запуск с ARB `generationCardsCountInvalid/TooLarge` (`:551–558`) |
| По умолчанию | пусто → `null` → `requestedCardCount(wishes)` (`generation_card_limit.dart:29`), т. е. прежний разбор «N карточек» из пожеланий; режима «авто» как переключателя нет |
| Максимум | `kMaxRepresentableRequestedCards = int.max` (`generation_card_limit.dart:20`) — технический предел представления, не продуктовый; невыполнимость — `tooManyChunks`/`requestedAbovePlan` (`generation_plan.dart:183–197`) |
| Путь значения | `GenerationRunRequest.requestedCards` (`generation_run.dart:26,57`) → `_buildPlan` (`pipeline:265–292`) → `GenerationPlanBuilder.build/buildPromptOnly` (`:120/:167`) → `_prepareBudget` (`chunk_planner:679–680`), `_distributeLimits` (`:2092`) → `PlannedChunk.limit` (`generation_plan.dart:407`) → `<limit>` (`generation_prompt.dart:44`) |
| Prompt-only | `PromptOnlyRequest.requestedCards` → `PromptOnlyPlanner`; число запросов `ceil(requested/cap)`, сумма лимитов = заказ (Q.3) |
| Предпросмотр | «запрошено/достижимо»: экран `generation_screen.dart:1322–1336`, предупреждения `:1339–1383`; результат `generation_preview_screen.dart:438–465` |
| «Повторить неудавшиеся» | `pipeline.retryFailed` (`:329–386`) берёт `previous.plan`, `failure.plannedChunk` (`:358–361`) — лимит и заказ сохраняются, повтор их не пересчитывает |
| Пробел | нет карточки «План генерации» с подробностями: только одна строка `generation-plan-preview` (`:1206–1212`) и предупреждения; нет источника/даты лимитов, точности оценки, частей/партий, стоимости, блока «Подробнее» |

### 5.6 Сообщение пользователя

`buildGenerationUserContent` (`generation_prompt.dart:12–54`) собирает
`<materials>…</materials>`, `<wishes>…</wishes>`, `<limit>N</limit>`,
`<images>…</images>` — именно в таком порядке, пустой блок пишется одной строкой
(`<materials></materials>`, `<images></images>`). В `<materials>` каждый файл
начинается со строки `Файл: <имя>` (`generation_chunk_planner.dart:49,1269–1274`),
заголовки разделов и стабильные `section_id` **не передаются**; `<outline>`,
`<task>`, `<focus>`, `<context_only>`, `<already_created>` отсутствуют.
Неизменного префикса, общего для нескольких запросов, нет: `<limit>` стоит до
`<images>` и меняется от запроса к запросу, а материалы разных фрагментов
различны — кэширование префикса сейчас невозможно.

Системный промпт — `gen-ru-v7` (`lib/api/prompts/system_prompt.dart:15,328–329`
= v6 + блок «ИЗОБРАЖЕНИЯ ИЗ PDF И СКАНОВ», ADR-037), дословная копия
`docs/prompts/gen-ru-v7.txt`, сверка байт — `test/unit/api/generation/prompt_test.dart:125–130`.

### 5.7 `requestBytes` и классификация переполнения

- План считает **тело фрагмента**: `textBytes + catalogBytes +
  base64(imageParts) + labelBytes + jsonBodyOverheadBytes(1024)`
  (`generation_chunk_planner.dart:1783–1788`, пересчёт при укрупнении
  `:2013–2018`), сравнивает с `_payloadLimit` (`:693`) и отказывает/помечает
  `omittedPayload` (`:1343–1350,1418`). После JSON-кодирования адаптером байты
  повторно не измеряются; сервис оценивает только токены
  (`generation_request_estimator.dart`).
- Классификация ошибок — `generation_http_client.dart:284–310`:
  HTTP **413** → `payloadTooLarge`; HTTP **400** с regex
  `_contextOverflowPattern` (`:318–325`: `context length|context window|
  context_length_exceeded|maximum context|too many tokens|prompt is too long|
  input is too long|request (is )?too large|exceeds the maximum|превышает…контекст|
  слишком длинн`) → `contextOverflow`; прочие 400 → `badRequest` без переплана.
  Пайплайн делит вход только для `contextOverflow`/`payloadTooLarge`
  (`generation_pipeline.dart:818–819,873–874`). Regex один на все протоколы (а
  не паттерны по протоколам), и он включает `request too large`, из-за чего
  часть «payload» 400 приходит как `contextOverflow`.

---

## 6. Таблица соответствия «понятие задания → реальный класс»

| Понятие | Существует? | Класс/файл | Что делать |
|---|---|---|---|
| `ModelLimits`, `Sourced<T>`, `ContextSemantics` | частично | `ModelCapabilities` (`model_capabilities.dart:78`) — nullable-поля + групповые источники (`contextSource/outputSource/imageSource/pricingSource`, `:160–180`) | расширить: `Sourced<T>` на каждое поле, `sourceRef`/`observedAt`, `ContextSemantics`, `isReasoningModel`; заполнять `maxInputTokens` |
| `CapabilitySource` | да, набор другой | `CapabilitySource{verified,preset,user,inferred,unknown}` (`:16–40`) | привести к `{userConfigured,providerApi,officialCatalog,assumption,unknown}` с миграцией wire-значений JSON (`provider_account.dart:183,234–236`) |
| `ContentInventory`/`ContentUnit` | да | `ContentInventory` (`content_unit.dart:417`), `DocumentUnit` (`:265`), `SectionUnit` (`:217`), `TextPiece` (`:81`), `ImageRef` (`:133`), `AttachmentUnit` (`:349`) | расширить: плотность/ёмкость раздела, статусы единиц, ошибки парсинга в inventory |
| `GenerationPlan` | да | `GenerationPlan` (`generation_plan.dart:610`), `PlannedChunk` (`:306`), `GenerationEstimate` (`:482`) | расширить: `inputStrategy`, части входа, партии, `focus`, покрытие `planned/generated/accepted` |
| `InputPlanner` | частично | `GenerationChunkPlanner` (`generation_chunk_planner.dart:167`), `PromptOnlyPlanner`, `GenerationPlanSplitter` | выделить стратегию whole-document-first и предварительную проверку всего запроса |
| `CardAllocator` | **нет** | inline `_distributeLimits` (`chunk_planner:2092`) | создать чистый доменный класс: плотность, вес, ёмкость, water-filling |
| `OutputBatchPlanner` | **нет** | «фрагмент = запрос» | создать: `cardsPerBatch`, сбалансированные партии, `focus`, независимость от числа частей |
| `RequestEstimator` | да | `GenerationPlanBuilder` (обвязка `:138–151`), `GenerationRequestEstimator` (фактический запрос), `ContentTokenEstimator` | перенастроить на формулы §3.4 (P/D/m, `tokensFor/cardsFor`), добавить нативный `count_tokens` для Anthropic/Gemini |
| `ContinuityState` | частично | `GenerationContinuityState` (`generation_continuity.dart:40`) — prompt-only | расширить на материаловые whole-запуски: `<already_created>` ≤5 % входа |
| Калибровка токенов | частично | `TokenCalibrationSample/Report` (`token_accounting.dart`) — только в памяти запуска; `tpc` = 1024 фикс. | создать store `generation.calibration` v1 в `app_settings`, `tokensPerCard` EMA после ≥2 замеров |
| Discovery | **нет** | — | порт `ModelCapabilityDiscovery` в domain + резолверы `lib/api/models/` + кэш `generation.model_capabilities` v1 |

---

## 7. Находки (основа отчёта A)

1. **Характеристики модели не имеют происхождения.** Окно — статическое число
   пресета без `sourceRef`/даты; `maxInputTokens` не заполняется; `maxOutput`
   и лимиты тела/изображений задаются только вручную и в UI не редактируются;
   discovery отсутствует. У каждого поля нет ни источника, ни даты проверки.
2. **Инференс по имени.** `supportsVision` выводится из имени модели
   (`provider_account.dart:304–319`) и автоматически ставится в UI
   (`provider_account_dialogs.dart:496–498`); при запросе флаг каталога
   перекрывает пользовательский (`generation_screen.dart:194`).
3. **Вход дробится из-за заказа карточек** (`_limitTarget` → бюджет, `:679–704`)
   и **из-за продуктовой мягкой цели 6000 токенов материала на карточку**
   (`:68,713–717,732–757`). Целый документ никогда не проверяется целиком:
   экономия резерва вывода вместо дробления не реализована.
4. **Распределение карточек — по объёму текста фрагмента**, а не по смысловой
   насыщенности разделов (`:2092–2126`); разделов как единиц распределения нет.
5. **Один фрагмент = один запрос**: число запросов не выводится из бюджета
   вывода независимо; целый документ нельзя обслужить несколькими партиями с
   `focus`; балансировки партий (15/15/14×5) нет.
6. **Нет continuity для материалов**: сводка уже созданных карточек есть только
   в prompt-only (`generation_continuity.dart`, `generation_request.dart:57–59`);
   повтор тем между запросами не предотвращается.
7. **Промпт и схема не описывают новый контракт**: нет `<outline>`, `<task>`,
   `<focus>`, `<context_only>`, `<already_created>`, `section_id`,
   `source_exhausted`; сообщение (`generation_prompt.dart:12–54`) переставляет
   `<limit>` перед `<images>` и не имеет стабильного префикса.
8. **Восстановление без классификации по протоколам**: один regex на 400
   (`generation_http_client.dart:318–325`), нет отмены оставшихся партий при
   `source_exhausted`/недоборе (<50 %), нет однократного перераспределения
   недостачи, лимита «≤3 операций на запрос / ≤max(3, M/2) на запуск».
9. **Калибровка не сохраняется**: `TokenCalibrationReport` живёт в памяти
   запуска; `tokensPerCard` фиксирован 1024, а не EMA по `usage`
   (`generation_budget.dart:23`).
10. **Дедупликация только точная** (`content_hash.dart:15`): почти-дубли по
    триграммам не отсеиваются.
11. **UI**: поле количества есть и работает, но предпросмотр плана — одна
    строка; нет подробностей (модель, источники лимитов, точность оценки,
    части/партии, статусы изображений, стоимость «Подробнее»); в настройках
    модели нет ручного ввода контекста/выхода, источника и даты, кнопки
    «Обновить характеристики»/«Сбросить к автоматическому».
12. **Нативный подсчёт токенов не используется**: оценки — эвристика
    2,5 симв./токен (`token_estimator.dart:15–20`), изображения 750 px/токен
    или 256 байт/токен (`content_token_estimator.dart:28,34`); `count_tokens`
    Anthropic/Gemini не вызывается.

---

## 8. Противоречия задания с фактическим кодом (решения — в ADR)

1. **`gen-ru-v7` уже занят.** В репозитории есть промпт `gen-ru-v7`
   (`system_prompt.dart:15,328–329`; `docs/prompts/gen-ru-v7.txt`; ADR-037, L76)
   и тесты, которые требуют `promptVersion == 'gen-ru-v7'`
   (`prompt_test.dart:125–130`, интеграционные тесты). Задание требует «новую
   версию — `gen-ru-v7`, файлы v5 и v6 сохраняются». Решение: новый
   планировочный промпт — **`gen-ru-v8`**; v5/v6/v7 остаются в коде и в
   `docs/prompts/` с прежними байт-в-байт тестами; тесты `promptVersion`
   обновляются на v8 (это не ослабление: контракт версии становится строже —
   добавляется новый тест v8). Фиксируется в ADR-040.
2. **Резерв вывода на карточку.** Сейчас `tokensPerCard = 1024`
   (`generation_budget.dart:23`) с обоснованием «front ≤500, back ≤2000 символов»;
   §3.4 задания задаёт `tokensPerCard = 300` и числа T1–T8, которые сходятся
   только с 300 (например, T2: `cardsFor(8192) = 22`). Решение: следовать §3.4
   (`tokensPerCard` — параметр `GenerationPlanningConfig` с калибровкой; 300 —
   начальное значение), а расхождение с консервативным 1024 объяснить в
   ADR-040: 300 — *средняя* карточка, а хвост больших карточек покрывается
   `outputFill = 0.85` и восстановлением `truncated` (уменьшение партии).
3. **«Один и тот же объект `GenerationPlan`».** Сейчас предпросмотр строит
   план тем же `GenerationPlanBuilder`, но **второй раз**
   (`generation_screen.dart:272–305`), а конвейер — свой
   (`generation_pipeline.dart:216`). Решение: план строится один раз и
   передаётся в конвейер из того же места (общий кэш/объект), либо план
   неизменяемо кэшируется по ключу входов, а конвейер принимает его как
   аргумент. Проверка — тест «один объект/один сборщик».
4. **Семантика бюджета.** Текущая D.1 (окно − резерв − обвязка − запас 5 %)
   заменяется формулами §3.4 (`inputTokens = ceil((P+D)(1+m))`, раздельные
   ограничения total/maxInput/выход/байты). Это меняет числа и требует
   осознанного обновления тестов `generation_budget_test.dart`,
   `generation_chunk_planner_test.dart`, `generation_distribution_test.dart`
   (не ослабление: новые числа — контракт T1–T9).
5. **`maxCardsPerRequest`** — сейчас всегда `null`; новые данные discovery
   смогут его заполнять, но до подтверждения провайдером остаётся `null`
   (источник `unknown`), а `batchCardsCeiling = 40` — явное допущение.
6. **Поле количества карточек** — уже существует (`generation-cards-count`),
   новые поля не создаются; технический максимум остаётся `int.max`
   (`kMaxRepresentableRequestedCards`), потому что продуктовая обрезка запрещена
   (§8 задания, «нет тихого обрезания»). В ADR-040 — обоснование.

---

## 9. План и номера ADR (предложение; код не менялся)

**Следующие свободные ADR:** последний в `docs/decisions/` — ADR-038
(`ADR-038-design-system-v2.md`), значит:

- **ADR-039 — «Discovery и происхождение характеристик модели»**:
  `Sourced<T>`, `CapabilitySource{userConfigured,providerApi,officialCatalog,assumption,unknown}`,
  `ContextSemantics`, `ModelLimits`; порт `ModelCapabilityDiscovery` с
  резолвером на протокол (OpenAI-compatible/DeepSeek/Groq/Moonshot/OpenRouter,
  Anthropic, Gemini, Ollama, generic без доверия полям); кэш
  `generation.model_capabilities` v1 в `app_settings` (ключ
  `accountId+protocol+baseUrl+modelId`, TTL 7 дней, `lastErrorCode`/`lastAttemptAt`,
  инвалидация по смене ключа/baseUrl/modelId, без значений ключей и хэшей);
  миграция legacy (`preset` → `officialCatalog` только при `sourceRef`+дате,
  иначе `assumption`; `inferred` Vision → `assumption` с меткой в UI).
- **ADR-040 — «Whole-document-first, распределение карточек, партии, gen-ru-v8»**:
  `GenerationPlanningConfig{tokensPerCard=300(+EMA), outputFill=0.85,
  schemaOverhead=200, minBatchCards=5, batchCardsCeiling=40, margin 0.03/0.10}`;
  `InputStrategy{promptOnly,wholeDocument,fragmented}`; формулы
  `tokensFor/cardsFor/desiredOutput`, `R = min(maxOutput, tokensFor(ceiling))`
  не зависит от заказа; `CardAllocator` (density/capacity/water-filling,
  столбец «запрошено/достижимо»); `OutputBatchPlanner` (партии независимо от
  частей, `focus`, балансировка); `gen-ru-v8` (`<materials>/<images>/<outline>/
  <wishes>` + изменяемый `<task>` с `<part>/<focus>/<cards>/<context_only>/
  <already_created>`), схема с `section_id` + `source_exhausted`, терпимый
  разбор v5–v8; покрытие `planned/generated/accepted`, `source_exhausted` и
  недобор <50 % → отмена оставшихся партий и однократное перераспределение;
  дедуп + почти-дубли (триграммы ≥0.85); восстановление (truncated → та же
  партия с половиной карточек; 413/распознанный 400 → переплан ×0.8; лимиты
  ≤3 на запрос, ≤max(3, M/2) на запуск); калибровка `generation.calibration` v1
  (EMA `completion_tokens/принятые карточки`, после ≥2 замеров); prompt
  version bump v7 → v8 и сохранение v5/v6/v7.

**Фазы** (по §4 задания, с воротами):

| Фаза | Содержание | Ворота |
|---|---|---|
| 0 | аудит (этот файл), baseline, STATE | `docs: аудит итерации 7.18` |
| 1 | ADR-039, ADR-040, `plan.md`, red-тесты domain §5.1–5.3 | тесты красные с assertion-выводом, коммит `test:` |
| 2 | domain: `Sourced`/`ModelLimits`/слияние, бюджет §3.4, InputPlanner whole-first, CardAllocator, OutputBatchPlanner, новый план (prompt-only через тот же интерфейс) | domain-тесты зелёные; `architecture_test` (domain без Flutter) |
| 3 | discovery-резолверы + фикстуры `test/fixtures/discovery/<provider>/*.json`, кэш, миграция legacy, инвалидация, нативный count_tokens | mock-HTTP/фикстуры зелёные |
| 4 | `gen-ru-v8`: промпт, сборщик префикса/хвоста, схема+проекции, разбор v5–v8, `cache_control` Anthropic | байтовая сверка промпта, тесты адаптеров |
| 5 | конвейер: выполнение плана, focus, дайджест, исчерпание, перераспределение, покрытие, дедуп, восстановление, калибровка, jobs | интеграционный тест на production-проводке (`app_providers`) с fake-транспортом |
| 6 | UI: поле количества (уже есть), карточка плана + «Подробнее», настройки модели, ARB | widget-тесты (`scrollUntilVisible`) |
| 7 | ревью на неизменяемом снимке → fix-коммиты с тестами → §6 ворота → документация → push → CI | все ворота §6 |

**Новые файлы (предварительно):** `lib/domain/generation/model_limits.dart`,
`generation_planning_config.dart`, `input_planner.dart`, `card_allocator.dart`,
`output_batch_planner.dart`, `model_capability_discovery.dart`;
`lib/api/models/{discovery_resolvers,discovery_result,ollama_discovery}.dart`;
`lib/data/generation/{drift_model_capability_cache,drift_token_calibration_store}.dart`;
`docs/generation-planning.md`; `docs/prompts/gen-ru-v8.txt`.

**Новые ключи `app_settings`:** `generation.model_capabilities` (v1),
`generation.calibration` (v1) — схема БД и `schemaVersion` не меняются.

---

## 10. Что не проверено на фазе 0

- Документация провайдеров не сверялась с сетью (это фаза 3): веб-доступ в
  сессии есть (`web_fetch` вернул официальную страницу DeepSeek, HTTP 200),
  поэтому сверка возможна, URL и даты будут записаны в ADR-039.
- Числа T1–T9 ещё не проверены кодом (это red-тесты фазы 1).
- Живые API-запросы запрещены заданием (§0.6) — не выполнялись и не будут.
