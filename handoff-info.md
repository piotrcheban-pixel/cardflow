# Handoff — CardFlow, после итерации 5

**Дата:** 2026-11-14 · **Режим:** ИТЕРАЦИИ · **Итерация 5 (Occlusion/Cloze/LaTeX) завершена**
**Следующая:** итерация 6 «Конструктор» (SPEC B2/A6.7, MVP).

> Предыдущая передача итерации 5 внешнему агенту отменена командой владельца; итерация выполнена в DSH.

## 1. Состояние и коммиты

- `HEAD` — `git rev-parse HEAD` (локальные docs/remember); **последний код** — `0e4e11b`
  (`fix: preserve occlusion and drawing gestures`), green — `5af8f70`.
- `origin/main` отстаёт: push итерации 5 **не выполнялся** (нет команды владельца). CI итерации 5 не
  запускался; последний известный зелёный CI — итерация 4, `e90f660` (9/9).
- Итерация 5: **1020 passed + 1 skipped**, покрытие **93.1% (6468/6946)**, analyzer 0, format 253/0,
  Windows release `cardflow.exe` (56,2 с). Отчёт — [`journal/iteration-5/summary.md`](<journal/iteration-5/summary.md>).
- Актуальное состояние и следующее действие — [`journal/STATE.md`](<journal/STATE.md>).

## 2. Что появилось в итерации 5

- **Image Occlusion:** PNG/JPEG picker; редактор прямоугольных/эллиптических масок eager-pointer-жестом;
  тап маски, «Показать все»/«Скрыть все», рендер в классике и ленте; `occlusion_json` v1 + первое `media`;
  транзакционная запись/замена/удаление файлов, откат, startup-GC.
- **Cloze:** тип в форме, `{{cN::…}}`, группы по N, пошаговое и общее раскрытие, пустой `back`.
- **LaTeX:** `flutter_math_fork`, `$…$`/`$$…$$`, шаги, fallback с ARB-предупреждением; `\(…\)` вне объёма.
- **Общий контент:** [`card_content_view.dart`](<lib/ui/cards/content/card_content_view.dart>) в
  [`review_card_view.dart`](<lib/ui/review/review_card_view.dart>) и
  [`feed_card_view.dart`](<lib/ui/review/feed_card_view.dart>); медиа в сессии — `CardMediaRepository`.
- **Данные:** схема БД и `format_version` **не менялись**; create → export → import покрыт интеграционным
  тестом. Формат `occlusion` — [`docs/archive-format.md`](<docs/archive-format.md>), решение — ADR-017.

## 3. Ключевые архитектурные решения

| ADR | Решение |
|---|---|
| ADR-001 | M3 Expressive только через `lib/ui/m3e/`; Material — `material_ui` |
| ADR-002 | Riverpod 3 без кодогенерации |
| ADR-005 | drift + `NativeDatabase`, schemaVersion 1, fail-fast upgrade |
| ADR-006 | `.zip` `format_version=1`; `media`, `latex`, `occlusion` уже в контракте |
| ADR-008/016 | классика и лента — отдельные движки поверх `ReviewRepository`; mode |
| ADR-009 + addendum 5 | форма карточки: cloze, неизменяемый тип, медиа/маски |
| ADR-010/011–015 | парсеры, провайдеры, HTTP, пайплайн генерации |
| **ADR-017** | `occlusion_json` v1 (нормализованные координаты), медиа первым `media_json`, общий рендер, GC |

## 4. Ограничения перед итерацией 6

- L1 (живые OpenAI/Gemini/Anthropic), L6 (golden/Linux), L11/L37/L38 (реальный picker/жесты/устройства),
  L12/L39 (screen-reader, golden M3E), L35 (независимый reviewer отсутствует), L36 (авто-продвижение под
  другим маршрутом), L2 (не-Windows сборки только CI).
- Полный список — [`journal/KNOWN_LIMITATIONS.md`](<journal/KNOWN_LIMITATIONS.md>). L17 снят startup-GC.

## 5. Итерация 6 «Конструктор» (следующая)

Источники: SPEC A6.7, A7.20, A5 `session_presets`, B2. Ожидаемый вертикальный срез:

- экран конструктора: multi-select колод, фильтры тегов/типа/состояния, режим (классика/лента),
  лимит N карточек или N минут, перемешивание, интерлинг, разминка;
- пресеты в `session_presets` (CRUD, применяемость), дневные лимиты новых/повторных;
- передача выборки в существующие движки без ослабления ADR-008/016;
- тесты на фильтры/порядок/лимиты, интеграция «конструктор → сессия», миграции не требуются;
- не писать post-MVP и не добавлять мёртвые кнопки.

## 6. Правила

Все команды — через FVM; TDD red→green; UI-текст только ARB; guard-тесты не ослаблять; секреты только
`ApiKeyStore`; ADR при развилке; коммит после каждого зелёного шага; push — только по команде владельца.
