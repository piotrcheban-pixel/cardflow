# Итерация 7.8 — универсальная обработка вложений (гибридный подход), 2026-11-15

**Статус:** завершена, локальные гейты зелёные; push `ea9fc16..5ac3789`, код-снимок CI
[`43650756271`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43650756271) — **9/9 job success**.
**Owner note:** любая модель; прямая загрузка файлов у провайдеров разная; Word — локальный текст +
санитизация; картинки/сканы — только при Vision.

## Сделано

1. **`TextSanitizer`** (`lib/domain/text/text_sanitizer.dart`) — единый санитайзер извлечённого
   текста: управляющие символы (`\x00`, `\x0B`, `\x07`, `\x7F`), CRLF, NBSP, хвостовые пробелы,
   сжатие пустых строк, trim; `normalizeDocumentText` делегирует в него; `CardGenerationService`
   повторно санитизирует материалы и пожелания. Пустой текст без вложений → `noMaterials` до сети.
   ARB: «В файле нет текста (скан или пустая форма)». Word-тест с `\u0000`/`\u000B` — зелёный.
2. **`supportsVision`** — `ProviderPresetModel.supportsVision` (каталог) и
   `ProviderAccount.supportsVision` (JSON `supports_vision`). Дефолты: GPT-4o/4o-mini, Gemini Flash,
   Claude 3.5, OpenRouter GPT-4o/Claude — true; DeepSeek Chat/Reasoner, Moonshot 8K, MiniMax Text,
   Groq Llama, Ollama llama/qwen — false. Старые записи: пресет/инференс по имени модели
   (`deepseek-flash` → true, `deepseek-chat`/`qwen2.5` → false). В диалоге пользовательской модели —
   переключатель; в карточке провайдера и диалоге каталога — подпись.
3. **Маршрутизация (API):** `GenerationAttachment` (JPG/PNG/PDF, base64, лимит 10 МБ);
   `GenerationRequest.images`, `GenerationRunRequest.images`, `GenerationChunk.images`; пайплайн
   режет текст как раньше, каждое вложение — отдельный фрагмент; имена в `generation_jobs.files` и
   `sourceFiles`; вложения в `GenerationChunkFailure` для повтора.
   - OpenAI/OpenAI-compatible — `image_url` data URI; PDF → `pdfScanUnsupported`.
   - Gemini — `inlineData` (image/PDF).
   - Anthropic — блоки `image`/`document` + beta-заголовок `pdfs-2024-09-25` для PDF.
   - vision=false: картинка → `visionUnsupported`; PDF-скан → `fileWithoutTextAndVision`;
     Vision без PDF-протокола → `pdfScanUnsupported`; >10 МБ → `attachmentTooLarge`.
4. **UI:** picker принимает JPG/JPEG/PNG; картинка не парсится, проверяется сигнатура; PDF без
   текстового слоя — скан-вложение; перед запуском проверяются Vision и PDF-возможность протокола;
   статусы «Изображение» / «Скан — отправится как изображение»; оценка токенов +1000 на вложение.
5. **400:** `GenerationHttpClient` извлекает `error.message`/`message`/`detail`, чистит управляющие
   символы, редактирует ключеподобные строки, ≤200 символов → `GenerationException.providerReason`;
   ARB «Запрос отклонён: {reason}»; `GenerationChunkFailure.providerReason` и
   `GenerationRunResult.fatalProviderReason` доходят до UI. Тела не логируются.
6. **Документы:** ADR-022, `docs/api-schema.md`, `docs/generation-pipeline.md`, `docs/parsers.md`,
   `AGENTS.md`, `KNOWN_LIMITATIONS.md` (L52–L56).

## Доказательства

| Команда | Результат |
|---|---|
| `fvm flutter test --exclude-tags golden` | **1324 passed + 2 skipped** |
| `fvm flutter test --coverage --exclude-tags golden` + `tool/coverage_check.dart` | **92.7 % (9013/9721)** |
| `fvm flutter analyze` | `No issues found!` |
| `fvm dart format lib test integration_test` | 324 файла, 0 changed |
| `fvm flutter build windows --release` | `cardflow.exe` (52,2 с) |
| CI run [`43650756271`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43650756271) (`5ac3789`) | **9/9 job success** |

## ADR итерации

- `docs/decisions/ADR-022-hybrid-attachments.md`.

## Осталось / не проверено

- L52–L56: живые Vision/PDF-сканы, инференс имени модели, >10 МБ, реальный DnD.
- Ручная приёмка владельцем: приложить JPG/PNG и PDF-скан к моделям с Vision/без Vision.
