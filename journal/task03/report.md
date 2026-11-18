# TASK 03 — итоговый отчёт (CARDFLOW)

**Дата:** 2026-11-19. **Старт:** `HEAD = e0f8e4b`, `git status --porcelain`
→ только `?? redesign/` (каталог владельца не тронут). **Baseline:**
`fvm flutter test --no-pub --exclude-tags golden` → **2000 passed + 8 skipped**,
`analyze` 0.

## 1. Найденные проблемы

Аудит по фактическому коду — `journal/task03/audit.md`, 27 подтверждённых
дефектов D1–D27. Критичные:

1. **D1** — prompt-only план в production строился без обвязки
   (`GenerationPipeline._buildPlan` → `PromptOnlyPlanner.plan` без `overhead`):
   бюджет не вычитал системный промпт/схему/обёртку, оценка занижалась.
2. **D2** — два независимых построителя prompt-only плана; production не
   использовал `GenerationPlanBuilder.buildPromptOnly`.
3. **D3** — UI считал третью независимую оценку (без схемы, резерва вывода,
   числа запросов) и не показывал «запрошено/достижимо» до запуска.
4. **D4** — не было оценки фактически собранного запроса перед отправкой;
   planner/executor не сравнивались.
5. **D5** — не было калибровки `estimated*` vs `usage`, отсутствие `usage`
   не фиксировалось.
6. **D7** — документные изображения уходили `imageParts` даже без поддержки
   изображений моделью; сервис их молча не отправлял.
7. **D8/D9/D10/D11** — fallback «8 изображений» продублирован в плане и
   сервисе; нет карты источников возможностей; `unknownFields` prompt-only и
   материалов расходятся; дедуп байтов только в сервисе.
8. **D12/D13** — нет компактного состояния prompt-only между запросами; нет
   резерва бюджета под него.
9. **D14** — `truncated` дробил вход раньше сокращения вывода (нарушение F.4).
10. **D15** — бюджет восстановления считался по числу детей, сокращение
    вывода списывало бюджет как дополнительный запрос.
11. **D16** — `Retry-After` терялся на пути к сбою фрагмента.
12. **D17** — при `truncated` и `limit == 1` повтор отправлял тот же запрос,
    шага «поднять резерв вывода» не было.
13. **D18** — `GenerationPlanSplitter` в production не использовал оценщик
    плана/image-модель.
14. **D19** — `context overflow`/413 для фрагмента с `limit == 1` не
    восстанавливались.
15. **D20** — мягкая цель упаковки не учитывала заказ: план занижал
    `achievableCards`, хотя материала хватало.
16. **D22/D23/D24** — нет статуса изображения (передано/каталог/без
    поддержки/исключено); сервис мог тихо отфильтровать часть; unit-id плана
    не связаны с id запроса.
17. **D25** — не было числового поля карточек (L132).
18. **D26/D27** — предпросмотр не показывал частичный успех/fatal постоянно,
    не показывал статус изображений и предупреждения плана.

Остальные подтверждённые пункты (D6, D21 и сопутствующие) — в аудите.

## 2. Исправленные проблемы

| # | Что сделано | Где |
|---|---|---|
| D1/D2 | pipeline строит prompt-only план через `GenerationPlanBuilder.buildPromptOnly`; обвязка (system/schema/wrapper) считается тем же builder-ом | `generation_pipeline.dart`, `generation_plan_builder.dart` |
| D3 | UI строит предпросмотр плана тем же builder-ом (кэш по входам), показывает фрагменты/запросы/запрошено/достижимо и предупреждения; оценка — `plan.estimate.totalTokens` | `generation_screen.dart` |
| D4 | `GenerationRequestEstimator` оценивает фактически собранный `userContent`; `GenerationResult` несёт оценку/версию; тест согласованности плана и запроса | `generation_request_estimator.dart`, `card_generation_service.dart`, `generation_result.dart` |
| D5 | `TokenValue` (exact/estimate/reserve/unknown), `TokenCalibrationSample/Report`, `GenerationRunResult.calibration`, debug-диагностика, явное «без usage» | `token_accounting.dart`, `generation_pipeline.dart`, `generation_diagnostics.dart` |
| D7 | без поддержки изображений моделью документные изображения — `unsupportedModel`/`catalogOnly`, предупреждение `imagesWithoutVision` | `generation_chunk_planner.dart`, `generation_plan.dart` |
| D8/D9 | единый `GenerationRequestLimits` с источником по каждому лимиту; fallback 8/10/24/32 МБ — явное допущение; `capabilitySources` в плане | `generation_request_limits.dart`, `model_capabilities.dart`, planner/service/UI |
| D10 | общий список `unknownFields`/`assumptionFields` для материалов и prompt-only | planner, `prompt_only_planner.dart` |
| D11 | дедуп одинаковых байтов перенесён в план (`documentImageDigest`), сервис фиксирует `skippedDocumentImageIds` | planner, service, `document_image.dart` |
| D12/D13 | `GenerationContinuityState` (до 1200 токенов, 40 карточек/тегов), резерв в prompt-only бюджете, передача в `<wishes>` без изменения исходного текста, восстановление при повторе | `generation_continuity.dart`, `prompt_only_planner.dart`, `generation_pipeline.dart`, `card_generation_service.dart` |
| D14/D17 | порядок F.4: лимит → резерв вывода → дробление; последняя попытка при `limit == 1` делит на две части | `generation_pipeline.dart`, `generation_plan_splitter.dart` |
| D15 | бюджет `generationRecoveryBudget` = max(configured, fragments/8), cap 64; списание по дополнительным запросам; поля результата | `generation_recovery_budget.dart`, `generation_pipeline.dart` |
| D16 | `GenerationChunkFailure.retryAfter`; UI показывает «повторите через N с» | `generation_run.dart`, `generation_pipeline.dart`, preview |
| D18 | `GenerationPlanSplitter.withContext` (оценщик плана + `imageTokens`) | `generation_plan_splitter.dart`, pipeline |
| D19 | `allowLimitOverflow` для context overflow/413/последней попытки | splitter, pipeline |
| D20 | `_tuneSoftTarget` по заказу (ceil(requested/cap), 80 % среднего, ≥ 512 токенов) | `generation_chunk_planner.dart` |
| D22/D23/D24 | `GenerationPlan.images`/`PlannedImage`/статусы; `documentImageParts` — префикс каталога, сервис отправляет ровно его; `sentDocumentImageIds` | `generation_plan.dart`, `generation_request.dart`, `card_generation_service.dart`, pipeline |
| D25 | поле `generation-cards-count` с валидацией и передачей `requestedCards` | `generation_screen.dart`, ARB |
| D26/D27 | постоянные баннеры частичного успеха/fatal, сводка изображений, число запросов восстановления | `generation_preview_screen.dart`, ARB |

