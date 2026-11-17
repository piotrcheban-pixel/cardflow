# Итерация cleanup-1 — «Зачистка и подготовка» (2026-11-18)

**Решение владельца:** дизайн-система «Nocturne» провалилась. Новые макеты
сделаны в Google Stitch; нужен чистый, быстрый UI на стандартном Material 3.
Задача итерации: полностью удалить наследие Nocturne, починить критический
баг «Создать колоду», вернуть экраны к простым Material-виджетам.

**ADR:** [ADR-036](../../docs/decisions/ADR-036-material3-clean-ui.md) отменяет
ADR-035.

## Факты старта

`git status --porcelain` → пусто, `HEAD = 4ca8e00`
(`docs(redesign): stage-3 verify report, state and limitations`), локально на
**43 коммита впереди** `origin/main = 8e9db8a` (push этапов 1–3 не уходил).
Baseline — 2121 passed + 8 skipped (этап 3 Nocturne). Прогоны — с `--no-pub`
(L64).

## Критический дефект: «Создать колоду» → белый экран

### Воспроизведение (красная фаза)

Тест открывает **production-проводку** (`CardFlowApp` + `createAppRouter`, то
есть настоящую оболочку `StatefulShellRoute`), жмёт FAB «Создать колоду» и
закрывает диалог:

```text
Expected: exactly one matching candidate
  Actual: _TypeWidgetFinder:<Found 0 widgets with type "DecksScreen": []>
  Экран «Мои колоды» не должен исчезать при закрытии диалога
```

Первопричина из стека исключения:

```text
You have popped the last page off of the stack, there are no pages left to show
'package:go_router/src/delegate.dart': Failed assertion: line 178 pos 7
#5 _CustomNavigatorState._handlePopPage
#6 NavigatorState.pop
#7 _showDeckNameDialog.<anonymous closure> (lib/ui/decks/deck_actions.dart:209)
```

### Диагноз

`DecksScreen` живёт в ветке `StatefulShellRoute` — у ветки **свой навигатор**.
`showNcDialog` (Nocturne) собирал `actions` во внешнем `BuildContext` экрана,
поэтому `Navigator.of(context).pop()` из кнопки диалога выталкивал из стека
**экран**, а не маршрут диалога:

1. ветка остаётся без страниц → под диалогом пусто (белый экран);
2. фьючер `showDialog` не завершается → колода не создаётся, кнопка «мертва»;
3. `!debugLocked`-ассерт на финализации дерева — добивает кадр.

Тот же шаблон был у диалогов удаления/импорта/провайдеров на экранах-ветках
(`/`, `/statistics`, `/settings`). Экран колоды (`/decks/:id` — корневой
маршрут) страдал меньше: там `Navigator.of(context)` случайно попадал в
корневой навигатор.

### Почему не поймали тесты

Виджет-тесты этапа 3 поднимали изолированный экран или роутер **без**
оболочки — один навигатор, дефект невоспроизводим. Ни один тест не открывал
диалог на `StatefulShellRoute`. Это ровно урок M5 (ретроспектива итерации 1):
фикс проверяется на production-проводке.

### Исправление

Возврат диалога к самодостаточному `StatefulWidget` (`_DeckNameDialog`),
который закрывает себя из **своего** `context` (маршрут диалога в корневом
навигаторе). Проверены все 12 мест `showDialog` в `lib/`: каждое либо передаёт
`dialogContext`, либо открывает диалог-виджет с собственным состоянием.

### Ограждение

`test/widget/decks/create_deck_dialog_test.dart` — три случая на
`CardFlowApp` + `createAppRouter`:

1. диалог открывается, «Отмена» закрывает его, «Мои колоды» остаются;
2. ввод имени создаёт колоду (`createdNames == ['ТОЭ']`, имя обрезано) и
   закрывает диалог;
3. пустое имя: ошибка `deckNameEmptyError`, диалог открыт, колода не создана.

## Что удалено

