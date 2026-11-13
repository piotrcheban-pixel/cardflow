# Итерация 1 — Колоды + БД. Итог (шаг 6) и ретроспектива (шаг 7)

**Дата:** 2026-11-12 · **Режим:** `ИТЕРАЦИИ` · **Статус:** завершена (после отчёта — стоп)
**Цель SPEC B2:** SQLite/drift-схема и миграции, CRUD колод, экран «Колоды» (A6.2), поиск/фильтр/архив с undo, импорт/экспорт `.zip` без потерь (A6.9).

## Сделано

**Данные и контракты**
- Полная drift-схема SPEC A5: 10 таблиц, 3 индекса, `schemaVersion=1`, `PRAGMA foreign_keys=ON`, fail-fast `onUpgrade`, `AppDatabase.inMemory()` для тестов; открытие БД — `NativeDatabase` + `path_provider` без `drift_flutter` (ADR-005).
- Миграционная инфраструктура: `drift_schemas/drift_schema_v1.json` + `test/migrations/**` (dump актуален, onCreate == dump).
- Доменные контракты без Flutter: `Deck`, `Card`, `DeckQuery/DeckFilter`, `DeckSummary`, `content_hash`, архивы/кодек/сервис/файловый шлюз (`lib/domain/**`).
- Репозитории: колоды (watch-сводки со счётчиками, поиск, 4 фильтра, архив, CRUD, каскадное удаление с очисткой media-строк и файлов) и карточки (полный маппинг полей).
- ZIP-формат v1 (публичный контракт): `meta.json`/`cards.json`/`media/`, строгая валидация, лимиты (размер файла до чтения, 300 МБ распакованного, 32 МБ JSON, 10 000 записей), zip-slip, пересчёт `content_hash` при импорте, дедупликация, новые id, атомарный импорт с откатом; экспорт/предпросмотр/импорт через `DriftDeckTransferService`.

**UI**
- Экран «Колоды» (A6.2) на M3 Expressive: M3ECard-список, поиск (ё-нормализация), 4 чипа фильтра, свайп-архив + undo, меню (Переименовать/Экспорт/Архивировать/Удалить), Split «Создать» (Вручную / Импорт ZIP), Extended FAB «Создать колоду», пустое/loading/error+retry состояния.
- Экран «Колода» (A6.3, минимальный): счётчики, список карточек без мёртвых тапов, меню переименования/экспорта/удаления, «Колода не найдена».
- Импорт/экспорт UI: предпросмотр, маппинг всех `ArchiveErrorCode` в ARB, тихий no-op при отмене диалогов; `StartupErrorApp` при сбое открытия БД.
- Корень: GoRouter (`/`, `/decks/:deckId`), `M3ETheme` в `MaterialApp.builder` (ADR-007), `ProviderScope`/БД/MediaStore в `main`.

**Прочее**
- 60+ строк ARB, ICU-плюрализация; guard-тесты зелёные.
- Документация: ADR-005 (БД/миграции), ADR-006 (zip v1 + fix-правила), ADR-007 (M3E + семантика списка колод), `docs/archive-format.md`, `docs/dependencies.md` §8, `journal/KNOWN_LIMITATIONS.md` (L2b снят, L9–L13).

## Доказательства (эта сессия)

- `fvm flutter test --coverage` → **378 тестов, все зелёные** (0 падений).
- `fvm dart run tool/coverage_check.dart --min=80` → **96,0% (1666/1736), порог пройден**.
- `fvm flutter analyze` → **No issues found!**
- `fvm dart format --output=none --set-exit-if-changed .` → **84 files, 0 changed**.
- `fvm flutter build windows --release` → **√ Built build\windows\x64\runner\Release\cardflow.exe** (локальная Windows-сборка впервые; L2b снят).
- Guard-тесты 35/35; миграционные/schema-тесты; интеграционные тесты `test/integration/` (реальные drift-БД, кодек, MediaStore, граф провайдеров).
- Независимое ревью: `journal/iteration-1/review.md` — blocker/critical/high = 0; H1 + M1–M13 закрыты/задокументированы.
- Подробный отчёт по критериям — `journal/iteration-1/verify.md`.
- **CI (добавлено 2026-11-13):** прогон GitHub Actions [`43436887755`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43436887755) — зелёный, все job success: `quality` (format + analyze), `test` × 3 ОС (ubuntu/windows/macos), `build-desktop` × 3 ОС, `build-mobile` Android + iOS. Коммит — `052d2a2` (= `origin/main`). Это закрывает L9 и L9b: сборки linux/macos/android/ios с native assets `sqlite3` подтверждены в CI. Статус — со слов владельца (репозиторий private, из окружения агента прогон независимо не проверяется: `gh` CLI/токен отсутствуют, анонимный fetch → 404).

## ADR итерации

- **ADR-005** — открытие SQLite (drift + `NativeDatabase` + native assets `sqlite3` 3.9.1), политика миграций; addendum: исключение декларативного `tables.dart` из покрытия.
- **ADR-006** — публичный контракт `.zip` v1 (структура, типы, лимиты, zip-slip, пересчёт хеша, новые id, транзакционность) + addendum fix-итерации.
- **ADR-007** — M3E-интеграция (`MaterialApp.router` + `M3ETheme`; `M3EMaterialApp` несовместим с GoRouter) и семантика списка колод (порядок, поиск, значения фильтров, архив/undo, границы экранов).

## Что осталось / следующий шаг (итерация 2 — «Классический режим»)

1. Session scaffold, 4 кнопки с прогнозом, undo, запись `review_logs`, обновление `due`/`fsrs_json` в одной транзакции (SPEC A7.2, A6.4).
2. `Card`-редактирование/создание (сейчас карточки появляются только импортом) — форма, валидация, `content_hash` (A5).
3. Кандидаты на закрытие ограничений: L10 (перезапрос due по таймеру), L13 (один decode + `Isolate.run`), L11/L12 — по мере появления устройств/CI.
4. ~~CI-прогон итерации 1 — после пуша по команде владельца (L9)~~ **закрыто 2026-11-13:** run [`43436887755`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43436887755) зелёный, L9/L9b сняты.

## Ретроспектива (шаг 7)

**Что замедлило:**
- Параллельная работа агентов дала большой выигрыш по времени, но фикс-слой «не дошёл до production» (M5: репозиторий чинит media, а `app_providers` не передаёт `MediaStore`) — ревью поймало это только на повторной проверке; ни один unit-тест слоя такое не ловит.
- API-drift `file_picker 13.3.3` (`saveFile` пишет байты сам) обнаружился уже в реализации и потребовал изменения domain-контракта `FileGateway` в середине итерации.
- Форматирование сгенерированных drift-файлов и `dart format` по всему дереву несколько раз давало «changed», приходилось перегонять после каждого codegen/ARB-шага.

**Какие тесты лишние/чего не хватило:**
- Тест на `tables.dart` был бы тавтологией (схема проверяется PRAGMA-тестом) — исключение обосновано.
- Не хватило сразу интеграционного теста «production-граф провайдеров»; он появился после ревью M5 и теперь ловит класс ошибок «фикс слоя не подключён».

**Где команда/навыки помогли:** `flutter_test`+`mocktail` фейки для UI (быстрые widget-тесты без БД), drift `SchemaVerifier`/schema dump для миграций, M3E-спайк до кода экрана (сэкономил переделки).

**Конкретное улучшение процесса (внесено в AGENTS.md):** фикс-итерация после ревью — отдельный шаг до verify; каждый фикс слоя обязан подтверждаться интеграционным тестом на production-проводке (`app_providers`/`main`), а не только unit-тестами слоя.
