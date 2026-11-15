# STATE — текущее состояние CardFlow

**Дата:** 2026-11-16 · **Этап:** итерация **fix-gen** «Исправление генерации»
(Д1–Д6, ADR-029/ADR-030) — пройдены локальные гейты, **push выполнен** · **Режим:** ИТЕРАЦИИ
**Факты (сверено командами в этой сессии):** на старте `git status --porcelain`
→ пусто, `HEAD = origin/main = c95e5a9` (`docs: record green CI for image ux
iteration`) — в STATE 7.12 был записан `c6dd64e`, после него был docs-коммит,
исправлено. Baseline — **1512 passed + 5 skipped** (7.12).
Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode нет (L2).
Прогоны — только с `--no-pub` (L64).

**Гейты fix-gen:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **1597 passed + 7 skipped** · покрытие рукописного кода **92.3 % (10814/11720)**
· `analyze` **0** · `dart format --set-exit-if-changed lib test integration_test`
→ **378 / 0 changed** · `build windows --release --no-pub` → `cardflow.exe`
(70,5 с) · Windows-смоук `integration_test/session_smoke_windows_test.dart
-d windows` → **All tests passed!** (10 с) · **живые тесты** 10 passed
(`deepseek-chat`): prompt-only v5 `cards=3, image_query=3, rejected=0`;
**статика 20 карточек, доля пометок 0.0 %**; **DOCX с рисунком: `images=1,
cards=9, image_id=1, with_image=1`**; PDF-скан `pages=3, cards=2`;
картинки 3/3 (Wikimedia).

## Следующее действие

1. Дождаться CI на снимке итерации (9 job'ов: format+analyze, test × 3 ОС,
   build desktop × 3, build mobile) — статус в отчёте.
2. Ручная приёмка владельцем (D1–D6): генерация без файлов по теме; DOCX с
   рисунками/формулами; частичный сбой → импорт. Скриншоты — за владельцем (L78).
3. Открытые вопросы: отдельная колонка причин сбоя в БД (сейчас перечень в
   `error_code`); изображения внутри PDF (L76); ключевой источник картинок (L71).

## Итерация fix-gen — итог

**Причины (диагностика `journal/iteration-fix-gen/diagnosis.md`):**
- Д4/Д6: модель пишет LaTeX одним `\` в JSON → `\frac`→form feed, `\alpha`→
  `FormatException`; фрагмент падал `invalidResponse`, формула молча портилась.
- Д6: все схема- и структурно-невалидные карточки роняли фрагмент; предпросмотр
  не импортировал пак из-за одной невалидной карточки.
- Д3: изображения файлов не извлекались (парсеры читали только текст).
- Д2: производный `image_query` из текста вопроса давал случайные картинки.

**Сделано:**
- Промпт `gen-ru-v5` дословно (`lib/api/prompts/system_prompt.dart` +
  `docs/prompts/gen-ru-v5.txt`, тест байт-в-байт); блоки `<materials>`,
  `<wishes>`, `<limit>`, `<images>`; `Файл: <имя>`; лимит карточек из пожеланий
  делится по фрагментам пропорционально (`generation_card_limit.dart`).
- Схема A8.4 + `image_id`, поштучная проверка, проекции OpenAI/Gemini/Anthropic
  (ADR-029); валидатор: `image_id` вне каталога → null; `image_query` — латиница
  ≤ 7 слов; абстрактные понятия без картинки; tags ≤ 3.
- LaTeX: `latex_escape_repair.dart` (до/после JSON), `\(\)`/`\[\]` → `$…$`,
  `\$` не формула; `LatexText`/`ClozeText`/`InlineLatexText` через `Math.tex`.
- Изображения DOCX/PPTX/ODT (`DocumentImage` + контекст, фильтры мусора) →
  `<images>` фрагмента → `image_id` → байты файла; предпросмотр: убрать/заменить.
- Причины сбоя фрагмента (`GenerationFailureReason`, 13 кодов) в
  `generation_jobs.error_code` и debug-лог; частичный импорт; кнопка неактивна
  только без выбранных карточек; ошибки «Фрагмент K из M: причина».
- Д5: мягкие проверки качества (7 пометок) + eval-набор 3 сценария + live-метрика.
- Д1: кнопка неактивна без файлов/темы, подсказка ARB, имя колоды из темы,
  `source_excerpt` при пустых материалах → null.

**Доказательства:** `journal/iteration-fix-gen/{diagnosis,red-output,review,verify,summary}.md`;
тесты `latex_escape_repair_test`, `latex_render_fix_test`, `document_images_test`,
`card_generation_images_test`, `generation_fix_gen_test`, `card_quality_test`,
`quality_eval_test`, `generation_preview_partial_test`, `failure_reasons_test`,
`generation_failure_message_test`, `prompt_test` (байты).

## Известные ограничения (актуальные)

L1, L2, L4–L8, L10–L16, L18–L20, L23–L25, L27, L28 (только Windows), L30,
L31–L34, L35, L36, L37–L44, L46–L52, L53 (живой PDF-part), L54, L55, L56,
L57–L59 (≤ 3 страниц), L60 (снято 7.12; предпросмотр — fix-gen), L61, L62–L64,
L65, L66 (обновлено L80), L67, L68, L69, L70, L71–L75,
**L76** (изображения внутри PDF не извлекаются), **L77** (только JPEG/PNG из
документов), **L78** (ручные клики/скриншоты владельца), **L79** (причины
сбоя перечнем в `error_code`), **L80** (поштучный отброс карточек моделей,
не следующих strict-схеме).

## История

- fix-gen «Исправление генерации» (2026-11-16) — ADR-029/030, гейты выше.
- 7.12 «Фикс UX картинок, лимитов и поиска ИИ» — CI run `43750931989` 9/9.
- 7.11 «FSRS новых карточек, картинки, сканы и Practice Mode» — CI run
  `43742161910` 9/9.
- 7.10 «Prompt-only, PDF и картинки» — CI run `43728048903` 9/9.
- 7.9 «PDF-сканы, иллюстрации и occlusion» — CI run `43703387395` 9/9.
- 7.8 «Вложения и Vision» — ADR-022, CI run `43650756271` 9/9.
- 7.6 «Пустой ответ LLM» — CI runs `43637919516`/`43639479927` 9/9.
- 7.5 «Провайдеры и ключи» — ADR-020, CI run `43632334916` 9/9.
