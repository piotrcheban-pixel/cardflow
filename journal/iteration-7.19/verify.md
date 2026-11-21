# Verify 7.19 — ворота качества и приёмка

**Дата:** 2026-11-21. **Снимок:** ветка `main`, коммиты итерации 7.19 (push — §7).
**Живых API-запросов нет** (запрет задания); все проверки офлайновые, кроме
Windows smoke на локальном процессе.

## 1. Ворота

| Ворота | Команда | Результат |
|---|---|---|
| Локализация | `fvm flutter gen-l10n` | ок (новые строки сторон/состояний) |
| Формат | `fvm dart format lib test integration_test tool` / `--set-exit-if-changed` | **0 changed** (566 файлов) |
| Анализатор | `fvm flutter analyze --no-pub` | **No issues found** |
| Полный набор | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2425 passed + 16 skipped + 0 failed** |
| Покрытие | `fvm dart run tool/coverage_check.dart --min=80` | **91.5 % (20177/22060)**, порог пройден |
| Windows Release | `fvm flutter build windows --release --no-pub` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (61,8 с) |
| Windows Smoke | `fvm flutter test integration_test/session_smoke_windows_test.dart -d windows` | **All tests passed!** (11 с) |

Baseline до итерации: **2365 passed + 16 skipped** (нетто **+60** тестов;
16 skipped — live/golden/платформенные, как раньше). Логи: `baseline-test.txt`,
`full-run-*.txt`, `final-test-run.txt`, `windows-build-final.txt`,
`windows-smoke.txt`, `coverage-run.txt`.

## 2. Приёмка §8 задания

### Сценарий A — метод конечных разностей

Вопрос: «В чём сущность метода конечных разностей?»

- **Установленная первопричина:** карточка получала нарисованную заглушку
  `PlaceholderImageGenerator` (градиент, круги, полосы, иконка `diagram` =
  оси и столбики) после неудачного поиска `finite difference method grid
  diagram`; палитра — `contentHash % 8`, поэтому картинка повторялась на других
  карточках (в фактической БД — 80 заглушек, 68 `diagram`).
- **Механизм устранён:** генератор удалён; `GenerationPipeline` при неудаче
  поиска оставляет сторону пустой с `imageNotFound`; в `media`/`MediaStore` не
  создаётся файл. Регрессия на production-проводке:
  `test/integration/image_placeholder_red_7_19_test.dart` — «ожидалось: пусто,
  получено: нарисованный PNG 22 906 Б» в красной фазе; теперь `media` пуст,
  каталог медиа пуст.
- **Существующая карточка владельца:** её заглушка удаляется
  `PlaceholderMediaPurger` при старте (строка `media`, файл, `.meta.json`, id из
  `media_json`), карточка остаётся без изображения — случайная картинка не
  показывается. Тесты пуржа — `card_media_sides_data_test.dart`.
- **Если в документе есть подходящая схема:** модель может назначить её
  `question_image_ids` (или `answer_image_ids`, если схема раскрывает ответ);
  если нет — карточка без изображения. Проверено A3/B16/B17.

### Сценарий B — формула воздухопроницаемости

Вопрос: «Какой формулой рассчитывают фактическую воздухопроницаемость окна?»

- **Установленная первопричина:** изображение из PDF (`provider=file`) с самой
  формулой лежало в общем `mediaIds`; `CardContentView` брал
  `mediaIds.first` без учёта стороны → формула видна до переворота.
- **Новый ответ модели:** `answer_image_ids: ["imgN"]`,
  `question_image_ids: []` — production-тест `image_sides_7_19_test.dart`
  («A3/B16») подтверждает: `questionMediaIds` пуст, `answerMediaIds` — 1,
  файл в `MediaStore` совпадает с исходным PNG; B17 — график-стимул уходит
  в `questionMediaIds`.
