# Редизайн «Nocturne» — этап 3 «Каталог: оболочка и экраны управления»

**Дата:** 2026-11-17 · **Режим:** ИТЕРАЦИИ (автономно) · **Старт:** `4b4cc21`
(`docs(redesign): fix component/primitive counts in stage-2 journal`), рабочее
дерево чистое; `HEAD` на 15 коммитов впереди `origin/main = 8e9db8a` (push
этапа 2 не ушёл в remote — выполняется в конце этой итерации по команде
владельца).
**Окружение:** Windows 11, FVM 4.3.2, Flutter 3.47.9 / Dart 3.13.7 (L2: нет
Android SDK/JDK/Xcode) — локально `test/analyze/format/golden`, `build windows`.

## Цель

Перевести на компоненты `Nc*` экраны REDESIGN-SPEC §9.1–9.4, 9.14–9.17 и
стили контента карточек (§9.20). Один экран — один шаг: red (тесты) → green →
скриншоты. Логика заморожена: обработчики и провайдеры вызываются теми же
методами с теми же аргументами; меняется только дерево `build`.

## Шаги

| Шаг | Экран / файлы | Red | Green | Скриншоты |
|---|---|---|---|---|
| 3.1 | Оболочка `shell/app_shell.dart`, `design/components/nc_nav.dart` | `aaa3ec1`, `e3d4acb` | `9672704` | `shell-*` (6) |
| 3.2 | «Мои колоды» `decks/decks_screen.dart`, `decks/deck_actions.dart` | `e4fc69e` | `266ca6a` | `decks-*` (6) |
| 3.3 | Экран колоды `decks/deck_screen.dart` | `b335ac2` | — | `deck-*` (6) |
| 3.4 | Форма карточки `cards/card_form_screen.dart`, `cards/occlusion_mask_editor.dart`, стили `cards/content/*` | — | — | — |
| 3.5 | Конструктор `session/session_constructor_screen.dart` | — | — | — |
| 3.6 | Статистика `statistics/statistics_screen.dart`, `statistics_charts.dart` | — | — | — |
| 3.7 | Настройки `settings/settings_screen.dart` | — | — | — |
| 3.8 | Провайдеры `settings/generation_settings_screen.dart`, `provider_account_dialogs.dart`, `provider_labels.dart` | — | — | — |
| 3.9 | Verify | — | — | — |

### 3.1 Оболочка — обработчики (до правки → после)

| Действие | До | После |
|---|---|---|
| Тап «Колоды»/«Статистика»/«Настройки» | `NavigationBar`/`NavigationRail.onDestinationSelected` → `_goBranch(index)` → `navigationShell.goBranch(index, initialLocation: index == currentIndex)` | `NcNavDock`/`NcNavRail`/`NcNavSidebar.onSelected` → `_handleSelected(index)` (сброс утопления дока) → тот же `_goBranch`; отклик `selectionClick` даёт `NcTappable` пункта |
| Повторный тап по активной вкладке | `initialLocation: true` | без изменений |
| Прокрутка контента | — | док утапливается на 8 px / 85 % при `ScrollUpdateNotification` вниз, возвращается вверх (`AppMotion.fast`) |

Ключи: `shell-nav-decks`, `shell-nav-statistics`, `shell-nav-settings`
(контракт §9.1), внутренние `nc-nav-capsule`, `nc-nav-logo`. `railBreakpoint`
= 600 сохранён, добавлен `wideBreakpoint` = 1024. Подсказка «⌘K / Ctrl+K —
быстрый переход» **не показана**: функция появляется на этапе 5, подсказка
была бы мёртвой (§«нет мёртвых функций»).

### 3.2 «Мои колоды» — обработчики (до правки → после)

| Действие | До | После |
|---|---|---|
| Поиск | `IconButton` → `decksSearchVisibleProvider.toggle()` / `clearSearch` + `close`; `TextField.onChanged` → `setSearch`; очистка → `clearSearch` | `NcIconButton` (тот же тумблер) → `NcSearchField.onChanged` (пусто → `clearSearch`, иначе `setSearch`), кнопка очистки → тот же `clearSearch` |
| Фильтр | `IconButton` → `decksFiltersVisibleProvider.toggle`; чипы `M3EChip` → `setFilter` | `NcIconButton` → тот же тумблер; `NcChip.filter` → `setFilter` (точка `aurum` при фильтре ≠ «Все») |
| Настройки | `IconButton` → `context.go(settingsPath)` | `NcIconButton` (ключ `decks-settings-action`) → тот же `context.go` |
| Создать вручную | split `onPressed` / пункт «Вручную» → `createDeckManually`; FAB → `createDeckManually` | `NcSplitButton.onPressed` / `NcMenuItem.onSelected` / `NcFab` → те же вызовы |
| Сгенерировать | пункт меню → `context.push(AppRoutes.generationPath)` | тот же `NcMenuItem` (ключ `decks-create-generate`) |
| Импорт | пункт меню → `importDeckZip` | тот же пункт → тот же вызов |
| Открыть колоду | `M3ECard.onPressed` → `context.push('/decks/<id>')` | `NcCardTile.onTap` → тот же push |
| Контекстное меню | `showModalBottomSheet` + `ListTile` → `_DeckMenuAction` | `showNcSheet` + `NcListRow` → тот же enum и ветки `_showContextMenu` |
| Архив свайпом | `Dismissible.onDismissed` → `_archiveDeck` | тот же `_archiveDeck`; порог → `NcHaptics.lightImpact()` (✋ `lightImpact`) |
| Удаление | `AlertDialog` → `deleteDeckWithConfirmation` | `NcDialog` + ключи `delete-deck-confirm/cancel`, тот же результат `bool` |
| Имя колоды | `AlertDialog` + `TextField` → `_showDeckNameDialog` | `NcDialog` + `NcTextField` + ключ `deck-name-submit`, Enter = отправка |
| Предпросмотр импорта | `AlertDialog` → `_showImportPreviewDialog` | `NcDialog` с теми же строками и ключами `import-confirm/cancel` |

