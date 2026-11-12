# Итерация 1 — Колоды + БД. План

**Дата:** 2026-11-12 · **Автономность:** `ИТЕРАЦИИ` · **Шаг:** 1 (план)
**Цель итерации (SPEC B2, строка 1):** SQLite/drift-схема и миграции, CRUD колод, экран «Колоды» (A6.2: поиск/фильтр/архив с undo), импорт/экспорт `.zip` без потерь (A6.9, SPEC 0.4.4).

## 0. Факты о текущем состоянии (проверено в этой сессии перед правками)

- Рабочее дерево: `git status` — **clean**, ветка `main`, `HEAD = d2dbf67` (`docs: record green CI run 43098651759 in journal`), remote `origin` синхронизирован.
- `fvm flutter --version` → **Flutter 3.47.9 stable / Dart 3.13.7** (framework `c197ca5199`, 2026-10-29), FVM 4.3.2.
- Последний прогон тестов до правок: **`fvm flutter test` — 76 тестов, все зелёные** (0 падений).
- Итерация 0 закрыта: ревью принято, CI run `43098651759` — 9/9 success. План итерации 1 в итерации 0 не создавался → создаётся сейчас.
- **Спайк S3 (drift + нативный SQLite) — выполнен в этой сессии и успешен:** `fvm dart run tool/spike_sqlite.dart` → `sqlite3.version = libVersion 3.54.1` («СПАЙК OK»); тот же код в `flutter test` → «All tests passed». Вывод: `drift` + `NativeDatabase` (FFI) работает без `drift_flutter`/`sqlite3_flutter_libs`; в CI (ubuntu/windows/macos) нативные ассеты соберутся так же. `drift_flutter` не добавляем (ADR-005).
- Ключей API нет (absent), `.doc/.xls` — ограничение (ADR-003), Android SDK/Xcode/Linux локально нет.

## 1. Задачи итерации, файлы, проверка

| # | Задача | Владелец | Файлы (контракт) | Проверка |
|---|---|---|---|---|
| 1.1 | Контракты домена: `Deck`, `Card`, `DeckSummary`, `DeckQuery`/`DeckFilter`, `content_hash`, интерфейсы репозиториев и transfer-слоя | Lead | `lib/domain/decks/**`, `lib/domain/cards/**`, `lib/domain/transfer/**` | `fvm flutter analyze`; unit-тесты нормализации/равенства |
| 1.2 | ADR-005 (открытие БД/миграции), ADR-006 (формат `.zip` v1 — публичный контракт), ADR-007 (семантика списка колод + M3E-интеграция) + `docs/archive-format.md`, обновление `docs/dependencies.md` | Lead | `docs/decisions/**`, `docs/archive-format.md`, `docs/dependencies.md` | документы существуют, контракты согласованы с кодом |
| 1.3 | drift-схема всей A5 (10 таблиц + 3 индекса, `schemaVersion=1`), открытие БД, стратегия миграций, репозитории колод/карточек (CRUD/watch/поиск/фильтр/архив/каскад) | data-drift | `lib/data/db/**`, `lib/data/decks/**`, `lib/data/cards/**`, `test/unit/data/{db,decks,cards}/**`, `test/migrations/**`, `drift_schemas/**` | schema-тест по `sqlite_master`/`PRAGMA` соответствует A5; CRUD/watch/filter/archive/cascade тесты зелёные; `build_runner` отработал |
| 1.4 | ZIP-кодек: `meta.json` (`format_version`), `cards.json`, `media/`; строгая валидация, zip-slip защита, лимиты; `FileGateway` (file_picker) + `MediaStore` | archive-zip | `lib/data/transfer/**`, `test/unit/data/transfer/**` | кодек: roundtrip без потерь, unknown version/corrupt/missing entry/лимиты/zip-slip — красные до реализации, затем зелёные |
| 1.5 | `DriftDeckTransferService`: экспорт колоды в zip, preview импорта, импорт одной транзакцией с дедупликацией, media roundtrip | archive-zip (фаза 2, после 1.3) | `lib/data/transfer/**` | тест export→import→export: карточки/поля/медиа без потерь; пустая колода; ошибки |
| 1.6 | Экран «Колоды» (A6.2): AppBar «Мои колоды», поиск, чипы фильтра, список, свайп-архив с undo-снекбаром, меню (Переименовать/Экспорт/Удалить), Split «Создать» (Вручную/Импорт .zip), FAB «Создать колоду», пустое состояние | ui-decks | `lib/ui/decks/**`, `lib/ui/state/**`, `lib/l10n/app_ru.arb`, `test/widget/**`, `test/helpers/**` | widget-тесты: loading/empty/error/success, поиск, фильтр, архив+undo, CRUD-диалоги, импорт/экспорт через фейковые gateway/repo; строки только из ARB |
| 1.7 | Экран колоды (минимальный A6.3 для навигации и экспорта): заголовок, счётчики, список карточек, меню переименовать/экспорт/удалить, пустое состояние | ui-decks | `lib/ui/decks/**` | widget-тест: счётчики, пустое состояние, экспорт, удаление с подтверждением |
| 1.8 | M3E runtime-спайк S2 (завершение): `M3ETheme` в корне, M3E-карточки/чипы/снекбар на экране «Колоды»; при провале — fallback ADR-001 вариант 2 | ui-decks + Lead | `lib/ui/m3e/**`, `lib/ui/app.dart` | widget-тест рендерит M3E-компонент; результат спайка зафиксирован в ADR-007/ADR-001 |
| 1.9 | Интеграция: `ProviderScope`/БД в `main.dart`, `GoRouter` (`/`, `/decks/:id`), тема, M3ETheme; провайдеры БД/репозиториев/трансфера | Lead | `lib/main.dart`, `lib/ui/app.dart`, `lib/ui/router/**`, `lib/data/**/**_provider.dart` | `fvm flutter test` полный прогон; приложение собирается (Windows — известное L2b) |
| 1.10 | Ревью (code + security для импорта/экспорта), устранение blocker/critical/high | reviewer | `journal/iteration-1/review.md` | отчёт с findings и статусами |
| 1.11 | Верификация: полный тест, analyze, format, покрытие ≥80%, guard-тесты, сборка Windows (ожидаемо L2b) | Lead | `journal/iteration-1/verify.md`, `journal/KNOWN_LIMITATIONS.md` | команды и вывод в журнале |
| 1.12 | Память: `summary.md`, `STATE.md`, checkpoint-коммиты, ретроспектива шага 7 | Lead | `journal/iteration-1/summary.md`, `journal/STATE.md`, `AGENTS.md` (при необходимости) | артефакты существуют; следующий шаг — одна строка |