- **Отображение:** C29 — до переворота виден только `questionMedia`;
  C30 — после переворота только `answerMedia`; C29/C30 отдельно на
  `ReviewCardView`. Предпросмотр показывает обе стороны («Изображения вопроса»
  / «Изображения ответа»), утечки нет.
- **Существующая карточка владельца:** её `media_json` — старый плоский массив.
  Безопасная политика ADR-042 (basic без occlusion/cloze → сторона ответа)
  переводит это изображение в `answerMediaIds`: формула больше не видна до
  переворота без ручных действий. Проверено `card_media_sides_data_test.dart`
  («старая строка media_json: basic — безопасно на стороне ответа»); occlusion
  legacy остаётся у вопроса отдельным тестом.

## 3. Группы тестов §6

| Группа | Покрытие | Где |
|---|---|---|
| A. Потеря/подстановка изображений (A1–A12) | 12/12 | `image_placeholder_red_7_19_test.dart`, `image_sides_7_19_test.dart` (A1/A2, A3, A11, A12), `media_integrity_test.dart` (A5–A8), `card_media_sides_data_test.dart` (A9/A10) |
| B. Авто-выбор ИИ (B13–B21) | 9/9 | `image_side_selection_test.dart` (B13–B15, B19–B21, v5/v8, side), `image_sides_7_19_test.dart` (B16/B17) |
| C. Редактор и отображение (C22–C31) | 10/10 | `card_form_sides_test.dart` (C22–C28), `card_sides_display_test.dart` (C29–C31), домен/данные |
| Domain | `card_media_sides_test.dart` (13) | кодек v2/legacy, `Card`/`CardDraft`, occlusion |
| Repository | `card_media_sides_data_test.dart` (11) | создание/обновление/порядок/GC/пурж/экспорт/перезапуск |
| Widget | 8 + 6 + 6 | отображение по сторонам, ошибки/повтор, редактор двух сторон, предпросмотр |
| Integration | production-граф | заглушек нет, стороны сохраняются, `image_id` из каталога, Excel/PDF/архив |

## 4. Приёмка исправлений ревью

R1 (утечка answerMedia в живую карточку генерации) и R2 («Повторить» в
сессиях) закрыты fix-коммитом с тестами: `generation_screen_test.dart`
(«живая карточка не показывает изображение ответа»), `card_sides_display_test.dart`
(«Повторить» вызывает колбэк), `image_side_selection_test.dart` (геттер
`image` — только вопрос). R3/R4 — тестами порядка и расширений.

## 5. Целостность данных владельца

`tool/media_integrity_report.dart` на фактической БД (локальная копия, в git не
коммитится): **207 связей** — 89 `ok`, **80 placeholder**, 38 `duplicateBytes`
(настоящие одинаковые байты у разных карточек), 0 отсутствующих файлов.
Отчёт — `media_integrity_owner.md`. После 7.19: 80 заглушек удаляются пуржем
при старте; 38 дубликатов среди настоящих изображений остаются (L187) и видны
в отчёте, а не маскируются.

## 6. Ограничения итерации

L186–L193 (`KNOWN_LIMITATIONS.md`): семантическая проверка «раскрывает ли
изображение ответ» остаётся за моделью/человеком; дубликаты настоящих
изображений между запусками; предпросмотр без переворота; reversed+общий медиа
в экспорте; пурж опирается на метаданные; checker — диагностика; strict-схема
v9 без живого прогона; сторона legacy-карточек определяется безопасной
политикой. Живые API-запросы не выполнялись (запрет задания).

## 7. Push и CI

Push: `16766f8..e63e88e` (4 коммита итерации: red-тесты, feat, fix ревью,
docs). Финальный CI-прогон —
[run 44924253292](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44924253292)
(`e63e88e`): **9/9 job success** — `format + analyze (ubuntu)`, `test`
(ubuntu/macOS/Windows), `build desktop` (linux/macOS/Windows), `build mobile`
(Android/iOS). Журнальный коммит с этими результатами — отдельный push; его
прогон фиксируется в `STATE.md`.
