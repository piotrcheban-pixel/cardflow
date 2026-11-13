# Итерация 3b — «Провайдеры». Итог (шаги 6–7)

**Дата:** 2026-11-13 · **Режим:** `ИТЕРАЦИИ` · **Статус:** завершена (`verify.md`, `review.md`)
**Цель (SPEC A8.2/A8.4/A8.5/A8.6):** API-слой генерации без UI: 3 адаптера провайдеров, единая каноническая
схема A8.4 и проекции, строгая локальная валидация, retry/backoff (429 `Retry-After`, 5xx, таймауты;
400/401/403 без повторов), редактирование логов (ключи/материалы не логируются), ключи только в
`flutter_secure_storage`, сообщения об ошибках — только ARB (ru).

## Сделано

- **Домен** (`lib/domain/generation/`): `GenerationProvider`, `GenerationErrorCode`/`GenerationException`
  (12 кодов + `retryAfter`), `GeneratedCard`/`CardIssueCode`, `TokenUsage`/`GenerationResult`,
  `GenerationRequest`, контракт `ApiKeyStore` — без Flutter.
- **Канон-схема A8.4** (`lib/api/generation/card_json_schema.dart`) + валидация через `json_schema 5.2.2`
  (`CardResponseSchema`); **проекции** (`provider_schema.dart`): OpenAI как есть, Gemini `nullable`/типы/
  `propertyOrdering`, Anthropic `anyOf` c `null` — программно от одного канона.
- **Скрытый промпт** `gen-ru-v2` (дословно A8.1) + сборка пользовательского сообщения
  `<materials>/<wishes>/<limit>`; проверка LaTeX через `flutter_math_fork` (`Math.tex(...).parseError`).
- **Контентные правила A8.4** (`card_content_validator.dart`): длины, cloze-маска, теги (≤3, без `#`),
  LaTeX-пометка, `source_excerpt` (сжатие пробелов + вхождение в исходник, иначе `null`) — карточка
  не отбрасывается, ставится машинная пометка.
- **Три адаптера** (`lib/api/providers/`): OpenAI Chat Completions + strict `response_format`; Gemini
  `generateContent` (ключ только в `x-goog-api-key`, `responseSchema`, `maxOutputTokens`); Anthropic
  `messages` + `tools emit_cards` + `tool_choice`; проверки причин остановки/refusal/пустого ответа/
  отсутствия `tool_use`, `truncated` отдельно (для 3c).
- **HTTP-слой** (`lib/api/http/`): `RetryPolicy` (4 попытки, 429 `Retry-After` сек./дата с осознанным
  cap 60 c, 5xx/таймауты/сеть — full-jitter backoff 1/2/4 c, 4xx без повторов, отмена прерывает паузу),
  `GenerationHttpClient` (Dio, таймауты 15/60/180 c, нормализация ошибок), `RedactingLogInterceptor`
  (редактированные заголовки/URI, тела не логируются), санитайзеры.
- **Сервис** (`card_generation_service.dart`): ключ из secure storage → промпт → адаптер → HTTP → разбор →
  схема → контент-валидация → `GenerationResult`; production-проводка `app_providers` (apiKeyStore,
  generationDio, generationHttpClient, cardGenerationService).
- **Хранилище ключей** (`lib/data/security/secure_api_key_store.dart`): `flutter_secure_storage`, ключи
  `cardflow.api_key.<provider>`, узкий тестируемый контракт; Android backup off.
- **Ошибки в UI** (`lib/ui/generation/generation_error_message.dart`) + 11 ARB-ключей (ICU-падежи для 429).
- **Документация:** ADR-011, ADR-012, `docs/api-schema.md`, `docs/system-prompt.md`, `docs/dependencies.md`
  §11, план/спайки/red/verify/review итерации.

## Доказательства

- `fvm flutter test --exclude-tags golden` → **745 тестов, all passed** (+142 к итерации 3a; 14 новых
  тестовых файлов, 2936 строк тестов);
- `fvm dart run tool/coverage_check.dart --min=80` → **95.0% (3808/4007)**; новый слой 90–100%
  (DTO 70.6–76.7%, см. verify);
