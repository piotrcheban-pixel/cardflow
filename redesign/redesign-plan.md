# REDESIGN-PLAN.md — дорожная карта редизайна «Nocturne»

> Источник визуальных требований — `REDESIGN-SPEC.md`. Промпты для каждого этапа — `DSH-PROMPTS.md`.
> Процесс — как в `AGENTS.md`: plan → test → implement → review → verify → remember → improve. Отдельный коммит на каждый зелёный шаг (red / green / verify / docs). Журнал — `journal/redesign-N/`, состояние — `journal/STATE.md`.

## Принципы дорожной карты

1. **Приложение работает после каждого шага.** Ни один коммит не оставляет экран наполовину Material, наполовину Nocturne без сборки. Переход идёт сверху вниз: токены → тема (автоматически перекрашивает все Material-виджеты) → компоненты → экраны по одному.
2. **Логика заморожена.** Файлы из «Красной зоны» (ниже) не меняются ни на одном этапе. Внутри экранов не меняются тела обработчиков (`onPressed`, `_startSession`, `_rate`, `_save` и т. п.), провайдеры, `ref.watch/read`, вызовы роутера и аргументы движков. Меняется только дерево `build` и приватные виджеты оформления.
3. **Ключи — контракт.** Все существующие `ValueKey` (≈ 230 шт., см. `REDESIGN-SPEC.md §9`, отмечены 🔑) сохраняются. Перед этапом 1 замораживается снимок `test/guards/fixtures/ui_keys.txt`. Guard-тест падает, если ключ исчез из `lib/ui/`.
4. **Существующие тесты не ослабляются.** Если widget-тест искал `FilledButton`/`ListTile`/`AppBar` по типу, он переписывается на поиск по ключу или семантике **в отдельном red-коммите с обоснованием** в журнале. Число проверок при этом не уменьшается.
5. **TDD для визуального слоя:** сначала тест (unit на токены и контраст, widget на поведение и ключи, golden на облик), потом код. Golden-тесты помечены тегом `golden` и прогоняются на Linux CI, шрифты Onest/Literata/JetBrains Mono в тестах подгружаются явно (`FontLoader`).
6. **Каждый этап закрывается** полным прогоном `fvm flutter test --no-pub --coverage --exclude-tags golden`, отдельным прогоном golden на CI, `analyze` 0, `dart format --set-exit-if-changed lib test integration_test` 0, `build windows --release`, Windows-смоуком и скриншотами в `journal/redesign-N/screenshots/` (обе темы, телефон 390 × 844 и ПК 1440 × 900).

## Зоны файлов `lib/ui/`

| Зона | Файлы | Правило |
|---|---|---|
| 🔴 **Красная** (не трогать) | `state/app_providers.dart`, `state/decks_ui_providers.dart`, `state/review_limits.dart`, `router/app_router.dart`, `review/review_session_engine.dart`, `review/feed_session_engine.dart`, `review/practice_session_engine.dart`, `review/feed_swipe.dart`, `review/review_interval_format.dart`, `review/session_media.dart`, `study/study_session_controller.dart`, `generation/generation_error_message.dart`, `generation/generation_failure_message.dart`, `generation/parser_error_message.dart`, `decks/archive_error_message.dart`, `decks/deck_archive_file_name.dart`, `settings/external_link_launcher.dart`, `settings/about_links.dart`, `cards/content/latex_spans.dart` | Ни одной правки. Нужна правка — стоп, ADR и вопрос владельцу |
| 🟡 **Жёлтая** (только оформление) | `app.dart` (только `theme/darkTheme`, `builder`), `settings/provider_labels.dart` (только `providerProtocolIcon`), `decks/deck_actions.dart` (только виджеты диалогов, `showAppMessage` и `showArchivedUndoSnackbar` внутри — сигнатуры прежние), все `*_screen.dart` (дерево `build` и приватные виджеты, обработчики не меняются), `cards/content/*` кроме `latex_spans.dart` (стили) | Публичные API, сигнатуры, ключи и семантика сохраняются |
| 🟢 **Зелёная** (свободно) | `theme/app_theme.dart`, `motion.dart` (только расширение), новый `design/**`, `m3e/m3e.dart` (на этапе 5 — решение о выводе из использования), `assets/fonts/**`, `assets/icons3d/**`, `shaders/**`, `pubspec.yaml` (`assets`, `fonts`, `shaders`, проверенные зависимости), `lib/l10n/app_ru.arb` (новые строки), `docs/**`, `test/**` | Новые файлы и токены |