## 2. Критерии приёмки итерации 1

- [ ] drift-схема соответствует SPEC A5: все 10 таблиц, колонки/типы, 3 индекса, `PRAGMA foreign_keys=ON`, `ON DELETE CASCADE`.
- [ ] Миграционная стратегия зафиксирована (ADR-005), schema-тест/`SchemaVerifier` зелёный.
- [ ] CRUD колод + архив/восстановление + каскадное удаление — покрыты тестами.
- [ ] Экран «Колоды»: все элементы A6.2, которые можно реализовать без мёртвых кнопок, работают; «Сгенерировать карточки», «Статистика», «Начать сессию», «Продолжить обучение» — **не отрисованы** до своих итераций.
- [ ] Поиск и фильтр (Все/Новые/В процессе/Просроченные) работают по семантике ADR-007.
- [ ] Архив свайпом влево + undo-снекбар «Колода в архиве. Отменить».
- [ ] Импорт/экспорт `.zip` формата v1 (`meta.json`/`cards.json`/`media/`) без потерь; неверная версия/битый архив — сообщение из ARB, не сырая ошибка.
- [ ] Дедупликация при импорте (`content_hash`), результат показан в предпросмотре.
- [ ] Все новые строки — в `app_ru.arb`; guard-тесты (`ru_strings`, `no_secrets`, `no_webview`, `architecture`) зелёные.
- [ ] `flutter analyze` — 0 issues, `dart format` применён, покрытие рукописного `lib/` ≥ 80%.
- [ ] Ревью без blocker/critical/high; security-аспекты импорта (zip-slip, лимиты, сырые ошибки) закрыты.
- [ ] `journal/iteration-1/{plan,red-*,review,verify,summary}.md` заполнены, `STATE.md` обновлён, checkpoint-коммиты созданы.

## 3. ADR итерации (планируемые)

- **ADR-005** — открытие БД: `sqlite3` 3.9.1 native assets + `drift` `NativeDatabase`, без `drift_flutter`; `schemaVersion=1`, policy миграций (schema dump + upgrade-тесты при появлении v2).
- **ADR-006** — публичный контракт `.zip` v1: структура `meta.json`/`cards.json`/`media/`, типы полей, правила импорта (новый id колоды/карточек, дедупликация, media), лимиты и zip-slip.
- **ADR-007** — семантика списка колод (порядок, поиск, значения фильтров, архив/undo) + интеграция M3E: `MaterialApp.router` + `M3ETheme` в `builder` (M3EMaterialApp не принимает `routerConfig`/GoRouter), набор M3E-компонентов; результат runtime-спайка S2.

## 4. Риски

