# Итерация 7.8 — Универсальная обработка вложений (гибридный подход)

**Дата:** 2026-11-15 · **Режим:** ИТЕРАЦИИ · **Owner note:** приложение должно работать с любой
моделью; прямая загрузка файлов поддерживается провайдерами по-разному; Word — локальное
извлечение текста + санитизация; картинки/сканы — только при поддержке Vision.

## Факты о текущем состоянии (проверено командами в этой сессии)

| Проверка | Результат |
|---|---|
| `git status --porcelain` | пусто (рабочее дерево чистое) |
| `HEAD` / `origin/main` | `ea9fc16` / `ea9fc16` (docs-коммит итерации 7.6; в `STATE.md` было `5925ea0` — исправлено) |
| Flutter / Dart | 3.47.9 / 3.13.7 (FVM) |
| Текущие тесты (STATE 7.6) | 1270 passed + 2 skipped, покрытие 92.6 %, analyze 0 |
| Вложения генерации | только текст `ParsedDocument`: изображения не принимаются, PDF-скан — ошибка парсера |
| Причина 400 | в `GenerationException.details` только `HTTP 400`, тело ответа не разбирается |
| `supportsVision` | отсутствует в каталоге и аккаунте |

## Шаг 1. План

### 1.1 TextSanitizer (фикс Word-бага)

- `lib/domain/text/text_sanitizer.dart`: `TextSanitizer.sanitize()` — `\r\n`→`\n`, удаление
  управляющих (`\u0000-\u0008`, `\u000B`, `\u000C`, `\u000E-\u001F`, `\u007F`, `\u00A0`→пробел),
  обрезка хвостовых пробелов строк, сжатие 3+ `\n` до `\n\n`, `trim()`; `isEmpty()`.
- `normalizeDocumentText` делегирует в `TextSanitizer` — один нормализатор на все парсеры.
- `CardGenerationService` повторно санитизирует `materialsText`/`wishes` (защита от обхода).
- Пустой текст (без картинок) → `GenerationException(noMaterials)` **до** адаптера/сети;
  ARB-строка «В файле нет текста (скан или пустая форма)».

### 1.2 supportsVision

- `ProviderPresetModel.supportsVision` (каталог): OpenAI `gpt-4o`/`gpt-4o-mini` — true, Gemini
  Flash — true, Anthropic Claude 3.5 — true, DeepSeek Chat/Reasoner, Groq/llama, MiniMax Text,
  Ollama llama/qwen, Moonshot 8k — false; OpenRouter — по модели.
- `ProviderAccount.supportsVision` + JSON `supports_vision`; старые записи без поля: пресет →
  модель каталога, пользовательские → инференс по имени модели (`gpt-4o`, `claude`, `gemini`,
  `flash`, `vision`, `vl`; `deepseek-flash` из аккаунта владельца → true, `deepseek-chat` → false).
- Диалог пользовательской модели: переключатель «Модель принимает изображения»; при вводе имени
  модели без ручного переключения значение выводится из имени.
- Карточка провайдера и диалог каталога показывают, принимает ли выбранная модель изображения.

### 1.3 Маршрутизация (API-слой)

- Домен: `GenerationAttachment` (`fileName`, `mediaType` jpeg/png/pdf, `bytes`), лимит inline
  10 МБ; `GenerationRequest.images`, `GenerationRunRequest.images`, `GenerationChunk.images`.
- Пайплайн: текстовые фрагменты как раньше; изображения/сканы — отдельные фрагменты (1 файл =
  1 запрос), `sourceFiles` и `generation_jobs.files` включают их.
- Сервис для каждого фрагмента:
  - текст непустой → текст (любая модель);
  - картинка (JPG/PNG) и `supportsVision=true` → image part base64;
  - картинка и `supportsVision=false` → `visionUnsupported` («Модель не поддерживает изображения»);
  - PDF-скан и `supportsVision=true`, протокол принимает PDF (Anthropic/Gemini) → PDF-part;
  - PDF-скан и vision/protocol нет → `fileWithoutTextAndVision` / `pdfScanUnsupported`;
  - пустой текст без вложений → `noMaterials`.
- Адаптеры: OpenAI/OpenAI-compatible — `image_url` data URI; Gemini — `inlineData`; Anthropic —
  `image`/`document` блоки; PDF в OpenAI-совместимом адаптере — ошибка `pdfScanUnsupported`.