## Обзор этапов

| # | Этап | Результат для пользователя | Оценка |
|---|---|---|---|
| 1 | **Фундамент** | Приложение перекрашено в Nocturne целиком (через тему), новые шрифты, живой фон, переходы страниц | 1 итерация |
| 2 | **Компоненты** | Библиотека `Nc*` с golden-тестами. На экранах пока не видна, кроме тостов, диалогов и листов (подключаются глобально) | 1–1,5 итерации |
| 3 | **Каталог** | Оболочка-док, «Мои колоды», экран колоды, форма карточки, конструктор, статистика, настройки, провайдеры | 1,5 итерации |
| 4 | **Сессии** | Монолит, док оценок, лента, тренировка, Тест, Ввод, Пары, Верно/Неверно, итоги | 1,5 итерации |
| 5 | **AI-студия, 3D и полировка** | Генерация и предпросмотр, интеграция 3D-иконок ComfyUI, hero-переходы, `Ctrl/⌘+K`, аудит доступности и производительности, финальные goldens | 1–1,5 итерации |

Параллельно с этапами 1–4 владелец генерирует 3D-иконки в ComfyUI по `REDESIGN-SPEC.md §5`. До этапа 5 вместо них работает резерв `NcIcon3D`, поэтому этапы от иконок не зависят.

---

## Этап 1 — Фундамент

**Цель:** вся система токенов, тема и инфраструктура тестов. После этапа любой экран уже выглядит «по-ночному», хотя компоненты ещё Material.

Шаги:
1. **1.0 Спайк и ADR.** `docs/decisions/ADR-035-nocturne-design-system.md`: замена SPEC A4.1/A4.3/A4.5 для визуального слоя (hex только в токенах, оценки по шкале ember→glacier, dynamic color только для акцента, superellipse вместо M3E-форм, Nocturne поверх `material_ui`). Спайки: `BackdropGroup` + `BackdropFilter.grouped` на Windows/Android, `RoundedSuperellipseBorder` в закреплённой версии Flutter, `FragmentProgram` в `flutter test`, кириллица во всех трёх шрифтах (`journal/redesign-1/spikes.md`).
2. **1.1 Guard-тесты (red).** `ui_key_contract_test.dart` + снимок `fixtures/ui_keys.txt` (генерируется скриптом `tool/extract_ui_keys.dart` один раз до правок); `design_tokens_test.dart` (литералы цвета только в `nc_colors.dart`); `no_network_fonts_test.dart` (нет `google_fonts` в `pubspec.lock`); расширить `architecture_test.dart`: `design/` не импортирует `state/`, `router/`, `domain/`, `data/`, `api/`.
3. **1.2 Токены.** `nc_colors` (dark/light/high-contrast/dynamic-accent), `nc_typography`, `nc_spacing`, `nc_radii`, `nc_depth`, `nc_glass` + unit-тесты: значения, контраст WCAG по таблице пар, HCT-акцент из dynamic-схемы.
4. **1.3 Шрифты.** Ассеты Onest / Literata / JetBrains Mono + OFL + регистрация лицензий в `LicenseRegistry`. Тест применения: `ThemeData.textTheme.bodyLarge.fontFamily == 'Onest'`; при `dyslexiaFont` — OpenDyslexic во всех ролях, включая Literata-роли.
5. **1.4 `NcTheme` + `AppTheme`.** `ThemeExtension<NcTheme>`, ручной `ColorScheme` (SPEC §1.5), `TextTheme`, глобальные темы компонентов (`filledButtonTheme`, `inputDecorationTheme`, `listTileTheme`, `switchTheme`, `sliderTheme`, `segmentedButtonTheme`, `bottomSheetTheme`, `dialogTheme`, `snackBarTheme`, `navigationBarTheme`, `navigationRailTheme`, `cardTheme`, `chipTheme`, `appBarTheme`, `progressIndicatorTheme`, `scrollbarTheme`, `tooltipTheme`, `pageTransitionsTheme`). `M3EThemeData.fromMaterial` продолжает проецироваться в `app.dart`. API `AppTheme.light/dark(...)` прежний.
6. **1.5 Движение и отклик.** Расширить `AppMotion` (press/snap/gentle/celebrate + длительности и кривые) с тестами ratio. `NcMotion.of(context)` выбирает пружины по `MotionPreference` и `disableAnimations`. `NcHaptics` (настройка `haptics`, ограничение 40 мс) с тестом на `SystemChannels.platform` mock. **Экраны пока не переводятся.**
7. **1.6 Фон и переходы.** `NcAmbientBackground` (Aurora + зерно, статичен в Standard / при disableAnimations / в тестах) и `NcPageTransitionsBuilder`. Подключение фона — в `builder` у `MaterialApp.router` под `M3ETheme`. Это самое безопасное место: роутер не трогается, а `Scaffold.backgroundColor` становится прозрачным через тему.
8. **1.7 Verify.** Полный прогон. Особое внимание — тестам, которые искали цвета `colorScheme.primary` у кнопок оценки: роли оценки меняются только на этапе 4, поэтому на этапе 1 `ColorScheme` должен оставить `primary` = акцент.

