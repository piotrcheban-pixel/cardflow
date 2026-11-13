# ADR-012 — HTTP-устойчивость, редактирование логов, хранение ключей

**Дата:** 2026-11-13 · **Статус:** принято (итерация 3b) · **Связано:** SPEC A8.6, 3.4; ADR-011;
`docs/dependencies.md`; `journal/iteration-3b/plan.md`

## Контекст

SPEC A8.6 требует: ключи только в `flutter_secure_storage`; Dio-перехватчик редактирует `Authorization`,
`x-api-key`, `x-goog-api-key` и поле `key` в query; тексты материалов пользователя в логи не пишутся;
ретраи — 429 с паузой по `Retry-After` (или экспоненциальный backoff с джиттером), 5xx и таймауты так же,
максимум 4 попытки; 400/401/403 — без повторов и сразу понятное сообщение; таймауты щедрые на приём,
разумные на соединение. UI-слой 3b не включает, поэтому логи живут в API-слое, а их sink инжектируется.

## Варианты

1. **Dio-перехватчик ретраев** (`onError` → повторный `fetch(requestOptions)`): стандартный подход, но
   повтор запроса внутри перехватчика плохо тестируется на количество/задержки, сложнее отмена и
   потоковые тела; собственный логирующий перехватчик всё равно нужен.
2. **Явный цикл попыток в `GenerationHttpClient` + чистый `RetryPolicy`** (выбран): политика — чистая
   функция с инжектируемыми random/now, HTTP-цикл — один `dio.postUri` на попытку; отмена проверяется
   до/после; тесты с fake `HttpClientAdapter` (спайк S3) детерминированы и быстрые.
3. `dio_smart_retry` как зависимость — новая зависимость ради ~60 строк логики, политику SPEC всё равно
   пришлось бы настраивать; отказ.

## Решение

### 1. Попытки и задержки (`lib/api/http/retry_policy.dart`)

- `maxAttempts = 4` (1 попытка + 3 повтора). Повторяются: HTTP 429; 5xx; таймауты
  (`connectionTimeout`/`sendTimeout`/`receiveTimeout`); сетевые ошибки (`connectionError`).
  Не повторяются: 400, 401, 403, остальные 4xx, ошибки разбора/схемы, отмена пользователя.
- 429: если есть `Retry-After` — пауза ровно по нему (секунды или HTTP-date, RFC 9110; отрицательное → 0);
  если заголовка нет — экспоненциальный backoff с джиттером.
- 5xx/таймауты/сеть: экспоненциальный backoff с джиттером: `delay = jitter01() * min(maxDelay,
  baseDelay * 2^(attempt-1))`, `baseDelay = 1 s`, `maxDelay = 30 s` (full jitter — не синхронизирует
  повторы разных фрагментов).
- Политика — чистая: принимает `attempt`, `statusCode`, флаги `isTimeout`/`isConnectionError`,
  `retryAfter`; отдаёт `RetryDecision(retry, delay)`. `jitter01` и `now` инжектируются — unit-тесты
  детерминированы.

### 2. Таймауты и транспорт (`lib/api/http/generation_http_client.dart`)

- `connectTimeout = 15 s`, `sendTimeout = 60 s`, `receiveTimeout = 180 s` (генерация десятки секунд;
  «щедрые на приём, разумные на соединение»). Стриминг в MVP не используется.
- Один `POST` JSON на попытку: `data: jsonEncode(body)`, `contentType: application/json`,
  `validateStatus: 2xx`; ответ обязан быть JSON-объектом, иначе `invalidResponse`.
- Классификация: таймаут → `timeout`; `connectionError` → `network`; 401/403 → `invalidApiKey`;
  400 (и прочие 4xx кроме 429) → `badRequest`; 429 после исчерпания попыток → `rateLimited`
  (с `retryAfter` последнего ответа); 5xx после исчерпания → `serverUnavailable`;
  отмена (`DioExceptionType.cancel`) → `cancelled`, не повторяется.
- `CancelToken` прокидывается от вызывающего (3c: кнопка «Отмена»).

### 3. Редактирование логов (`lib/api/http/log_redaction.dart`, `redacting_log_interceptor.dart`)

- Собственный `RedactingLogInterceptor` (Dio `LogInterceptor` не используется):
  - заголовки `authorization`, `x-api-key`, `x-goog-api-key` (регистр не важен) → `***`;
  - query-параметры `key`, `api_key`, `apikey` → `***` (плюс защита, если ключ попал в путь/query);
  - **тела запросов и ответов не логируются вообще** — в них материалы пользователя и ответ модели;
    логируются только метод, URI без секретов, статус, тип ошибки и длительность.
- Sink инжектируется (`void Function(String)`); в production-проводке включается только в debug
  (`kDebugMode`), в тестах — capture-функция. Гарантия проверяется тестом: значение ключа и текст
  материала не встречаются в выводе.
- Ключи не попадают в `toString` исключений: `GenerationException.details` не содержит ключ/материалы,
  UI их не показывает.

### 4. Хранение ключей

- Контракт домена: `ApiKeyStore { Future<String?> read(provider); Future<void> write(provider, key);
  Future<void> delete(provider); }`.
- Реализация: `lib/data/security/secure_api_key_store.dart` поверх `flutter_secure_storage 11.2.0`;
  ключи хранилища — `cardflow.api_key.<provider.wireName>`; чтение/запись только по одному провайдеру.
  Для тестируемости — узкий интерфейс `SecureKeyValueStore` (реализация — тонкая обёртка над плагином,
  тесты — in-memory fake).
- Android Auto Backup уже исключён в `android/app/src/main/AndroidManifest.xml`
  (`android:allowBackup="false"`, `android:fullBackupContent="false"` — факт итерации 0); ключи в БД,
  экспорте `.zip`, логах и `generation_jobs` не хранятся (нет полей).
- «Проверить» ключ (A6.6) — итерация 7: использует тот же store и адаптеры (малый запрос моделей/токенов);
  в 3b сетевого экрана нет.

### 5. Production-проводка

`lib/ui/state/app_providers.dart`: `apiKeyStoreProvider` (реальный store), `generationHttpClientProvider`
(Dio с таймаутами, redaction-перехватчиком, `RetryPolicy`) и `cardGenerationServiceProvider`
(адаптеры OpenAI/Gemini/Anthropic + валидатор). UI-потребитель появится в 3c; интеграционный тест проверяет
живой граф с fake-транспортом и fake-store (урок H1 итерации 2: фикс/слой подтверждается на
production-проводке).

## Последствия

- Ретраи не дублируют дорогие запросы на детерминированных ошибках (400/401/403) и отмене.
- Логи безопасны by design: нет тел — нет материалов/ключей; заголовки и query редактируются даже если
  провайдер/будущая база URL положат ключ в query.
- `Retry-After` и backoff детерминированно проверяются; джиттер не делает тесты флаки.
- Живые таймауты/ретраи провайдеров не проверены (L1, нет ключей); при появлении ключа — live-тесты
  под тегом `live`.
