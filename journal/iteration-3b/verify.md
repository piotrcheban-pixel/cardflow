# Итерация 3b — «Провайдеры». Проверка (шаг 5, T24)

**Дата:** 2026-11-13 · **Снимок:** `8d8f7d4` (`fix: address low review findings…`; после fix-итерации
`81efc9a`, `c7a8099`, `8d8f7d4`) · **Режим:** ИТЕРАЦИИ
**Ревью:** `journal/iteration-3b/review.md` — 0 blocker / 0 critical / 0 high / 2 medium / 10 low;
medium + lows закрыты fix-коммитами, каждый — с новым тестом.

## Команды и результаты (все — в этой сессии, текущее дерево)

| # | Команда | Результат |
|---|---|---|
| V1 | `fvm flutter test --exclude-tags golden` | **745 тестов, All tests passed** (было 603 до итерации; +142) |
| V2 | `fvm flutter analyze` | **No issues found!** (5.3 s) |
| V3 | `fvm dart format --output=none --set-exit-if-changed lib test` | **Formatted 178 files (0 changed)**, exit 0 |
| V4 | `fvm flutter test --coverage --exclude-tags golden` + `fvm dart run tool/coverage_check.dart --min=80` | **95.0% (3808/4007)**, порог 80% пройден |
| V5 | `fvm flutter build windows --release` | **`√ Built build\windows\x64\runner\Release\cardflow.exe`** (29.2 s) |
| V6 | `fvm flutter gen-l10n` (в зелёной фазе) | новые ARB-ключи сгенерированы, ICU-падежи работают |
| V7 | `git status --short` | clean (после docs-коммита; на момент verify — только docs/STATE под коммит) |
| V8 | guard-тесты в общем прогоне V1 | `no_webview`, `ru_strings`, `no_secrets`, `architecture`, `ci_pdfium` — зелёные |

Покрытие нового слоя (V4, рукописный код): `card_generation_service` 100%, `card_json_schema` 100%,
`card_response_schema` 100%, `generation_prompt` 100%, `latex_checker` 100%, `provider_json` 100%,
`secure_api_key_store` 100%, `generation_error_message` 100%, `anthropic_adapter` 100%,
`openai_adapter` 94.7%, `gemini_adapter` 90.4%, `generation_http_client` 94.3%,
`card_content_validator` 95.3%, `provider_schema` 90.4%, `generated_card` 76.7% (DTO-равенство),
`generation_result` 70.6% (DTO `toString`/равенство). Не измерены (нет исполняемых строк/интерфейсы):
`system_prompt.dart` (константа), `api_key_store.dart` (интерфейс) — в списке «не измерены» lcov.

## Сверка критериев приёмки итерации (C1–C15)

