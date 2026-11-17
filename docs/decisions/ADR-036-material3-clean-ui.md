# ADR-036 — Отказ от дизайн-системы «Nocturne»: возврат к Material 3 и Indigo-акценту

**Дата:** 2026-11-18 · **Итерация:** cleanup-1 («Зачистка и подготовка») ·
**Статус:** принято — **отменяет ADR-035**

## Контекст

ADR-035 заменил визуальный слой SPEC A4 на дизайн-систему «Nocturne»
(`redesign/REDESIGN-SPEC.md`): тёплый чёрный холст с анимированным фоном
«Aurora», слоновая кость вместо белого, шампанское золото (Aurum) как
единственный акцент, стекло (`BackdropFilter`) для хрома, `rim light` и
градиенты в кнопках/карточках, собственный слой токенов `NcTheme`.

Решение владельца (2026-11-18): **дизайн-система провалилась**. Претензии —
скорость и стабильность: анимированный фон и стекло дают постоянные кадры,
приложение «тормозит», а критический путь (создание колоды) вешает приложение
белым экраном. Макеты переделаны во внешнем инструменте (Google Stitch); нужен
чистый, быстрый UI на стандартном Material 3.

### Критический дефект, закрывший вопрос

Кнопка «Создать колоду» на экране «Мои колоды» → диалог имени → любая кнопка
диалога → **белый экран, приложение повисает**.

Корневая причина найдена на production-проводке (`CardFlowApp` +
`createAppRouter`), а не догадкой:

```text
You have popped the last page off of the stack, there are no pages left to show
'package:go_router/src/delegate.dart': Failed assertion: line 178 pos 7
#5 _CustomNavigatorState._handlePopPage
#6 NavigatorState.pop
#7 _showDeckNameDialog.<anonymous closure> (deck_actions.dart:209)
```

`DecksScreen` живёт в ветке `StatefulShellRoute`, у ветки **свой навигатор**.
`showDialog` по умолчанию кладёт маршрут в **корневой** навигатор
(`useRootNavigator: true`), а `showNcDialog` строил `actions` во внешнем
`BuildContext` экрана. Поэтому `Navigator.of(context).pop()` попадал в навигатор
ветки: экран «Мои колоды» выталкивался из стека (последняя страница), фон под
диалогом становился пустым (белый экран), фьючер `showDialog` не завершался
(кнопка «Создать» не создавала колоду), а `!debugLocked`-ассерт на финализации
дерева добивал кадр. Те же `actions` были у диалогов удаления, импорта,
провайдеров и настроек на экранах-ветках (`/statistics`, `/settings`).

Почему это не поймали тесты: виджет-тесты экранов поднимали изолированный
экран (`appWithHome`) или роутер **без** оболочки — там один навигатор, и
`Navigator.of(context)` случайно оказывался верным. Ни один тест не открывал
диалог на оболочке с `StatefulShellRoute`.

Ретроспектива 3b/1 и урок M5 прямо предупреждали: «фикс слоя обязан
подтверждаться интеграционным тестом на production-проводке».

## Решение

### 1. Визуальный слой — снова стандартный Material 3

- Единственная тема — `lib/ui/theme/app_theme.dart`: `ColorScheme.fromSeed` +
  `ThemeData(useMaterial3: true)`; никаких `ThemeExtension`-токенов, стекла,
  градиентов и `rim light`.
- Акцент — **Indigo `#4F46E5`** (`AppTheme.seedColor`): нейтральный синий,
  читается в светлой и тёмной схеме, динамический цвет платформы и
  повышенный контраст продолжают работать через `fromSeed`.
- Слой M3 Expressive `lib/ui/m3e/` (ADR-007) остаётся: он проецируется из
  Material-темы (`M3EThemeData.fromMaterial`) и Material-виджеты не подменяет.

### 2. Что удалено полностью (`lib/ui/design/**`, 57 файлов)

- `ambient/ambient_background.dart` — анимированный фон «Aurora» с зерном и
  его вызов в `app.dart`.
- `components/nc_glass.dart`, `tokens/nc_glass.dart`, все `NcGlassGroup` и
  `BackdropFilter` — стекло, зерно, `rim light`, `NcGlassMaterials`.
- `nc_theme.dart` и токены (`nc_colors`, `nc_typography`, `nc_spacing`,
  `nc_radii`, `nc_depth`) — коричнево-золотая палитра (Aurum) и шрифты
  Onest/Literata/JetBrains Mono вместе с ассетами (7 файлов, ~4 МБ) и
  регистрацией лицензий в `main.dart`.
- 37 компонентов `Nc*`, `motion_scope.dart`, `haptics.dart`,
  `transitions/nc_page_transitions.dart`, `font_licenses.dart`.
- Инфраструктура: `golden`-тесты Nocturne (346 PNG), скриншот-тулы
  (`tool/screenshots/`, `tool/extract_ui_keys.dart`), guard-тесты дизайн-системы
  (`design_tokens`, `haptics`, `no_network_fonts`, `ui_key_contract`,
  `legacy_material_guard`), пакет документации `redesign/`.
- Экраны этапа 3 («Мои колоды», колода, форма карточки, конструктор,
  статистика, настройки, провайдеры) и оболочка возвращены к версии до
  редизайна: простые Material/M3E-виджеты (`Scaffold`, `AppBar`, `ListTile`,
  `Card`, `TextField`, `NavigationBar`/`NavigationRail`).

Продуктовый код (домен, данные, API, парсеры, генерация, сессии, схема БД,
`format_version`) не менялся: ни одна строка `lib/{domain,data,api}` не
затронута — удаление коснулось только визуального слоя и его тестов.

### 3. Правило для диалогов (следствие дефекта)

Маршрутные действия диалога **обязаны** закрывать маршрут диалога, а не экран:

- либо `Navigator.of(dialogContext).pop(...)` внутри `builder:`,
- либо отдельный `StatefulWidget` диалога, который закрывает себя из
  собственного `context` (как `_DeckNameDialog`).

Список `actions`, собранный во внешнем `BuildContext` экрана, запрещён: на
экранах-ветках `StatefulShellRoute` он попадает в навигатор ветки. Ограждение —
`test/widget/decks/create_deck_dialog_test.dart` (открыть/закрыть/создать на
`CardFlowApp` + `createAppRouter`) — он падал на коде Nocturne с
`has popped the last page` и зелёный на текущем.

## Последствия

- Приложение снова стартует без непрерывной анимации фона: кадры рисуются
  только по событиям (`ListView`-скролл, переходы, диалоги).
- Визуальный слой — один файл темы; новые экраны берут виджеты у Material/M3E,
  а не у собственной библиотеки компонентов.
- Историческая часть редизайна сохранена в `journal/redesign-1..3/` (журнал,
  скриншоты, ретроспективы) и в ADR-035 со статусом «отменён» — это запись о
  том, **почему** направление закрыто, а не действующая спецификация.
- Журналы этапов 1–3 не удалены: решения и их причины не переписываются
  задним числом (правило AGENTS.md про ADR).
