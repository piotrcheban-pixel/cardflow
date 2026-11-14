# Итерация 5 — Occlusion / Cloze / LaTeX

**Дата:** 2026-11-14 · **Режим:** ИТЕРАЦИИ · **Шаг:** 1 (план)

## Факты до изменений

- `git status --short --branch` → `## main...origin/main`, рабочее дерево чистое;
  `HEAD = origin/main = 8dfa6e5d29aed3a5a1805d6ebc6f96c84ebf3065`.
- `git log --oneline -5`: `8dfa6e5`, `4b4157b`, `490eb80`, `e90f660`, `4ef3038` — после кода итерации 4
  только docs/handoff. `journal/iteration-5/` отсутствует, внешняя реализация в репозиторий не поступала.
- `fvm flutter test --exclude-tags golden` → **959 passed + 1 skipped**; `fvm flutter --version` →
  Flutter **3.47.9**, Dart **3.13.7**. Прежняя запись STATE об отставании `origin/main` устарела и исправлена.
- Навыков `tdd-workflow`, `dart-flutter-patterns`, `material-3-skill` в каталоге нет (L5);
  работаем по TDD и правилам `docs/agent-prompt.md`.

## Объём и критерии SPEC

1. **A7.8 Image Occlusion:** PNG/JPEG + прямоугольные/эллиптические маски; тап раскрывает одну,
   «Показать все»/«Скрыть все»; форма карточки выбирает изображение, рисует и удаляет маски,
   сохраняет нормализованные координаты в `occlusion_json` и файл/связь в `media`.
2. **A7.9 Cloze:** ручной тип `cloze`, разбор `{{cN::ответ}}`, раскрытие групп по одному,
   общее раскрытие показывает всё; валидатор ручной формы не принимает карточку без пропуска.
3. **A7.10 LaTeX:** нативный `flutter_math_fork`, `$…$`/`$$…$$`, пошаговое раскрытие нескольких
   формул, общее раскрытие всех шагов; ошибка — исходный текст + «Ошибка разметки формулы».
4. **A0.1/A6.3:** всё это рендерится в классике и ленте, новых пунктов в листе режимов нет;
   оценки/FSRS/undo продолжают работать теми же движками.
5. **A5/A6.9:** экспорт/импорт существующего `.zip` сохраняет разметку и изображение;
   схема БД и публичная версия архива не меняются.
6. **Качество:** новые ветки сначала красные по assertion, production-проводка покрыта интеграционными
   тестами; полный прогон, analyze, format, coverage ≥80%, Windows release.

## Задачи, файлы и проверки

### 1. Чистые модели разметки и черновика

- Новые: `lib/domain/cards/{occlusion,cloze_markup,latex_markup,card_media}.dart`.
- Изменить: `lib/domain/cards/card_draft.dart`, `lib/data/cards/drift_card_repository.dart`.
- Тесты: нормализация/round-trip/ошибки координат и JSON; группы cloze; делимитеры LaTeX;
  валидация cloze/occlusion; сохранение медиа и разметки в drift, откат при ошибке файла.

### 2. Медиа-шлюз и чтение в сессиях

- Новые: `lib/data/cards/{file_picker_image_gateway,drift_card_media_repository,media_garbage_collector}.dart`,
  `lib/domain/cards/card_media_repository.dart`; расширить `MediaStore` безопасным листингом.
- Проводка: `lib/ui/state/app_providers.dart`, `lib/main.dart`.
- Тесты: picker по контракту `file_picker`, чтение байтов по `media.id`, удаление только сирот,
  production-граф `app_providers`.

### 3. Общий рендер карточки

- Новые виджеты в `lib/ui/cards/content/`: `card_content_view.dart`, `cloze_text.dart`,
  `latex_text.dart`, `occlusion_image_view.dart`.
- Подключить `review_card_view.dart` и `feed_card_view.dart`; экраны сессий загружают байты медиа.
- Widget-тесты: одиночное/групповое раскрытие, показать/скрыть все, формулы и fallback,
  одинаковое поведение в классике и ленте, отсутствие изображения не скрывает текст карточки.

### 4. Редактор карточки

- Новый `lib/ui/cards/occlusion_mask_editor.dart`; изменить `card_form_screen.dart`, ARB и
  сгенерированную локализацию через `fvm flutter gen-l10n`.
- Тесты: выбор изображения через fake gateway, рисование rect/ellipse pointer-жестом, удаление,
  ошибки без изображения/масок, cloze в форме, round-trip редактирования.

### 5. Сквозные проверки и ревью

- Integration: create occlusion → export → import → открыть классику и ленту → раскрыть → оценить/undo.
- Review на неизменяемом снимке после green; high/medium — fix-коммитом с новым тестом на находку.
- Verify: `fvm flutter test --coverage --exclude-tags golden`, `tool/coverage_check.dart`,
  `fvm flutter analyze`, `fvm dart format lib test` + `--set-exit-if-changed`, Windows release.

## Риски и решения до реализации

- **Формат `occlusion_json` в SPEC не задан** — ADR-017: `version=1`, нормализованные координаты 0..1,
  ссылка на изображение через существующий `media_json`, публичный `.zip` не меняется.
- **Жесты маски vs flip/swipe** — дочерний recognizer маски; тесты доказывают, что тап по маске не даёт
  оценку и не листает ленту. Общий тап/Space по-прежнему раскрывает карточку целиком.
- **Ошибка изображения/разметки** — текст и оценки остаются доступны, сообщение только из ARB.
- **Сироты медиа** — удаление при замене/удалении карточки + conservative GC только файлов/строк без ссылок;
  тест на сохранение связанных и неизвестных файлов вне `media/`.
- **Независимый reviewer** — проверить `list_agents`; при отсутствии повторить Lead-review по чек-листу (L35).

## Вне объёма

Произвольные маски, `\(…\)`, WebView/HTML, новые режимы, изменение схемы БД/версии экспорта,
post-MVP-функции. Push — только по отдельной команде владельца.