Сводка шапки — UI-вычисление по загруженным `deckSummariesProvider`
(сумма `dueCards` и число колод), новой логики нет. Аватар —
`NcIcon3D('deck_gem_<FNV-1a(id) % 8 + 1>')` в `Hero('deck-avatar-<id>')`,
название — `Hero('deck-title-<id>')`. `Dismissible` с `deck-card-<id>`
остаётся внешним виджетом. Плитка — 92 px на телефоне (88 в спецификации не
вмещают 2 строки `titleM` + `bodyS` при padding 14; отклонение 4 px
зафиксировано), 168 px на 2–3 колонках. Общий `NcSplitButton` получил
`Flexible` для подписи (иначе 2,2 px overflow при textScale 2,0).

### 3.3 Экран колоды — обработчики (до правки → после)

| Действие | До | После |
|---|---|---|
| Назад | `AppBar` (авто) → `Navigator.pop` | `NcIconButton.glass` → `context.canPop()` → `context.pop()` |
| Меню ⋯ | `PopupMenuButton.onSelected` → `_handleMenuAction` | `showNcMenu` с той же ветвью `_handleMenuAction` (generate/rename/export/delete) |
| «Начать сессию» | `M3ECard.onPressed` → `_startSession` | `NcSurface.onTap` (✋ selectionClick `NcTappable`) → тот же `_startSession` |
| Лист режимов | `showModalBottomSheet` + `ListTile` → `_SessionModeAction` | `showNcSheet` + сетка плиток (ключи `review-mode-*`) → тот же enum и те же переходы |
| Лимит дня | `AlertDialog` + кнопки → `_LimitChoice` | `NcDialog` (`hourglass_time`) + ключи `review-limit-*`, тот же `_LimitChoice` |
| Карточка | `ListTile` → `_openCardForm(cardId)` | `NcListRow` + `CardText` + точка состояния → тот же вызов |
| Добавить | `FloatingActionButton.small` → `_openCardForm` | `NcSurface`-круг 48 в парящем стеклянном тулбаре → тот же вызов |
| Сгенерировать | `IconButton.deck-generate-action` → `context.push(deckGenerationPath)` | тот же ключ в тулбаре → тот же push |
| Пусто | текст + подсказка | `NcEmptyState` (`empty_cards`) с «Добавить карточку»/«Сгенерировать» |
| Ошибка / не найдено | `Column` + `TextButton` | `NcErrorState` / текст `deckNotFound` |

Отступления: миниатюра карточки 36 × 36 не показана — экран не грузит байты
`media` (это добавило бы новый запрос, а этап меняет только оформление); при
textScale > 1,3 стат-пилюли показывают только число с прежней семантикой
(`deckDueCount` и т. п.), иначе `NcBadge` переполнялся; CTA растёт вместе с
масштабом текста (120 × clamp(scale, 1, 1,8)). `NcTopBar` и стеклянный
`NcIconButton` теперь `grouped: true`: экран обёрнут `NcGlassGroup`, поэтому
шапка + тулбар = одна группа стекла (бюджет §4.4).

## Тестовая инфраструктура этапа

- `test/helpers/nc_screen_harness.dart` — производственная обвязка экрана:
  тема Nocturne, `NcMotionScope`, `NcHapticsScope` с рекордером,
  `NcAmbientBackground`, `M3ETheme`, `MediaQuery.textScaler`, размер окна,
  опциональный `GoRouter`, `pumpNcScreen`/`pumpNcScreenAtTextScale2`.
- `test/helpers/redesign_screen_fixtures.dart` — фейковые данные и экраны этапа.
- `test/guards/legacy_material_guard_test.dart` — guard миграции: в файлах
  этапа нет `AppBar/ListTile/SwitchListTile/FilledButton/SegmentedButton/
  Card/M3ECard/M3ESplitButton/M3EExtendedFab/CircularProgressIndicator`.
- `test/golden/redesign_screens_golden_test.dart` — golden dark+light экранов
  (тег `golden`), каталог `test/golden/goldens/screens/`.
- `tool/screenshots/redesign3_test.dart` — скриншоты журнала (2 темы ×
  390/800/1440).

## Обработчики экранов (инвентарь до правки)

Заполняется по шагам ниже (перед правкой экрана): что вызывается по каждой
кнопке — после правки вызывается то же и с теми же аргументами.

## Гейты (итог)

Заполняется в шаге 3.9.
