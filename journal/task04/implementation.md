# TASK 04 — что изменено в коде и почему

**Дата:** 2026-11-25. Основание: `audit.md` (измеренные дефекты M-01…M-22),
`design-research.md`, решение `docs/decisions/ADR-046-mobile-design-system-v4.md`.
Все пути — от корня репозитория; сборка/проверки — в `report.md`.

## 1. Дизайн-система и общие компоненты

| Файл | Что сделано | Почему |
|---|---|---|
| `docs/decisions/ADR-046-mobile-design-system-v4.md` | новое решение: компактная панель, подсказки по запросу, draggable-лист, лента «только ответ», карточка сессии, редактор | фиксирует изменённые контракты, на которые ссылаются тесты |
| `lib/ui/components/app_info_hint.dart` | новый `AppInfoButton` + `showAppInfoSheet` | M-07/M-10/M-14: второстепенный текст — по нажатию «?» |
| `lib/ui/components/app_section_header.dart` | новый единый заголовок секции (название, подсказка, действие) | M-02: убирает `Row(Expanded(Text), Button)` — источник узкой колонки |
| `lib/ui/components/app_action_bar.dart` | новая нижняя панель с SafeArea и ограничением ширины | M-09: редактор и длинные формы |
| `lib/ui/components/app_dialogs.dart` | `showAppSheet` учитывает клавиатуру/SafeArea; новый `showAppDetentSheet` (DraggableScrollableSheet, 0.72/0.4/0.92) | M-03: лист больше не открывается на 98 % и закрывается свайпом из содержимого |
| `lib/ui/theme/app_tokens.dart` | **не менялись** (палитра ADR-045 уже кобальт/графит, без фиолетового) | требование «убрать фиолетовый фон» выполнено текущими токенами; переписывание сломало бы guard контраста и другие экраны |

## 2. Оценки (M-01)

`lib/ui/review/review_toolbar.dart`:

* сетка 2×2 при ширине панели < 520, иначе ряд 4;
* высота 48 на телефоне / 56–68 на широком (цель ≥ 44 сохранена);
* кегль 16 / 18; `FittedBox(scaleDown)` вместо `ellipsis` — «Затрудняюсь»
  больше не обрезается;
* те же цвета/иерархия/ключи `review-rating-*`; добавлен ключ
  `review-rating-label-*` для измерений;
* `tapTargetSize: shrinkWrap` — высота кнопки ровно 48, а не 48+8.

## 3. Карточка классики/тренировки (M-10…M-12, M-14)

`lib/ui/review/session_card.dart`:

* на обороте повтор вопроса — **без изображений** (кроме occlusion): они уже
  были показаны до переворота и отнимали у ответа 30–40 % высоты;
* нижняя полоса карточки на телефоне — 12 px сверху/снизу вместо 16/20;
* остальная геометрия/переворот 300 мс/скролл с градиентом сохранены.

`lib/ui/review/review_session_screen.dart`:

* на < 600 px прогресс — «1 / 12» + полоса; «Оценено: N» скрыт (M-11);
* уменьшен верхний отступ строки прогресса.

`lib/ui/review/practice_session_screen.dart` + `review_chrome.dart`:

* подпись «Карточки идут без учёта интервалов…» убрана из тела; смысл режима —
  в кнопке «i» шапки (`infoMessage`/`infoTooltip`); на тренировке прогресс
  «1 / 2»;
* шапка классики на телефоне не показывает чип «FSRS» (M-14).

## 4. Режим «Лента» (M-04/M-05/M-13)

`lib/ui/review/feed_card_view.dart` — переписан:

* собственный `AnimationController` (Y-поворот, `AppDurations.flip`,
  reduced motion → мгновенно), в дереве одна грань;
* оборот — **только ответ** и его изображения; вопроса/эхо-изображений нет;
* тап возвращает вопрос; вопрос — компактная галерея изображений (96–160 px);
* переполнение измеряется по `ScrollController.maxScrollExtent` после кадра;
  «Открыть полностью» — в нижней полосе, градиент у кромки; текст не
  перекрывается;
* лицевая сторона — одна кнопка «Показать ответ» (без второй подсказки).

`lib/ui/review/feed_session_screen.dart`:

* `itemCount = total + 1`, последняя страница — `_FeedEndView` («Лента
  пройдена», число карточек, «Готово»); свайп вверх открывает итог, вниз —
  возвращает;
* чип «Лента» скрыт на телефоне; прогресс — короткий счётчик.

`lib/ui/review/feed_progress_bar.dart` — на < 600 px счётчик «1 / 2» вместо
«Карточка 1 из 2».

FSRS-инварианты ADR-044 не менялись: ни оценок, ни записи `review_logs`, ни
изменения `due`/`fsrs_json`. Итог ленты прямо сообщает, что расписание не
изменилось.

## 5. Редактор карточки (M-02/M-07/M-08/M-09/M-15)

`lib/ui/cards/card_form_screen.dart`:

* «Дополнительно» — `AnimatedCrossFade` с подсказкой/тегами/источником;
  открыто, если данные есть, и при ошибке валидации (поле не остаётся
  невидимым);
* тип: причина неизменяемости — в `AppInfoButton` (ключ
  `app-info-card-form-type-info`); сегменты/чипы сохранены, чтобы работали
  существующие сценарии;
* изображения: `AppSectionHeader` с «?» (длинный абзац убран из потока);
  заголовок стороны + компактная «+» (44×44) на телефоне; пустая сторона —
  одна кнопка «Добавить к вопросу»; изображения — сетка 2 колонки, плитка
  132 px, превью целиком, «Заменить»/⋮ поверх, тап — fullscreen; прежние
  ключи/действия сохранены;
* нижняя панель — `AppActionBar` (полная ширина, SafeArea, высота ≤72).

## 6. Экран колоды (M-06)

`lib/ui/decks/deck_screen.dart` — ряд действий в заголовке списка карточек
заменён на `Wrap`: на 320 px и при кегле 130 % больше нет `RenderFlex
overflow 14–17 px`.

## 7. Лист режимов (M-03)

`lib/ui/decks/deck_modes_sheet.dart` — `showAppDetentSheet`; тело —
`SingleChildScrollView(controller)` + `Column` (все плитки построены, свайп
вниз закрывает лист, высота 72 % → 92 %). Тесты, которым нужна нижняя
плитка, прокручивают её (`ensureVisible`) — как пользователь.

## 8. Локализация

`lib/l10n/app_ru.arb` — добавлены только новые строки (подсказки, короткий
счётчик, итог ленты, «Дополнительно», «Добавить изображение»); сырых
литералов в UI нет. Новые ключи: `appInfoClose`, `appInfoTooltip`,
`cardFormMoreSection`, `cardFormMoreSectionHint`, `cardFormImageInfoTitle`,
`cardFormTypeInfoTitle`, `practiceInfoTooltip`, `reviewCardCounterShort`,
`feedAnswerNavHint`, `feedEndTitle`, `feedEndMessage`. Неиспользуемые
черновые ключи (`feedEndOpen`, `feedLastCardHint`, `cardFormAddImageTooltip`,
`cardFormNoImages`, `feedAnswerBackHint`) удалены перед финальным прогоном;
подписи «Теги через запятую…» и «Цитата для кнопки «Почему?»…» сокращены до
«Теги» и «Цитата источника» (M-26).

## 9. Тесты

Обновлены осознанно (см. ADR-046 §1/§4/§7):

* `test/widget/review/review_gates_test.dart` — G2/G10 под мобильную
  геометрию (≥44/≥56, кегль ≥14/≥16, зазор ≥8/≥12) + комментарии;
* `test/widget/review/feed_card_view_test.dart` — оборот без вопроса-эха;
* `test/widget/review/feed_session_screen_test.dart` — после последней
  карточки итоговая страница;
* `test/widget/review/practice_session_screen_test.dart` — подпись режима в
  подсказке, не в теле;
* `test/widget/cards/card_form_screen_test.dart` — раскрытие
  «Дополнительно», причина типа в «?»;
* `test/widget/decks/deck_screen_test.dart` — прокрутка нижней плитки листа,
  подсказка тренировки.

Новые тесты: `test/widget/review/rating_panel_mobile_test.dart` (6),
`test/widget/cards/card_form_mobile_test.dart` (5),
`test/widget/review/feed_flip_test.dart` (4),
`test/widget/components/app_sheet_test.dart` (2). Итоговый прогон — в
`report.md` §12.