`git diff --stat 7458346..HEAD` до зачистки: **657 добавленных файлов**, из них
**511 — Nocturne** (остальные 146 — журналы этапов). Удалено:

| Группа | Файлов |
|---|---|
| `lib/ui/design/**` (токены, 37 компонентов, ambient, transitions, motion scope, haptics, лицензии шрифтов) | 56 |
| `test/golden/**` (эталоны компонентов и экранов, PNG) | 346 |
| `tool/screenshots/**` + `tool/extract_ui_keys.dart` | 51 |
| `test/widget/design/**`, `test/widget/redesign/**` | 18 |
| `test/unit/ui/design/**`, `test/unit/ui/motion_nocturne_test.dart`, `app_theme_nocturne_test.dart` | 10 |
| `test/guards/{design_tokens,haptics,no_network_fonts,ui_key_contract,legacy_material_guard}_test.dart` + фикстуры | 8 |
| `test/helpers/{nc_golden,nc_harness,nc_screen_harness,glass_budget,redesign_screen_fixtures,wcag,katex_fonts}.dart` | 7 |
| `assets/fonts/{Onest,Literata,JetBrainsMono}` + 3 OFL + `assets/textures/grain.png` | 7 |
| пакет документации `redesign/` (spec, plan, prompts) | 6 |

Плюс восстановлены из `7458346` 46 файлов: экраны этапа 3, оболочка, тема,
`app.dart`, `main.dart`, ARB (88 строк Nocturne-строк), `pubspec.yaml`
(шрифты, `material_color_utilities`, `cupertino_ui`), `pubspec.lock`,
`.gitignore`, `docs/dependencies.md`, зависимые тесты.

Ни одна строка `lib/{domain,data,api}` не изменилась: продуктовый код, схема
БД и `format_version` не затронуты.

## Что стало вместо

- Тема — `lib/ui/theme/app_theme.dart`: `ColorScheme.fromSeed` +
  `ThemeData(useMaterial3: true)`, акцент **Indigo `#4F46E5`**
  (`AppTheme.seedColor`), без стекла, градиентов, `rim light` и ThemeExtension.
- Экраны — простые Material/M3E-виджеты (`Scaffold`, `AppBar`, `ListTile`,
  `Card`, `TextField`, `NavigationBar`/`NavigationRail`).
- Фон статичен: кадры рисуются только по событиям (скролл, переходы, диалоги).

## Историческое наследие

Журналы `journal/redesign-1..3/` (146 файлов, 29,3 МБ) и ADR-035 **сохранены**
как запись о закрытом направлении: `git rm` не уменьшает размер репозитория
(история остаётся), а удаление журнала уничтожило бы причины решения. В
ADR-035 проставлен статус «отменён».

## Ограничения

См. `journal/KNOWN_LIMITATIONS.md` (новая секция итерации cleanup-1, L111–L114).

## Гейты и выкладка

| Гейт | Результат |
|---|---|
| `fvm flutter test --no-pub --coverage --exclude-tags golden` | **1775 passed + 8 skipped** |
| покрытие `tool/coverage_check.dart --min=80` | **92.5 % (12948/13996)** |
| `fvm flutter analyze --no-pub` | **No issues found!** |
| `fvm dart format --set-exit-if-changed lib test integration_test tool` | **438 / 0 changed** |
| `fvm flutter build windows --release --no-pub` | `cardflow.exe` (65,2 с) |
| `integration_test/session_smoke_windows_test.dart -d windows --no-pub` | **All tests passed!** (10 с) |

**Коммиты (5):** `ac3f109` удаление Nocturne + возврат экранов, `6de6eca`
Indigo-сид, `493f732` тест диалога на production-проводке, `500c9aa` шаг
диалога в Windows-смоуке, `ae9227a` ADR-036/STATE/journal/limitations.

**Push:** `8e9db8a..ae9227a` (44 коммита). **CI:**
[`44184233645`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44184233645)
— **9/9 job success**.
