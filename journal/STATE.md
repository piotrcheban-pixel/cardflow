# STATE — текущее состояние CardFlow

**Дата:** 2026-11-15 · **Этап:** итерация **7.8** «Универсальная обработка вложений (гибридный подход)» —
локальные гейты зелёные, готово к push · **Режим:** ИТЕРАЦИИ
**Факты (сверено командами в этой сессии):** на старте `git status --porcelain` → пусто, `HEAD` =
`origin/main` = `ea9fc16` (docs-коммит итерации 7.6; в STATE 7.6 было записано `5925ea0` — исправлено).
Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode нет (L2).

## Следующее действие

1. Push всех коммитов итерации 7.8, дождаться одного прогона CI (9/9 job), записать run в STATE.
2. Приёмка владельцем: приложить JPG/PNG и PDF-скан к модели с Vision и без: картинка при Vision
   уходит в генерацию, без Vision — «Модель не поддерживает изображения»; Word с управляющими
   символами больше не даёт 400; при 400 в сообщении видна реальная причина.
3. Дизайн (стекло, тени, анимации) — отдельная задача, не начиналась.

## Итерация 7.8 — итог

**Сделано (ADR-022):**
- `TextSanitizer` — единый санитайзер локального текста (NUL/VT/BEL/DEL, CRLF, NBSP, пустые строки,
  trim); `normalizeDocumentText` делегирует; сервис повторно санитизирует материалы/пожелания;
  пустой текст → `noMaterials` до сети, ARB «В файле нет текста (скан или пустая форма)».
- `supportsVision` у `ProviderPresetModel` и `ProviderAccount` (JSON `supports_vision`, инференс для
  старых записей); переключатель в диалоге пользовательской модели, подписи в каталоге/карточке.
- `GenerationAttachment` (JPG/PNG/PDF, ≤10 МБ) + маршрутизация: текст — любой модели; картинки —
  image part при Vision; PDF-скан — только Anthropic/Gemini (PDF-part), иначе понятные ошибки
  `visionUnsupported`/`fileWithoutTextAndVision`/`pdfScanUnsupported`/`attachmentTooLarge`.
- Адаптеры: OpenAI/compatible `image_url`, Gemini `inlineData`, Anthropic `image`/`document` +
  `anthropic-beta: pdfs-2024-09-25` для PDF.
- Пайплайн: вложения — отдельные фрагменты (1 файл = 1 запрос), имена в `generation_jobs.files`,
  вложения в `GenerationChunkFailure` для повтора.
- UI: JPG/JPEG/PNG в picker, скан-вложение PDF, проверка Vision/PDF-протокола до запуска, статусы
  «Изображение» / «Скан — отправится как изображение», +1000 токенов оценки на вложение.
- 400: `providerReason` (очищенная причина провайдера, ≤200 симв.) → ARB «Запрос отклонён: {reason}»,
  сквозь пайплайн/предпросмотр; тела запросов/ответов не логируются.

**Доказательства:** `fvm flutter test --coverage --exclude-tags golden` → **1324 passed + 2 skipped**
(live без ключа в env); покрытие рукописного кода **92.7 % (9013/9721)**; `fvm flutter analyze` →
`No issues found!`; `dart format` 324 файла → 0 changed; `fvm flutter build windows --release` →
`cardflow.exe` (52,2 с).

**Документы:** `journal/iteration-7.8/{plan,red,review,verify,summary}.md`,
`docs/decisions/ADR-022-hybrid-attachments.md`, обновлены `docs/api-schema.md`,
`docs/generation-pipeline.md`, `docs/parsers.md`, `AGENTS.md`, `KNOWN_LIMITATIONS.md` (L52–L56).

## Известные ограничения (актуальные)

L1, L2, L4–L8, L10–L16, L18–L20, L23–L25, L27, L28 (только Windows), L30 (DeepSeek success;
негативные контракты — ADR-014), L31–L34, L35, L36, L37, L38–L44, L46–L51,
**L52** (живые Vision-вызовы), **L53** (живой PDF-скан), **L54** (инференс Vision по имени модели),
**L55** (изображения >10 МБ не сжимаются), **L56** (реальный DnD изображения).

## История

- 7.6 «Пустой ответ LLM» — завершена, CI run `43637919516`/`43639479927` 9/9; подробности —
  `journal/iteration-7.6/summary.md`.
- 7.5 «Провайдеры и ключи» — ADR-020, CI run `43632334916` 9/9.
