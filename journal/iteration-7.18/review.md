# Ревью итерации 7.18 (снимок `ddc0946`, HEAD после fix-коммита)

Ревью проведено Lead-агентом по чек-листу §11 задания на неизменяемом снимке
`ddc0946` (после коммита fix по стабильным id изображений). Независимый
reviewer в сессии недоступен (L35), поэтому дополнительно прогонялись
guard-тесты, полный набор и целевые проверки формул/границ.

## Чек-лист §11

| # | Пункт | Статус | Подтверждение |
|---|---|---|---|
| 1 | Три решения независимы: Input Planner, Card Allocator, Output Batch Planner | ✅ | `InputPlanner.plan` не принимает `requestedCards`; `planning_independence_test.dart` (заказ 1/10/100/500 → одинаковая стратегия и части); `GenerationChunkPlanner` — фасад |
| 2 | План опирается на реальные характеристики с происхождением, без догадок по имени | ✅ | `Sourced<T>` + `CapabilitySource`; `resolveModelLimits` (пользователь > API > каталог > допущение > unknown); `inferred` Vision → assumption; `ModelLimits` не содержит «типовых» чисел |
| 3 | Discovery: документированные поля, политики, ошибки не стирают кэш; план без сети | ✅ | `model_discovery.dart` (idsOnly/documented, OpenRouter min(context), Anthropic after_id, Gemini pageToken, Ollama show); 12 тестов; `ModelCapabilityService.refresh` сохраняет прежнее значение при ошибке; pipeline читает только кэш |
| 4 | Whole-document-first и формулы §3.4 | ✅ | T1–T9: whole, fragmented `Dmax`, inputOnly, unknown context, границы `53363/53364`; `InputPlan.strategy` объясняет выбор |
| 5 | Заказ карточек распределяется по содержанию без «20 на фрагмент» | ✅ | `SectionFeatures`/water-filling/largest remainder; `card_allocator_test.dart`; achievableCards не режется клампом |
| 6 | Prompt v8: фокус, части, дайджест, схема `section_id`/`source_exhausted`, разбор v5–v8 | ✅ | `systemPromptGenRuV8` + байтовый тест; `buildGenerationUserContent` стабильный префикс; канон `{cards, source_exhausted}`; локальная терпимая схема; `GeneratedCard.sectionId` |
| 7 | Исчерпание и однократное перераспределение | ✅ | `source_exhausted`/недобор < 50 % → фокус сокращается, полностью исчерпанные партии пропускаются; одна доп. партия в `generation_pipeline_v8_test` |
| 8 | Дедуп `content_hash` + почти-дубли ≥ 0.85 | ✅ | `_acceptCard` (обратный хеш для reversed, триграммы Jaccard; короткие стороны — только хеш); тест «почти-дубли» |
| 9 | Восстановление и лимиты попыток | ⚠️ | truncated/413/400 → только проблемная партия (`GenerationPlanSplitter`, глубина ≤3), бюджет `generationRecoveryBudget`; полный «переплан ×0.8» не реализован — L160 |
| 10 | Калибровка и `generation_jobs` | ✅ | `generation.calibration` v1, EMA после ≥2 замеров, один замер на прогон; `chunk_count` = части входа, `tokens_used` факт; тесты store + pipeline |
| 11 | Промпт-сборка: стабильный префикс, включая изображения | ✅ | После fix: display-id `img1…` назначаются один раз по плану, `documentImages` по id, `documentImageParts` — явные части; тест префикса с изображениями |
| 12 | UI: план/«Подробнее», источники/даты, обновить/сбросить, итог | ⚠️ | Сводка плана и предупреждения есть; блок «Характеристики модели» (источник/дата, refresh/reset) + ARB + 3 widget-теста; отдельной «Подробнее» со стратегией нет — L161; ручные поля лимитов — L157 |
| 13 | Тесты: red→green, независимость, без ослабления | ✅ | Red-фаза `f191375` (assertion-level); 27 planning, 20 chunk planner, 14 batches, 12 discovery, 9 resolver, 7 cache, 5 counter, 4 service, 7 calibration, 5 pipeline v8; guard-тесты зелёные |
| 14 | Инварианты: ключи/логи/БД/сеть/SPEC | ✅ | Ключи только `ApiKeyStore`; discovery без тел в логах; JSON v1 в `app_settings`, `schemaVersion` не менялся; живых запросов нет (mock/fixtures); `SPEC.md` не редактировался |
| 15 | Документация и гейты | ✅ | ADR-039/040, `docs/generation-planning.md`, `system-prompt.md`, `api-schema.md`, KNOWN_LIMITATIONS L154–L161, plan.md; analyze/format/coverage/build — `verify.md` |

## Находки ревью

| # | Severity | Находка | Действие |
|---|---|---|---|
| R1 | **medium** | При изображениях в нескольких партиях `withCatalogIds` перенумеровывал id в каждой партии: `<images>` и `image_id` менялись между запросами, префикс не кэшировался | **Исправлено** `ddc0946`: стабильная карта id по плану, явные `documentImageParts` по id (legacy-префикс без id сохранён), каталог по id; тест префикса с изображениями |
| R2 | **medium** | Калибровка писалась отдельной записью на каждую партию (N перезаписей `app_settings` за прогон) | **Исправлено** `ddc0946`: один агрегированный замер на прогон (суммарный usage / принятые карточки) |
| R3 | medium | Нативный `count_tokens` (Anthropic/Gemini) и `exactInputTokens` не подключены к конвейеру — план всегда `estimated` | Открыто, L156; контракт и тесты готовы, подключение требует асинхронной сборки плана |
| R4 | medium | Prompt-only production использует старый `PromptOnlyPlanner` (7 карточек/запрос), не общий Output Batch Planner | Открыто, L159; общая машинерия умеет `allowPromptOnly` и покрыта тестом |
| R5 | low | Recovery после overflow — splitter по единицам, а не «переплан ×0.8» | Открыто, L160 (вне объёма итерации) |
| R6 | low | Нет раскрывающейся карточки «Подробнее» (стратегия/части/партии) в предпросмотре | Открыто, L161 |
| R7 | low | UI характеристик только у активного аккаунта, без ручного ввода лимитов | Открыто, L157 (осознанный объём) |
| R8 | low | `providerApi`-значение требует `sourceRef`; при будущем discovery без ссылки возможен assert | Задокументировано контрактом `Sourced`; discovery всегда передаёт sourceRef/дату |
| R9 | low | Дайджест `already_created` усечён (20×80) и может не отражать все темы при длинном запуске | Осознанный лимит ≤5 %; дубли дополнительно отсекаются хешем/триграммами |
| R10 | low | `ModelCapabilitySection` даёт дату только при `observedAt` (у каталога её нет) | Честно показывается источник без даты |

High/critical находок нет. R1/R2 закрыты fix-коммитом с новым тестом; R3–R10
зафиксированы в `journal/KNOWN_LIMITATIONS.md` как осознанные ограничения с
условиями снятия.

## Итог

Итерация 7.18 закрывает три независимых решения, происхождение характеристик
модели, discovery/кэш, whole-document-first, распределение карточек, партии и
стабильный префикс сообщения, исчерпание/перераспределение, дедуп и
калибровку. Открытые medium (R3/R4) не блокируют поведение по умолчанию:
план остаётся консервативным (`estimated`, вопрос-только путь legacy), но
честно помечен в документации и ограничениях.
