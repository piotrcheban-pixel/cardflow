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
| 3.1 | Оболочка `shell/app_shell.dart`, `design/components/nc_nav.dart` | `aaa3ec1`, `5f944a2` | `делается` | `shell-*` (6) |
| 3.2 | «Мои колоды» `decks/decks_screen.dart`, `decks/deck_actions.dart` | — | — | — |
| 3.3 | Экран колоды `decks/deck_screen.dart` | — | — | — |
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
