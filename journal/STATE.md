# STATE — текущее состояние CardFlow

**Дата:** 2026-11-15 · **Этап:** итерация **7.10** «Фикс генерации без файлов, PDF и картинок»
(ADR-024) — завершена локально, verify зелёный; **push выполнен, CI 9/9 success** · **Режим:** ИТЕРАЦИИ
**Факты (сверено командами в этой сессии):** на старте `git status --porcelain` → пусто,
`HEAD = origin/main = bdb0bd1` (`docs: record green CI for iteration 7.9`; в STATE 7.9 было
записано `31a5999` — исправлено). Baseline — **1369 passed + 2 skipped**. Flutter 3.47.9 /
Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode нет (L2). Прогоны — только с `--no-pub`:
`fvm flutter test`/`build` без него зависают на `dart pub get --example` (сеть pub в сессии агента).

**Push/CI (2026-11-15):** `origin/main = 5cbb653` (`bdb0bd1..5cbb653`, 2 коммита итерации
7.10); код-снимок `5cbb653` — run
[`43728048903`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43728048903) —
**9/9 job success** (`format + analyze`, `test` × 3 ОС, `build-desktop` × 3, `build-mobile`
Android + iOS). Предыдущий снимок 7.9 — run `43704209787` 9/9.

## Следующее действие

1. **Стоп:** итерация 7.10 принята локальными гейтами; код-снимок CI 9/9; ждать команды владельца.
2. Приёмка владельцем: (а) сгенерировать карточки **без файлов** по теме; (б) загрузить PDF —
   при нечитаемом тексте строка «PDF содержит нечитаемый текст», при 400 — причина API в UI;
   (в) Word/тема → карточки с картинками; предпросмотр показывает иллюстрацию.
3. Дизайн (стекло, тени, анимации) — отдельная задача, не начиналась.

## Итерация 7.10 — итог

**Сделано (ADR-024):**
- Prompt-only: файлы необязательны; тема в `<wishes>`; пустой `<materials>`; промпт `gen-ru-v4`
  (карточки по общим знаниям, `source_excerpt=null`); `noMaterials` — только без любого входа.
- PDF: `TextSanitizer` удаляет C1/Unicode Cc-Cf/BOM/zero-width/bidi/одиночные суррогаты;
  `PdfTextQuality` → `ParserErrorCode.garbledText` (5 замен / 5 %); ARB «PDF содержит нечитаемый
  текст».
- Диагностика: `GenerationDiagnostics` (debug-only, release no-op) — тело ошибки провайдера,
  сырой ответ модели (`image_query`), итог поиска картинки; редакция секретов, лимит 2000.
  400 → в UI безопасная причина провайдера (сквозной тест).
- Картинки: `image_query` обязателен для предметных `basic`/`cloze`; интеграционный тест с
  реальным `ImageSearchService` (Openverse через fake-Dio) → картинка → `media` + файл.

**Доказательства:** `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1409 passed
+ 3 skipped**; покрытие **92.9 % (9393/10114)**; `analyze` 0; `format` 334 файла / 0 changed;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (63,9 с). **Живой DeepSeek:** 3
live-теста passed — `cards=3, tokens=1467`; fallback `strict=400 → tolerant=200`;
**prompt-only без файлов: `cards=3, image_query=3, prompt=gen-ru-v4, tokens=1502`**.
Детали — `journal/iteration-7.10/{plan,red-output,review,verify,summary}.md`.

## Известные ограничения (актуальные)

L1, L2, L4–L8, L10–L16, L18–L20, L23–L25, L27, L28 (только Windows), L30 (DeepSeek success;
негативные контракты — ADR-014), L31–L34, L35, L36, L37, L38–L44, L46–L51,
**L52** (живые Vision-вызовы), **L53** (живой PDF-скан), **L54** (инференс Vision по имени модели),
**L55** (изображения >10 МБ не сжимаются), **L56** (реальный DnD изображения),
**L57** (Openverse-лимиты), **L58** (атрибуция CC), **L59** (≤ 4 страницы PDF/Vision),
**L60** (замена иллюстрации basic), **L61** (живой Openverse с хоста агента),
**L62** (качество prompt-only), **L63** (эвристический порог garbledText),
**L64** (живые проблемные PDF владельца).

## История

- 7.9 «PDF-сканы, иллюстрации и occlusion» — CI run `43703387395` 9/9; summary —
  `journal/iteration-7.9/summary.md`.
- 7.8 «Вложения и Vision» — ADR-022, CI run `43650756271` 9/9.
- 7.6 «Пустой ответ LLM» — CI runs `43637919516`/`43639479927` 9/9.
- 7.5 «Провайдеры и ключи» — ADR-020, CI run `43632334916` 9/9.
