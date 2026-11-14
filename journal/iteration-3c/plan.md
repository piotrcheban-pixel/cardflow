# Итерация 3c — «Экран генерации». План (шаг 1)

**Дата:** 2026-11-14 · **Режим:** `ИТЕРАЦИИ` · **Ветка:** `main` · **HEAD на старте:** `3878777`
(дерево clean; `3878777` — docs-коммит ADR-014, кода не менял)
**Baseline:** `fvm flutter test --exclude-tags golden` → **800 passed + 1 skipped** (live-тест DeepSeek
self-skip без ключа); `fvm flutter analyze` → No issues; `fvm dart format --set-exit-if-changed lib test`
→ 0 changed. Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2), Windows 11.
**Цель SPEC B2/A6.8, A8.5, A8.6:** вертикальный срез «Генерация карточек» поверх готового слоя 3b:
прикрепление файлов (picker + drag-n-drop на ПК), пожелания, провайдер/модель, локальная оценка токенов,
чанкинг по бюджету модели, последовательные вызовы с прогрессом и отменой, дробление обрезанного
фрагмента, дедупликация, предпросмотр с чекбоксами и инлайн-редактированием, импорт одной транзакцией,
`generation_jobs` на каждом шаге, частичный успех и повтор неудавшихся фрагментов, входы с экранов
«Колоды» и «Колода».

Граница с 3b: каноническая схема, адаптеры, retry/backoff, redaction, `ApiKeyStore`,
`CardGenerationService` **не переписываются** — 3c вызывает их как есть. Новый код — вокруг:
оценка/чанкинг, пайплайн, задания, импорт, экран, входы.

## Критерии приёмки итерации (SPEC)

