# STATE — текущее состояние CardFlow

**Дата:** 2026-11-15 · **Этап:** итерация **7.9** «Фиксы UI, PDF-сканы и Rich-генерация с поиском
картинок» — завершена локально (verify зелёный), ждёт push и CI · **Режим:** ИТЕРАЦИИ
**Факты (сверено командами в этой сессии):** на старте `git status --porcelain` → пусто, `HEAD` =
`origin/main` = `31a5999` (`docs: record green CI for attachment iteration`; в STATE 7.8 было
записано `5ac3789` — исправлено). Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11;
Android SDK/JDK/Xcode нет (L2).

**Push/CI (2026-11-15):** `origin/main = 31a5999`; код-снимок итерации 7.8 (`5ac3789`) — run
[`43650756271`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43650756271) —
**9/9 job success**.

## Следующее действие

1. Push коммитов 7.9 (`31a5999..HEAD`) и дождаться одного CI-прогона; записать run в STATE/AGENTS.
2. Отчёт владельцу и стоп до команды.
3. Дизайн (стекло, тени, анимации) — отдельная задача, не начиналась.

## Итерация 7.9 — итог

**Сделано:**
- Лента: контр-поворот обратной стороны (`Matrix4.rotationY(pi)`), widget-тест `m00 > 0`.
- PDF-скан < 50 символов → первые ≤ 4 страницы PNG (pdfrx + image, `Isolate.run`), один фрагмент
  по `groupKey`, `pdfScanVisionRequired` без Vision, fallback на PDF при сбое рендера.
- Схема/промпт `gen-ru-v3`: `image_query` и wire `card_type: occlusion`; Openverse-поиск без ключа
  (`ImageSearchService`, CC, ≤ 5 МБ, троттлинг); пайплайн привязывает `GeneratedCard.image`,
  occlusion → базовая маска по центру / понижение до basic с пометкой.
- Импорт: `MediaStore` + `media` + `media_json` + `occlusion_json` одной транзакцией; basic-карточка
  показывает иллюстрацию. ADR-023, docs, L57–L60.

**Доказательства (эта сессия):** `fvm flutter test --coverage --exclude-tags golden` → **1369 passed
+ 2 skipped**; покрытие **92.8 % (9277/9994)**; `analyze` 0; `format` 331 файл / 0 changed;
`fvm flutter build windows --release` → `cardflow.exe` (80,5 с); live DeepSeek — 2 passed
(`cards=3, tokens=1351`; fallback strict=400 → tolerant=200).
Детали — `journal/iteration-7.9/{plan,red,review,verify,summary}.md`.

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
