# Итерация 2 — «Классический режим». Проверка (шаг 5)

**Дата:** 2026-11-13 · **Режим:** `ИТЕРАЦИИ` · **HEAD на момент проверки:** `c589e8a` + fix-итерация (фикс H1/M1–M3 и low ревью)
**Цель SPEC B2:** ReviewSessionScaffold (A6.4), 4 кнопки с прогнозом (A7.2), undo, `review_logs` + обновление `due`/`fsrs_json` в одной транзакции (A5), создание/редактирование карточек (A6.3).

## Доказательства (эта сессия, после fix-итерации)

| Команда | Результат |
|---|---|
| `fvm flutter test` | **484 теста, все зелёные** (0 падений) |
| `fvm flutter analyze` | **No issues found!** |
| `fvm dart format --output=none --set-exit-if-changed lib test tool` (эквивалент `dart format` в CI) | **110 files, 0 changed** |
| `fvm flutter test --coverage` + `fvm dart run tool/coverage_check.dart --min=80` | **95,3% (2523/2648), порог пройден**; не измерены только интерфейсные/точки входа (см. ниже) |
| `fvm flutter test test/guards` | 35/35 зелёные (WebView, ru-строки, секреты, архитектура) — входят в 484 |
| `fvm flutter build windows --release` | **√ Built build\windows\x64\runner\Release\cardflow.exe** (41,3 с) |
| `fvm dart run tool/fsrs_intervals_probe.dart` | таблица интервалов по состояниям — `journal/iteration-2/fsrs-intervals.md` |
| Ревью | `journal/iteration-2/review.md`: blocker 0 / critical 0 / high 1 / medium 3 / low 14 → после fix-итерации (`review-fixes.md`) **blocker/critical/high = 0, medium = 0** |

Покрытие не считает: `lib/main.dart` (точка входа), интерфейсные порты (`card_repository`, `deck_repository`, `review_repository`, `archive_codec`, `deck_transfer_service`, `file_gateway`), `lib/ui/m3e/m3e.dart` (реэкспорт) — стандартная практика проекта (ADR-005 addendum).

## Критерии приёмки итерации (plan.md C1–C12)

| # | Критерий | Статус | Доказательство |
|---|---|---|---|
| C1 | Каркас A6.4: прогресс, undo, выход с диалогом, «Почему?», карточка, панель | **выполнено** | `test/widget/review/review_session_screen_test.dart` (13 тестов: каркас, flip, выход, why, пусто/завершено/ошибка); после ревью — единая точка выхода `PopScope` + тест системного back (M2) |
| C2 | 4 кнопки: цвета ролей, клавиши 1–4, haptics A7.2 | **выполнено** | test «цвета кнопок A7.2 и значение прогресса», «пробел…, клавиши 1–4», haptic-канал (последовательность из 6 значений); `review_haptics_test.dart` |
| C3 | Прогноз == фактический `due` (та же операция планировщика) | **выполнено** | `fsrs_scheduler_test.dart`: preview==факт для new/learning/review/relearning + монотонность; engine-тест «прогноз == фактический due»; числа — `fsrs-intervals.md` |
| C4 | Тап/пробел → 3D-flip с Expressive-пружиной, вторая сторона `back` | **выполнено** (визуальная трансформация не asserted) | widget-тесты flip по тексту (тап и пробел); код — `SpringSimulation(AppMotion.expressiveSpring())`, `Matrix4.rotateY` |
| C5 | Undo откатывает лог + `due`/`fsrs_json`/`state`; стек в памяти | **выполнено** | data-тест undo (полное восстановление), widget undo, интеграционный flow; стек — только в движке (ADR-008) |
| C6 | `review_logs` + `cards` — атомарно; ошибка → ни одной записи | **выполнено** | успех (data), **ошибка после первой записи** — триггер `RAISE(ABORT)` на `review_logs` (M1), undo-откат при падении UPDATE; интеграционный flow на production-провайдерах |
| C7 | Поля лога: rating 1–4, reviewed_at ms, mode, scheduled_days, actual_days, elapsed_ms | **выполнено** | data-тест: rating=3, epoch ms, `classic`, `recognition_flag=0`, `scheduled_days=closeTo(10/1440)`, `actual_days=null`, `elapsed_ms=7000`; второй повтор — `actual_days=1.0` |
| C8 | Запуск из колоды: «Начать сессию» → режим (только классический), пустая очередь — сообщение | **выполнено** | widget-тесты экрана колоды + production-роутер тест (L2); пустая очередь — snackbar без перехода |
| C9 | Создание: поля; `basic_reversed` — 2 строки, mutual sibling; `content_hash` | **выполнено** | `card_crud_test.dart` (поля/нормализация/sibling/hash/транзакция), widget-форма; data-слой отвергает некорректный черновик (L7) |
| C10 | Редактирование/удаление: форма, update+hash, удаление с подтверждением, sibling | **выполнено** | `card_crud_test.dart` (update/hash/тип неизменен/удаление пары), widget (предзаполнение, update, диалог) |
| C11 | Валидация: front ≤500/non-empty, back ≤2000, теги ≤3 без `#`, ARB-сообщения | **выполнено** (отступление L13: >3 тегов — ошибка, не обрезка — зафиксировано ADR-009) | `card_draft_test.dart` (500/501, 2000/2001, 3/4, 400/401, cloze, несколько ошибок), widget-ошибки; сброс ошибки при правке (L10) |
| C12 | Только ARB/ru; guard-тесты | **выполнено** | guard 35/35; `dart format` 0 changed; `analyze` 0; новых литералов `Text('…')` нет |