| # | Критерий | Источник | Проверка |
|---|---|---|---|
| C1 | Локальная оценка объёма в токенах до отправки; «Примерно N токенов»; бюджет модели = контекст − резерв ответа − промпт; предупреждение при превышении порога | A8.5 шаг 4, A8.6, A6.8 | unit-тесты `TokenEstimator`/бюджета + widget-тест оценки на экране |
| C2 | Чанкинг по границам разделов `ParsedDocument` (заголовки/слайды/листы) с запасом под ответ; слишком большой раздел делится по абзацам/жёстко; `<limit>` на фрагмент ограничивает ответ | A8.5 шаг 5, A8.1 | unit-тесты чанкера: упаковка, порядок, отсутствие потерь текста, oversized-раздел, лимит карточек |
| C3 | Зона прикрепления: picker (множественный выбор) на всех платформах, drag-n-drop на ПК (`desktop_drop`); список файлов (иконка формата, имя, размер, удаление, статус парсинга); ошибка файла не блокирует остальные; 25 МБ и неподдерживаемый формат — сообщением из ARB | A6.8, A8.3, A8.5 шаг 3 | unit-тесты шлюза документов; widget-тесты экрана (выбор, ошибка, удаление, DnD-подпись) |
| C4 | Селектор провайдера (OpenAI/Gemini/Anthropic/OpenAI-совместимый) и модели (dropdown из списка провайдера); для совместимого — модель из настроек; при отсутствии ключа кнопка ведёт в настройки, где ключ можно сохранить | A6.8, A6.6 (API-блок), ADR-013 | разводка ключей OpenAI/Gemini/Anthropic на экране настроек + ARB; widget-тесты выбора, перехода и сохранения ключа |
| C5 | Прогресс: «Читаем файлы…» → «Отправляем в нейросеть… (фрагмент K из M)» → «Получаем карточки…»; фактический расход после; кнопка «Отмена» прерывает текущий запрос, полученное можно импортировать частично | A6.8, A8.5 шаг 6 | unit-тесты пайплайна (progress/cancel) + widget-тест экрана |
| C6 | Ответ проверяется схемой/контентными правилами/LaTeX (слой 3b); при `truncated` фрагмент делится пополам и повторяется **один раз**; повторный `truncated` — ошибка фрагмента с возможностью повтора | A8.5 шаги 7–8, A8.2 | unit-тесты пайплайна: split→успех, split→ошибка, ровно один split |
| C7 | Дедупликация: нормализация/хеш `front + "\u0000" + back`; между фрагментами и с существующими карточками целевой колоды; для `basic_reversed` — обе стороны | A8.5 шаг 9, A5 | unit-тесты пайплайна и импорта |
| C8 | Предпросмотр: чекбоксы, инлайн-редактирование front/back, пометки A8.4, «Импортировать все» / «Импортировать выбранные» / «Отмена» | A6.8, A8.5 шаг 10 | widget-тесты предпросмотра (выбор, редактирование, импорт) |
| C9 | Импорт одной транзакцией: колода создаётся (имя по умолчанию из первого файла/темы) или карточки добавляются в существующую; `basic_reversed` — две строки; `generation_jobs` обновляется на каждом шаге (status, tokens, cards, chunks, files, prompt_version, error_code, result_deck_id) | A8.5 шаги 11–12, A5 | unit-тесты `DriftGenerationCardStore`/`DriftGenerationJobRepository` на in-memory БД; интеграционный тест полного потока |
| C10 | Частичный успех: предпросмотр полученного + ошибки по фрагментам + «Повторить неудавшиеся» (только упавшие фрагменты, без дублей) | A6.8, A8.5 | unit-тест retry + widget-тест кнопки |
| C11 | Все сообщения пользователю — только ARB (ru), сырые исключения/`details` не показываются | 3.1, A8.6 | widget-тесты текстов ошибок; guard `ru_strings` |
| C12 | Входы: Split-кнопка «Создать» на экране «Колоды» → «Сгенерировать карточки»; Toolbar экрана «Колода» → генерация в эту колоду; после импорта — переход в колоду | A6.2, A6.3 | widget-тесты навигации на production-роутере |
| C13 | Безопасность: ключи только `ApiKeyStore`; `generation_jobs.files_json` — только имена файлов (без материалов/ключей); материалы не логируются; DnD — только `desktop_drop` | 3.4, A8.6 | unit-тест сериализации задания; guard `no_webview`/`no_secrets`; ревью |
| C14 | Качество: полный прогон тестов зелёный, `analyze` 0, `format` 0 changed, покрытие рукописного кода ≥80%, Windows-сборка | B6 | `fvm flutter test --coverage`, `analyze`, `format`, `build windows --release` |
| C15 | Независимое ревью на неизменяемом снимке зелёной фазы; blocker/critical/high закрыты fix-коммитами с новыми тестами | процесс, шаги 4–5 | `journal/iteration-3c/review.md`, fix-коммит |
| C16 | Документация: ADR-015, `docs/generation-pipeline.md`, зависимости (`desktop_drop`/`file_picker` факт), `STATE.md`, `AGENTS.md`, `KNOWN_LIMITATIONS.md` (L8/L25/L23 остатки) | §11, критерий 8 | ревью файлов |

## Задачи (TDD: red → green на каждую)

### Домен (`lib/domain/generation/`, без Flutter)
- **T1. `token_estimator.dart`:** эвристика для русского текста (≈2,5 символа/токен), пустой → 0,
  `estimateMessages` с запасом на обёртку; бюджет модели из каталога.
- **T2. `generation_model.dart`:** `GenerationModel {id, label, provider, contextTokens}`, каталог для
  OpenAI/Gemini/Anthropic, `inputTokenBudget` (контекст − резерв ответа − промпт; для совместимого —
  консервативный дефолт).
- **T3. `generation_chunker.dart`:** `GenerationChunk {materialsText, sourceFiles, limit, splitAttempted}`;
  упаковка разделов по бюджету, деление oversized по абзацам, жёсткий резерв; `splitInHalf` для
  `truncated`.
- **T4. `generation_job.dart`:** `GenerationJobStatus` (`running/done/partial/error/cancelled`),
  immutable `GenerationJob` c полями SPEC A5, `GenerationJobRepository` (save/get), JSON-имена файлов.