- UI: picker принимает JPG/JPEG/PNG; картинка грузится без парсера; PDF-скан сохраняется как
  вложение; перед генерацией проверяются `supportsVision` и PDF-возможность протокола.

### 1.4 Понятные ошибки 400

- `GenerationHttpClient` извлекает `error.message`/`message`/`detail` из тела 400/404/422,
  очищает управляющие символы, редактирует секретоподобные строки, ограничивает 200 символов.
- `GenerationException.providerReason` → `GenerationChunkFailure.providerReason` →
  UI-строка ARB «Запрос отклонён: {reason}» (для 400 с причиной), иначе прежняя строка.
- Тела запросов/ответов по-прежнему не логируются; ключи в причину не попадают.

### 1.5 ADR и документы

- `docs/decisions/ADR-022-hybrid-attachments.md` (контекст, варианты, решение, последствия).
- `docs/api-schema.md` — секция вложений/vision; `AGENTS.md` — абзац о маршрутизации;
  `journal/KNOWN_LIMITATIONS.md` — что не проверено живьём (Vision у облачных провайдеров).

## Шаг 2. Красная фаза (тесты до кода)

1. `test/unit/domain/text_sanitizer_test.dart` — NUL/VT/BEL, пустые строки, trim, идемпотентность.
2. `test/unit/api/parsers/docx_parser_test.dart` — DOCX с `\u0000` в `w:t` → текст без NUL.
3. `test/unit/domain/generation/provider_preset_test.dart`, `provider_account_test.dart` —
   дефолты `supportsVision`, JSON round-trip, инференс для старых записей.
4. `test/unit/api/generation/card_generation_service_test.dart` — пустой текст без сети; vision=true +
   картинка → image parts; vision=false + картинка → ошибка; PDF-скан без PDF-vision → ошибка;
   400 с `invalid characters in content` → причина в `GenerationException`.
5. `test/unit/api/providers/provider_adapters_test.dart` — image parts OpenAI/Gemini/Anthropic,
   PDF-блоки Gemini/Anthropic, отказ PDF в OpenAI-совместимом.
6. `test/unit/api/http/generation_http_client_test.dart` — 400 с телом → `providerReason`.
7. `test/unit/ui/generation_error_message_test.dart`, `parser_error_message_test.dart` — новые коды и
   строка с причиной.
8. Widget: `generation_screen_test.dart` — JPG с vision=true уходит в `GenerationRunRequest.images`;
   vision=false → сообщение без запуска; `generation_settings_screen_test.dart` — переключатель
   «изображения» сохраняется.
9. Интеграция: `generation_flow_test.dart` — production-граф, image-only → `image_url` в HTTP-теле;
   DeepSeek-аккаунт с изображением → `visionUnsupported` без HTTP-запроса.

## Шаг 3. Зелёная фаза

Домен → адаптеры → сервис → пайплайн → UI → ARB → тесты. Каждый шаг — отдельный зелёный коммит.

## Критерии приёмки итерации

| # | Критерий | Проверка |
|---|---|---|
| 1 | Word с `\x00` не ломает запрос | unit DOCX + `TextSanitizer` |
| 2 | Пустой текст — ошибка без сети | service test: `transport.calls == 0`, `buildCalls == 0` |
| 3 | vision=true + картинка → image part | service + адаптеры + интеграция HTTP-тела |
| 4 | vision=false + картинка → понятная ошибка | service + widget-тест |
| 5 | PDF-скан: PDF-vision или понятная ошибка | service + адаптеры |
| 6 | 400 показывает реальную причину | HTTP + ARB + UI-сообщение |
| 7 | Любая модель: текст всегда работает | прежние тесты + новые image-only пути |
| 8 | Сборка/анализатор/формат/покрытие | полный прогон, `analyze`, `format`, build windows |

## Риски и решения

- **PDF как inline-документ** ограничен по размеру у провайдеров → лимит 10 МБ и понятная ошибка;
  рендер страниц в изображения — post-MVP (нет требования).
- **Кастомные OpenAI-совместимые серверы** не имеют стандарта PDF-vision → считаем, что нет;
  PDF-скан для них — `pdfScanUnsupported`.
- **Инференс vision по имени модели** может ошибаться → переключатель в настройках и явное поле
  в JSON; ошибка провайдера вернётся понятной причиной 400.
- **Размер запроса base64** (+33 %) → лимит 10 МБ на файл.
- **Секреты/материалы** — тела не логируются; причина 400 очищается и редактируется.
