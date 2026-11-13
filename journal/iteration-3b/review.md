# Итерация 3b — «Провайдеры». Независимое ревью (шаг 4, T23)

**Дата ревью:** 2026-11-13 · **Ревьюер:** reviewer (делегированный, независимый) · **Режим:** ИТЕРАЦИИ

**Снимок:** HEAD `e2801a6` (`feat: card generation service, ARB error messages and production wiring`).
Красная фаза — `856cf4a`; зелёная фаза — `926cc04`, `c342aef`, `096b2c5`, `e2801a6`;
диапазон среза — `git diff 856cf4a~1..HEAD` (44 файла, +5439/−0), `git show 856cf4a --stat` (43 файла).
Baseline перед срезом — `16a3e44` (603 теста зелёные).

**Состояние рабочего дерева:** **не clean** — `M journal/STATE.md` (mtime 13.11.2026 23:03:16, содержимое
«шаг 4 (ревью)»; вероятно, Lead обновил STATE при переходе к ревью). Production-код и тесты в дереве
соответствуют `e2801a6`: `git status --porcelain` содержит только `journal/STATE.md`; в `lib/`, `test/`,
`docs/`, `pubspec*.yaml`, `analysis_options.yaml` незакоммиченных изменений нет. Ревьюер ничего не менял
и не коммитил; единственная запись ревьюера — этот файл. Подробности — находка #4.

**Статус по наивысшей серьёзности:** **medium** — 0 blocker / 0 critical / 0 high / **2 medium** / 10 low.
Блокеров и утечек секретов не найдено. Найдены два реальных риска поведения (ретраи/отмена), не покрытые
документацией; остальное — техдолг качества/документации.

---

## Таблица находок