- **T5. `generation_run.dart`:** `GenerationRunRequest` (документы, провайдер, модель, пожелания, целевая
  колода, имя), `GenerationProgress` (фазы, K/M), `GenerationChunkFailure`, `GenerationRunResult`
  (карточки, ошибки, токены, дедуп, отмена, `jobId`).
- **T6. `document_gateway.dart`:** `PickedDocument {path, name, sizeBytes}`, `DocumentGateway`
  (`pickDocuments`, `readDocument`, `maxFileBytes`).
- **T7. `generation_card_store.dart`:** `existingContentHashes(deckId)`, `importGeneratedCards(...)`,
  `GenerationImportResult`; импорт получает выбранные карточки + jobId.

### API (`lib/api/generation/`)
- **T8. `generation_caller.dart`:** узкий интерфейс вызова модели; `CardGenerationService` реализует его.
- **T9. `generation_pipeline.dart`:** `GenerationPipeline` — создание/обновление задания, оценка,
  чанкинг, последовательные вызовы, progress/cancel, split-once, дедуп, частичный успех, retry failed;
  fatal-коды (`missingApiKey`, `providerNotConfigured`, `invalidApiKey`) останавливают пайплайн.
- **T10. `generation_cancellation.dart`:** обёртка `CancelToken` Dio для UI (без Dio в домене).
- **T11. `GenerationErrorCode.noMaterials`** + ARB-строка (нет текста после парсинга).

### Данные (`lib/data/`)
- **T12. `generation/drift_generation_job_repository.dart`:** upsert и чтение задания; `files_json` —
  JSON-массив имён; `provider` — wire-имя.
- **T13. `generation/drift_generation_card_store.dart`:** хеши существующей колоды; импорт в транзакции
  (создание колоды/добавление, дедуп внутри, `basic_reversed` — две строки с `sibling_id`, `state=new`,
  `content_hash`), обновление `generation_jobs.result_deck_id/cards_count`.
- **T14. `generation/file_picker_document_gateway.dart`:** `file_picker 13.3.3` (multiple, форматы A8.3),
  `dart:io` чтение с лимитом 25 МБ до чтения; ошибки — `ParserErrorCode`-совместимые.

### UI (`lib/ui/`)
- **T15. `generation/generation_screen.dart`:** зона прикрепления + `DropTarget`, список файлов со
  статусами, пожелания, провайдер/модель, имя колоды (когда целевой нет), оценка токенов, кнопка
  «Сгенерировать», прогресс/отмена, ошибки ARB, переход в предпросмотр.
- **T16. `generation/generation_preview_screen.dart`:** чекбоксы, инлайн-редактирование, пометки,
  import all/selected/cancel, partial failures + «Повторить неудавшиеся».
- **T17. Входы и роутер:** `/generate`, `/decks/:deckId/generate`, Split-меню «Колоды», Toolbar «Колоды»,
  пункт в меню действий колоды; после импорта — `context.go(deckPath(deckId))`.
- **T18. Настройки генерации:** блок ключей OpenAI/Gemini/Anthropic (сохранить/удалить, статус
  «ключ сохранён»), чтобы кнопка «Ключ не задан» вела в рабочую настройку (A6.8/A6.6).
- **T19. ARB:** все новые строки (заголовок, зона, статусы, провайдеры, оценка, прогресс, предпросмотр,
  ошибки, импорт) + `generationErrorNoMaterials`; guard `ru_strings` зелёный.
- **T20. Проводка `app_providers.dart`:** `documentGatewayProvider`, `generationJobRepositoryProvider`,
  `generationCardStoreProvider`, `generationPipelineProvider`, `fileParsingServiceProvider`; fake-провайдеры
  в тестах.

### Ревью, проверка, память
- **T21. Ревью** независимым reviewer на снимке зелёной фазы (`journal/iteration-3c/review.md`);
  fix-итерация отдельным коммитом с новыми тестами.
