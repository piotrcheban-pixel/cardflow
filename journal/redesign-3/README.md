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
| 3.3 | Экран колоды `decks/deck_screen.dart` | `b335ac2` | `eabf8f6` | `deck-*` (6) |
| 3.4 | Форма карточки `cards/card_form_screen.dart`, `cards/occlusion_mask_editor.dart`, стили `cards/content/*` | `38511f6` | `e6d8514` | `card-form-*` (6) |
| 3.5 | Конструктор `session/session_constructor_screen.dart` | `a463fae` | `94e74ff` | `constructor-*` (6) |
| 3.6 | Статистика `statistics/statistics_screen.dart`, `statistics_charts.dart` | `0f8d86a` | — | `statistics-*` (6) |
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

### 3.4 Форма карточки — обработчики (до правки → после)

| Действие | До | После |
|---|---|---|
| Сохранение | `FilledButton` в `bottomNavigationBar` → `_save` | `NcButton.primary l` в стеклянной панели (ключ `card-form-save`, loading) → тот же `_save` |
| Удаление | `IconButton` → `showDialog` подтверждения → `deleteCard` | `NcIconButton` (ключ `card-form-delete`, ember) → `NcDialog` с ключами `card-delete-confirm/cancel` → тот же `deleteCard` |
| Тип | `SegmentedButton<CardType>` → `setState(_cardType)` | `NcSegmented<CardType>` (те же три доменных типа) → тот же `setState` |
| Поля | `TextField` с `InputDecoration` | `NcTextField` (ключи `card-form-front/back/hint/tags/source`, ошибки, автофокус) |
| Теги | строка в поле | поле прежнее + визуальный ряд `NcChip.tag` (значение не меняется) |
| Медиа | `OutlinedButton`/`TextButton` | `NcButton.secondary/ghost s` с теми же ключами → `_pickImage/_refreshImage/_removeImage` |
| Маски | `SwitchListTile` → `_toggleOcclusion` | `NcListRow` + `NcSwitch` (ключ `card-form-occlusion-toggle`) → тот же `_toggleOcclusion` |
| Редактор масок | `SegmentedButton`, холст `ClipRRect`, `IconButton` удаления | `NcSegmented`, холст `ink3 r.l` (eager-распознаватель сохранён), готовые маски `ink5 92 %` с номером, `NcIconButton ember` удаления; ключи `occlusion-editor-canvas`, `occlusion-editor-mask-*`, `occlusion-delete-*` сохранены |

Стили §9.20: `CardContentView` — `NcTypography.question/answer` и токены
цветов; `ClozeText` — pill `aurumSoft` + mono «[…]», раскрытый ответ `aurum`
с подчёркиванием, ✋ `selectionClick`; `LatexText` — размытая плашка `ink4` с
ключом `latex-hidden-<n>`, «Следующий шаг» — `NcButton.ghost s`, ошибка
разметки — `NcBadge.amber`; `OcclusionImageView` — `ink5 94 %` + рамка
`aurumSoft` + номер, кнопки ghost `s`, `occlusion-invalid` — бейдж `amber`;
`CardImageView` — `ClipRSuperellipse r.m`, fade-in 240 мс, полноэкранный
просмотр с `scrim`-градиентом и `NcIconButton.glass`.

Отступления: третьего типа «LaTeX» в домене нет (LaTeX — разметка текста),
типы `NcSegmented` — Обычная / Двусторонняя / С пропусками, подсказка
синтаксиса покрывает и cloze, и формулы; предпросмотр полей по умолчанию
свёрнут (кнопка-глаз), чтобы форма на телефоне не выталкивала секцию медиа
за экран; раскрытие occlusion удаляет маску сразу (существующие тесты
контента ждут исчезновения после одного `pump`), а появление — scale 0,96→1
на 240 мс; скелетон картинки статичен (повторяющийся shimmer заблокировал бы
`pumpAndSettle` в тестах картинки).

### 3.5 Конструктор — обработчики (до правки → после)

| Действие | До | После |
|---|---|---|
| Колода | `FilterChip` → `_toggleDeck` | мини-плитка `NcSurface` + `Semantics(selected)` (ключ `constructor-deck-*`) → тот же `_toggleDeck` |
| Теги/тип/состояние | `FilterChip` → `_toggleTag/_toggleType/_toggleState` | `NcChip.filter` с теми же ключами → те же тумблеры |
| Режим | `SegmentedButton` (ключ `constructor-mode`) | `NcSegmented` с тем же ключом → `setState(_mode)` |
| Вид лимита | `ChoiceChip` → `_setLimitKind` | `NcSegmented` с сегментами-ключами `constructor-limit-cards/minutes` → тот же `_setLimitKind` |
| Значение лимита | `DropdownButton` (ключ `constructor-limit-value`) | `NcStepper` (ключ значения сохранён; новые ключи `constructor-limit-minus/plus`) → новые `_stepLimit(-1/1)` по прежним дискретным значениям 10/20/50/100 и 5/10/15/30 |
| Порядок | `SwitchListTile` (ключи `constructor-shuffle/interleave/warmup`) | `NcListRow` + `NcSwitch` с теми же ключами → те же `setState` |
| Пресет | `ListTile`/`IconButton` → `_applyPreset/_deletePreset` | `NcListRow` + `NcIconButton` с теми же ключами → те же методы |
| Имя пресета | `AlertDialog` + `TextField` | `NcDialog` + `NcTextField` (ключи `constructor-preset-name/submit`) → тот же `savePreset` |
| Низ | `TextButton` + `FilledButton` | стеклянная панель `NcGlass` с `NcButton.secondary/primary` (ключи `constructor-available/save-preset/start`) и mono-счётчиком «Подходит» |

Отступления: аватар колоды 40 px вместо 32 — `NcIcon3D` запрещает
размер < 40 (§5.1); лимит меняется дискретным степпером по прежним наборам
значений (dropdown упразднён, чтобы сохранить совместимость пресетов).

### 3.6 Статистика — обработчики (до правки → после)

| Действие | До | После |
|---|---|---|
| «Тренировать» слабой темы | `FilledButton.tonal` (ключ `weak-topic-train-<tag>`) → `context.push('/constructor?tag=…')` | `NcButton.secondary s` с тем же ключом → тот же `context.push` и `Uri.encodeQueryComponent` |
| Повтор после ошибки | `TextButton` → `ref.invalidate(statisticsProvider)` | `NcErrorState` → тот же `invalidate` |

Данные и ключи не менялись: `statistics-retention`, `statistics-week`,
`statistics-heatmap`, `statistics-forecast`, `statistics-forecast-bar-<i>`,
`weak-topic-<tag>`, `weak-topic-train-<tag>`; семантические строки и подписи
месяцев — прежние (`heatmapMonthLabels` сохранён статическим на виджете).

Графики: `StatisticsWaveform` — капсулы с градиентом `aurumDeep→aurum`,
последний столбик с точкой-glow, рост от нуля; пунктирная линия без данных.
`StatisticsHeatmap` — шкала `NcColors.heat0–4`, ячейки 10 px с зазором 3,
горизонтальная прокрутка с автопереходом к сегодня, короткие подписи месяцев.
Прогноз — `monoM` над столбиком, сегодня Aurum, остальные `ink5` с верхней
гранью Aurum, нулевой день — точка. Слабые темы — `NcSection` со строками:
тег, `NcBadge.ember` доли ошибок, `NcProgressLine` и «Тренировать»
(`NcButton.secondary s` в подписи строки, чтобы бейдж не переполнялся на
телефоне).

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