**Критерии готовности:** все старые тесты зелёные без ослабления; новые guard-тесты зелёные; скриншоты «до/после» каждого экрана; ни одного изменения в Красной зоне (`git diff --stat` в журнале).

**Риски:** golden-тесты меняются массово → они перегенерируются **одним** отдельным коммитом с пометкой `test(golden): rebaseline Nocturne foundation` и скриншотами diff в журнале. `BackdropFilter` в тестах дорогой → на этапе 1 стекло ещё не используется.

---

## Этап 2 — Компоненты

**Цель:** библиотека `lib/ui/design/components/` по `REDESIGN-SPEC.md §8`, каждая единица — с widget-тестом и golden (dark/light × default/high-contrast × textScale 1,0/2,0).

Порядок (от атомов к составным; каждый пункт — red → green коммиты):
1. **2.1 Примитивы:** `NcSurface`, `NcGlass` (+ счётчик групп BackdropFilter в тестовом хелпере `test/helpers/glass_budget.dart`), `NcIcon3D` (с резервом), `NcKeyHint`, `NcBadge`, `NcSpinner`, `NcSkeleton`.
2. **2.2 Действия:** `NcButton` (5 вариантов, 3 размера, loading), `NcIconButton`, `NcSplitButton`, `NcFab` (схлопывание по `ScrollNotification`).
3. **2.3 Ввод:** `NcTextField`, `NcSearchField`, `NcSwitch`, `NcSegmented`, `NcSlider`, `NcStepper`, `NcChip`, `NcDropdown`.
4. **2.4 Структура:** `NcListRow`, `NcSection`, `NcCardTile`, `NcTopBar` (large title + стекло по скроллу), `NcEmptyState`, `NcErrorState`.
5. **2.5 Оверлеи:** `NcMenu`, `NcSheet` (`showNcSheet<T>` — тонкая обёртка над `showModalBottomSheet<T>`, на ПК — диалог), `NcDialog` (`showNcDialog<T>`), `NcToast`. **Глобальное подключение:** `showAppMessage` и `showArchivedUndoSnackbar` в `deck_actions.dart` начинают показывать `NcToast` (сигнатуры прежние, тесты на текст и «Отменить» остаются зелёными).
6. **2.6 Прогресс:** `NcProgressLine`, `NcSegmentedProgress` (повторяющаяся анимация — тесты через `pump(Duration)`), `NcRing`.
7. **2.7 Сессионные:** `NcMonolith` (+ переворот как отдельный `NcFlip`, параметризованный пружиной), `NcRatingButton`, `NcRatingDock` (neighbor-squish, 2 × 2 при большом textScale).
8. **2.8 Verify + каталог.** `test/golden/components_catalog_test.dart` собирает все компоненты на одном полотне (для ревью владельцем). Debug-маршрутов и «витрин» в приложении **нет**: это была бы мёртвая функция.

**Критерии:** покрытие `design/` ≥ 90 %; каждый компонент поддерживает Semantics/фокус/disabled; ни один экран (кроме тостов) ещё не изменён.

---

## Этап 3 — Каталог (экраны вне сессии)

**Цель:** перевести на компоненты экраны навигации и управления. Каждый экран — отдельный шаг с red-тестами: ключи на месте, новые элементы облика (например, сводка «К повторению: N» в шапке колод), бюджет стекла ≤ 2, textScale 2,0 без overflow, golden.