1. **drift codegen + CI:** сгенерированные `*.g.dart` коммитятся; CI не запускает `build_runner`. Убедиться, что `dart format --set-exit-if-changed` стабилен на сгенерированных файлах.
2. **M3E-компоненты в widget-тестах** могут требовать `M3ETheme` и давать долгие анимации → тестовый harness с `M3ETheme`, `pump` с длительностями; при невозможности — fallback ADR-001 вариант 2 (зафиксировать).
3. **Дрейф API drift 2.35.4** (имена `named()`, `customSelect`, `SchemaVerifier` — версия `drift_dev` 2.35.3) — сверять с документацией пакета/исходниками, спайк в отдельном тесте.
4. **Параллельная работа агентов:** пересечение файлов исключено scopes; `build_runner` запускает только data-drift; git-коммиты делает только Lead.
5. **Покрытие:** новый UI/кодек большой; писать тесты вместе с реализацией, после прогона добить непокрытые ветки.
6. **OneDrive-блокировки файлов** при codegen/сборке — фиксировать фактом, при сбое повторить.

## 5. Порядок исполнения и параллелизация

1. Lead: контракты домена (1.1) + план + ADR-005/006/007 (1.2) + обновление STATE.md (шаг 1).
2. Параллельно: data-drift (1.3), ui-decks (1.6/1.7/1.8 — сначала M3E-спайк + экраны на фейках), archive-zip (1.4 → 1.5 после появления схемы).
3. Lead: интеграция (1.9) по мере готовности кусков; коммиты после каждого зелёного куска.
4. reviewer (1.10) — после зелёного полного прогона; независимое ревью и security-фокус на импорте.
5. Lead: устранение findings, верификация (1.11), память (1.12), отчёт, стоп.

## 6. Красная фаза: требования к доказательствам

TDD: тест → красный (вывод с ожидаемым поведением assertion-level, не только ошибка компиляции) → минимальная реализация → зелёный.
Каждый агент сохраняет фрагмент красного прогона в отдельный файл (без конкурентной записи):
`journal/iteration-1/red-data.md`, `red-transfer.md`, `red-ui.md`. Lead сводит их в verify.md.
Red-вывод должен содержать «ожидалось: X, получено: Y» (assertion-level), например:
`Expected: <basic> Actual: <null>` / `Expected: [deck-1] Actual: []`.

## 7. Коммиты (делает только Lead; агенты git не трогают)

1. `docs: iteration 1 plan, ADRs and archive format contract`
2. `feat(domain): deck, card and transfer contracts with tests`
3. `feat(data): drift schema, migrations and deck/card repositories with tests`
4. `feat(data): zip archive codec and deck transfer service with tests`
5. `feat(ui): decks and deck screens on M3E with widget tests, go_router wiring`
6. `fix: review findings ...`
7. `docs: iteration 1 verify, review, summary and state`

## 8. Фактическое выполнение (итог, 2026-11-12)

| Задача | Статус | Подтверждение |
|---|---|---|
| 1.1 Контракты домена | выполнено | `lib/domain/**`, unit-тесты; коммит `6f6482b` |
| 1.2 ADR-005/006/007 + archive-format + dependencies §8 | выполнено | `docs/decisions/**`, `docs/archive-format.md`; ADR-007 после спайка S2 |
| 1.3 drift-схема/миграции/репозитории | выполнено (data-drift) | 60 тестов, schema/migration-тесты; коммит `197ff36` |
| 1.4 ZIP-кодек/MediaStore/FileGateway | выполнено (archive-zip) | 142 теста transfer (после fix-итерации); коммит `d4b9e89` + fix |
| 1.5 DriftDeckTransferService | выполнено (archive-zip) | export/preview/import, интеграционный roundtrip; fix H1/M8/M9/M10 |
| 1.6 Экран «Колоды» | выполнено (ui-decks) | 16 widget-тестов; коммит `aafc448` + fix M11 |
| 1.7 Экран «Колода» | выполнено (ui-decks) | widget-тесты; коммит `aafc448` |
| 1.8 M3E runtime-спайк S2 | выполнено | M3ECard/M3EChip/M3ESnackbar/M3EExtendedFab/M3ESplitButton; ADR-007; тест spike |
| 1.9 Интеграция main/app/router/провайдеры | выполнено | GoRouter, ProviderScope, M3ETheme; `test/integration/`, `test/widget/app_test.dart` |
| 1.10 Ревью (code+security) | выполнено | reviewer: H1 + M1–M13; blocker/critical/high = 0 после фиксов |
| 1.11 Верификация | выполнено | `verify.md`: 374 теста, analyze 0, format 0, покрытие 96,0%, build windows OK |
| 1.12 Память/ретро | выполнено | `summary.md`, STATE, AGENTS (улучшение процесса) |

**Отступления от плана:** (а) `FileGateway`-контракт изменён в середине итерации из-за API `file_picker 13.3.3` (`saveZipFile` вместо pick+write) — зафиксировано в ADR-006; (б) добавлена fix-итерация по findings ревью (task-5/6/7 + Lead) — отдельный коммит `fix:`; (в) `tables.dart` исключён из покрытия (ADR-005 addendum).