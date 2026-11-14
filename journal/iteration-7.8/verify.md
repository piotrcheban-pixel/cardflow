# Проверка итерации 7.8 — вложения и Vision (2026-11-15)

## Команды и результаты (эта сессия)

| Команда | Результат |
|---|---|
| `fvm flutter test --exclude-tags golden` | **1324 passed + 2 skipped** (`All tests passed!`; skipped — live без ключа в env) |
| `fvm flutter test --coverage --exclude-tags golden` | **1324 passed + 2 skipped**, `coverage/lcov.info` |
| `fvm dart run tool/coverage_check.dart` | **92.7 % (9013/9721)**, порог 80 % пройден |
| `fvm flutter analyze` | `No issues found!` |
| `fvm dart format lib test integration_test` | 324 файла, 0 changed; `--set-exit-if-changed` — 0 changed |
| `fvm flutter build windows --release` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (52,2 с) |

Красная фаза — `red.md`/`red-phase.txt`; полный прогон зелёной фазы — `final-test.txt`; покрытие — `coverage-test.txt`.

## Критерии приёмки итерации

| # | Критерий | Статус | Доказательство |
|---|---|---|---|
| 1 | Word с `\x00`/`\x0B` → санитизация | **выполнено** | `text_sanitizer_test.dart`; `docx_parser_test.dart` — DOCX с NUL → `Первый абзац` без управляющих |
| 2 | Пустой текст → ошибка без сети | **выполнено** | `card_generation_service_test.dart`: `noMaterials`, `buildCalls == 0`, `transport.calls == 0` |
| 3 | vision=true + картинка → image part | **выполнено** | service → `buildArgs.images`; адаптеры OpenAI `image_url` data URI, Gemini `inlineData`, Anthropic `image`; интеграция production-графа: HTTP-тело `image_url` |
| 4 | vision=false + картинка → ошибка | **выполнено** | service `visionUnsupported` без запроса; widget-тест экрана; интеграция DeepSeek + PNG → HTTP 0 |
| 5 | PDF-скан: PDF-vision или понятная ошибка | **выполнено** | service: OpenAI → `pdfScanUnsupported`, Anthropic → `document` + beta-заголовок; Gemini → `inlineData application/pdf`; UI — скан-вложение и сообщение без Vision |
| 6 | 400 показывает реальную причину | **выполнено** | `generation_http_client_test.dart` (`invalid characters in content`), ARB `generationErrorBadRequestReason`, UI-маппинг; HTML/секреты не утекают |
| 7 | Любая модель: текст всегда работает | **выполнено** | прежние 1270 тестов зелёные; проверка Vision — до запроса, текст без вложений не зависит от Vision |
| 8 | 400/401/403/429/5xx не регрессировали | **выполнено** | `generation_http_client_test.dart`, `retry_policy_test.dart`, полный прогон |
| 9 | Настройки: каталог и кастомная модель | **выполнено** | `provider_preset_test.dart` (дефолты), `provider_account_test.dart` (JSON/инференс), widget-тесты диалога и карточки |
| 10 | Схема БД не менялась | **выполнено** | `app_settings` JSON `supports_vision`; миграции не нужны, старые записи читаются |
| 11 | Локализация/guard’ы | **выполнено** | `ru_strings`, `no_webview`, `no_secrets`, `architecture` — в полном прогоне; новые строки только ARB |
| 12 | Покрытие ≥ 80 % | **выполнено** | 92.7 % (9013/9721) |

## Не проверено / известно

- L52: живые Vision-вызовы облачных провайдеров (нет ключей OpenAI/Gemini/Anthropic; DeepSeek без Vision).
- L53: живой PDF-скан в Anthropic/Gemini.
- L54: инференс Vision по имени модели для старых кастомных аккаунтов.
- L55: ресайз/компрессия изображений >10 МБ (в MVP — ошибка).
- L56: реальный DnD изображения на ОС.
- Живой DeepSeek success-путь не перепроверялся в этой итерации: текстовая маршрутизация не менялась,
  сетевые тесты — fake; live-тест без ключа в env скипается (2 skipped).

## Вывод

Все критерии итерации 7.8 выполнены локальными гейтами; непроверенное живьём зафиксировано в
`journal/KNOWN_LIMITATIONS.md` (L52–L56) и не выдаётся за выполненное.
