# Итерация 7.11 — план: FSRS новых карточек, картинки, сканы, Practice Mode

**Дата:** 2026-11-15 · **Режим:** ИТЕРАЦИИ · **Ветка:** main

## Диагностика owner-note (по фактическим данным приложения, урок 7.6)

Файл БД владельца: `%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite`
(скопирован для чтения, приложение не менялось).

| Факт из БД | Значение |
|---|---|
| Карточек `state='new'` | 43, у всех `due IS NULL`, `fsrs_json IS NULL` |
| Карточек с медиа | 4 (все — новая колода «цуа», PNG 17–2283 КБ) |
| `review_logs` за 15.11 | **30** записей, у всех `actual_days IS NULL` (10 «Лента» 12:10 + 20 классика 19:05–19:06) |
| Настройки | `daily_new_limit = 20`, `daily_review_limit = 200` |
| Колода «цуа» | 4 новые карточки **с файлами media**, созданы 19:08–19:14 |

**Корневая причина «Нет карточек к повторению»:** дневной лимит новых карточек
(20) уже израсходован (30 «новых» оценок за день). `ReviewSessionScreen._load`
передаёт `RemainingReviewLimits.newCards = 0` в `ReviewQueue.build`, очередь
пустая → `ReviewEmptyView`. При этом предварительная проверка на экране колоды
(`ReviewQueue.build(cards, now:)` **без** лимитов) проходит, поэтому
пользователь попадает в пустую сессию и не видит причины. `due = NULL` у новых
карточек делает их невидимыми для любого запроса «due <= now».

Дополнительно подтверждено (L61 перепроверен 2026-11-15): Openverse API с хоста
агента отвечает 200 на первый запрос и **таймаутит** последующие (в т.ч.
англоязычные) — при поиске картинок на 20 карточек это до 20×20 с ожидания и
импорт без иллюстраций. Wikimedia Commons API с русскими запросами отвечает за
1–2 с и возвращает релевантные изображения (проверено запросами «Московский
Кремль», «Иван Грозный»).

## Шаги (TDD: red-тест → минимальная реализация → зелёный)

### Шаг 1. Инвариант новых карточек + очередь (критический)
- Red: `test/integration/generation_flow_test.dart` — генерация с медиа →
  `importGeneratedCards` (реальная drift-БД) → `cardsByDeck` → `ReviewQueue.build`
  содержит карточку; `due` не NULL и `<= now`; `fsrs_json` разбирается
  `CardSchedulingMapper` и указывает на эту карточку.
- Red: `test/unit/data/decks/deck_repository_test.dart` — счётчик «к повторению»
  не считает новые карточки, даже когда у них `due <= now`.
- Реализация: `CardSchedulingMapper.initialScheduling`; `DriftCardRepository` и
  `DriftGenerationCardStore` пишут `due = now` + `fsrs_json` новой карточки;
  счётчик due в SQL экранов колод исключает `state = 'new'`;
  `SessionBuilder._baseOrder` делит карточки по `state`, а не по `due`.

### Шаг 2. Честное пустое состояние и дневной лимит
- Red (widget): экран колоды — предварительная проверка очереди использует тот
  же остаток лимитов, что и сессия; при исчерпанном лимите сообщение
  «Дневной лимит…» вместо «Нет карточек к повторению».
- Red (widget): экран сессии при `total == 0`, но непустой колоде — причина
  (лимит) и кнопка «Тренировать».
- Реализация: `remainingReviewLimitsProvider`; `ReviewEmptyView` с причиной и
  CTA; передача лимитов в проверку листа режимов.

### Шаг 3. Practice Mode (тренировка)
- Red (domain): `PracticeQueue.build` — все не приостановленные карточки,
  включая `due` в будущем и старые/новые; детерминированный порядок.
- Red (data): `DriftPracticeRepository.recordPractice` пишет `review_logs` с
  `mode = 'practice'`, **не** меняет `cards.state/fsrs_json/due`; undo удаляет
  строку; расход дневных лимитов не учитывает `mode='practice'`.
- Red (widget): экран тренировки — карточка, раскрытие, оценка, переход,
  завершение; счётчик оценённых.
- Реализация: `reviewModePractice`, порт `PracticeRepository`, движок
  `PracticeSessionEngine`, экран `PracticeSessionScreen`, маршрут
  `/decks/:deckId/practice`, пункт «Тренировать» в листе режимов, ARB.

### Шаг 4. Картинки в предпросмотре и поиск иллюстраций
- Red (widget): предпросмотр генерации рендерит `Image` для карточки с байтами;
  после импорта карточки картинка доступна в `CardContentView` (media-байты).
- Red (unit/integration): `WikimediaImageSearchService` (Commons API) —
  разбор ответа, фильтр MIME, скачивание, лицензия/атрибуция; композитный
  `CompositeCardImageFinder` — Wikimedia первым, Openverse резервом; бюджет
  времени поиска в `GenerationPipeline` (после бюджета карточки импортируются
  без иллюстраций, генерация не ждёт 20×20 с).
- Реализация: `lib/api/images/wikimedia_image_search_service.dart`,
  `composite_card_image_finder.dart`, провайдер `cardImageFinderProvider`,
  `GenerationPipeline` — дедлайн поиска.

### Шаг 5. PDF-сканы (Vision)
- Red: `PdfScanRenderer` по умолчанию ≤ 3 страниц (ADR-027);
  `FileParsingService.renderPdfPages` → PNG; интеграционный тест: скан-PDF
  (реальный PDFium) → экран генерации → вложение-страницы → **image parts** в
  теле запроса (fake HTTP); модель без Vision → строка
  «Модель не поддерживает сканы».
- Реализация: `maxPages = 3`; при необходимости — уменьшение ширины/байтов.
- Живая проверка: DeepSeek (`deepseek-flash`) принимает image_url (проверено
  probe-запросом 2026-11-15) — live-тест со сканом под тегом `live`.

### Шаг 6. Verify + приёмка
- `fvm flutter test --no-pub --coverage --exclude-tags golden`, `analyze`,
  `dart format`, `build windows`, запуск приложения `fvm flutter run -d windows`
  + прогон на Windows интеграционного смоук-теста на реальном графе
  (drift-БД файл + MediaStore + PDFium + роутер).
- ADR-025 (practice), ADR-027 (источники иллюстраций), обновление
  `journal/STATE.md`, `KNOWN_LIMITATIONS.md`, push, один прогон CI.

## Риски
- `due = now` для новых карточек: счётчики/порядок/фильтры, которые опирались на
  `due IS NULL`, обязаны смотреть на `state` — закрыто тестами (шаг 1).
- `review_logs.mode='practice'`: расход лимитов и статистика не должны считать
  тренировку планируемым повторением — закрыто тестами (шаг 3).
- Второй источник картинок: лицензии Commons — только свободные, атрибуция в
  `GeneratedCardImage.attribution` (как у Openverse).
