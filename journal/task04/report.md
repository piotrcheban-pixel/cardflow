# TASK 04 — итоговый отчёт (CARDFLOW)

**Дата:** 2026-11-19. **Старт:** `HEAD = dba80ec` (`docs(generation): record
TASK 03 reliability work`), `git status --porcelain` → только `?? redesign/`.
**Baseline:** `fvm flutter test --no-pub --exclude-tags golden` → **2110 passed
+ 8 skipped**, `analyze` 0. Схема БД и `format_version` не менялись;
`redesign/` не читался и не изменялся.

## 1. Найденные провайдеры

Каталог приложения (`kProviderPresets`): **DeepSeek, OpenAI, Anthropic,
Gemini, OpenRouter, Moonshot (Kimi), MiniMax, Groq, Ollama (local)** — девять
аккаунтов-пресетов. Отдельных классов-провайдеров нет (ADR-020): все они
обслуживаются **четырьмя** адаптерами.

## 2. Реально реализованные адаптеры

| Адаптер | Файл | Протокол |
|---|---|---|
| `OpenAiAdapter` | `lib/api/providers/openai_adapter.dart` | OpenAI Chat Completions, strict `json_schema` |
| `OpenAiCompatibleAdapter` | `lib/api/providers/openai_compatible_adapter.dart` | OpenAI-совместимый с настраиваемым `base_url`, лестница ADR-021 |
| `AnthropicAdapter` | `lib/api/providers/anthropic_adapter.dart` | Messages + принудительный инструмент `emit_cards` |
| `GeminiAdapter` | `lib/api/providers/gemini_adapter.dart` | `generateContent` + `responseSchema` |

Единый список вынесен в `lib/api/providers/generation_adapters.dart` и
используется и приложением (`app_providers.dart`, реэкспорт), и live-тестами.
Подробная матрица «текст/Vision/JSON/usage/статус» — `journal/task04/audit.md` §1.

## 3. Модели и подтверждённые характеристики

**Подтверждено официальными страницами (2026-11-19):**
- DeepSeek `deepseek-flash`: контекст **1 000 000**, максимальный вывод
  **384 000**, JSON-вывод ✓, Vision ✓, тариф $0.30/$1.20 за 1M (peak);
  `deepseek-v4-pro`: 1M/384K, Vision ✗, $1.32/$3.96;
- OpenAI `gpt-4o` — $2.50/$10.00 за 1M (standard), `gpt-4o-mini` —
  $0.15/$0.60.

**Не подтверждено / неизвестно:** id `deepseek-chat`/`deepseek-reasoner`
(в актуальной таблице DeepSeek отсутствуют), оба `claude-3-5-*`
(в актуальной таблице тарифов Anthropic отсутствуют), оба Gemini (страница
тарифов недоступна из окружения), модели OpenRouter/Moonshot/MiniMax/Groq
(официальные страницы в TASK 04 не проверялись), Ollama (сервера нет).
Для всех этих моделей цена — **неизвестна** (не 0), окно/вывод/лимиты — из
каталога (`preset`), а не из документации; Vision — из каталога.
Полная таблица с источниками — `journal/task04/audit.md` §3.

## 4. Неизвестные характеристики

- тарифы всех моделей, кроме четырёх (L138);
- окно/максимальный вывод для OpenAI/Anthropic/Gemini/OpenRouter/Moonshot/
  MiniMax/Groq — не перепроверены по официальным страницам (используются
  значения каталога);
- лимиты изображений/тела запроса у всех провайдеров — допущения приложения
  (8 частей / 10 МБ / 24 МБ / 32 МБ, `unknownFields`);
- поддержка strict-схемы конкретной моделью (`supportsStrictJsonSchema: null`);
- точный токенизатор (эвристика 2,5 симв./токен, L122).

## 5. Состояние API-ключей и безопасности

Ключи вводятся в диалоге провайдера (`obscureText`, без подстановки
сохранённого значения), хранятся только в `flutter_secure_storage`
(`cardflow.api_key.<id>`), после записи — read-back, при расхождении —
ошибка ARB; удаление — `keyStore.delete` + удаление аккаунта. В
`app_settings`/БД/экспорт не попадают, в `generation_jobs` — только id
аккаунта. Логи: `Authorization`, `x-api-key`, `x-goog-api-key`,
`proxy-authorization` редактируются, тела **запросов** не логируются;
debug-диагностика включается только вне release и редактирует текст;
`GenerationException.details` не содержит заголовков/тел; проверено по
исходникам dio 5.11.1, что `DioException.toString()` не печатает URI и
заголовки.

**Исправлено:** единый санитайзер `redactSecretsInText` (диагностика +
`providerReason`) теперь маскирует заголовки, `Bearer`, `sk-`/`AIza`/`gsk_`/
`xai-`/`nvapi-` и секретные query-параметры (`?key=`, `&api_key=`). Реальной
утечки не найдено; это устранение расхождения между двумя разными
регулярками и защита от будущих текстов ошибок. Тесты:
`test/unit/api/http/redaction_test.dart` (+4),
`test/unit/api/generation/generation_diagnostics_test.dart` (7).

