# TASK 05 — отчёт готовности к A–C

**Дата:** 2026-11-19. **Статус:** подготовлено, live-тесты **не запускались**.
**Вердикт:** READY FOR USER APPROVAL (при условии, что офлайновые гейты ниже
зелёные; блокирующих дефектов не найдено).

## 1. Что проверено

- production-путь: `GenerationPlanBuilder` → `GenerationPlan` →
  `CardGenerationService` (`generationAdapters`) → `GenerationHttpClient` →
  `GenerationPipeline`; live-harness использует те же классы, а не
  упрощённую реализацию;
- каталог DeepSeek и официальная документация (pricing + chat completions,
  2026-11-19);
- сценарии A–C: планы, число запросов, лимиты, стоимость;
- бюджеты: logical / HTTP / физические попытки / стоимость; общие на файл;
- отсутствие автоматического переключения провайдера (в коде только
  fallback-лестница протокола strict → tolerant, не смена провайдера);
- секреты: ключ не печатался, отчёт не содержит ключей/заголовков/материалов;
- Test F (офлайн) и live-skip без opt-in.

## 2. Модель и endpoint

| Параметр | Значение | Статус |
|---|---|---|
| provider | `deepseek` | подтверждён каталогом |
| model | `deepseek-flash` | официальная страница DeepSeek, 2026-11-19 |
| endpoint | `https://api.deepseek.com` + `POST /chat/completions` | официальная страница; совпадает с `ProviderPreset` и `OpenAiCompatibleAdapter` |
| формат | OpenAI Chat Completions, `messages`/`max_tokens`/`response_format` | совместим; strict-схема отклоняется, работает tolerant (ADR-021) |
| контекст | 1 000 000 | подтверждён |
| max output | 384 000 (модель); приложение отправляет 8 192 | подтверждено/политика приложения |
| Vision | да | подтверждено страницей; живой Test E не запускался |
| цена | $0.30 вход / $1.20 выход за 1M (peak) | подтверждено 2026-11-19 |

Production default каталога DeepSeek теперь `deepseek-flash`; legacy
`deepseek-chat`/`deepseek-reasoner` оставлены для сохранённых аккаунтов, их
живая доступность UNKNOWN. Подробности — `audit.md`.

## 3. Сценарии A–C

| Сценарий | Карточек | Логических | HTTP-обменов | Оценка | Готовность |
|---|---:|---:|---:|---:|---|
| A — prompt-only | 5 | 1 | 2 | $0.00534 | готов |
| B — prompt-only continuity | 40 | 6 | 12 | $0.04140 | готов |
| C — небольшой документ (DOCX, 3 раздела, production-парсер) | 6 | 1 | 2 | $0.00606 | готов |
| **Итого** | **51** | **8** | **16** | **$0.05280** | |

Планы проверены офлайновым `live_task05_readiness_test.dart` на production
`GenerationPlanBuilder`: A — 1 фрагмент/лимит 5, B — 6 фрагментов/сумма
лимитов 40/continuity-резерв > 0, C — 1 фрагмент/`omitted` пуст/связи `doc:`.

## 4. Бюджет и лимиты

| Параметр | Значение |
|---|---:|
| логические запросы | **20** |
| HTTP-обмены (strict + tolerant) | **40** |
| физические HTTP-попытки (×4) | **160** |
| стоимость | **$0.12** |
| таймаут запроса | 120 с |

Ожидаемый расход — **$0.0528** peak / **$0.0264** off-peak. Верхняя оценка с
учётом тарификации strict-400 (не подтверждена) — ≈ **$0.0738**. Если
тарифицируются повторы 429/5xx (не подтверждено), теоретический потолок
160 попыток ≈ $2.00; cost guard резервирует каждую физическую попытку и
блокирует новые при $0.12, но правила биллинга неуспешных запросов остаются
UNKNOWN. Детали — `budget.md`.

## 5. Что именно защищает от лишнего расхода

- `CARDFLOW_LIVE_TESTS` не задан — live-набор пропускается; `maxRequests=0`,
  `maxCost=0` по умолчанию;
- **явный список** `CARDFLOW_LIVE_SCENARIOS` — A–C не запускают Test D,
  хотя C и D делят флаг `_ENABLE_MATERIALS`;
- `LiveRecordingCaller` + `LiveRequestBudget` — логические запросы;
- `LiveProbeTransport` + `LiveRequestBudget` — HTTP-обмены;
- `LiveAttemptLimiter` — физические попытки;
- `LiveCostGuard` в `LiveAttemptLimiter` — резерв до каждой попытки, факт из
  `usage` после ответа, освобождение strict-400; превышение $0.12 блокирует
  отправку;
