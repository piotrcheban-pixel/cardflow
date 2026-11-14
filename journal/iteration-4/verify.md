# Итерация 4 — проверка (шаг 5)

**Дата:** 2026-11-14 · **HEAD:** `1857589` (fix ревью; docs-коммит после verify) · **Ветка:** `main`,
дерево чистое на момент прогонов.
**Команды и результаты (эта сессия):**

| Проверка | Команда | Результат |
|---|---|---|
| Полный прогон тестов | `fvm flutter test --coverage --exclude-tags golden --reporter compact` | **959 passed + 1 skipped**, exit 0 (baseline 897 → +62 теста) |
| Покрытие | `fvm dart run tool/coverage_check.dart --min=80` | **93.6% (5788/6181)**, порог 80 пройден |
| Покрытие новых файлов | тот же отчёт | `feed_swipe` 100%, `feed_progress_bar` 100%, `review_chrome` 100%, `feed_card_view` 99.3%, `feed_session_screen` 96.4%, `feed_session_engine` 95.8% |
| Анализатор | `fvm flutter analyze` | **No issues found!** |
| Формат | `fvm dart format --set-exit-if-changed lib test` | **229 files, 0 changed** |
| Windows-сборка | `fvm flutter build windows --release` | **`√ Built build\windows\x64\runner\Release\cardflow.exe`** (51,9 s) |
| Ревью | `journal/iteration-4/review.md` | H1 + M1–M4 закрыты fix-коммитом `1857589` с новыми тестами; открытых H/M нет |

## Критерии приёмки итерации

| # | Критерий | Статус | Доказательство |
|---|---|---|---|
| C1 | Вертикальный `PageView.builder`, свайп вверх/вниз — навигация, без записи | **выполнено** | widget-тест «вертикальный свайп листает без оценки»; engine-тест `visit` |
| C2 | Тап раскрывает/скрывает ответ; раскрытие — `selectionClick` | **выполнено** | widget-тест «тап раскрывает и скрывает ответ»; haptics-тест |
| C3 | Свайпы вправо/влево, долгие >60% | **выполнено** | 12 unit-тестов политики; widget-тесты fling/долгих свайпов |
| C4 | Порог 80 px + скорость; spring-back | **выполнено** | unit-границы 80/300/60%; widget-тест «короткий медленный свайп возвращает карточку пружиной» |
| C5 | Stories: заполнение, пульсация, семантика | **выполнено** | widget-тесты «Stories…» и «семантическая подпись прогресса» |
| C6 | Авто-продвижение 3/5/8, пауза, без оценки | **выполнено** | widget-тесты авто-продвижения 3 с, паузы/возобновления, «фон останавливает», «Почему? останавливает» |
| C7 | Нижняя панель: колода, счётчик, «Пауза», выбор интервала | **выполнено** | widget-тест каркаса + меню 3 с; клавиатура Space/1–4 — тест |
| C8 | Haptics по A7.2 и `mediumImpact` завершения | **выполнено** | widget-тест haptics-канала: selectionClick/light/heavy/light/medium |
| C9 | Форма 28→16→pill, токены `AppMotion` | **выполнено** | widget-тест радиуса 28→<28 при drag→28 после spring; пилл при commit (радиус 999) |
| C10 | `review_logs.mode='feed'`, одна оценка, undo | **выполнено** | engine-тесты + integration на in-memory drift (`mode=feed`, undo восстанавливает `fsrs_json`/`due`) |
| C11 | Завершение по всем оценённым, пустая очередь | **выполнено** | engine- и widget-тесты завершения/пустой очереди |
| C12 | Лист режимов и production-маршрут | **выполнено** | widget-тесты «лист режимов содержит „Ленту“» и `CardFlowApp(router: createAppRouter('/decks/deck-1/feed'))` |
| C13 | Только ARB/ru, без сырых ошибок; ошибка БД | **выполнено** | widget-тесты ошибок, guard `ru_strings` в полном прогоне; `no_secrets` |
| C14 | Полный прогон/analyze/format/покрытие/Windows | **выполнено** | таблица выше |
| C15 | Ревью: H/M закрыты fix-коммитом с тестами | **выполнено (L35)** | `review.md`, `1857589`; независимый reviewer недоступен — Lead, L35 |
| C16 | Документация: ADR-016, STATE, AGENTS, KNOWN_LIMITATIONS, summary | **выполнено** | ADR-016 + addendum, `summary.md`, `STATE.md`, `AGENTS.md`, `KNOWN_LIMITATIONS.md` |

## Критерии остановки MVP, затронутые итерацией

- **Функциональность (п.2):** классика, лента — приёмочные widget/unit/integration-тесты; occlusion,
  cloze/LaTeX, конструктор — будущие итерации, не мёртвые кнопки (режимы не отрисованы).
- **Дизайн (п.6):** токены темы, пружины `AppMotion`, haptics по A7.2; dynamic color — итерация 7 (L6c).
- **Качество (п.7):** покрытие 93.6%, analyze 0, ревью без открытых blocker/critical/high.

## Не проверено и почему

- ~~**CI-прогон итерации 4** — push не выполнялся~~ **снято 2026-11-14:** push выполнен
  (`origin/main = e90f660`), прогоны [`43587472135`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43587472135)
  и [`43588247850`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43588247850) — оба **9/9 job success**.
- **Реальный свайп/жест на устройстве или мышью** — widget-тесты отправляют pointer events; ручного
  прогона на платформе нет (L37, по аналогии с L33).
- **Авто-продвижение при открытом другом маршруте поверх ленты** — таймер не останавливается; оценок
  нет, данные не теряются (L36).
- **Golden/скриншоты ленты (форма/pill/пульсация)** — golden нет, L6 (Linux CI, итерация 7).
- **Полный screen-reader проход** — семантика прогресса/карточки/подсказки есть, ручной VoiceOver/
  TalkBack не делался (L12, итерация 7).
- **Живые OpenAI/Gemini/Anthropic** — не относятся к ленте; L1/L30 без изменений.
