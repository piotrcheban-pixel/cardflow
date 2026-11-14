# Итерация 5 — красная фаза

**Дата:** 2026-11-14 · **Шаг:** 2

## Команды

```powershell
fvm flutter test test/unit/domain/occlusion_test.dart test/unit/domain/cloze_markup_test.dart test/unit/domain/latex_markup_test.dart test/unit/domain/card_markup_draft_test.dart test/unit/data/cards/card_occlusion_repository_test.dart test/unit/data/cards/card_media_test.dart test/widget/cards/card_content_test.dart test/widget/cards/card_markup_form_test.dart
```

Первый прогон выявил две ошибки самого тестового каркаса (конфликт импортов matcher/drift и скрытие Material `Card`);
они исправлены без изменения ожиданий. Повтор:

```powershell
fvm flutter test test/unit/data/cards/card_media_test.dart test/widget/cards/card_content_test.dart test/widget/cards/card_markup_form_test.dart
```

Оба прогона завершились `[exit code: 1]` по ожидаемым причинам: контракты есть, поведение ещё не реализовано.

## Assertion-level доказательства

- Occlusion round-trip: `Expected: not null; Actual: <null>`; `toJson`: ожидались `id/shape/x/y/width/height`,
  получено `{}`.
- Cloze: `Expected: true; Actual: <false>` для `hasGaps`; ожидались номера `[1, 2, 1]`, получено `[]`.
- LaTeX: ожидалось 5 сегментов, получен 1; `hasUnclosedDelimiter`: ожидалось `true`, получено `false`.
- `CardDraft`: ожидалась `clozeMissing`, получена пустая карта ошибок; нормализация `mediaIds`:
  ожидалось `['old-media']`, получено `[]`.
- drift occlusion: ожидался один `mediaIds`, получено `[]`; ошибка записи файла: ожидался
  `FileSystemException`, карточка вместо этого создана без медиа.
- Чтение медиа: ожидались ключи `['media-1']`, получено `[]`; GC: ожидалось 3 удалённые сущности, получено 0.
- Классика/лента: `cloze-gap-1` — найдено 0 вместо 1; `Math` — 0 вместо 1; `Image` — 0 вместо 1;
  предупреждение «Ошибка разметки формулы» отсутствует.
- Форма: «С пропусками» и `card-form-pick-image` — найдено 0 вместо 1.

Это не только ошибки компиляции: сохранены конкретные расхождения ожидаемого и фактического поведения.
Некорректные occlusion-фикстуры уже возвращают `null` у заглушки и потому проходят; полноценная валидация
всё равно проверяется round-trip/границами в зелёной фазе.

## Покрытие новых требований

- Unit: JSON/границы масок, cloze-группы, LaTeX-делимитеры, CardDraft, запись/откат/удаление медиа, GC.
- Widget: общий контент в классике и ленте, нативные формулы/fallback, маски, cloze и вход выбора изображения.
- Следующий шаг: минимальная реализация до зелёного; затем дополнить редактор pointer-жестами и
  production-integration create → export → import → session.
