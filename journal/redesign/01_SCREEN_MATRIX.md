# 01 — Матрица экранов и маршрутов

**Дата:** 2026-11-19 · Маршруты — `lib/ui/router/app_router.dart`.
Статусы: ✅ готово, 🟡 частично, ⏳ ожидает, ➖ не применимо.

| № | Экран | Маршрут | Файл | Визуальные требования | Провайдеры/данные | Тесты | Реализация | Визуальная проверка |
|---|---|---|---|---|---|---|---|---|
| 1 | Колоды | `/` | `ui/decks/decks_screen.dart` | `r2-decks-desktop.png`: шапка, 4 KPI, тулбар, сетка 3× | `deckSummariesProvider`, `allDeckSummariesProvider`, `decksQueryProvider`, `decksSortProvider`, `decksViewModeProvider` | `test/widget/decks/decks_screen_test.dart` | ✅ | ✅ `decks-1440.png`, `mobile-decks.png` |
| 2 | Колода | `/decks/:deckId` | `ui/decks/deck_screen.dart` | новая система: чипы, прогресс, запуск сессии, список | `deckProvider`, `deckCardsProvider`, `deckSummaryProvider`, `review_limits` | `test/widget/decks/deck_screen_test.dart` | ✅ | ✅ `deck-1440.png` |
| 3 | Классическая сессия | `/decks/:deckId/study` | `ui/review/review_session_screen.dart` | `r2-study-desktop.png`: полоса 56, карточка 640, 4 оценки | `cardRepositoryProvider`, `schedulerProvider`, `ReviewQueue`, `readRemainingReviewLimits` | `test/widget/review/review_session_screen_test.dart` | ✅ | ✅ `study-1440.png` |
| 4 | Лента | `/decks/:deckId/feed` | `ui/review/feed_session_screen.dart` | общий каркас сессии, Stories-прогресс | `FeedSessionEngine` | `test/widget/review/feed_session_screen_test.dart` | ✅ | ✅ (каркас общий) |
| 5 | Тренировка | `/decks/:deckId/practice` | `ui/review/practice_session_screen.dart` | общий каркас без прогноза интервалов | `PracticeRepository` | `test/widget/review/practice_session_screen_test.dart` | ✅ | ✅ (каркас общий) |
| 6 | Тест (варианты) | `/decks/:deckId/test` | `ui/study/multiple_choice_screen.dart` | общий каркас, `CardText` | `StudySessionController` | `test/widget/study/study_modes_test.dart` | ✅ | ✅ (каркас общий) |
| 7 | Ввод ответа | `/decks/:deckId/typing` | `ui/study/typing_screen.dart` | общий каркас | то же | `study_modes_test.dart`, `study_mode_latex_test.dart` | ✅ | ✅ (каркас общий) |
| 8 | Подбор пар | `/decks/:deckId/match` | `ui/study/match_screen.dart` | общий каркас, сетка пар | то же | `match_and_true_false_test.dart` | ✅ | ✅ (каркас общий) |
| 9 | Верно/Неверно | `/decks/:deckId/true-false` | `ui/study/true_false_screen.dart` | общий каркас | то же | `match_and_true_false_test.dart` | ✅ | ✅ (каркас общий) |
| 10 | Конструктор сессии | `/constructor` | `ui/session/session_constructor_screen.dart` | секции-панели, чипы, sticky-старт | `sessionPresetRepositoryProvider`, `leechRepositoryProvider` | `test/widget/session/session_constructor_screen_test.dart` | ✅ | ✅ (структура; снимок не снят) |
| 11 | Классика по плану | `/session/classic` | `ui/review/review_session_screen.dart` | как №3 | `SessionPlan` через `extra` | `review_session_screen_test.dart` | ✅ | ✅ (каркас общий) |
| 12 | Лента по плану | `/session/feed` | `ui/review/feed_session_screen.dart` | как №4 | `SessionPlan` | `feed_session_screen_test.dart` | ✅ | ✅ (каркас общий) |
| 13 | Генерация (новая колода) | `/generate` | `ui/generation/generation_screen.dart` | `r2-ai-desktop.png`: 3 секции, dropzone, sticky-запуск | `generationPipelineProvider`, `providerAccountsProvider`, файлы, ключи | `test/widget/generation/generation_screen_test.dart` | ✅ | ✅ `generation-1440.png` |
| 14 | Генерация в колоду | `/decks/:deckId/generate` | `ui/generation/generation_screen.dart` | как №13 (+ карточка колоды) | то же | `generation_entry_test.dart` | ✅ | ✅ (та же форма) |
| 15 | Предпросмотр генерации | в потоке `/generate` | `ui/generation/generation_preview_screen.dart` | панели/карточки дизайн-системы | `generationCardStoreProvider` | `generation_preview_screen_test.dart` | ✅ | ✅ (тесты + тема) |
| 16 | Создание карточки | `/decks/:deckId/cards/new` | `ui/cards/card_form_screen.dart` | поля/секции, sticky-сохранение | `cardRepositoryProvider`, `mediaStoreProvider` | `card_form_screen_test.dart` | ✅ | ✅ (тесты + тема) |
| 17 | Редактирование карточки | `/decks/:deckId/cards/:cardId/edit` | `ui/cards/card_form_screen.dart` | как №16 | то же | `card_form_screen_test.dart` | ✅ | ✅ |
| 18 | Статистика | `/statistics` | `ui/statistics/statistics_screen.dart` | `r1-stats-desktop.png`: KPI, карта, удержание, прогноз, темы | `statisticsProvider`, `effectiveAppSettingsProvider` | `test/widget/statistics_screen_test.dart` | ✅ | ✅ `statistics-1440.png` |
| 19 | Настройки | `/settings` | `ui/settings/settings_screen.dart` | `r2-settings-desktop.png`: поднавигация + секции | `appSettingsProvider`, `providerAccountsProvider`, `weeklyTokensProvider` | `test/widget/settings_screen_test.dart` | ✅ | ✅ `settings-1440.png`, `mobile-settings.png` |
| 20 | Провайдеры ИИ | `/settings/generation` | `ui/settings/generation_settings_screen.dart` | карточки аккаунтов, диалоги | `providerAccountsProvider`, `ApiKeyStore` | `test/widget/settings/generation_settings_screen_test.dart` | ✅ | ✅ (тесты + тема) |
| 21 | Оболочка | все ветки | `ui/shell/app_shell.dart`, `app_sidebar.dart`, `app_top_header.dart` | панель 240, шапка 56, Drawer <1024 | `totalDueCardsProvider`, навигация веток | `test/widget/shell_test.dart` | ✅ | ✅ `decks-1440.png`, `mobile-drawer.png` |
| 22 | Модальные окна/листы | — | `ui/components/app_dialogs.dart`, `deck_actions.dart`, `provider_account_dialogs.dart` | r16–20, шапка/футер, действия в контексте диалога | действия репозиториев | `create_deck_dialog_test.dart`, провайдеры | ✅ | ✅ (тема; выход из сессии на снимке) |
| 23 | Пустые/ошибки/загрузка | все | `ui/components/app_surfaces.dart` | иконка-бейдж, заголовок, пояснение, действия | — | все widget-тесты | ✅ | ➖ |

## Маршруты, не потерянные при редизайне

`/`, `/decks/:deckId`, `/decks/:deckId/study`, `/decks/:deckId/feed`,
`/decks/:deckId/practice`, `/decks/:deckId/test`, `/decks/:deckId/typing`,
`/decks/:deckId/match`, `/decks/:deckId/true-false`, `/constructor`,
`/session/classic`, `/session/feed`, `/decks/:deckId/generate`, `/generate`,
`/decks/:deckId/cards/new`, `/decks/:deckId/cards/:cardId/edit`,
`/statistics`, `/settings`, `/settings/generation` — **19 маршрутов**, все
сохранены; карта совпадает с `AppRoutes`.

## Что не изменилось

Схема БД (`schemaVersion`), `format_version`, домен, данные, API-адаптеры,
пайплайн генерации, FSRS-планировщик, парсеры, импорт/экспорт, провайдеры —
не менялись. Редизайн затронул `lib/ui/`, ARB, ассеты шрифта и документацию.