Порядок (по частоте использования):
1. **3.1 Оболочка** — `shell/app_shell.dart`: `NcNavDock` (< 600), `NcNavRail` (600–1023), сайдбар (≥ 1024). Сохранить `railBreakpoint` = 600 и добавить второй порог 1024. Тесты 7-й итерации на `NavigationBar`/`NavigationRail` переписываются на ключи `shell-nav-<branch>`, которые добавляются в контракт.
2. **3.2 «Мои колоды»** — `decks/decks_screen.dart` (+ диалоги в `deck_actions.dart`).
3. **3.3 Экран колоды** — `decks/deck_screen.dart` (лист режимов-сетка, лимит-диалог, список карточек, парящий тулбар).
4. **3.4 Форма карточки и редактор масок** — `cards/card_form_screen.dart`, `cards/occlusion_mask_editor.dart` (+ стили `cards/content/*`: Literata, cloze-pill, LaTeX-шаги, маски occlusion, `CardImageView` и полноэкранный просмотр).
5. **3.5 Конструктор** — `session/session_constructor_screen.dart`.
6. **3.6 Статистика** — `statistics/statistics_screen.dart`, `statistics/statistics_charts.dart` (палитра `heat0–4`, капсулы waveform, прогноз).
7. **3.7 Настройки** — `settings/settings_screen.dart`.
8. **3.8 Провайдеры** — `settings/generation_settings_screen.dart`, `settings/provider_account_dialogs.dart`, иконки в `provider_labels.dart`.
9. **3.9 Verify** + интеграционный тест на production-проводке: смена темы, high contrast, dyslexia, textScale, motion на реальном `CardFlowApp` (ретроспектива 1: применение настройки — на корне приложения).

**Критерии:** на экранах этапа нет `AppBar`, `ListTile`, `FilledButton`, `SegmentedButton`, `SwitchListTile`, `Card`, `M3ECard`, `M3ESplitButton`, `M3EExtendedFab`, `CircularProgressIndicator` (guard-тест по списку файлов этапа); Hero аватара колоды работает в обе стороны.

---

## Этап 4 — Сессии

**Цель:** главные моменты продукта — повторение и игровые режимы. Сюда входит самое заметное: монолит с 3D-переворотом, док оценок, свайпы ленты, празднование.

Порядок:
1. **4.1 Каркас** — `review/review_chrome.dart` (капсула действий, «Почему?», выход, пустая сессия, итоги, «время истекло», ошибка, «план потерян»). `ReviewSessionAppBar` остаётся `PreferredSizeWidget` с прежними параметрами.
2. **4.2 Классика** — `review/review_card_view.dart` (монолит + `NcFlip` + блик), `review/review_toolbar.dart` (`NcRatingDock`, функция `reviewIntervalLabel` и её вывод не меняются), `review/review_session_screen.dart` (оформление тела, «Показать ответ», вспышка Aurora; `_playHaptic` переходит на `NcHaptics` с той же таблицей).
3. **4.3 Лента** — `review/feed_card_view.dart` (свечение края, штамп, морфинг радиуса; пороги и `feedSwipeRating` не меняются), `review/feed_progress_bar.dart`, `review/feed_session_screen.dart` (`_FeedBottomBar`).
4. **4.4 Тренировка** — `review/practice_session_screen.dart`.
5. **4.5 Тест и Ввод** — `study/multiple_choice_screen.dart`, `study/typing_screen.dart` (вместе с `AnswerDiffView`).
6. **4.6 Пары и Верно/Неверно** — `study/match_screen.dart`, `study/true_false_screen.dart`.
7. **4.7 Итоги новых режимов** — `study/study_session_chrome.dart`.
8. **4.8 Verify** + Windows-смоук `integration_test/session_smoke_windows_test.dart` (должен пройти без правок логики; если смоук ищет виджет по типу — правка теста отдельным коммитом) + замер кадров (DevTools / `flutter run --profile`) на переворот и свайп: ≤ 16 мс на кадр на Windows и Android-эмуляторе. Отчёт — `journal/redesign-4/perf.md`.

**Критерии:** гайд-тесты LaTeX (`study_mode_latex_test.dart`, `card_text_test.dart`) зелёные; клавиши Space/1–4 работают; `HapticFeedback.` есть только в `design/haptics.dart`; режимы Standard и disableAnimations проверены тестами (переворот → кроссфейд, нет искр, нет каскада).

