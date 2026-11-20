# ADR-039 — Происхождение характеристик модели и discovery

**Дата:** 2026-11-20 · **Итерация:** 7.18 «Планирование генерации» ·
**Статус:** принято.
Связано: SPEC A8.5/A6.6; ADR-011/012/013/020/021/022/024; аудит
`journal/iteration-7.18/audit.md` §5.1–5.2.

## Контекст

Аудит 7.18 показал: планировщик получает лимиты модели без происхождения и без
даты. Окно контекста берётся только из статического каталога пресетов
(`lib/domain/generation/provider_preset.dart:96–300`) — там нет ни `sourceRef`,
ни даты проверки; `maxInputTokens` не заполняется никогда; лимиты вывода,
изображений, тела запроса и цены задаются только вручную в JSON аккаунта, а в
UI полей нет. Discovery отсутствует: `lib/api/models/` не существует, `GET
/models` не вызывается. Поддержка изображений для legacy-записей выводится из
имени модели (`provider_account.dart:304–319`), а UI ставит флаг сам
(`provider_account_dialogs.dart:496–498`). Неизвестная модель получает
консервативные 6000/2048/8192 токенов (`generation_budget.dart:73,76,32`) без
явного источника в модели.

## Решение

### 1. Каждое значение — с источником, датой и ссылкой

```dart
enum CapabilitySource {
  userConfigured,   // введено пользователем в настройках модели
  providerApi,      // получено от API провайдера (discovery)
  officialCatalog,  // официальный каталог/документация приложения
  assumption,       // консервативное допущение приложения
  unknown,          // подтверждённого значения нет
}

final class Sourced<T> {
  const Sourced(this.value, {required this.source, this.observedAt, this.sourceRef});
  final T? value;
  final CapabilitySource source;
  final DateTime? observedAt; // для providerApi / userConfigured
  final String? sourceRef;    // URL/имя эндпоинта БЕЗ query-параметров
  bool get isKnown => value != null && source != CapabilitySource.unknown;
}
```

- `Sourced` — неизменяемое значение; «неизвестно» — `null`, а не 0.
- `sourceRef` не содержит query-параметров (в них бывают ключи); ключи и их
  хэши не сохраняются нигде.
- `observedAt` обязателен для `providerApi` и `userConfigured`; для
  `officialCatalog` дата проверки хранится в записи каталога/кэша.

### 2. `ModelLimits` и слияние по каждому полю

```dart
enum ContextSemantics { totalInputPlusOutput, inputOnly, unknown }

final class ModelLimits {
  final Sourced<int> contextTokens;
  final ContextSemantics contextSemantics;
  final Sourced<int> maxInputTokens;
  final Sourced<int> maxOutputTokens;
  final Sourced<int> maxRequestBytes;
  final Sourced<bool> supportsImageInput;
  final Sourced<bool> supportsPdfInput;
  final Sourced<bool> isReasoningModel;
  final Sourced<ModelPricing> pricing;
}
```

Слияние — **по каждому полю отдельно**, приоритет:
`userConfigured` → `providerApi` → `officialCatalog` → `assumption` → `unknown`.
`mergeModelLimits` берёт для каждого поля значение слоя с наибольшим рангом,
у которого значение известно. Если значение пользователя расходится со
значением API, в UI видны оба (пользовательское — действующее), рядом кнопка
«Сбросить к автоматическому» (в этом случае запись `userConfigured` удаляется и
поле снова берётся из `providerApi`/`officialCatalog`/`assumption`).

`ModelCapabilities` (существующий класс планировщика) не удаляется: его поля —
проекция `ModelLimits` для уже написанных потребителей. `resolveModelCapabilities`
продолжает работать, но получает данные из `ModelLimits`-слоёв, а не из
`ProviderAccount.contextTokens` (тот остаётся legacy-полем JSON и окном не
считается).

### 3. Discovery — порт в домене, резолвер на протокол в API

