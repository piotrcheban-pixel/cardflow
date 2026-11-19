# 01 — Матрица экранов и маршрутов

**Дата:** 2026-11-19 · Маршруты — `lib/ui/router/app_router.dart`.
Статусы: ✅ готово по дизайн-системе, 🟡 в работе, ⏳ ожидает, ➖ не применимо.

| № | Экран | Маршрут | Файл | Визуальные требования | Провайдеры/данные | Тесты | Реализация | Визуальная проверка |
|---|---|---|---|---|---|---|---|---|
| 1 | Колоды | `/` | `ui/decks/decks_screen.dart` | `r2-decks-desktop.png`: шапка + 4 KPI + тулбар + сетка 3× | `deckSummariesProvider`, `allDeckSummariesProvider`, `decksQueryProvider`, `decksSortProvider`, `decksViewModeProvider` | `test/widget/decks/decks_screen_test.dart` | 🟡 | 🟡 |
| 2 | Колода | `/decks/:deckId` | `ui/decks/deck_screen.dart` | новая система: шапка, KPI, режимы, список карточек | `deckProvider`, `deckCardsProvider`, `deckSummaryProvider`, `review_limits` | `test/widget/decks/deck_screen_test.dart` | 🟡 | ⏳ |
| 3 | Классическая сессия | `/decks/:deckId/study` | `ui/review/review_session_screen.dart` | `r2-study-desktop.png`: полоса сессии 896, карточка 640, 4 оценки | `cardRepositoryProvider`, `schedulerProvider`, `ReviewQueue`, `readRemainingReviewLimits` | `test/widget/review/review_session_screen_test.dart` | ⏳ | ⏳ |
| 4 | Лента | `/decks/:deckId/feed` | `ui/review/feed_session_screen.dart` | тот же каркас сессии | `FeedSessionEngine` | `test/widget/review/feed_session_screen_test.dart` | ⏳ | ⏳ |
| 5 | Тренировка | `/decks/:deckId/practice` | `ui/review/practice_session_screen.dart` | тот же каркас, без прогноза интервалов | `PracticeRepository` | `test/widget/review/practice_session_screen_test.dart` | ⏳ | ⏳ |
| 6 | Тест (варианты) | `/decks/:deckId/test` | `ui/study/multiple_choice_screen.dart` | новая система, `CardText` | `StudySessionController` | `test/widget/study/study_modes_test.dart` | ⏳ | ⏳ |
| 7 | Ввод ответа | `/decks/:deckId/typing` | `ui/study/typing_screen.dart` | новая система | то же | `study_modes_test.dart`, `study_mode_latex_test.dart` | ⏳ | ⏳ |
| 8 | Подбор пар | `/decks/:deckId/match` | `ui/study/match_screen.dart` | новая система | то же | `match_and_true_false_test.dart` | ⏳ | ⏳ |
| 9 | Верно/Неверно | `/decks/:deckId/true-false` | `ui/study/true_false_screen.dart` | новая система | то же | `match_and_true_false_test.dart` | ⏳ | ⏳ |
| 10 | Конструктор сессии | `/constructor` | `ui/session/session_constructor_screen.dart` | новая система: панели, чипы, лимиты | `sessionPresetRepositoryProvider`, `leechRepositoryProvider` | `test/widget/session/session_constructor_screen_test.dart` | ⏳ | ⏳ |
| 11 | Классика по плану | `/session/classic` | `ui/review/review_session_screen.dart` | как №3 | `SessionPlan` через `extra` | `review_session_screen_test.dart` | ⏳ | ⏳ |
| 12 | Лента по плану | `/session/feed` | `ui/review/feed_session_screen.dart` | как №4 | `SessionPlan` | `feed_session_screen_test.dart` | ⏳ | ⏳ |
| 13 | Генерация (новая колода) | `/generate` | `ui/generation/generation_screen.dart` | `r2-ai-desktop.png`: секции 1–3, dropzone, параметры | `generationPipelineProvider`, `providerAccountsProvider`, файлы, ключи | `test/widget/generation/generation_screen_test.dart` | ⏳ | ⏳ |
| 14 | Генерация в колоду | `/decks/:deckId/generate` | `ui/generation/generation_screen.dart` | как №13 | то же | `generation_entry_test.dart` | ⏳ | ⏳ |
| 15 | Предпросмотр генерации | в потоке `/generate` | `ui/generation/generation_preview_screen.dart` | новая система: карточки, пометки, импорт | `generationCardStoreProvider` | `generation_preview_screen_test.dart` | ⏳ | ⏳ |
| 16 | Создание карточки | `/decks/:deckId/cards/new` | `ui/cards/card_form_screen.dart` | новая система: поля, occl. редактор | `cardRepositoryProvider`, `mediaStoreProvider` | `card_form_screen_test.dart` | ⏳ | ⏳ |
| 17 | Редактирование карточки | `/decks/:deckId/cards/:cardId/edit` | `ui/cards/card_form_screen.dart` | как №16 | то же | `card_form_screen_test.dart` | ⏳ | ⏳ |
| 18 | Статистика | `/statistics` | `ui/statistics/statistics_screen.dart` | `r1-stats-desktop.png`: KPI, карта, неделя, слабые темы, прогноз | `statisticsProvider` | `test/widget/statistics_screen_test.dart` | ⏳ | ⏳ |
| 19 | Настройки | `/settings` | `ui/settings/settings_screen.dart` | `r2-settings-desktop.png`: поднавигация + секции | `appSettingsProvider`, `providerAccountsProvider`, `weeklyTokensProvider` | `test/widget/settings_screen_test.dart` | ⏳ | ⏳ |
| 20 | Провайдеры ИИ | `/settings/generation` | `ui/settings/generation_settings_screen.dart` | новая система: карточки аккаунтов, диалоги | `providerAccountsProvider`, `ApiKeyStore` | `test/widget/settings/generation_settings_screen_test.dart` | ⏳ | ⏳ |
| 21 | Оболочка | все ветки | `ui/shell/app_shell.dart`, `app_sidebar.dart`, `app_top_header.dart` | панель 240, шапка 56, Drawer <1024 | `totalDueCardsProvider`, навигация веток | `test/widget/shell_test.dart` | 🟡 | 🟡 |
| 22 | Модальные окна/листы | — | `ui/components/app_dialogs.dart`, `deck_actions.dart`, `provider_account_dialogs.dart` | `Modals.tsx`: 512–672, r16, шапка/футер | действия репозиториев | `create_deck_dialog_test.dart`, `provider_*` | ⏳ | ⏳ |
| 23 | Пустые/ошибки/загрузка | все | `ui/components/app_surfaces.dart` | иконка-бейдж, заголовок, пояснение, действия | — | все widget-тесты | 🟡 | ➖ |

## Маршруты, не потерянные при редизайне

`/`, `/decks/:deckId`, `/decks/:deckId/study`, `/decks/:deckId/feed`,
`/decks/:deckId/practice`, `/decks/:deckId/test`, `/decks/:deckId/typing`,
`/decks/:deckId/match`, `/decks/:deckId/true-false`, `/constructor`,
`/session/classic`, `/session/feed`, `/decks/:deckId/generate`, `/generate`,
`/decks/:deckId/cards/new`, `/decks/:deckId/cards/:cardId/edit`,
`/statistics`, `/settings`, `/settings/generation` — **19 маршрутов**, все
сохранены; карта совпадает с `AppRoutes`.
