# Итерация 2 — fix-итерация по findings ревью (шаг 4a)

**Дата:** 2026-11-13 · **Вход:** `journal/iteration-2/review.md` (blocker 0 / critical 0 / **high 1** / medium 3 / low 14; security high/critical 0).
**Правило AGENTS.md (ретро итерации 1):** каждый фикс слоя подтверждается тестом, а фикс, меняющий поведение на стыке слоёв, — интеграционным тестом на production-проводке.

## Итог: blocker/critical/high = 0, medium = 0

| ID | Что сделано | Доказательство |
|---|---|---|
| **H1** (high) | `_prepareImport` теперь валидирует `fsrs_json` как `SchedulingCard` и **перепривязывает `cardId` к новому id** карточки; `state`/`due` берутся из снимка FSRS (колонки архива информативны). Битый снимок → `ArchiveException(invalidCards)` (история не теряется молча); `fsrs = null` → инвариант A5 (`state = new`, `due = null`). Поведение контракта описано в `docs/archive-format.md` §Импорт п.5 и ADR-009 addendum | unit: `deck_transfer_service_test.dart` — «H1: fsrs перепривязывается к новому id карточки», «H1: невалидный fsrs → invalidCards, транзакция откатывается», «H1: fsrs = null нормализует state/due»; integration: `review_session_flow_test.dart` — «H1: оценка → export → import → сессия импортированной колоды работает» (production-провайдеры: export → import → `ReviewQueue` → `ReviewSessionEngine.start()` → `rate()` → новый `review_logs`) |
| **M1** (medium, C6) | Тесты атомарности, падающие **после** первой записи транзакции: триггер `RAISE(ABORT)` на `INSERT review_logs` (UPDATE карточки откатывается) и отсутствующая карточка при undo (удаление лога откатывается) | `review_repository_test.dart` — «атомарность: ошибка вставки лога откатывает UPDATE карточки (C6)», «атомарность: ошибка восстановления карточки откатывает undo» |
| **M2** (medium) | Единая точка выхода: `PopScope(canPop: false)` ведёт системный back в тот же диалог; back-стрелка AppBar скрыта (`automaticallyImplyLeading: false`) | widget: «системный back открывает диалог выхода (M2)» (дерево `колода → сессия`); ADR-008 addendum |
| **M3** (medium) | Haptics A4.4: `selectionClick` при раскрытии ответа (тап/Space, однократно), `mediumImpact` при завершении сессии; haptics оценок — только после успешной записи | widget: «haptics A4.4/A7.2: reveal, 4 оценки и завершение — через канал» — перехват `SystemChannels.platform` проверяет точную последовательность `selectionClick → heavyImpact → lightImpact → lightImpact → selectionClick → mediumImpact` |
| L1 | `applyOutcome` больше не мёртвый код: `DriftReviewRepository.recordReview` пишет карточку через единый маппер | data-тесты репозитория зелёные; поведение полей лога не изменилось |
| L2 | Навигационный тест на **production-роутере** (`CardFlowApp`/`createAppRouter`): колода → «Начать сессию» → режим → сессия | `app_test.dart` — «production-роутер: колода → «Начать сессию» → классическая сессия (L2)» |
| L3 | Фейк `FakeCardRepository.updateCard` пересчитывает `contentHash` как боевой репозиторий | код фейка; widget-тесты формы зелёные |
| L4 | Дополнены widget-тесты: цвета ролей A7.2 и значение `LinearProgressIndicator`; клавиши 1/2/4 (расширен тест клавиатуры — все 1–4); haptic-канал (M3). Не asserted: визуальная трансформация 3D-flip и busy-состояние (busy покрыт unit-тестами движка) | `review_session_screen_test.dart` |
| L5 | Косметика A4.2/A4.3: обратная сторона — `bodyLarge` с увеличенным межстрочным (вместо `headlineSmall`); кнопки оценок — pill (`StadiumBorder`). **Neighbor-squish** не реализован — зафиксирован L18 | код; widget-тесты проходят |
| L6 | «Почему?» неактивна при пустом/пробельном `source_excerpt` | widget: ««Почему?» неактивна при пустой цитате (L6)» |
| L7 | Валидация на границе data-слоя: `createCards/updateCard` отвергают некорректный черновик (`ArgumentError`), правила — по-прежнему `CardDraft.validate()` | `card_crud_test.dart` — «валидация на границе data-слоя» (create/update) |
| L8 | Уточнён `KNOWN_LIMITATIONS` L10: счётчик due устаревает и после возврата из сессии (push не пересоздаёт экран) | KNOWN_LIMITATIONS L10 |
| L9 | Зафиксировано L19: сводка «Новые» включает suspended/buried, очередь — нет; согласование — итерация 6 | KNOWN_LIMITATIONS L19 |
| L10 | Форма: ошибка поля сбрасывается при правке; кнопка удаления недоступна во время сохранения; haptic оценки — после успешной записи | код формы/экрана; widget-тесты зелёные |
| L11 | `_disposed` в движке покрыт тестом: завершение записи после dispose не дёргает слушателей | `review_session_engine_test.dart` — «dispose во время записи не дёргает notifyListeners (L11)» |
| L12 | Red-журнал T1 уточнён (`fromWireName → fromWire`, `FormatException` вместо `ArgumentError`); артефакты T17/ADR/probe вошли в коммиты | `red-domain.md`; git |
| L13 | ADR-009: зафиксировано осознанное отступление «теги >3 — ошибка, а не молчаливое обрезание» | ADR-009 addendum |
| L14 | ADR-008: зафиксировано «оценка до раскрытия ответа разрешена осознанно» | ADR-008 addendum |

## Изменение поведения по сравнению с коммитами зелёной фазы (осознанно, по ревью)

- Импорт `.zip`: `fsrs_json` больше не копируется «как есть» — валидируется и перепривязывается к новому id; битый → `invalidCards`; `fsrs = null` нормализует `state`/`due`. Формат v1 не менялся (структура та же), меняется строгость/корректность импорта; фикстуры roundtrip-тестов переведены на валидный FSRS-снимок, сравнение — по распарсенному снимку без `cardId` (H1).
- Выход из сессии: системный back и кнопка в AppBar проходят диалог (M2).
- Haптики A4.4 (M3); haptic оценки перенесён после записи (L10).

## Что не исправлено и почему

- **L4-остатки:** визуальная трансформация 3D-flip assert'ом не проверяется (виджет-тест проверяет смену текста; трансформация — визуальная проверка итерации 7/golden).
- **L5 neighbor-squish** — требует групповой анимации кнопок; вынесено в L18 (итерация 7).
- **L8/L9** — pre-existing/согласование семантики счётчиков вынесено в L10/L19 (итерация 6).