```dart
abstract interface class ModelCapabilityDiscovery {
  Future<DiscoveryResult> discover(ProviderAccount account, {CancelToken? cancel});
}

final class DiscoveryResult {
  final ModelLimits limits;      // поля со source=providerApi и observedAt
  final DateTime fetchedAt;
  final DiscoveryStatus status;  // success / unauthorized / timeout / unsupported / error
  final String? errorCode;       // только машинный код, не тело ответа
}
```

- Реализации — **по одной на протокол/провайдера** в `lib/api/models/`
  (`openai_models_discovery.dart`, `anthropic_models_discovery.dart`,
  `gemini_models_discovery.dart`, `ollama_models_discovery.dart`,
  `generic_openai_models_discovery.dart`). Универсальный JSON-парсер для всех
  провайдеров запрещён: у каждого свой ответ, пагинация и семантика поля.
- HTTP — только через существующий `GenerationTransport`/`provider_endpoint.dart`,
  с таймаутами (подключение ~10 с, ответ ~20 с), отменой и
  `RedactingLogInterceptor`; тела не логируются (ADR-012/024).
- Discovery **никогда** не вызывает генерацию и платные эндпоинты; только
  документированные GET-эндпоинты моделей (Anthropic/Gemini — пагинация;
  Ollama — нативные `GET /api/tags` + `POST /api/show`).
- Произвольный `baseUrl` — те же правила схемы/хоста, что у генерации; http
  разрешён только localhost/Ollama (как в `provider_endpoint.dart`); редиректы
  на другой хост не выполняются.
- Значения лимитов **не угадываются по имени модели**: модель `foo-128k`
  получает `unknown`, пока провайдер их не отдаст или пользователь не введёт.

### 4. Кэш `generation.model_capabilities` v1 (без изменения схемы БД)

Одно JSON-значение в существующей `app_settings` (по образцу
`generation.providers`, `drift_provider_accounts_store.dart:46`):

```json
{
  "version": 1,
  "records": [
    {
      "account_id": "...", "protocol": "openai_completions",
      "base_url": "https://api.deepseek.com", "model": "deepseek-flash",
      "fetched_at": "2026-11-20T12:00:00Z", "checked_at": "2026-11-20",
      "source_ref": "https://api-docs.deepseek.com/api/get-models",
      "limits": { "...": "wire-форма Sourced" },
      "last_error_code": null, "last_attempt_at": "2026-11-20T12:00:00Z"
    }
  ]
}
```

- Ключ записи — `accountId + protocol + нормализованный baseUrl + modelId`.
  Смена `baseUrl` или `modelId` даёт новую запись, старая остаётся как история.
- TTL — 7 дней. Устаревшая запись **используется** до успешного обновления.
- Ошибка обновления **не стирает** последнее удачное значение: пишутся
  `last_error_code` и `last_attempt_at`.
- Смена ключа API инвалидирует записи этого аккаунта (по событию сохранения
  ключа); значения ключа и его хэш в кэш не попадают.
- Когда обновляется: при сохранении аккаунта/модели; в фоне при открытии экрана
  генерации или настроек модели, если запись устарела (не блокирует экран); по
  кнопке «Обновить характеристики». **Построение плана никогда не обращается к
  сети за метаданными** — только к кэшу.

### 5. Миграция legacy-данных

| Что было | Как читается |
|---|---|
| `ProviderAccount.context_tokens`, введённый пользователем | `userConfigured` (observ = дата правки записи) |
| `contextTokens` из пресета | `officialCatalog` только если у пресета есть `sourceRef` и дата проверки; иначе `assumption` |
| `supports_vision` (JSON v2), заданный пользователем | `userConfigured` |
| `supports_vision` из пресета | `officialCatalog` при `sourceRef`+дате, иначе `assumption` |
| `inferSupportsVisionFromModelId` (ADR-022) | **больше не подтверждение**: значение рабочее, но `assumption`, в UI — метка «Предположение»; discovery перезаписывает |
| `max_output_tokens`/`max_images_per_request`/`max_image_bytes`/`max_request_bytes` (JSON v2) | `userConfigured` |
| `pricing` (JSON v2) | `userConfigured` |