- `fvm flutter analyze` → **0 issues**; `fvm dart format --set-exit-if-changed lib test` → **0 changed**;
- `fvm flutter build windows --release` → **`√ Built ... cardflow.exe`** (29.2 s);
- независимое ревью на снимке `e2801a6`: **0 blocker/critical/high, 2 medium, 10 low** → fix-коммиты
  `81efc9a`, `c7a8099`, `8d8f7d4` (каждый — с новым тестом/документацией);
- `git diff 856cf4a~1..HEAD -- test/` до fix-итерации — пусто (тесты red↔green не ослаблены; fix-тесты
  добавлены отдельно), guard-тесты и `pubspec*` не менялись; новых зависимостей нет.

## ADR итерации

- **ADR-011** — каноническая схема A8.4 и программные проекции под провайдеров, контракт адаптеров
  (`ProviderRequest`/`ProviderRawResponse`), локальная валидация пометками, 12 кодов ошибок, промпт
  `gen-ru-v2`; Flutter в API-слое — только `latex_checker.dart` (инъекция), `maxOutputTokens` по провайдерам.
- **ADR-012** — явный цикл повторов (без Dio-перехватчика ретраев), 429 `Retry-After` с осознанным cap 60 c,
  full-jitter backoff, отмена прерывает паузу, таймауты 15/60/180 c, собственный redaction-перехватчик
  (заголовки/URI редактируются, тела не логируются), ключи — `ApiKeyStore` поверх `flutter_secure_storage`.

## Коммиты итерации

`16a3e44` (docs: план/ADR-011/012/`docs/api-schema.md`/`docs/system-prompt.md`/спайки 3b),
`856cf4a` (red: 12 файлов тестов, 136 тестов), `926cc04` (домен/схема/промпт/валидация), `c342aef`
(адаптеры+проекции), `096b2c5` (HTTP/redaction/ключи), `e2801a6` (сервис/ARB/проводка), `81efc9a`
(fix medium #2), `c7a8099` (docs medium #1), `8d8f7d4` (lows #5–#12), `+ docs` (verify/summary/STATE/AGENTS/
KNOWN_LIMITATIONS).

## Что осталось (3c / ограничения)

- Экран A6.8, drag-n-drop, чанкинг по бюджету модели, оценка токенов, дедупликация, `generation_jobs`,
  кнопка «Отмена» в UI, предпросмотр — **итерация 3c** (слой 3b отдаёт всё нужное: `truncated`,
  `CancelToken`, `GenerationErrorCode`, `ApiKeyStore`).
- Live-вызовы провайдеров (L1/L30), платформенное secure storage (L28), CI 3b (L29), cap 429 (L31).
- «Проверить» ключ в настройках — итерация 7 (использует `ApiKeyStore` + адаптеры).

## Открытые вопросы к владельцу

Нет. Новых зависимостей/платных пакетов нет; SPEC не менялся; удаление функций не предлагалось.
Push коммитов 3b не выполнялся — по команде владельца (CI-прогон 3b тогда же).

## Улучшение процесса (шаг 7, ретроспектива)

1. **Сработало:** тесты-спецификация red-фазы как неизменяемый контракт + два исполнителя на
   непересекающихся write-scope (адаптеры; HTTP/безопасность) и Lead на ядре (домен/схема/промпт/
   валидатор/сервис/проводка) — оба слоя закрыты параллельно без конфликтов; независимое ревью на снимке
   нашло 2 реальных medium (отмена в паузе, недокументированный cap) — закрыты отдельными fix-коммитами
   с новыми тестами.
2. **Гейт формата:** `fvm dart format --output=none --set-exit-if-changed .` **не пишет** файлы и маскирует
   расхождение — на ревью это дало ложное «format 0 changed». Улучшение зафиксировано в `AGENTS.md`:
   перед коммитом — `fvm dart format lib test` (пишет) и проверка `--set-exit-if-changed lib test` (без
   `--output=none`), тогда `STATE.md` отражает факт.
3. **Замедлило:** объём итерации (26 production-файлов + 14 тестовых); в 3c — резать на подшаги
   (парсинг/чанкинг → экран → пайплайн) и заранее объявлять write-scope, как в 3b.
