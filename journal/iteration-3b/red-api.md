# Итерация 3b — красная фаза (провайдеры)

**Дата:** 2026-11-13 · **Тесты:** 12 новых файлов, **136 тестов: 120 падений, 16 проходят**
(только тривиальные данные: `wireName`/`fromWire`, DTO-равенство `TokenUsage`/`GeneratedCard`, дефолты
`CardResponseSchema`/`ProviderRawResponse`, конфигурация production-Dio и сборка 3 адаптеров — поведения нет)
· **Команда:** `fvm flutter test <12 новых файлов>`

## Что создано в красной фазе

- **Скелеты production-кода** (без поведения, `UnimplementedError` там, где нужна логика):
  - домен: `lib/domain/generation/{generation_provider,generation_error,generated_card,generation_result,generation_request,api_key_store}.dart`;
  - схема/промпт: `lib/api/generation/{card_json_schema,card_response_schema,provider_schema,system_prompt,generation_prompt,latex_checker,card_content_validator,card_generation_service}.dart`;
  - адаптеры: `lib/api/providers/{generation_provider_adapter,openai_adapter,gemini_adapter,anthropic_adapter}.dart`;
  - HTTP: `lib/api/http/{retry_policy,generation_http_client,log_redaction,redacting_log_interceptor}.dart`;
  - данные/UI: `lib/data/security/secure_api_key_store.dart`, `lib/ui/generation/generation_error_message.dart`;
  - проводка: `lib/ui/state/app_providers.dart` (`apiKeyStoreProvider`, `generationDioProvider`,
    `generationHttpClientProvider`, `cardGenerationServiceProvider`, `generationAdapters`).
- **ARB-ключи** (11): `generationError*` + ICU-плюрализация для 429 (`{seconds, plural, …}`) + `fvm flutter gen-l10n`.
- **Тесты:** домен; канон-схема/валидация/проекции; промпт/пользовательское сообщение/LaTeX; контент-валидатор;
  3 адаптера; retry-политика; HTTP-цикл (fake `HttpClientAdapter`); redaction (санитайзеры + перехватчик);
  secure-хранилище ключей; сервис генерации; интеграционный срез production-проводки.
- **Хелперы:** `test/helpers/fake_http_adapter.dart` (fake-транспорт Dio), `test/helpers/generation_fakes.dart`
  (fake key store/адаптер/транспорт).

## Фрагменты вывода (ожидаемое vs получено)

```
00:06 +16 -120: Some tests failed.
```

- `GenerationProvider.fromWire`/DTO: ожидалось значение/равенство → получено (тривиальные данные, 16 pass).
- `copyCanonicalCardsResponseSchema`: ожидалось `return normally` → `любым способом`? Получено
  `UnimplementedError: copyCanonicalCardsResponseSchema` (канон-схема ещё пустая, A8.4 не заведена).
- `CardResponseSchema.validate`: ожидалось `[]` для валидного ответа → `threw UnimplementedError`.
- `projectCardSchema`/`geminiCardSchema`/`anthropicToolCardSchema`: ожидалось, что union `[T,"null"]`
  станет `nullable: true`/`anyOf` → `threw UnimplementedError`.
- `buildGenerationUserContent`: ожидалась строка `<materials>…</materials>\n<wishes>…</wishes>\n<limit>10</limit>`
  → `UnimplementedError`.
- `systemPromptGenRuV2`: ожидалось содержимое A8.1 (`contains('экспертный методист…')`) → `Actual: <''>`
  (пустая константа).
- `extractLatexFormulas`/`latexIsValid`: `UnimplementedError` (извлечения/проверки нет).
- `OpenAiAdapter.buildRequest`/`parseResponse`, `GeminiAdapter.*`, `AnthropicAdapter.*`: `UnimplementedError`
  (контрактов запроса/ответа нет; проверяются strict-схема, `finish_reason`/`finishReason`/`stop_reason`,
  refusal, пустой контент, отсутствие `tool_use`).
- `RetryPolicy.decide`/`parseRetryAfter`: `UnimplementedError` (политики ретраев нет; тесты ожидают
  backoff 1s/2s/4s, паузу по `Retry-After`, отсутствие повторов на 400/401/403).
- `GenerationHttpClient.postJson`: `UnimplementedError` (HTTP-цикла/классификации ошибок нет).
- `redactHeadersForLog`/`redactUriForLog`/`RedactingLogInterceptor.*`: `UnimplementedError` (редактирования
  логов нет; тесты проверяют отсутствие ключей/материалов/тел в выводе).
- `SecureApiKeyStore.read/write/delete`, `FlutterSecureKeyValueStore.*`: `UnimplementedError`.
- `CardContentValidator.validateResponse`: `UnimplementedError` (контентных правил A8.4 нет).
- `CardGenerationService.generate`: `UnimplementedError` (оркестрации ключ→промпт→адаптер→HTTP→валидация нет).
- `generationErrorCodeMessage`/`generationErrorMessage`: `UnimplementedError` (ARB-маппинга нет).
- Тривиально проходят: `provider.wireName`, DTO-равенство, дефолты, production-Dio (таймауты/перехватчик —
  конфигурация), «3 адаптера собраны» — поведения не проверяют.

## Проверки красной фазы

- `fvm flutter analyze` → **No issues found!** (скелеты и тесты компилируются; падения поведенческие).
- Fake-транспорт Dio (спайк S3) работает: HTTP-тесты доходят до `GenerationHttpClient.postJson`
  и падают на нём, а не на инфраструктуре.
- `fvm flutter test --exclude-tags golden` (полный прогон) — **603 старых теста зелёные** (проверено до
  красной фазы; новые поведенческие тесты падают ожидаемо).

## Ожидаемо зеленеет в зелёной фазе

Домен + канон-схема/валидация (T1–T6) → проекции/адаптеры (T7, T11–T14, параллельно http-dev) → HTTP/redaction/
ключи (T15–T17, T20, параллельно) → промпт/LaTeX (T8–T10) → контент-валидатор/сервис (T18–T19) →
UI-маппинг/ARB (T21) → интеграция (T22); после каждого слоя — тесты + `analyze`/`format`, отдельный коммит.
