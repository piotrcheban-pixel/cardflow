# Итерация 3c — проверка (шаг 5)

**Дата:** 2026-11-14 · **HEAD:** `9db83ab` (fix ревью) · **Ветка:** `main`, дерево чистое.
**Команды и результаты (эта сессия):**

| Проверка | Команда | Результат |
|---|---|---|
| Полный прогон тестов | `fvm flutter test --exclude-tags golden --reporter compact` | **897 passed + 1 skipped**, exit 0 |
| Анализатор | `fvm flutter analyze` | **No issues found!** |
| Формат | `fvm dart format --set-exit-if-changed lib test` | 218 files, **0 changed** |
| Покрытие | `fvm flutter test --coverage --exclude-tags golden` + `fvm dart run tool/coverage_check.dart --min=80` | **93.2% (5219/5597)**, порог 80 пройден |
| Windows-сборка | `fvm flutter build windows --release` | **`√ Built build\windows\x64\runner\Release\cardflow.exe`** (56,9 s) |
| Ревью | `journal/iteration-3c/review.md` | 2 high, 12 medium, 11 low; fix-коммит `9db83ab`, все H/M закрыты новыми тестами (`review-fixes.md`) |

## Критерии приёмки итерации

| # | Критерий | Статус | Доказательство |
|---|---|---|---|
| C1 | Оценка токенов до отправки, бюджет модели, предупреждение | **выполнено** | `TokenEstimator`/`inputTokenBudget`; UI «Примерно N токенов»; unit/widget тесты |
| C2 | Чанкинг по разделам/абзацам, `<limit>`, split | **выполнено** | `GenerationChunker` + 11 unit-тестов (упаковка, oversized, runes, split) |
| C3 | Файлы: picker, DnD, статусы, удаление, ошибки по файлу, 25 МБ | **выполнено (DnD runtime — L33)** | `FilePickerDocumentGateway`, `DropTarget`, widget-тесты экрана; реальный drag на ОС не проверялся |
| C4 | Провайдер/модель, ключ → настройки, сохранение ключей | **выполнено** | chooser + dropdown, блок «Ключи API»; widget-тесты выбора/сохранения/удаления |
| C5 | Прогресс, факт расхода, отмена; частичный результат | **выполнено** | pipeline progress/cancel + widget-тесты, Back-отмена |
| C6 | Валидация 3b, split-once при truncated | **выполнено** | `generation_pipeline_test`: split→успех, повторный truncated → ошибка; retry-split |
| C7 | Дедупликация между фрагментами и с колодой, reversed обе стороны | **выполнено** | pipeline + data unit-тесты, integration flow |
| C8 | Предпросмотр: чекбоксы, инлайн-редактирование, импорт all/selected/cancel | **выполнено** | `generation_preview_screen_test` (6 сценариев) |
| C9 | Импорт одной транзакцией, колода/добавление, `generation_jobs` | **выполнено** | `drift_generation_card_store_test`, `generation_flow_test` (production-граф) |
| C10 | Частичный успех и «Повторить неудавшиеся» | **выполнено** | pipeline retry + preview failure UI + H1-тест |
| C11 | Только ARB, без сырых ошибок | **выполнено** | guard `ru_strings`, widget-тесты ошибок, `generationErrorCodeMessage` |
| C12 | Входы «Колоды» и «Колода» (Toolbar), переход после импорта | **выполнено** | entry widget-тесты; DeckScreen: иконка + меню |
| C13 | Безопасность: ключи только `ApiKeyStore`, в jobs только имена, без логов | **выполнено (live-границы L1/L30, ADR-014)** | `generation_jobs.files_json` — имена; guard `no_secrets`; ревью не подтвердило утечек |
| C14 | Тесты/analyze/format/покрытие/Windows | **выполнено** | таблица выше |
| C15 | Независимое ревью, H/M закрыты fix-коммитом с тестами | **выполнено** | `review.md`, `review-fixes.md`, `9db83ab` |
| C16 | Документация: ADR-015, docs, STATE/AGENTS/limits/summary | **выполнено** | ADR-015, `docs/generation-pipeline.md`, `STATE.md`, `AGENTS.md`, `KNOWN_LIMITATIONS.md`, `summary.md` |

## Критерии остановки MVP, затронутые итерацией

- **Генерация (п.3):** экран A6.8, файлы A8.3, строгая схема/валидация, провайдеры, ключи в secure storage,
  retry/backoff, отмена, предпросмотр, дедупликация — **выполнено**; живая проверка OpenAI/Gemini/Anthropic —
  **не проверено** (L1), DeepSeek success — L30 (3b). Живые негативные контракты — ADR-014.
- **Нативность (п.4):** guard `no_webview` зелёный; DnD — `desktop_drop`, файлы — `file_picker`.
- **Данные (п.5):** импорт сгенерированных карточек в одной транзакции, `generation_jobs` обновляется.
- **Качество (п.7):** покрытие 93.2%, analyze 0, ревью без blocker/critical/high после фиксов.

## Не проверено и почему

- **Живые OpenAI/Gemini/Anthropic** — ключей нет (L1); DeepSeek success проверен в 3b (L30), повторно
  в 3c не запускался (ключ в env процесса агента отсутствует; передача из реестра возможна, но не требовалась
  для приёмки 3c — успешный путь уже доказан).
- **Реальный DnD/picker на Windows/Android/iOS** — нет ручного прогона (L11/L23/L33); widget-тесты и
  контракт шлюза покрывают логику, но не платформенные события.
- **Реальные документы и 25 МБ/OOM** — L23/L25; программные фикстуры и лимиты.
- ~~**CI-прогон итерации 3c** — push не выполнялся~~ **снято 2026-11-14:** push выполнен
  (`origin/main = e5f64c4`), прогон [`43583803312`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43583803312) — **9/9 job success**.
- **Точная оценка токенов** — эвристика (2,5 символа/токен), фактический расход из ответа; ADR-015 §1.
