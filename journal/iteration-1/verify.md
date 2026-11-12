# Итерация 1 — Колоды + БД. Проверка (шаг 5)

**Дата:** 2026-11-12 · **Автономность:** `ИТЕРАЦИИ` · **Исполнитель:** Lead + команда (data-drift, archive-zip, ui-decks, reviewer)
**Скоуп:** SPEC B2 итерация 1: SQLite/drift + миграции, CRUD колод, экран «Колоды» (A6.2), поиск/фильтр/архив с undo, импорт/экспорт `.zip` (A6.9), минимальный экран «Колода» (A6.3).
**Связанные документы:** `journal/iteration-1/plan.md`, `summary.md`, `review.md`, `red-{data,transfer,ui}.md`; ADR-005, ADR-006, ADR-007; `docs/archive-format.md`.

## 1. Финальный прогон (эта сессия, финальный снимок дерева)

| # | Команда | Результат |
|---|---|---|
| 1 | `fvm dart format --output=none --set-exit-if-changed .` | **Formatted 84 files (0 changed)**, exit 0 |
| 2 | `fvm flutter analyze` | **No issues found! (3.5s)** — 0 issues |
| 3 | `fvm flutter test --coverage --reporter compact` | **All tests passed! +378** (0 падений), включая guard-тесты |
| 4 | `fvm dart run tool/coverage_check.dart --min=80` | **96.0% (1666/1736), ПОРОГ ПРОЙДЕН** — см. §2 |
| 5 | `fvm flutter build windows --release` | **√ Built build\windows\x64\runner\Release\cardflow.exe** (44,3 s) — впервые локально (L2b снят) |
| 6 | `fvm flutter gen-l10n` | OK (после правок ARB; `databaseOpenError`, `deckActionArchive` и др. сгенерированы) |
| 7 | `fvm flutter test test/guards` (в составе полного прогона) | 35 тестов: `no_webview`, `ru_strings`, `no_secrets`, `architecture` — зелёные |

Минимальные покрытия по файлам: `database_opener.dart` 83,3% (пути с `path_provider` не исполняются в тестах), `zip_deck_archive_codec.dart` 91,3%, `drift_deck_transfer_service.dart` 96,6%, `decks_screen.dart` 95,2%, `app_providers.dart` 88,9%; остальные ≥95% либо 100%. Исключён из покрытия только декларативный `lib/data/db/tables.dart` (drift-DSL, ADR-005 addendum).

**Не измерены (нет исполняемых строк / entry point):** абстрактные интерфейсы `lib/domain/**/**_repository.dart`, `archive_codec.dart`, `deck_transfer_service.dart`, `file_gateway.dart`, `lib/main.dart` (точка входа), `lib/ui/m3e/m3e.dart` (только export).

## 2. Критерии приёмки итерации 1 (plan §2) — статусы

| Критерий | Статус | Доказательство |
|---|---|---|
| drift-схема соответствует SPEC A5 (10 таблиц, колонки/типы, 3 индекса, `PRAGMA foreign_keys=ON`, `ON DELETE CASCADE`) | **выполнено** | `test/unit/data/db/schema_test.dart` (20 тестов: PRAGMA/sqlite_master, FK, каскад), `test/migrations/migration_test.dart` (dump v1 == schemaVersion, 10 таблиц + 3 индекса), drift dump `drift_schemas/drift_schema_v1.json` |
| Миграционная стратегия зафиксирована, schema-тест/`SchemaVerifier` зелёный | **выполнено** | ADR-005; `test/migrations/migration_test.dart` (4 теста: актуальность dump, onCreate == dump, открытие поверх v1) |
| CRUD колод + архив/восстановление + каскадное удаление (в т.ч. media-строки/файлы — M5) | **выполнено** | `test/unit/data/decks/deck_repository_test.dart` (33 теста, включая 4 M5-кейса и каскад) |
| Экран «Колоды»: элементы A6.2 без мёртвых кнопок; «Сгенерировать», «Статистика», «Продолжить обучение» не отрисованы | **выполнено** | `test/widget/decks/decks_screen_test.dart` (16 тестов), `test/widget/app_test.dart`; ревью подтвердило отсутствие мёртвых элементов |
| Поиск и фильтр (Все/Новые/В процессе/Просроченные) по семантике ADR-007 | **выполнено** | ADR-007; `test/unit/data/decks/deck_repository_test.dart` (поиск: регистр/ё-е/подстрока; 4 фильтра; порядок), `decks_screen_test.dart` (чипы/поиск в UI) |
| Архив свайпом влево + undo-снекбар «Колода в архиве. Отменить» (+ доступность: пункт меню, M11) | **выполнено** | `decks_screen_test.dart`: свайп+undo, «Архивировать» из меню+undo (fix M11) |
| Импорт/экспорт `.zip` v1 (`meta.json`/`cards.json`/`media/`) без потерь; ошибки — из ARB | **выполнено** | `test/unit/data/transfer/**` (142 теста: кодек 70, MediaStore 31, FileGateway 18, сервис 23), `test/integration/deck_zip_roundtrip_test.dart` (export→import→export: карточки/настройки/медиа без потерь; дубликаты; deckNotFound) |
| Дедупликация при импорте (`content_hash`, пересчёт при импорте — M9), результат в предпросмотре | **выполнено** | `deck_transfer_service_test.dart` (пересчёт, подмена хеша, дубликаты), `import_export_test.dart` (диалог предпросмотра: карточки/дубликаты/медиа) |
| Все строки в ARB; guard-тесты зелёные | **выполнено** | guard 35/35; `ru_strings` (ARB без латиницы вне allow-list, нет литералов в `Text`), `architecture` (material_ui/M3E-изоляция/domain без Flutter), `no_webview`, `no_secrets` |
| `flutter analyze` 0 issues, `dart format` применён, покрытие ≥80% | **выполнено** | §1: analyze 0, format 0 changed, покрытие 96,0% |
| Ревью без blocker/critical/high; security-аспекты импорта закрыты | **выполнено** | `journal/iteration-1/review.md`: H1 закрыт (проверка размера до чтения), M-серия закрыта/задокументирована; blocker/critical/high = 0 |
| Журнал/verify/summary/STATE обновлены, checkpoint-коммиты | **выполнено** | этот файл, `summary.md`, `journal/STATE.md`, коммиты сессии |