## 6. Готовность инфраструктуры live-тестирования

- Отдельная категория: тег `live` + файлы `test/live/`; обычный
  `flutter test` платных запросов не делает.
- Явное разрешение: `CARDFLOW_LIVE_TESTS=1` (без него пропускаются и
  платные, и сетевые live-тесты; раньше два Wikimedia-теста выполнялись в
  обычном прогоне).
- Параметры: provider, model, base_url, maxRequests, maxEstimatedCost,
  timeout, enableImages, enablePromptOnly, enableMaterials, enableRecovery,
  vision, allowUnknownCost, report — **по умолчанию запросы запрещены**
  (`maxRequests=0`, `maxCost=0`).
- Бюджет: логические запросы (`LiveRequestBudget`/`LiveProbeTransport`) +
  лимит HTTP-попыток (`LiveAttemptLimiter`); отсутствие ключа — skip;
  отключить можно `Ctrl+C`, а бюджет/таймаут ограничивают расход при сбое.
- Запись фактического количества запросов: размер тела, время, число
  запросов и HTTP-попыток — в `LiveRunRecord` (JSON Lines).
- Test F офлайн: локальный endpoint `local_provider_server.dart` +
  `test/integration/generation_recovery_http_test.dart` (413, 429+`Retry-After`,
  таймаут, context overflow, битый JSON, `truncated`, 5xx, 401) — 10 тестов
  на реальном сокете loopback, без оплаты.
- 28 офлайновых тестов инфраструктуры: `test/unit/live/live_infrastructure_test.dart`.

## 7. Предварительная стоимость сценариев

DeepSeek `deepseek-flash` (пиковый тариф $0.30/$1.20 за 1M; off-peak вдвое
ниже). Оценка сверху; факт придёт в `usage`.

| Сценарий | Запросы | Вход | Выход | Стоимость |
|---|---:|---:|---:|---:|
| Test A — короткий prompt-only | 1 | 7 800 | 1 500 | $0.0041 |
| Test B — 20 карточек prompt-only | 3 | 27 000 | 10 500 | $0.0207 |
| Test C — небольшой документ | 1 | 8 200 | 3 000 | $0.0061 |
| Test D — большой документ | 5 | 50 000 | 17 500 | $0.0360 |
| Test E — PDF с изображением (Vision) | 1 | 10 200 | 2 000 | $0.0055 |
| **Итого A–E** | **11** | **103 200** | **34 500** | **≈ $0.0724** |
| Минимальный набор A–C | 5 | 43 000 | 15 000 | ≈ $0.0309 |

Расхождение факта и оценки ожидаемо; стоимость других моделей **неизвестна**
(тариф не подтверждён) и блокирует автоматический запуск. Детали и оговорки —
`journal/task04/live-test-plan.md` §3.

## 8. Подготовленные тестовые сценарии

- `test/live/adaptive_generation_live_test.dart`: **Test A** (prompt-only
  3 карточки: запрос, системный промпт, JSON, парсинг, `usage`, предпросмотр),
  **Test B** (20 карточек: несколько запросов, сводка продолжения, сумма
  лимитов, дубли), **Test C** (небольшой документ: план, материал, потери),
  **Test D** (большой документ: адаптивное дробление, порядок, покрытие),
  **Test E** (PDF с изображением: image-части, статусы, каталог).
  Все пропускаются по умолчанию.
- **Test F** — офлайн-симуляция ошибок (см. §6), реальный платный recovery не
  выполнялся.
- Материалы: `test/live/support/live_fixtures.dart` (нейтральные тексты,
  PNG, PDF с изображением); качество: `live_quality.dart` (чек-лист + авто-метрики).
- План испытаний, критерии успеха и риски TASK 05 —
  `journal/task04/live-test-plan.md`.

## 9. Исправленные проблемы

1. **Битый JSON ответа классифицировался как `network` и повторялся.**
   `GenerationHttpClient` просит `ResponseType.plain` и разбирает тело сам —
   битый JSON теперь `invalidResponse` без повторов (раньше Dio падал в
   трансформере до `Response`, ошибка шла как сетевая и повторялась до 4 раз —
   потенциальные лишние платные запросы). Тест: локальный HTTP-сервер
   (`generation_recovery_http_test.dart`).
2. **Диагностика/`providerReason` не редактировали query-параметры и часть
   форматов ключей** — единый `redactSecretsInText` (+тесты).
3. **Список адаптеров дублировался** в тестах/приложении — вынесен в
   `lib/api/providers/generation_adapters.dart` (production и live-тесты
   используют один набор).
