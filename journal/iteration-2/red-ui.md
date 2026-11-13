# Итерация 2 — красная фаза: UI, роутер, интеграция (шаг 2)

**Команды:** `fvm flutter test` полный прогон; фрагменты ниже — из `.dart_tool/red_phase_output.txt`.
**Итог:** 77 падений, все — новые тесты итерации 2; существующие widget-тесты итерации 1 зелёные.

## Экран сессии (SPEC A6.4, A7.2) — 13 падений

Скелет `ReviewSessionScreen` показывает заглушку. Падения assertion-level — finder не находит ожидаемые виджеты:

```
test/widget/review/review_session_screen_test.dart:
каркас: прогресс, первая карточка и 4 кнопки с прогнозом [E]
  Expected: exactly one matching candidate
    Actual: _TextWidgetFinder:<Found 0 widgets with text "Первый вопрос": []>
```

Ожидания тестов:
- каркас: front текущей карточки, скрытый back, `LinearProgressIndicator`, 4 подписи оценок, прогнозы (`<1 мин`, `10 мин`, `16 д`);
- тап по карточке и пробел раскрывают ответ; цифры 1–4 дают оценку (Good по «3»);
- кнопка «Знаю»: оценка уходит в порт (`mode = classic`), сессия переходит к следующей карточке;
- undo: вызов порта undo и возврат к предыдущей карточке;
- ошибка записи → сообщение `reviewSaveError` из ARB, без сырого текста, карточка не меняется;
- завершение: «Сессия завершена», плюрализованный итог, «Готово»;
- пустая очередь: `reviewEmptyTitle/Message` + «Назад»;
- ошибка загрузки: `reviewLoadError` + «Повторить» (без сырого `boom`);
- «Почему?»: `onPressed == null` без `source_excerpt`; с цитатой — bottom sheet с заголовком и цитатой;
- запуск с экрана колоды: «Начать сессию» → bottom sheet «Выберите режим» → «Классический» → сессия; выход с диалогом (`reviewExitDialogTitle/Message`) и возврат на экран колоды; «Продолжить» остаётся в сессии.

## Форма карточки (SPEC A6.3, A8.4, ADR-009) — 8 падений

```
test/widget/cards/card_form_screen_test.dart:
создание basic-карточки: черновик уходит в репозиторий [E]
The finder "Found 0 widgets ..." (used in a call to "tap()") could not find any matching widgets.
```

Ожидания: FAB «Добавить» на экране колоды открывает форму; ввод front/back/тегов → `createCards` с нормализованным черновиком; ошибки валидации (пустые, >500, >3 тегов) из ARB без записи; «Двусторонняя» → `cardType = basicReversed` + подсказка о парной карточке; тап по карточке → edit-форма с заполненными полями и `cardFormTypeImmutable`; сохранение → `updateCard` + сообщение; удаление из формы → диалог + `deleteCard`; несуществующая карточка → `cardFormLoadError`.

## Экран колоды (A6.3) — 4 падения

Ожидания: Expressive Card «Начать сессию» → лист режима → сессия; пустая очередь → `reviewStartEmptyMessage` без перехода; FAB → форма; тап по карточке → форма редактирования.

## Роутер — 1 падение

```
test/unit/ui/app_router_test.dart: содержит 5 маршрутов итерации 2 с именами [E]
  Expected: an object with length of <5>
    Actual: [GoRoute(name: "decks", path: "/"), GoRoute(name: "deck", path: "/decks/:deckId")]
     Which: has length of <2>
```

Ожидания: `/decks/:deckId/study`, `/decks/:deckId/cards/new`, `/decks/:deckId/cards/:cardId/edit` с именами `study/cardNew/cardEdit`; пути в `AppRoutes` (`studyPath`, `cardNewPath`, `cardEditPath`).

## Интеграция (production-проводка, урок итерации 1) — 1 падение

`test/integration/review_session_flow_test.dart`: реальная in-memory drift-БД + `ProviderContainer` с production-провайдерами. Ожидает: `cardRepositoryProvider = DriftCardRepository`, `reviewRepositoryProvider = DriftReviewRepository`, `schedulerProvider = FsrsScheduler`; создание двух карточек через репозиторий, просроченная карточка в состоянии `review` с согласованным `fsrs_json`; очередь [просроченная, новая]; оценка через порт → `review_logs` + `due/fsrs_json`; undo → лог удалён, снимок восстановлен. Красная причина:

```
UnimplementedError: DriftCardRepository.createCards: красная фаза итерации 2
  test\integration\review_session_flow_test.dart 66:41
```

Тест графа провайдеров итерации 2 (`reviewRepositoryProvider isA<DriftReviewRepository>`) зелёный сразу — это проверка типа проводки, поведение проверяется flow-тестом.