## 3. Независимое ревью (шаг 4): findings и закрытие

Исполнитель — отдельный агент `reviewer` (не участвовал в реализации), отчёт — `journal/iteration-1/review.md`.

| ID | Severity | Суть | Статус |
|---|---|---|---|
| H1 | high | лимит 100 МБ проверялся после полного чтения файла → OOM | **closed**: `FilePickerGateway.readFile` проверяет `File.length()` до `readAsBytes` → `ArchiveException(tooLarge)`; тесты |
| M1 | medium | битые управляющие символы в `docs/dependencies.md` §8 и ADR-005 addendum | **closed**: секции перезаписаны, проверено отсутствие control-char |
| M2 | medium | ссылка на ещё не созданный verify.md | **closed**: `verify.md` создан до коммита |
| M3 | medium | STATE.md отставал от реальности | **closed**: STATE перезаписан по шагам |
| M4 | medium | red-evidence не для всех тестов | **documented deviation** (см. §4) |
| M5 | medium | удаление колоды оставляло media-строки/файлы | **closed**: транзакция в `deleteDeck` + `MediaStore` + production-проводка в `app_providers` + интеграционный тест |
| M6 | medium | нет обработки ошибок открытия БД | **closed**: `StartupErrorApp` + ARB `databaseOpenError` + try/catch в `main.dart`, widget-тест |
| M7 | medium | двойной decode и тяжёлый decode на UI-изоляте | **deferred**: KNOWN_LIMITATIONS L13 (кандидат итерации 2) |
| M8 | medium | нет лимита числа zip-записей | **closed**: `DeckArchiveLimits.maxEntries` + проверка до валидации, тесты |
| M9 | medium | импорт доверял `content_hash` из архива | **closed**: хеш всегда пересчитывается, dedup/запись по нему, тесты |
| M10 | medium | пустое имя колоды при импорте | **closed**: `invalidMeta` для пустого/пробельного `deck.name`, trim override, тесты |
| M11 | medium | архив только свайпом (доступность) | **closed**: пункт «Архивировать» в меню + тест |
| M12 | medium | изменение существующего теста не отражено в журнале | **closed**: зафиксировано в §4 настоящего файла |
| M13 | medium | семейства провайдеров не autoDispose | **closed**: `StreamProvider.autoDispose.family` для `deckProvider`/`deckCardsProvider`/`deckSummaryProvider`; KNOWN_LIMITATIONS L10 обновлён |
| M14 | medium | docs-дефекты: мусорная строка в ADR-006, управляющие символы/противоречие в KNOWN_LIMITATIONS | **closed**: ADR-006 очищен, `KNOWN_LIMITATIONS.md` перезаписан (L9/L9b/L11 исправлены, L9b не противоречит L2b, добавлены L14–L17) |
| Low | low | 16 замечаний (L1–L16 ревьюера) | **закрыто частично/задокументировано**: исправлены filename-санитизация (ADR-006 п.8 и `cardflow`-fallback), нейтральная строка tooLarge, двойное вложение `media/media` в `main.dart`, тавтологичные проверки в тестах, autoDispose `deckSummariesProvider`, zip-slip кейсы с `\` и `C:`; остальное — KNOWN L11/L14/L15/L16/L17 + review.md §low |

## 4. Изменения существующих тестов и осознанные отступления

1. **`test/widget/app_localization_test.dart` (изменён):** корень приложения стал `MaterialApp.router` + экран «Колоды» на Riverpod (итерация 1), поэтому тест обёрнут в `ProviderScope` с фейковым data-слоем; удалена проверка `find.text('CardFlow')` (заголовок приложения больше не отображается телом — он в `onGenerateTitle`, что и проверяет `AppLocalizations.appTitle`). Поведение по SPEC не менялось — изменилась обвязка корня.
2. **Red-evidence (M4):** assertion-level красная фаза сохранена для data (`red-data.md`: `+25 -30` на скелетах), transfer (`red-transfer.md`: `+11 -38`, mutation-контроль `+1 -64`, fix-итерация `+135 -7`), UI (`red-ui.md`: `+0 -31` на заглушках, fix M11). Для Lead-контрактов домена и migration/spike-тестов красная фаза была **компиляционной** (тесты писались после контрактов) — фабриковать assertion-level вывод не стали; это осознанное отступление процесса, зафиксировано здесь и в `summary.md`.
3. **`tool/coverage_check.dart`:** добавлено исключение `lib/data/db/tables.dart` (drift-декларативный DSL, 0/89 исполняемых строк, задокументировано в ADR-005 addendum); порог не понижался.
4. **ADR-006:** добавлены правила fix-итерации (лимит чтения, maxEntries, пересчёт `content_hash`, валидация имени, очистка media при удалении колоды); `docs/archive-format.md` синхронизирован.
5. **`AGENTS.md`:** обновлены факты хоста (Windows-сборка работает, L2b снят).

## 5. Что не проверено и почему (KNOWN_LIMITATIONS)

| # | Не проверено | Причина | Где зафиксировано |
|---|---|---|---|
| L9 | CI-прогон итерации 1 | push — только по команде владельца | KNOWN_LIMITATIONS L9 |
| L9b | сборки linux/macos/android/ios | нет соответствующих тулчейнов на хосте | L9b |
| L11 | реальные диалоги `file_picker`, `content://` на Android/iOS | нет Android SDK/Xcode; unit-тесты подменяют платформу | L11 |
| L12 | screen-reader/keyboard-обход M3E-меню, golden-тесты | golden — Linux CI; устройства недоступны | L12 |
| L10 | устаревание `due`-счётчиков при открытом экране | drift не переизлучает по времени | L10 |
| L13 | двойной decode + синхронная работа на UI-изоляте (M7) | требует изменения контракта сервиса/изолята — итерация 2 | L13 |
| — | OOM на реальных 100 МБ и 10 000 записей не воспроизводился | лимиты покрыты инжектируемыми значениями на temp-файлах; специально не создавали гигантские архивы | `red-transfer.md` §13–15 |

