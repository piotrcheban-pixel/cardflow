# Итерация 3b — расширение: провайдер «OpenAI-совместимый» (ADR-013)

**Дата:** 2026-11-13 · **Статус:** реализация завершена, проверка — ниже · **ADR:** `docs/decisions/ADR-013-openai-compatible-provider.md`
**Задача владельца:** четвёртый путь генерации — OpenAI-совместимый сервер с настраиваемым `base_url`
(DeepSeek, Ollama, LM Studio и любой Chat Completions). До итерации 3c, отдельно от неё; 3c не начиналась.

## Что сделано

| Слой | Файлы |
|---|---|
| Домен | `generation_provider.dart` (+`openaiCompatible`/`openai_compatible`), `generation_error.dart` (+`providerNotConfigured`), `openai_compatible_settings.dart`, `generation_settings_store.dart` |
| API | `openai_compatible_endpoint.dart` (разбор/нормализация `base_url`), `openai_compatible_adapter.dart` (копия логики OpenAI: endpoint из настроек, необязательный Bearer, отключаемый strict `response_format`), расширение контракта `generation_provider_adapter.dart` необязательными `baseUrl`/`strictSchema` (три прежних адаптера игнорируют) |
| Сервис | `card_generation_service.dart`: для `openaiCompatible` адрес+модель из настроек, ключ опционален; при `badRequest` — ровно один fallback без `response_format`; толерантное извлечение JSON из markdown/текста только для compatible-провайдера; та же схема A8.4 и контент-валидатор |
| Данные | `lib/data/generation/drift_generation_settings_store.dart` — одна строка `app_settings` (`generation.openai_compatible`, JSON `{baseUrl, model}`); ключ API в БД не пишется |
| Проводка | `app_providers.dart`: `generationSettingsStoreProvider`, `openAiCompatibleSettingsProvider`, 4-й адаптер в `generationAdapters`, сервис получает settings store |
| UI | экран «Настройки генерации» (OpenAI-совместимый сервер: адрес/модель/необязательный ключ), маршрут `/settings/generation`, иконка на экране колод — см. `journal/iteration-3b/openai-compatible-ui.md` |
| Строки | `app_ru.arb`: `generationErrorProviderNotConfigured` + `settings*` (латиница только `OpenAI`, «API» в UI не используется) |
| Live | `test/live/openai_compatible_deepseek_live_test.dart` (тег `live`, self-skip без `DEEPSEEK_API_KEY`); `dart_test.yaml` объявляет теги `live`/`golden` |

## Красная фаза (TDD)

1. `test/unit/domain/generation_domain_test.dart` → ожидаемо не компилировался:
   `Error: Member not found: 'openaiCompatible'`, `Member not found: 'providerNotConfigured'`.
2. Настройки/хранилище: новые тесты падали на отсутствии `OpenAiCompatibleSettings`/`DriftGenerationSettingsStore`
   (плюс пойман неверный тип в seed-строке — `Value<String>` вместо `String`; исправлен до реализации).
3. Адаптер/endpoint: падение на отсутствии `OpenAiCompatibleEndpoint`/`OpenAiCompatibleAdapter`.
4. Сервис: падение на отсутствующем параметре `generationSettingsStore` и новых ветках.
5. Проводка: падение интеграционных тестов на отсутствии `generationSettingsStoreProvider` и 4-го адаптера.

## Зелёная фаза — доказательства (локально, текущая сессия)

- `fvm flutter test test/unit/api/providers` → 44 passed (endpoint, compatible-адаптер, три эталонных адаптера).
- `fvm flutter test test/unit/api/generation/card_generation_service_test.dart` → 20 passed
  (включая fallback 400→без `response_format`, providerNotConfigured, markdown-извлечение только у compatible).
- `fvm flutter test test/integration/generation_pipeline_test.dart test/integration/app_providers_test.dart
  test/unit/ui/generation_error_message_test.dart` → 22 passed (production-граф: локальный сервер без ключа,
  DeepSeek strict 400 → fallback; `app_settings` через реальную БД).
- `fvm flutter test test/live` → 1 skipped (`Нет DEEPSEEK_API_KEY — live-тест пропущен (L30)`).
- `fvm flutter analyze` → No issues found.

## Live-проверка (L30)

Статус: **ожидает ключ владельца** (в окружении `DEEPSEEK_API_KEY` отсутствует). Пока ключа нет, L30
остаётся как есть; «проверено» не заявляется. Запуск при наличии ключа:
`set DEEPSEEK_API_KEY=...` → `fvm flutter test test/live --run-skipped --tags live`.
Результат будет внесён сюда и в ADR-013 §9 / `KNOWN_LIMITATIONS.md` L30.

## Ограничения и риски

- LM Studio/Ollama живьём не проверялись (серверы не запущены); контракт покрыт mock/fake-тестами.
- Fallback — осознанное отступление от «только strict»; ответ всё равно проверяется каноном A8.4.
- `http` не запрещён (нужен локальным серверам), ключ по `http` — риск пользователя (ADR-013 §3, §8).
- Один активный совместимый сервер; список моделей не вводится (post-MVP).