## 3. Оставшиеся ограничения

`journal/KNOWN_LIMITATIONS.md` L122–L136: эвристика/калибровка без точного
токенизатора (L122), бюджет восстановления — предохранитель (L128),
приближённый recovery-пересчёт (L129), prompt-only сводка без семантического
дедупа (L130/L136), парсерные пределы (L131), возможности/цены не вводятся в
UI (L133), отброшенные парсером изображения не отчитываются (L134), `usage`
упавших/обрезанных ответов недоступен (L135). Реальные платные API не
вызывались, `redesign/` не изменялся.

## 4. Изменённые файлы

**Новые (lib):** `token_accounting.dart`, `generation_request_limits.dart`,
`generation_continuity.dart`, `generation_recovery_budget.dart`,
`generation_request_estimator.dart`.

**Изменённые (lib):** `generation_pipeline.dart`, `card_generation_service.dart`,
`generation_plan_builder.dart`, `generation_diagnostics.dart`,
`generation_images.dart`, `generation_chunk_planner.dart`,
`generation_plan.dart`, `generation_plan_splitter.dart`,
`generation_request.dart`, `generation_result.dart`, `generation_run.dart`,
`prompt_only_planner.dart`, `model_capabilities.dart`, `document_image.dart`,
`generation_screen.dart`, `generation_preview_screen.dart`,
`lib/l10n/app_ru.arb` (+ generated `app_localizations*.dart`).

**Тесты:** новые `token_accounting_test`, `generation_request_limits_test`,
`generation_continuity_test`, `generation_recovery_budget_test`,
`generation_request_estimator_test`, `generation_plan_images_test`,
`generation_distribution_test`, `generation_pipeline_reliability_test`;
изменены `generation_pipeline_test`, `generation_plan_builder_test`,
`generation_chunk_planner_test`, `generation_plan_splitter_test`,
`card_generation_service_test`, `adaptive_generation_flow_test`,
`generation_screen_test`, `generation_preview_screen_test`,
`test/helpers/generation_plan_fakes.dart`.

**Документация:** `docs/adaptive-generation-architecture.md` (раздел R),
`docs/generation-pipeline.md`, `journal/STATE.md`,
`journal/KNOWN_LIMITATIONS.md`, `journal/task03/audit.md`, этот отчёт.

## 5. Результаты тестов и сборки

- `fvm flutter test --no-pub --exclude-tags golden` → **2110 passed + 8
  skipped** (`All tests passed!`; baseline 2000 + 8, +110 net)
- покрытие рукописного кода → **92.4 % (16193/17529)**
- `fvm flutter analyze --no-pub` → **No issues found!**
- `fvm dart format --set-exit-if-changed lib test integration_test tool` →
  **484 файла / 0 changed**
- `fvm flutter build windows --release --no-pub` → **`cardflow.exe`** (60,8 с)

## 6. Новые коммиты

- `a94357e` — `docs(journal): audit adaptive generation defects for TASK 03`
  (аудит D1–D27).
- `0dc70d3` — `feat(domain): add token accounting, request limits, continuity
  and recovery budget` (доменный фундамент).
- `eb32ef1` — `feat(generation): unify request estimate, image statuses,
  prompt-only continuity and recovery` (планировщик/пайплайн/сервис).
- `8581420` — `feat(ui): add card count field and plan/partial/submodule
  diagnostics` (UI, ARB, локализации).
- `2488d31` — `test(generation): cover token calibration, capabilities,
  continuity, recovery, images, D.5 and UI` (тесты).
- docs-коммит TASK 03 (`docs(generation): record TASK 03 reliability work`) —
  документация, журнал и этот отчёт; присутствует в `git log` после `2488d31`.

Push и deploy **не выполнялись** (условие задания).

## 7. Реальные платные API

Не вызывались: ни одного live-запроса к OpenAI/Gemini/Anthropic/DeepSeek в
этой задаче не выполнялось. Все проверки — unit/widget/integration-тесты на
моках и программных фикстурах.

## 8. `redesign/`

Каталог `redesign/` не читался, не изменялся и не коммитился; в `git status`
он остаётся неотслеживаемым каталогом владельца.