## 6. Вывод

Итерация 1 по критериям приёмки — **выполнена**: все пункты plan §2 имеют статус «выполнено» с доказательством в этой сессии; H1 и все критичные для релиза medium ревью закрыты; оставшиеся пункты переведены в известные ограничения (L9/L9b/L10/L11/L12/L13) и не блокируют MVP-срез. Blocker/critical/high по ревью — 0.

## 7. Post-review правки (M14 + low)

После повторной проверки reviewer (M14) исправлено и перепроверено:
- `docs/decisions/ADR-006-zip-archive-format.md` — удалена мусорная строка PowerShell в конце addendum; п.8 про имя файла приведён к фактической реализации (санитизация в пробел, обрезка 80, fallback ARB → `cardflow.zip`).
- `journal/KNOWN_LIMITATIONS.md` перезаписан: управляющих символов нет, L9b больше не противоречит работающей Windows-сборке (L2b), пустая строка таблицы устранена, добавлены L14–L17.
- Low: `main.dart` — корень `MediaStore` = `cardflow/` (пути `media/<id>`, без вложенного `media/media`); `deck_archive_file_name.dart` — брендовый fallback `cardflow` вместо литерала; ARB `archiveErrorTooLarge` — нейтральная формулировка; `deckSummariesProvider` — `autoDispose`; тавтологичные проверки в тестах заменены; добавлены zip-slip кейсы `media\evil` и `C:/evil`.
- Финальный прогон после правок: см. журнал коммитов и `summary.md` (analyze/format/тесты/покрытие перепрогнаны).