| # | severity | файл:строка | проблема | почему важно (SPEC/риск) | что фиксить |
|---|---|---|---|---|---|
| 1 | **medium** | `lib/api/http/retry_policy.dart:60,66,109` (тесты: `test/unit/api/http/retry_policy_test.dart:104`, `test/unit/api/http/generation_http_client_test.dart:244`) | При 429 с `Retry-After` больше `maxRetryAfter` (по умолчанию 60 с) политика делает **giveUp после 1-й попытки**, а не паузу по заголовку; `Retry-After` до 60 с соблюдается. Поведение **не задокументировано** ни в ADR-012 §1 (там «пауза ровно по нему», стр. 32), ни в `docs/api-schema.md` §6 (стр. 106), ни в плане C8; тесты его закрепляют | SPEC A8.6: «429 — пауза по `Retry-After`, … максимум 4 попытки»; ADR-012 §1 буквально требует «паузу ровно по нему». Код расходится с собственным ADR/SPEC без ADR-правки — скрытое отступление, которое verify не увидит; пользователь при лимите «через 2 минуты» вместо автоповтора получает ошибку (само по себе разумно, но это решение, а не требование) | Выбрать и оформить: (а) соблюдать `Retry-After` и делать до 4 попыток (с учётом #2, чтобы отмена не ждала); **или** (б) оставить cap, но явно описать его в ADR-012 §1 + `docs/api-schema.md` §6 + verify (причина: не блокировать UI) и оставить/обновить тест-закрепление. Молчаливое расхождение недопустимо |
| 2 | **medium** | `lib/api/http/generation_http_client.dart:80` (`await delay(decision.delay)`), `:147-154` (`_throwIfCancelled` только до/после запроса) | Отмена во время паузы перед повтором **не прерывает ожидание**: `CancelToken` проверяется только перед очередным POST; при backoff до 30 с и `Retry-After` до 60 с `postJson` вернёт `cancelled` только после конца паузы. Ветка «отмена до отправки» тестами не покрыта (есть только отмена, пришедшая как `DioExceptionType.cancel` из запроса) | SPEC A6.8: кнопка «Отмена» «прерывает текущий запрос»; A8.5 шаг 6; ADR-012 §2 «`CancelToken` прокидывается от вызывающего (3c: кнопка „Отмена“)». В 3c пользователь увидит «зависшую» отмену до 30–60 с — реальный UX/контрактный риск, который дешевле закрыть в 3b | Ожидать паузу в гонке с `cancelToken.whenCancel` (или проверять `isCancelled` после `Future.any`), бросать `GenerationException(cancelled)` немедленно; добавить unit-тест «отмена во время backoff/Retry-After-паузы не повторяет запрос» и тест «токен уже отменён до отправки» (инъекция `delay` уже есть) |
| 3 | low | `lib/ui/generation/generation_error_message.dart:27-29`; `journal/STATE.md:8` | `fvm dart format --output=none --set-exit-if-changed lib test` → **1 файл не отформатирован** (`Changed lib\ui\generation\generation_error_message.dart`: ветка `rateLimited` должна быть в одну строку), exit code 1. При этом `journal/STATE.md` заявляет «`format` 0 changed» — **утверждение журнала не соответствует снимку** | B6/C14: «`dart format` применён» — обязательный пункт приёмки; заявление в журнале без доказательства запрещено процессом. Форматирование — единственная причина красного гейта | `fvm dart format lib test`, закоммитить в fix-коммите; после этого исправить/подтвердить строку STATE; на verify повторить `--set-exit-if-changed` |
| 4 | low | `journal/STATE.md` (рабочее дерево, mtime 23:03:16) | На момент ревью дерево **не clean**: изменён `journal/STATE.md` (обновлён на шаг 4). Код/тесты/доки соответствуют `e2801a6`; на результаты прогонов это не влияет, но формально нарушено «ревью на неизменяемом снимке» | Ретро-2 и C15: ревью запускается на снимке после коммита зелёной фазы; грязное дерево делает findings/verify потенциально невоспроизводимыми | До verify: закоммитить `journal/STATE.md` отдельным docs-коммитом (или вернуть к `e2801a6` и обновить после ревью). Ревьюер не правит; фиксирует факт |
| 5 | low | `lib/api/http/log_redaction.dart:27,37`; `lib/api/http/redacting_log_interceptor.dart:29-33`; ADR-012 `docs/decisions/ADR-012-http-resilience-secrets.md:56-57` | Санитайзеры `redactHeadersForLog`/`redactUriForLog` в production-коде: `redactUriForLog` используется перехватчиком (URI), **`redactHeadersForLog` не используется нигде в `lib/`** — перехватчик вообще не логирует заголовки. ADR-012 §3 утверждает «заголовки … → `***`» и «защита, если ключ попал в путь/query», но путь не редактируется, а header-санитайзер подключён только к тестам | SPEC 3.4/A8.6: «в логах редактировать `Authorization`, `x-api-key`, `x-goog-api-key`». Сейчас утечки нет (заголовки не логируются вовсе — сильнее требования), но ADR описывает несуществующее поведение, а санитайзер не привязан к перехватчику: при добавлении любого вывода заголовков в 3c защита не сработает автоматически | Либо явно зафиксировать в ADR-012 §3: «заголовки не логируются вообще; sanitizer — API для будущих логов/тестов» и убрать обещание про путь, либо подключить `redactHeadersForLog` (логировать отредактированные заголовки) и добавить тест перехватчика на заголовки; защиту от `key` в path — либо реализовать, либо убрать из ADR |
| 6 | low | `lib/api/providers/gemini_adapter.dart:38-69`; `lib/api/providers/openai_adapter.dart:23-25,39`; контракт `lib/api/providers/generation_provider_adapter.dart:45-51` | Параметр `maxOutputTokens` обязателен в контракте адаптера, но **Gemini его молча игнорирует** (`generationConfig` без `maxOutputTokens`); OpenAI — осознанно (есть комментарий), Gemini — без обоснования. `CardGenerationService.maxOutputTokens = 8192` доезжает только до Anthropic | Контракт `buildRequest` вводит в заблуждение; нет верхней границы ответа/стоимости для 2 из 3 провайдеров (SPEC A8.2 «точные детали — по документации провайдера», A8.5 — ограничение ответа). Обрезание ловится (`truncated`), но стоимость и полнота ответа не ограничены | Для Gemini передать `generationConfig.maxOutputTokens`; для OpenAI — либо `max_completion_tokens` по актуальной документации, либо убрать параметр из контракта для этого адаптера и зафиксировать в ADR-011/комментарии; добавить тест на тело (в духе существующего `expect(request.body.containsKey('max_tokens'), isFalse)` для OpenAI) |
| 7 | low | `lib/api/providers/provider_json.dart:27` | `jsonIntOrNull`: `value is num ? value.toInt()` — на нечисловом JSON всё ок, но на `Infinity`/`NaN` (JSON `1e999` декодируется Dart в `Infinity`) `toInt()` бросает `UnsupportedError` (это `Error`, не `GenerationException`), и адаптер отдаёт наружу сырое падение вместо `invalidResponse`/`TokenUsage()` | Фокус «обработка недоверенного JSON без падений (типы/границы)»; UI 3c, ловящий `GenerationException`/`Exception`, не поймает `Error`; ожидаемое поведение — устойчивый разбор | `if (value is num && value.isFinite)` (или try/catch) → `null`; unit-тест на `1e999`/`NaN` в `usage`; аналогично проверить остальные числовые поля |
| 8 | low | `test/integration/generation_pipeline_test.dart:68-112` | Интеграционный тест production-проводки (`app_providers` → сервис → реальные адаптеры → HTTP-клиент → fake-Dio) проверяет **только OpenAI**. Стык «Gemini/Anthropic адаптер → Dio-запрос (заголовок ключа, тело) → ответ → разбор» на production-графе не подтверждён, хотя C12 говорит о 3 адаптерах в графе | Урок H1 итерации 2: фикс/слой подтверждается на production-проводке; unit-тесты адаптеров не ловят, например, потерю заголовка при прохождении через `GenerationHttpClient` (Dio пересобирает заголовки) | Параметризовать интеграционный тест на 3 провайдера (fake-ответы `FakeHttpAdapter`: OpenAI/Gemini/Anthropic) с проверкой заголовка ключа на уровне `adapter.requests` и карточек/`usage` из `generate` |
| 9 | low | `docs/dependencies.md:258-259` | §11 ссылается на `journal/iteration-3b/verify.md` и «§12 ниже», но `verify.md` ещё не создан (шаг 5), а **§12 в `docs/dependencies.md` отсутствует** — висячая ссылка; впечатление, что verify уже выполнен | C13/критерий 8 документации; журнал без доказательств запрещён процессом | На шаге verify добавить §12 с фактическим прогоном (или убрать ссылку до шага 5); проверить ссылки скриптом/ревью перед коммитом docs |
| 10 | low | `journal/iteration-3b/plan.md:32` | C11: «8 кодов», но перечислено и реализовано **12** кодов (`MissingApiKey`…`invalidResponse`), ADR-011 §5 и ARB тоже дают 12. Внутреннее противоречие плана | Контроль C11 неоднозначен; при verify легко засчитать/не засчитать пункт по-разному | Поправить формулировку C11 в summary/verify («12 кодов C11»), при ретроспективе — план |
| 11 | low | `docs/api-schema.md:45,63` | (а) стр. 45: «union с null и `additionalProperties` **допустимы** в strict» — неверно: strict-режим OpenAI **требует** `additionalProperties: false` (union с null — допустимая форма nullable); (б) стр. 63 (таблица причин): для Anthropic «нет текстового/`tool_use` контента → `emptyResponse`», но код (и SPEC A8.2/ADR-011 §3) при отсутствии `tool_use` отдаёт **`invalidResponse`**, а `emptyResponse` для Anthropic не возникает вовсе | Документация — источник для 3c/verify; расхождение доков и кода уже сейчас (хотя код соответствует SPEC) | Привести две строки `docs/api-schema.md` в соответствие коду: «strict требует `additionalProperties:false`; nullable — union с null»; в таблице причин Anthropic — «нет `tool_use` `emit_cards` → invalidResponse» |
| 12 | low | `lib/api/generation/latex_checker.dart:5` | `lib/api/` (слой, по AGENTS — «провайдеры, DTO, валидация, промпты, парсеры») теперь напрямую импортирует Flutter-widget-пакет `flutter_math_fork`; architecture guard проверяет только `lib/domain/`, поэтому это не поймано. План это признал (изоляция в одном файле + инъекция `latexChecker`), но ни AGENTS, ни ADR-011 не фиксируют это как единственную Flutter-зависимость API-слоя и не защищают guard-ом | AGENTS: domain без Flutter (выполнено); но «API не тянет UI» — flutter_math_fork — рендер-пакет; при будущем рефакторинге легко протащить Flutter/рендер глубже в API-слой/изолят | Зафиксировать в `docs/decisions/ADR-011` (или AGENTS) правило: Flutter в `lib/api/` допустим только через `latex_checker.dart`/инъекцию; при ретро — добавить guard-проверку «lib/api не импортирует flutter/material и material_ui» и/или инъекция `latexChecker` в production-проводке оставляет ядро валидатора чистым |

---

## Что проверено и чисто

Команды и результаты (все — в текущей сессии, снимок `e2801a6`, код/тесты дерева не менялись):

1. **Полный прогон:** `fvm flutter test --exclude-tags golden` → **`01:03 +739: All tests passed!`**
   (739 тестов; совпадает с заявлением STATE).
2. **Анализатор:** `fvm flutter analyze` → **`No issues found!`** (5.6 с).
3. **Точечные тесты нового слоя** (12 файлов = 136 тестов, ровно как в красной фазе):
   `fvm flutter test test/unit/api/generation test/unit/api/providers test/unit/api/http test/unit/data/security test/unit/domain/generation_domain_test.dart test/unit/ui/generation_error_message_test.dart test/integration/generation_pipeline_test.dart`
   → **`+136: All tests passed!`**. Итог по файлам: domain 9, card_schema 14, prompt 12,
   content_validator 14, adapters 22, retry_policy 14, http_client 12, redaction 8, key_store 6,
   service 12, error_message 8, integration 5.
4. **Тесты не ослаблены:** `git diff 856cf4a..HEAD -- test/` → **пусто**. Тестовые файлы красной и зелёной
   фаз идентичны; guard-тесты (`no_secrets`, `architecture`, `ru_strings`, `no_webview`, `ci_pdfium`),
   `analysis_options.yaml`, `pubspec.yaml`/`pubspec.lock` в срезе **не менялись** (`git diff
   856cf4a~1..HEAD --name-status` — только 44 новых/изменённых файла итерации). Скипов/`// ignore`/`@Tags`
   в новых тестах нет; новых зависимостей нет.
5. **Red→green:** тесты red-коммита идентичны HEAD-версии (см. п.4); в `856cf4a` production-скелеты были
   с `UnimplementedError` (проверено по `git show 856cf4a --stat` и содержимому red-коммита), поэтому
   падения красной фазы поведенческие, а не компиляционные; `git show 856cf4a --stat` и `red-api.md`
   согласуются (136/120/16). Повторно красную фазу не воспроизводил (снимок неизменяем).
6. **Безопасность (3.4, A8.6) — утечек не найдено:**
   - ключ читается только из `ApiKeyStore` (`card_generation_service.dart:70`); в `lib/` нет других
     источников ключа; `SecureApiKeyStore` не пишет пустое (`secure_api_key_store.dart:64-75`) и
     возвращает `null` для пустого (`:57-62`);
   - Gemini-ключ только в заголовке `x-goog-api-key` (`gemini_adapter.dart:47-50`), в URL его нет
     (тест `provider_adapters_test.dart:175-186`); ключа в query нет ни у одного адаптера;
   - тела запросов/ответов не логируются: перехватчик пишет только метод/URI/статус/тип/длительность
     (`redacting_log_interceptor.dart:29-56`); в новом коде нет вызовов `print`/`debugPrint`/
     `developer.log` (grep по новым файлам; единственная ссылка на `debugPrint` — sink перехватчика в
     `app_providers.dart:116-118`, включается только при `kDebugMode`); `details` исключений — только
     статические строки/`HTTP <код>` без ключа и материалов,
     это проверяет тест `generation_http_client_test.dart:281-293`; `Auth`/`x-api-key`/`x-goog-api-key`/
     query `key`/`api_key`/`apikey` редактируются санитайзерами (`log_redaction.dart`) и покрыты тестами;
   - `generation_jobs`/БД/экспорт в 3b ключей не касаются; Android `allowBackup="false"` +
     `fullBackupContent="false"` подтверждены в `android/app/src/main/AndroidManifest.xml:5-6`;
   - guard `no_secrets` не ослаблен (шаблоны `sk-…`/`sk-ant-…`/`AIza…` с длинами 20+/30+,
     самопроверка детектора) и зелёный в полном прогоне; тестовые заглушки ключей (`test-key-*`) под
     шаблоны не попадают; ключей в фикстурах нет.
7. **Контракты провайдеров (A8.2) — соответствуют SPEC/ADR-011:**
   - OpenAI: `POST https://api.openai.com/v1/chat/completions`, `Authorization: Bearer`,
     `response_format: {type: json_schema, json_schema: {name, strict: true, schema}}`,
     разбор `choices[0].message.content`, `refusal`, `finish_reason == length` → `truncated`,
     пустой контент → `emptyResponse` (тесты — по эталонным ответам, включая мусор/типы);
   - Gemini: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`,
     `systemInstruction`, `contents`, `generationConfig.responseMimeType/responseSchema`,
     `candidates[0]`, `finishReason` (`MAX_TOKENS` → `truncated`; `SAFETY`/`RECITATION`/`BLOCKLIST`/
     `PROHIBITED_CONTENT`/`SPII` → `refused`; `promptFeedback.blockReason` → `refused`), пустой
     candidate/текст → `emptyResponse`;
   - Anthropic: `POST https://api.anthropic.com/v1/messages`, `x-api-key` + `anthropic-version:
     2023-06-01`, `max_tokens`, `tools` с `emit_cards` + `tool_choice` `{type: tool, name: emit_cards}`,
     `stop_reason` (`max_tokens` → `truncated`, `refusal` → `refused`), нет `tool_use` →
     `invalidResponse`;
   - `truncated` — отдельный код от `invalidResponse` (для дробления фрагмента в 3c, ADR-011 §3);
   - разбор недоверенного JSON — через `jsonObjectOrNull`/`jsonListOrNull`/`jsonIntOrNull`, без
     `dynamic`-хаков (только неизбежные `Response<dynamic>` Dio); типы/`Map`/`List`/null проверяются;
     единственный найденный край — `Infinity` в `jsonIntOrNull` (находка #7).
8. **Схема и валидация (A8.2/A8.4):**
   - канон в `card_json_schema.dart` — **дословно A8.4**: все 7 свойств карточки в `required`,
     nullable `hint`/`source_excerpt`/`source_file` — union c `null`, `additionalProperties: false` на
     корне и карточке, enum `basic/basic_reversed/cloze`, `name = cards_response`; тест структуры +
     `json_schema.validate` (валидный/лишнее свойство/отсутствующий required/неверные типы/enum) —
     зелёные;
   - проекции: OpenAI — канон как есть; Gemini — `nullable: true`, типы в верхнем регистре, без
     `additionalProperties`, `propertyOrdering`, union-типов нет (проверяется рекурсивно); Anthropic —
     union → `anyOf` с `null`, `additionalProperties` сохранён; канон не портится проекциями;
   - контентные правила A8.4: `front` не пустой ≤500, `back` ≤2000, `cloze` регулярка + хотя бы один
     пропуск, теги ≤3/пустые/`#`, LaTeX через `flutter_math_fork` (`Math.tex(...).parseError`,
     инъекция в валидатор), `source_excerpt` — сжатие пробелов и проверка вхождения, иначе `null`;
     карточка **не отбрасывается**, ставятся машинные пометки (`CardIssueCode`); границы включительно
     проверены тестами;
   - системный промпт: `systemPromptGenRuV2` **побайтно равен SPEC A8.1** (сравнение скриптом:
     45/45 строк, 0 отличий) и `docs/system-prompt.md` (45 строк, 0 отличий); версия `gen-ru-v2`;
     пользовательское сообщение — `<materials>`, `<wishes>` только при непустых пожеланиях, `<limit>N</limit>`
     (проверено тестами, включая обрезку/ArgumentError на пустые материалы и limit<1).