## Дополнительно проверено

- **FSRS-числа (T17):** `journal/iteration-2/fsrs-intervals.md` — new 1 мин / 5 мин 30 с / 10 мин / 16 д; learning 1 мин / 10 мин / 4 д / 8 д; review (S=16.151, D=2.482) 10 мин / 27 д / 65 д / 164 д; relearning 10 мин / 15 мин / 3 д / 7 д. Fuzzing выключен (ADR-004), прогноз детерминирован и монотонен.
- **Интеграционные:** `review_session_flow_test.dart` — создание карточек → очередь → оценка → undo на реальной drift-БД и production-провайдерах; **H1**: оценка → export `.zip` → import → очередь → сессия импортированной колоды (новый id, fsrs перепривязан).
- **Регрессии:** тесты итерации 1 и guard-тесты не ослаблены; единственные правки существующих тестов — переименование `CardState.newState→newCard`/`fromWireName→fromWire` (T1, документировано) и валидный FSRS-снимок в фикстурах экспорта/импорта (H1, документировано).
- **Мёртвых кнопок нет:** всё отрисованное работает; нереализованное (другие режимы, настройки сессии, «Изменить/Отложить/Флаг», свайп-удаление, cloze-редактор) не отрисовано — план §«Вне объёма», ADR-008/009.

## Не проверено и почему

| Что | Причина | Где учтено |
|---|---|---|
| CI-прогон итерации 2 | push — только по команде владельца | `STATE.md`; CI итерации 1 зелёный (`43436887755`) |
| Сборки linux/macos/android/ios локально | на хосте нет Android SDK/Xcode/Linux; CI-матрица существует | L2, L9b (снят для итерации 1) |
| Визуальная трансформация 3D-flip, golden | golden-тестов нет, нужны Linux CI и шрифты с кириллицей | L6/L12; C4 «выполнено (визуальная трансформация не asserted)» |
| Live-вызовы API | нет ключей | L1 (вне объёма итерации 2) |
| Реальные `file_picker`/`content://`, mobile-жесты back | нет устройств/SDK | L11; системный back проверен widget-тестом (`handlePopRoute`) |
| Neighbor-squish кнопок A7.2/A4.5 | косметика, требует групповой анимации | L18 (итерация 7) |
| Keyboard/screen-reader M3E-меню, haptics на устройстве | нет устройств | L12 |

## Итог шага 5

**Все критерии C1–C12 — «выполнено».** Blocker/critical/high ревью устранены, medium закрыты, low закрыты или задокументированы. Проверка пройдена; переход к шагу 6 (память/checkpoint) и шагу 7 (ретроспектива).
