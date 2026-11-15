# Проверка (fix-gen, шаг verify)

**Снимок:** рабочее дерево после правок ревью (см. коммиты итерации).
**Дата:** 2026-11-16.

## Гейты

| Гейт | Команда | Результат |
|---|---|---|
| Формат | `fvm dart format lib test integration_test` → `fvm dart format --set-exit-if-changed lib test integration_test` | 378 файлов, **0 changed** (после записи) |
| Анализатор | `fvm flutter analyze --no-pub` | **No issues found!** (63,8 с) |
| Тесты | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **1597 passed + 7 skipped** (skipped — live без ключа в env прогона; живьём запускались отдельно) |
| Покрытие | разбор `coverage/lcov.info` (lib/, без `*.g.dart`/`*.freezed.dart`/l10n) | **92.3 % (10 814/11 720)** ≥ 80 % |
| Windows-сборка | `fvm flutter build windows --release --no-pub` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (70,5 с) |
| Windows-смоук | `fvm flutter test --no-pub integration_test/session_smoke_windows_test.dart -d windows` | **All tests passed!** (10 с): Basic+картинка без масок через реальную форму, лимит, генерация → Wikimedia → предпросмотр → media |
| Guard-тесты | входят в полный прогон | зелёные (`no_webview`, `ru_strings`, `no_secrets`, `architecture`, `ci_pdfium`) |

## Живые тесты (ключ `DEEPSEEK_API_KEY`: present в Windows User scope; значение не выводилось)

`$env:DEEPSEEK_API_KEY = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY','User'); fvm flutter test --no-pub test/live --tags live` → **10 passed**.

Ключевые доказательства (`deepseek-chat`):

- prompt-only, животные: `cards=3, image_query=3, abstract_query=0,
  latex_broken=0, rejected=0, prompt=gen-ru-v5, tokens=4436`.
- **Д5:** тема «Статика: аксиомы, связи, плоские фермы»:
  `cards=20, prompt=gen-ru-v5, rejected=0, tokens=6293, marked=0 (0.0 %), issues={}`.
  Первые 10 карточек дословно (front / back / image) — в `summary.md`.
- **Д3:** DOCX с рисунком: `images=1, status=done, cards=9, image_id=1,
  with_image=1, tokens=5504` — модель выбрала изображение из файла (каталог
  `<images>` работает и живьём, байты файла в карточке).
- Картиночный пайплайн: `status=done, cards=3, failures=[]`,
  `with_image=3` (Wikimedia Commons, JPEG 219/259/318 КБ).
- PDF-скан: `pages=3, cards=2, tokens=5794`.
- Wikimedia/Wikipedia: JPEG 97 КБ (CC BY-SA 4.0), JPEG 239 КБ («Минерал»).

## Соответствие приёмке Д1–Д6

| # | Тест-доказательство | Статус |
|---|---|---|
| Д1 | `generation_screen_test.dart` (кнопка неактивна + подсказка; prompt-only запрос с темой и именем колоды), `content_validator_test.dart` (source_excerpt → null без удаления), live prompt-only | выполнено |
| Д2 | `card_quality_test.dart` (абстрактный query → null), `generation_fix_gen_test.dart` (без `image_query` поиска нет), live тема статики: `image_query=null` у 20/20 карточек | выполнено |
| Д3 | `document_images_test.dart` (DOCX/PPTX/ODT, фильтры, контекст), `card_generation_images_test.dart` (каталог `<images>`), `generation_fix_gen_test.dart` (image_id → байты), live DOCX (`image_id=1, with_image=1`), предпросмотр: убрать/заменить | выполнено |
| Д4 | `latex_escape_repair_test.dart` (16 фикстур), `latex_render_fix_test.dart` (Math-виджет, блок, испорченный `\f rac`, `\(…\)`, `\$`, cloze), `latex_markup_test.dart` | выполнено |
| Д5 | `card_quality_test.dart` (5 мягких правил), `quality_eval_test.dart` (3 сценария), live: 20 карточек, доля пометок 0.0 % | выполнено |
| Д6 | `failure_reasons_test.dart` (коды), `generation_fix_gen_test.dart` (`error_code=json_parse,http_5xx`, лог), `generation_preview_partial_test.dart` (2 успешных + 1 упавший → импорт), `card_generation_images_test.dart` (одна плохая карточка не роняет фрагмент) | выполнено |

## Не проверено (KNOWN_LIMITATIONS)

- L76: изображения внутри PDF; L77: EMF/WMF/SVG; L78: ручные клики и скриншоты
  владельца (агент не кликает GUI); L79: перечень причин строкой `error_code`.
- OpenAI/Gemini/Anthropic живьём (L1) — только DeepSeek; проекции схем проверены
  unit-тестами.

## CI (снимок итерации)

Push `c95e5a9..08b42d8`; run [`43764143830`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43764143830) —
**9/9 job success** (`format + analyze`, `test` × 3 ОС, `build-desktop` × 3,
`build-mobile` Android + iOS).