- нет автоматической смены провайдера; при неизвестном тарифе запуск
  блокируется (allowUnknownCost — только ручное решение);
- ключ читается только из окружения, не печатается; `note` редактируется;
- отчёт не содержит тел запросов/материалов.

## 6. Офлайн-гейты

| Гейт | Результат |
|---|---|
| `fvm flutter test --no-pub --exclude-tags golden` | **2177 passed + 16 skipped** |
| `fvm flutter test --no-pub test/unit/live` | **48 passed** (`live_infrastructure` + `live_task05_readiness`) |
| `fvm flutter test --no-pub test/integration/generation_recovery_http_test.dart` (Test F) | **11 passed** |
| `fvm flutter test --no-pub test/live --tags live` | **16 skipped, 0 запросов** |
| `fvm flutter analyze --no-pub` | **No issues found!** (33,0 с) |
| `fvm dart format --set-exit-if-changed lib test integration_test tool` | **500 файлов / 0 changed** |
| `fvm flutter build windows --release --no-pub` | **`cardflow.exe`** (62,1 с) |
| `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2177 passed + 16 skipped**, покрытие рукописного кода **92.4 % (16202/17535)** |

## 7. Найденные и исправленные дефекты

1. **Каталог DeepSeek не содержал актуальных моделей.** Unknown-модель давала
   1 карточку/запрос; Test B требовал бы 40 логических запросов. Добавлены
   `deepseek-flash` (default, 1M, Vision) и `deepseek-v4-pro` (1M).
2. **Бюджет считал HTTP-обмены как «логические запросы».** Введено разделение
   logical/HTTP/attempts/retries.
3. **Бюджет был на каждый тест.** Сделан общим на файл.
4. **Не было per-request cost guard.** `LiveCostGuard` в `LiveAttemptLimiter`
   резервирует стоимость каждой физической попытки.
5. **Отчёт не содержал цен/стоимости/ретраев/latency.** Расширен
   `LiveRunRecord`, добавлены `requestCosts[]`.
6. **`note` не редактировался.** `redactSecretsInText` перед записью.
7. **Сценарии A/B не соответствовали TASK 05** (3/20). Теперь 5/40; continuity
   проверяется по `LiveCallRecord`, importability — по `CardDraft.validate()`.
8. **Test C не проходил production-парсер.** Добавлена DOCX-фикстура с тремя
   Heading1; `DocxParser` реально извлекает текст и разделы.
9. **Не было ручной рубрики.** 8 критериев 0/1/2 + `LiveDocumentAssessment`.
10. **Нельзя было запустить только A–C** (D делил флаг материалов). Добавлен
    `CARDFLOW_LIVE_SCENARIOS`.

## 8. Неизвестные характеристики

- доступность legacy `deepseek-chat`/`deepseek-reasoner` на живом endpoint;
- тарификация strict-400 и повторов 429/5xx/таймаута;
- учёт reasoning-токенов thinking mode в `max_tokens`;
- фактический выход модели (факт придёт в `usage`);
- тарифы всех моделей, кроме четырёх (L138);
- точный токенизатор (эвристика 2,5 симв./токен, L122).

## 9. Что остаётся за владельцем

- явное разрешение на live-прогон A–C (см. `test-plan.md`);
- ручная оценка карточек по рубрике после прогона;
- фактический импорт в drift-БД/предпросмотр GUI (live-тест проверяет
  importability, но не пишет в БД пользователя — L146);
- решение по legacy-моделям DeepSeek в каталоге (L147).

## 10. Изменения и коммиты

- `4e385ff` `feat(generation): align DeepSeek catalog with current model ids` —
  `deepseek-flash`/`deepseek-v4-pro`, default flash, тесты каталога/аккаунта/
  model capabilities/экранов;
- `e401c69` `test(live): harden A-C budgets, cost guard and reports` —
  раздельные бюджеты, cost guard, отчёт, сценарии A/B/C, DOCX-парсер,
  continuity/importability, рубрика, `CARDFLOW_LIVE_SCENARIOS`;
- `docs(journal): record TASK 05 live readiness for tests A-C` —
  аудит, план, бюджет, отчёт, `results/`, docs, L137/L139/L143–L148, STATE.

Push/deploy **не выполнялись**; коммиты локальные.

## 11. Точная команда

См. `test-plan.md` §1. Кратко:

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

**LIVE TEST STATUS: NOT EXECUTED**

**REASON: Awaiting explicit user authorization.**

**READY FOR USER APPROVAL: YES**
