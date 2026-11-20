# Итерация 7.18 — планирование генерации: резюме

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
- Ревью — `review.md` (чек-лист §11, 15 пунктов; high/critical нет, R1/R2
  закрыты с тестами, R3–R10 — L156–L161).

## Ограничения

L154–L161: неполная сверка документации discovery (Anthropic 404, Gemini
redirect, OpenAI/OpenRouter без таблицы), legacy `supports_vision` = assumption,
нативный подсчёт не подключён к конвейеру, UI характеристик только у активного
аккаунта и без ручного ввода лимитов, prompt-only — legacy-планировщик,
recovery без явного ×0.8, нет раскрывающейся «Подробнее» в предпросмотре.
