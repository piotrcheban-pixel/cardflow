# Итерация 7.12 — красная фаза

Фрагменты падений по новым тестам до реализации (зафиксированы прогонами в
сессии; полные логи — `work/red-review-queue.log`, `work/red-card-form.log`).

## ADR-028 §2 — сегодняшние новые карточки вне дневного лимита

Тест `test/unit/domain/review_queue_limits_test.dart`, группа
«ReviewQueue — новые карточки текущего дня (ADR-028)» против старой
`ReviewQueue.build` (лимит применялся ко всем новым):

```
ReviewQueue — новые карточки текущего дня (ADR-028) лимит новых исчерпан,
но сегодняшние карточки доступны [E]
  Expected: ['today-1', 'today-2']
    Actual: []
  ... is shorter than expected
```

Четыре теста группы падали одинаково: очередь пуста при `newLimit: 0`, хотя
карточки созданы в текущий локальный день. Ожидаемое поведение: пользователь,
только что создавший пак, видит его в сессии.

## ADR-028 §1 — Basic-карточка с картинкой без масок

Тест `test/widget/cards/card_markup_form_test.dart` «basic: картинка без масок
сохраняется как иллюстрация» против старой формы (при выборе картинки сразу
включался `OcclusionDocument()`):

```
The following TestFailure was thrown running a test:
  Expected: no matching candidates
  Actual: _KeyFinder:<Found 1 widget with key [<'occlusion-editor-canvas'>]>
    at line 94: expect(find.byKey(occlusion-editor-canvas), findsNothing)
The test description was: basic: картинка без масок сохраняется как иллюстрация
```

Ожидаемое поведение: после выбора картинки редактор масок не появляется, а
сохранённый черновик имеет `imageUpload` и `occlusionJson == null`.

## ADR-028 §3 — распознавание запрета картинок в пожеланиях

Тест `test/unit/domain/image_query_test.dart` «wishesForbidImages русские
формулировки запрета»:

```
Expected: true
  Actual: <false>
test\unit\domain\image_query_test.dart 123:7
```

`не добавляй картинки` не распознавалось: `\w*` в Dart ASCII-only не покрывал
кириллическое окончание глагола. Исправлено на `(?:добав|встав|ищ|рис)\S*`.

## Диагностика ИИ (до фикса)

Живой зонд сырого ответа (диагностика ADR-024, вывод в консоль) на
`deepseek-flash` и тексте о минералах:

```
PROBE q=null | Минерал
PROBE q=null | Спайность минерала
PROBE q=conchoidal fracture mineral specimen | Что такое излом минерала...
...
PROBE unique queries=4
PROBE search "mineral scratch hardness test" → null
```

— модель отдаёт `image_query` только для части карточек, а поиск по русским
определениям в Commons возвращает 0 результатов. Ошибка поиска при этом нигде
не показывалась: карточка импортировалась без изображения молча.
