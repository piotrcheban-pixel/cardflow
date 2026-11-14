# Итерация 5 — итог

**Дата:** 2026-11-14 · **Статус:** завершена (шаги 1–7) · **Ветка:** `main`, локально впереди
`origin/main` на 6 коммитов (push не выполнялся).

## Что сделано

- **Image Occlusion (A7.8):** загрузка PNG/JPEG через системный picker, редактор масок
  (прямоугольник/эллипс, pointer-рисование, удаление), тап/«Показать все»/«Скрыть все»,
  сохранение `media` + `occlusion_json` в транзакции с откатом, удаление/замена файлов, startup-GC.
- **Cloze (A7.9):** тип в форме, валидация хотя бы одного `{{cN::…}}`, группы по номеру, пошаговое
  раскрытие тапом, общее раскрытие, empty back разрешён.
- **LaTeX (A7.10):** нативный `flutter_math_fork`, `$…$`/`$$…$$`, последовательные формулы,
  fallback исходным текстом с ARB-предупреждением; `\(…\)` не поддержан.
- **Общий рендер:** `CardContentView` в классике и ленте; медиа загружается через
  `CardMediaRepository`; оценки/undo/FSRS не изменены; новых режимов в листе нет.
- **Совместимость:** схема БД и `format_version` не менялись; create → export → import → чтение
  покрыто интеграционным тестом; ADR-017.
- **Качество:** ARB/gen-l10n, guard-тесты, production-граф провайдеров, `main` GC, docs.

## Ключевые файлы

- `lib/domain/cards/{occlusion,cloze_markup,latex_markup,card_media,card_media_repository}.dart`
- `lib/data/cards/{drift_card_media_repository,file_picker_image_gateway,media_garbage_collector}.dart`
- `lib/ui/cards/content/*`, `lib/ui/cards/occlusion_mask_editor.dart`, `card_form_screen.dart`
- `lib/ui/review/{review_card_view,feed_card_view,review_session_screen,feed_session_screen}.dart`
- `test/{unit,widget,integration}`: разметка, редактор, сессии, export/import, provider wiring
- `journal/iteration-5/{plan,red,green,review,verify,summary}.md`, ADR-017

## Доказательства приёмки (B6)

| Пункт | Статус | Доказательство |
|---|---|---|
| План соответствует SPEC | да | `plan.md`: A7.8–A7.10, A0.1, A5, A6.3, A6.9 |
| Каждая задача была красной | да | `red.md`: 27 assertion-level падений; новые medium-тесты тоже воспроизводили дефекты |
| Полный прогон/analyze/format | да | 1020 passed + 1 skipped; analyzer 0; format 253/0 |
| Покрытие ≥80% | да | 93.1% (6468/6946) |
| Guard-тесты | да | no_webview, ru_strings, no_secrets, architecture — зелёные в полном прогоне |
| Ревью, high закрыты | да | `review.md`: high 0, M1–M4 исправлены с тестами; независимый reviewer недоступен (L35) |
| Сборки доступной платформы | да | Windows release `cardflow.exe`, 56,2 с |
| Критерии с доказательствами | да | `verify.md`; непроверенное — L6/L11/L12/L37/L38/L39, CI/L2 |
| STATE/summary/следующий шаг | да | этот файл + `STATE.md` |
| Checkpoint-коммиты | да | plan, red, green, review-fix, verify, remember |

## Не проверено

Golden (L6), live API (L1), реальные picker/жесты/устройства (L11/L37/L38), screen-reader масок
(L12/L39), CI и не-Windows сборки (L2). Причины — `KNOWN_LIMITATIONS.md`.

## Следующее действие

Итерация 6 «Конструктор»: фильтры, пресеты, перемешивание, интерлинг, разминка — по SPEC B2/A6.7.