9. **Ретраи/ошибки (A8.6) — в основном соответствуют, кроме #1/#2:** `429` → пауза по
   `Retry-After` (секунды и HTTP-date, отрицательное → 0), без заголовка — backoff с full jitter;
   `5xx`/таймауты/`connectionError` — backoff 1/2/4 с до 4 попыток (тест: 4 запроса, 3 паузы);
   `400/401/403` — без повторов (`badRequest`/`invalidApiKey`); отмена — `cancelled` без повтора;
   классификация статусов и `DioException` — по ADR-012 §2; двойного ретрая нет (Dio-перехватчика
   ретраев нет, `dio_smart_retry` не подключён); в `details` секретов нет; таймауты production-Dio
   15/60/180 с проверены интеграционным тестом; ARB-сообщения для всех 12 кодов — русские, ICU-плюрализация
   429 (`1 секунду`/`3 секунды`/`5 секунд`/`11 секунд`/`21 секунду`), сырые `details` не показываются
   (тесты маппинга).
10. **Архитектура/качество:** `lib/domain/generation/*` без Flutter/UI (architecture guard зелёный);
    новые модели — `const`-конструкторы, `final`-поля (списки — как в существующих доменных моделях
    проекта, напр. `Card`); Riverpod-проводка `app_providers` собирается и проверена интеграционным
    тестом (fake Dio + fake key store); `late`/`dynamic`-хаков нет; новых зависимостей, отключений
    анализатора, `// ignore` нет; `docs/api-schema.md`/`docs/system-prompt.md`/ADR-011/012/`docs/dependencies.md` §11
    в целом соответствуют коду (расхождения — находки #1, #5, #9, #11).
11. **Тестовые риски — flaky не обнаружено:** `RetryPolicy` принимает инжектируемые `jitter`/`now`;
    тесты используют детерминированные значения (`jitter: () => 1.0`, `now: () => DateTime.utc(...)`),
    fake-Dio без сети; в тестах нет реального времени/сети/платформенных каналов; `flutter_secure_storage`
    замокан/заменён fake-бэкендом. Полный прогон и точечный прогон стабильно зелёные.

## Что не проверено (остаётся на verify / ограничения)

- **L1:** живые вызовы OpenAI/Gemini/Anthropic не выполнялись (ключей нет); контракты подтверждены
  эталонными JSON и fake-HTTP. Live-тестов в срезе нет (осознанно: `plan.md` §«Вне объёма»), риск
  расхождения с реальными API остаётся известным ограничением — отразить в `KNOWN_LIMITATIONS.md`/verify.
- **Покрытие ≥80% (C14)** в ревью не измерялось (это шаг verify; `--coverage` не запускал, чтобы не
  создавать артефакты в снимке). Без покрытия не проверить точечные непокрытые ветки: отмена до
  отправки/во время паузы, `badCertificate`/`unknown` типы, пустой 2xx-ответ, `jsonIntOrNull`-границы,
  `source_excerpt == ''`, не-списочные теги (последние две защищены схемой).
- **`fvm flutter build windows --release`**, CI-прогон 3b, Linux/macOS/Android/iOS-сборки — verify/CI
  (CI 3b не выполнялся: нет push).
- **Платформенное поведение `flutter_secure_storage`** (Windows/Linux/macOS/Android/iOS, Keystore/Keychain)
  — не проверено на устройстве (юнит-тесты на fake-бэкенде).
- **`Retry-After` HTTP-date на уровне HTTP-клиента** — проверен только unit-тест `parseRetryAfter`;
  интеграционного теста «429 c датой» нет (не критично).
- **Фактический вывод красной фазы** не воспроизводился (снимок неизменяем; сверены идентичность тестов
  red↔green и `red-api.md`) — оценка TDD-доказательности по журналу + коду.

---

## Итог

**Вердикт: итерацию можно закрывать по ревью после fix-итерации по находкам #1 и #2 (medium) и
тривиальных #3–#4 (format/чистота дерева); blocker/critical/high отсутствуют.** Утечек ключей и
материалов, ослабления тестов/guard-ов, выключенного анализатора, двойных ретраев и битых контрактов
не найдено; 739 тестов зелёные, `analyze` чистый, системный промпт и канон-схема точно соответствуют SPEC.

**Обязательно до verify (шаг 5):**

1. **#1 (medium):** урегулировать `maxRetryAfter` — либо соблюдать `Retry-After` (тогда закрыть #2,
   чтобы отмена не ждала), либо явно задокументировать cap в ADR-012 §1 + `docs/api-schema.md` §6 +
   verify, обновив закрепляющий тест; отдельный fix-коммит.
2. **#2 (medium):** отмена должна прерывать паузу перед повтором (fix + тест «отмена во время паузы»);
   отдельный fix-коммит. Совместно с #1 закрывает риск «зависшая Отмена» в 3c.
3. **#3 (low, но гейт):** `fvm dart format lib test` + коммит; привести `journal/STATE.md` («format 0 changed»)
   в соответствие с фактом.
4. **#4 (low, процесс):** дерево должно быть clean к verify — закоммитить/обновить `journal/STATE.md`.
5. Перепроверить `fvm flutter analyze`, полный прогон, guard-тесты и добавить в verify: coverage,
   `build windows --release`, live-ограничение L1, `KNOWN_LIMITATIONS` для 3b, исправленные #5–#12
   (по желанию/в summary; #6/#8/#7 желательно в 3c, #9–#11 — docs-правки в шаг verify/summary).

**Проверка после fix-итерации (T23 → verify):** повторить `analyze`, `fvm flutter test
--exclude-tags golden` (ожидаемо 739 + новые тесты fix-коммитов), `fvm dart format --output=none
--set-exit-if-changed lib test` → 0 changed, `git status --short` → clean.