4. **Live-тесты могли выполняться без явного разрешения** (и два
   Wikimedia-теста шли в обычном прогоне) — введён opt-in `CARDFLOW_LIVE_TESTS=1`,
   обычный прогон стал полностью офлайновым (+7 skipped).

## 10. Оставшиеся ограничения

L137–L142 (`journal/KNOWN_LIMITATIONS.md`): устаревшие/непроверенные id
моделей каталога; неизвестные тарифы большинства моделей; неверный
Vision-флаг пресета DeepSeek; отсутствие отдельного кода для 404/402/422;
live-тесты не входят в CI и требуют ручного запуска; в TASK 04 платных
запросов не было. Действуют и прежние L1 (нет ключей OpenAI/Gemini/Anthropic),
L47, L122 (эвристика токенов), L133 (возможности/цены не вводятся в UI),
L135 (`usage` упавших ответов).

## 11. Результаты offline-тестов

| Гейт | Результат |
|---|---|
| `fvm flutter test --no-pub --exclude-tags golden` | **2158 passed + 15 skipped** (`All tests passed!`; baseline 2110 + 8; +48 passed, +7 skipped) |
| `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2158 passed + 15 skipped**, покрытие рукописного кода **92.4 % (16201/17535)** |
| `fvm flutter analyze --no-pub` | **No issues found!** (40,2 с) |
| `fvm dart format --set-exit-if-changed lib test integration_test tool` | **499 файлов / 0 changed** |
| `fvm flutter build windows --release --no-pub` | **`cardflow.exe`** (63,0 с) |

Новые тесты: `test/unit/live/live_infrastructure_test.dart` (28),
`test/integration/generation_recovery_http_test.dart` (10),
`test/unit/api/generation/generation_diagnostics_test.dart` (7),
`test/live/adaptive_generation_live_test.dart` (5, пропускаются),
`test/unit/api/http/redaction_test.dart` (+4). Обычный прогон полностью
офлайновый: сетевые live-тесты пропускаются без `CARDFLOW_LIVE_TESTS=1`.

## 12. Windows Release Build

`fvm flutter build windows --release --no-pub` → `√ Built
build\windows\x64\runner\Release\cardflow.exe` (63,0 с).

## 13. Изменённые файлы

**Новые (`lib`):** `lib/api/providers/generation_adapters.dart`.

**Изменённые (`lib`):** `lib/api/http/log_redaction.dart` (единый
`redactSecretsInText`), `lib/api/http/generation_http_client.dart`
(`ResponseType.plain`, делегирование санитайзеру),
`lib/api/generation/generation_diagnostics.dart` (единый санитайзер),
`lib/ui/state/app_providers.dart` (реэкспорт списка адаптеров).

**Новые (тесты):** `test/live/support/` (`live_test_config`, `live_pricing`,
`live_cost`, `live_budget`, `live_scenarios`, `live_fixtures`,
`live_quality`, `live_run_report`, `live_harness`,
`local_provider_server`), `test/live/adaptive_generation_live_test.dart`,
`test/unit/live/live_infrastructure_test.dart`,
`test/unit/api/generation/generation_diagnostics_test.dart`,
`test/integration/generation_recovery_http_test.dart`.

**Изменённые (тесты):** `test/live/openai_compatible_deepseek_live_test.dart`,
`test/live/images_v6_live_test.dart`, `test/live/wikimedia_images_live_test.dart`
(opt-in gate), `test/unit/api/http/redaction_test.dart` (+4 теста).

**Документация/журнал:** `AGENTS.md` (правило live-тестов),
`docs/adaptive-generation-architecture.md` (раздел S),
`docs/generation-pipeline.md` (§5 разбор тела ответа, §9 управляемые
испытания), `journal/KNOWN_LIMITATIONS.md` (L137–L142),
`journal/task04/{audit.md,live-test-plan.md,report.md}`, `journal/STATE.md`.

## 14. Новые коммиты

- `feat(api): classify malformed provider JSON as invalid response` —
  `ResponseType.plain` + разбор тела, единый санитайзер, общий список
  адаптеров (с тестами).
- `test(live): add opt-in budgets, pricing and calibration reports` —
  инфраструктура live-тестов, Test A–E, офлайновый Test F, тесты.
- `docs(journal): record TASK 04 live readiness audit` — аудит, программа
  испытаний, отчёт, STATE, ограничения, docs, AGENTS.

Push и deploy **не выполнялись** (условие задания); коммиты остаются
локальными до отдельной команды владельца.

## 15. Платные API-запросы

**Не выполнялись.** За весь TASK 04 ни одного запроса к OpenAI/Gemini/
Anthropic/DeepSeek не отправлено: live-тесты пропущены (нет opt-in), новые
HTTP-тесты работают на `127.0.0.1`, остальные — на моках/фикстурах. Ключи не
печатались; проверка — present/absent.

## 16. `redesign/`

Каталог `redesign/` не читался, не изменялся и не коммитился; в `git status`
остаётся неотслеживаемым каталогом владельца.