---

## Этап 5 — AI-студия, 3D и полировка

**Цель:** самый «вау»-экран, финальные ассеты и шлифовка всего продукта.

1. **5.1 Генерация** — `generation/generation_screen.dart`: Iris-Aurora, hero-сфера, зона прикрепления с marching-ants, файлы с бейджами форматов, чипы провайдеров, `NcButton.ai`, прогресс-орбита, живая лента. **Тело файла большое (1222 строки):** разрешено выносить приватные виджеты оформления в новый файл `generation/generation_widgets.dart` (части библиотеки, `part`/`part of` или отдельные приватные виджеты с публичными параметрами), не трогая `_GenerationScreenState`, кроме `build`-методов.
2. **5.2 Предпросмотр** — `generation/generation_preview_screen.dart`.
3. **5.3 3D-иконки.** Импорт ассетов ComfyUI (`assets/icons3d/`, 3 плотности), тест «каждое имя из инвентаря §5.3 существует в бандле» (`icons3d_inventory_test.dart`), выключение резерва там, где ассет есть. Тонирование аватаров колод.
4. **5.4 Микровзаимодействия и hero.** Hero колоды (если не завершён на этапе 3), анимированные цифры (`NcAnimatedNumber`), каскады, hover-подъём на ПК, кольцо фокуса во всех компонентах.
5. **5.5 Клавиатурный слой ПК.** `Ctrl/⌘+K` — командная палитра (`NcSheet`-диалог на `glass.thick` с поиском) **только с переходами по существующим маршрутам и существующими действиями**: «Мои колоды», «Статистика», «Настройки», «Генерация карточек», «Конструктор сессии», «Провайдеры», а также открыть колоду по имени (из `deckSummariesProvider`). Маршруты — через уже существующие `AppRoutes.*` и `context.go/push`. Роутер не меняется. Если владелец не подтверждает палитру — шаг пропускается и фиксируется в журнале.
6. **5.6 Аудит.** Доступность (контраст по токенам, textScale 2,0 на всех экранах, обход фокуса, screen reader — `journal/redesign-5/a11y.md`), производительность (бюджет стекла, Aurora ≤ 30 Гц, шейдеры прогреваются), размер бандла (шрифты и иконки ≤ 6 МБ суммарно).
7. **5.7 M3E-слой.** Если после этапов 3–5 `material_3_expressive` нигде не используется, кроме `M3ETheme` в `app.dart`, — ADR-036: оставить фасад (дешевле) или удалить зависимость вместе с guard-правилом. Решение принимает владелец. По умолчанию фасад **остаётся**.
8. **5.8 Документация.** Обновить `AGENTS.md` (раздел «Дизайн-система Nocturne»: где токены, правила стекла, `NcHaptics`, guard-тесты), `docs/m3e-tokens.md` → `docs/design-tokens.md`, `README.md` (скриншоты), закрыть `REDESIGN-PLAN.md` отметками.

**Критерии готовности редизайна:** все экраны из `REDESIGN-SPEC.md §9` переведены; полный набор golden обеих тем; ни одного `Colors.`/`Color(0x` вне токенов; Красная зона не изменилась с начала редизайна (`git diff <старт>..HEAD -- <файлы>` пуст); CI 9/9.

---

## Решения, которые нужны от владельца (до или во время этапов)

| # | Вопрос | Вариант по умолчанию |
|---|---|---|
| О-1 | Тема по умолчанию для новых установок — «Тёмная» вместо «Системной»? Это правка `AppSettings` (domain), то есть логики | **Не меняем**: Nocturne — основная, но выбор пользователя и системный режим уважаются. Если владелец разрешит — отдельный ADR и один тест в domain |
| О-2 | Командная палитра `Ctrl/⌘+K` (этап 5.5) | Делаем: только существующие маршруты |
| О-3 | Пакеты `material_symbols_icons`, `flutter_animate` | Проверяем на pub.dev. Если хоть один пункт ADR-001 не выполнен — встроенные средства |
| О-4 | Удалять ли M3E-зависимость в конце | Оставить фасад |
| О-5 | Финальный набор 3D-иконок (ComfyUI) | До поставки работает резерв `NcIcon3D` |