| # | Критерий | Статус | Доказательство |
|---|---|---|---|
| C1 | Канон-схема A8.4: required, nullable-union, `additionalProperties:false`, enum | **выполнено** | `test/unit/api/generation/card_schema_test.dart` (структура + `json_schema.validate`); ревью: побайтное сравнение с A8.4 |
| C2 | Проекции: OpenAI как есть; Gemini nullable/типы/`propertyOrdering`; Anthropic `anyOf` | **выполнено** | `card_schema_test.dart` группа «проекции»; `provider_schema.dart` 90.4% |
| C3 | OpenAI-адаптер: endpoint/заголовки/strict-схема; length→truncated, refusal→refused, пусто→emptyResponse | **выполнено** | `test/unit/api/providers/provider_adapters_test.dart`; интеграционный production-граф |
| C4 | Gemini: ключ только в `x-goog-api-key`, `responseMimeType/responseSchema`, MAX_TOKENS/SAFETY | **выполнено** | adapters test + `generation_pipeline_test.dart` (Gemini через production-граф) |
| C5 | Anthropic: tools `emit_cards` + `tool_choice`, tool_use, max_tokens/refusal/нет tool_use | **выполнено** | adapters test + production-граф (Anthropic) |
| C6 | Локальная валидация A8.4: длины, cloze, теги, LaTeX-пометка, source_excerpt | **выполнено** | `content_validator_test.dart` (14 тестов, пометки, не удаление) |
| C7 | Скрытый промпт `gen-ru-v2`, блоки `<materials>/<wishes>/<limit>` | **выполнено** | `prompt_test.dart`; ревью: промпт побайтно = SPEC A8.1 и `docs/system-prompt.md` |
| C8 | Retry/backoff: 429 Retry-After, 5xx/таймауты, 4 попытки, 400/401/403 без повторов; cap задокументирован | **выполнено** | `retry_policy_test.dart` + `generation_http_client_test.dart`; cap — ADR-012 §1, `docs/api-schema.md` §6 (ревью #1) |
| C9 | Логи: секретные заголовки/query редактируются, тела не логируются, материалы не утекают | **выполнено** | `redaction_test.dart`; ревью: утечек нет, `redactHeadersForLog` подключён к перехватчику (ревью #5) |
| C10 | Ключи только в secure storage, Android backup off, нет ключей в БД/экспорте/логах | **выполнено** | `api_key_store_test.dart` (fake backend + mocktail плагина); guard `no_secrets`; `AndroidManifest.xml:5-6`; ревью §6 |
| C11 | 12 кодов ошибок → ARB (ru), 429 «Повтор через N секунд», сырые исключения не утекают | **выполнено** | `generation_error_message_test.dart` (12 кодов, падежи, без details); план C11 поправлен (ревью #10) |
| C12 | Production-проводка: `ApiKeyStore`→`GenerationHttpClient`→адаптеры→сервис; живой граф | **выполнено** | `test/integration/generation_pipeline_test.dart` (7 тестов: OpenAI/Gemini/Anthropic, 401, нет ключа, таймауты Dio, 3 адаптера) — ревью #8 |
| C13 | Документация: ADR-011/012, `docs/api-schema.md`, `docs/system-prompt.md`, `docs/dependencies.md` §11 | **выполнено** | файлы в снимке; расхождения из ревью #9/#11/#12 исправлены |
| C14 | Качество: тесты/analyze/format/покрытие/Windows-сборка/guard | **выполнено** | V1–V5, V8 |
| C15 | Независимое ревью на снимке; high/medium закрыты fix-коммитами с новыми тестами | **выполнено** | `review.md`; fix-коммиты `81efc9a` (medium #2 + 2 теста), `c7a8099` (medium #1 + тест cap), `8d8f7d4` (lows #5–#12) |

## Что не проверено и почему (в `journal/KNOWN_LIMITATIONS.md`)

- **L1/L30:** живые вызовы OpenAI/Gemini/Anthropic — ключей нет (absent); контракты подтверждены эталонными
  JSON и fake-транспортом, live-тесты в срезе не добавлены (нет ключей). Реальные таймауты/`Retry-After`
  от провайдеров не проверялись.
- **L28:** платформенное поведение `flutter_secure_storage` (Keychain/Keystore/DPAPI) не проверялось —
  делегирование покрыто mocktail, контракт — in-memory fake; ручная проверка при экране настроек (итерация 7).
- **L29:** CI-прогон итерации 3b не выполнялся — push не запрашивался (по команде владельца).
- **L31:** осознанное отступление: при `Retry-After > 60 c` нет автоматического повтора (cap, ADR-012 §1);
  UI покажет «Повтор через N секунд».
- Сборки Linux/macOS/Android/iOS локально недоступны (хост) — CI после push (L2/L29).
- `Retry-After` HTTP-date проверен unit-тестом `parseRetryAfter`, но не интеграционным тестом клиента —
  принято (риск низкий, разбор один и тот же).
- Golden-тестов для новых экранов нет (экрана A6.8 в 3b нет — итерация 3c); L6.

## Итог

Итерация 3b: **выполнена** — все критерии C1–C15 закрыты доказательствами выше; ревью-находки закрыты
fix-итерацией; известные ограничения зафиксированы. Предусловия для 3c (API-слой, ключи, ошибки, промпт)
готовы; UI-экран A6.8 — итерация 3c.