Wire-имена `capabilities_source` меняются на `user_configured`/`provider_api`/
`official_catalog`/`assumption`/`unknown`; чтение старых значений
(`user`/`preset`/`verified`/`inferred`) поддерживается и отображается в новые:
`user→userConfigured`, `preset|verified→officialCatalog`, `inferred→assumption`.

### 6. Что проверено по документации провайдеров (2026-11-20)

| Провайдер | Источник/проверка | Что реализовано |
|---|---|---|
| DeepSeek | `https://api-docs.deepseek.com/quick_start/pricing` (HTTP 200): модели `deepseek-flash` 1M, `deepseek-v4-pro` 1M, цены; страница `api/get-models` редиректит на quickstart — **поля ответа `/models` не документированы** | `GET {base}/models`; `id` доверяется; `context_window`/`max_output_tokens` принимаются, если присутствуют и корректны, иначе `unknown` |
| Ollama | `https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md` (HTTP 200): `GET /api/tags` → `models[].name/model/details`; `POST /api/show` → `model_info` (`<arch>.context_length`), `capabilities`, `parameters` (`num_ctx`) | Нативно: теги + show; контекст — `providerApi`, рабочий `num_ctx` — `assumption` (`ollama_num_ctx_assumption`) |
| OpenRouter | `https://openrouter.ai/docs/api_reference/models` (HTTP 200), но таблица полей в полученном тексте отсутствует | Структура по гипотезе задания (`context_length`, `top_provider.*`, `architecture.input_modalities`, `pricing` за токен); поля принимаются только при корректном типе; помечено «не сверено» |
| Anthropic | `docs.anthropic.com/en/api/models-list` → 301 на `platform.claude.com` → **404**; сверка не удалась | `GET /v1/models` + `after_id`-пагинация, `max_input_tokens`/`max_tokens`/`capabilities` — только если присутствуют; `inputOnly` |
| Gemini | `ai.google.dev/api/models` → редирект на `aistudio.google.com`, сверка не удалась | `GET v1beta/models` + `pageToken`, `inputTokenLimit`/`outputTokenLimit`/`supportedGenerationMethods`; `inputOnly` |
| OpenAI | Веб-страница API reference без авторизованного доступа не получена | `GET /v1/models`: только `id`; лимиты `unknown` |
| Groq / Moonshot / MiniMax | Документация не проверялась (время истекло, внешний блокер) | `id` + присутствующие поля с проверкой типов, иначе `unknown` |

Если поле не документировано или отсутствует — значение `unknown` (или
`assumption` с предупреждением), а не «типовое число семейства». Фикстуры
`test/fixtures/discovery/<provider>/*.json` построены по документированной
структуре (Ollama) и по гипотезе задания (остальные) — это зафиксировано в
`KNOWN_LIMITATIONS.md`.

## Последствия

- Планировщик больше не выдумывает лимиты: у каждого значения есть источник и,
  где применимо, дата; неизвестное честно помечено и видно в UI.
- Появляется сетевой вызов discovery, но **не** в пути построения плана: план
  читает только кэш. Ошибка/таймаут discovery не ломает генерацию.
- Схема БД и `schemaVersion` не меняются (кэш — JSON в `app_settings`).
- Идентификаторы моделей и документация могут устареть: TTL и кнопка
  «Обновить характеристики» — механизм обновления, а не гарантия.

## Ограничения

- Точные пределы моделей известны только там, где провайдер их документирует
  (видно в таблице фазы 3); у OpenAI `GET /v1/models` лимитов не отдаёт.
- Ollama: `model_info["<arch>.context_length"]` — максимум обучения; рабочий
  `num_ctx` меньше, пока его не задал пользователь (`assumption` +
  предупреждение).
- Живые запросы в этой итерации запрещены: discovery проверяется только на
  mock-HTTP и фикстурах.