- **T22. Verify:** полный `fvm flutter test --coverage`, `analyze`, `format`, покрытие, `build windows`,
  сверка C1–C16 → `journal/iteration-3c/verify.md`; `KNOWN_LIMITATIONS.md`.
- **T23. Память:** ADR-015, `docs/generation-pipeline.md`, `journal/iteration-3c/summary.md`, `STATE.md`,
  `AGENTS.md` (устойчивые факты), шаг 7.

## Вне объёма итерации 3c (осознанно)

- Живые вызовы OpenAI/Gemini/Anthropic — ключей нет (L1); DeepSeek success-путь проверен в 3b, повторный
  live-прогон в 3c не обязателен (можно выполнить как доказательство, если ключ доступен).
- «Проверить» ключ (A6.6) — итерация 7; в 3c ключ сохраняется/удаляется без сетевой проверки.
- Профили нескольких OpenAI-совместимых серверов, список моделей произвольного сервера, автоподбор —
  post-MVP/итерация 7 (ADR-013).
- Стриминг ответа, параллельные запросы — не в MVP (A8.6: последовательно).
- Реальные файлы с устройств и OOM на 25 МБ — L23/L25; программные фикстуры и лимиты.
- Редактор масок/LaTeX-предпросмотр карточек — итерации 5; в 3c предпросмотр текстовый.

## Риски

| Риск | Митигация |
|---|---|
| Экран A6.8 разрастается (файлы + прогресс + предпросмотр) и ломает UI-тесты | разделить экраны «генерация» и «предпросмотр», фейковые `DocumentGateway`/`GenerationPipeline` в widget-тестах |
| `desktop_drop 0.8.4` несовместим с `file_picker 13.3.3` | версии уже зафиксированы в `pubspec.lock` и разрешены (docs/dependencies §7); DnD — отдельный слой UI, на мобайле не активен |
| Чанкинг режет текст/теряет разделы | unit-тесты «объединение чанков содержит весь текст», границы разделов, oversized-раздел |
| Оценка токенов неточна → обрезание | консервативная эвристика + `<limit>` на фрагмент + split-once (A8.5 шаг 8); фактический расход — из ответа |
| Дубли при импорте/`basic_reversed` | дедуп дважды: пайплайн (preview) и внутри транзакции импорта; для reversed — оба направления |
| Частичный успех теряет полученные карточки | результат пайплайна возвращает карточки даже при ошибках; job status `partial`; retry только упавших |
| Секреты/материалы в `generation_jobs` | `files_json` — только имена; ключи не входят в сущность; guard `no_secrets`; ревью |
| Тесты флакают на async-прогрессе | инжектируемые часы/последовательные фейки вызовов, `pumpAndSettle` после завершения Completer |

## ADR итерации

- **ADR-015** — пайплайн генерации: оценка токенов и бюджеты моделей, чанкинг/лимит карточек, каталог
  моделей, политика ошибок (fatal/частичный успех/split-once), дедупликация и импорт, `generation_jobs`,
  клавиши API трёх облачных провайдеров на экране настроек, DnD `desktop_drop 0.8.4`.

## Порядок работы

1. План + ADR-015 + `docs/generation-pipeline.md` + `journal/iteration-3c/plan.md` → коммит `docs:`.
2. Красная фаза: тесты T1–T20 (домен, пайплайн, данные, UI) на скелетах с `UnimplementedError`;
   фрагменты «ожидалось/получено» → `journal/iteration-3c/red-generation.md` → коммит `test:`.
3. Зелёная фаза по слоям: домен (T1–T7) → API (T8–T11) → данные (T12–T14) → UI (T15–T19) → проводка
   (T20); после каждого слоя тесты + `analyze`/`format` → коммиты `feat:`.
4. Ревью T21 (независимый reviewer на снимке после зелёного/format-коммита); fix-итерация отдельным
   коммитом с новыми тестами.
5. Verify T22; docs/STATE/AGENTS/summary T23; ретроспектива (шаг 7).
