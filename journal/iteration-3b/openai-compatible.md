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
| UI | экран «Настройки генерации» (OpenAI-совместимый сервер: адрес/модель/необязательный ключ, валидация, индикатор сохранённого ключа), маршрут `/settings/generation`, иконка в шапке экрана колод — `lib/ui/settings/generation_settings_screen.dart`, ADR-013 §6 |
| Строки | `app_ru.arb`: `generationErrorProviderNotConfigured` + `settings*` (латиница только `OpenAI`, «API» в UI не используется) |
| Документация | ADR-013, `docs/openai-compatible.md`, обновлён `docs/api-schema.md` (v2) |
| Live | `test/live/openai_compatible_deepseek_live_test.dart` (тег `live`, self-skip без `DEEPSEEK_API_KEY`) |

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
- UI: `fvm flutter test test/widget/settings/generation_settings_screen_test.dart test/unit/ui/app_router_test.dart
  test/widget/app_test.dart` → 19 passed (11 экранных: загрузка/ошибки/3 валидации/ключ/удаление; 6-й маршрут;
  production-wiring иконка → экран). Red-фаза UI: `+5 -14` (assertion-level: нет поля/индикатора/тултипа).
- Guard-тесты: `test/guards test/widget test/unit/ui` → 181 passed (после фикса подсказки ARB без «API»;
  `dart_test.yaml` удалён — guard `ci_pdfium` запрещает конфиг тегов, live-тег задан в `test(tags:)`).
- Полный прогон: `fvm flutter test --exclude-tags golden --coverage` → **800 passed + 1 skipped** (live);
  `coverage_check --min=80` → **95.1% (4071/4279)**; `fvm flutter analyze` → 0 issues;
  `fvm dart format --set-exit-if-changed lib test` → 0 changed; `fvm flutter build windows --release` → ок.
- CI (GitHub Actions, run `43505863077`, коммит `b850f6c`): **9/9 job success** (quality, test × 3 ОС,
  build-desktop × 3, build-mobile × 2); live-тест на CI self-skip без ключа.

## Live-проверка (L30)

**Не выполнена.** Владелец выбрал способ передачи ключа DeepSeek через переменную окружения
`DEEPSEEK_API_KEY`, но в процессе агента переменная отсутствует (проверено: present = нет; окружение
запущенного процесса не перечитывается). L30 остаётся как есть; «проверено» не заявляется. Тест готов:
после перезапуска сессии с переменной — `set DEEPSEEK_API_KEY=...` → `fvm flutter test test/live --tags live`;
необязательно `DEEPSEEK_BASE_URL` / `DEEPSEEK_MODEL`. Локальные Ollama/LM Studio не запущены (L32).
Результат будет внесён в ADR-013 §9, этот журнал и `KNOWN_LIMITATIONS.md` L30 после прогона.

## Ограничения и риски

- LM Studio/Ollama живьём не проверялись (серверы не запущены); контракт покрыт mock/fake-тестами.
- Fallback — осознанное отступление от «только strict»; ответ всё равно проверяется каноном A8.4.
- `http` не запрещён (нужен локальным серверам), ключ по `http` — риск пользователя (ADR-013 §3, §8).
- Один активный совместимый сервер; список моделей не вводится (post-MVP).
