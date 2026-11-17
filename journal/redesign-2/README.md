# Редизайн «Nocturne» — этап 2 «Компоненты»

**Дата:** 2026-11-17 · **Режим:** ИТЕРАЦИИ (автономно) · **Старт:** `8e9db8a`
(`docs: confirm 9/9 CI for docs commit 734c120`), рабочее дерево чистое.
**Окружение:** Windows 11, FVM 4.3.2, Flutter 3.47.9 / Dart 3.13.7 (L2: нет
Android SDK/JDK/Xcode) — локально проверены `test/analyze/format/golden` и
`build windows`.

## Цель и результат

Цель — библиотека `lib/ui/design/components/` по REDESIGN-SPEC §8: каждый
компонент на токенах (`NcTheme.of`), пружины из `NcMotion.of`, отклик через
`NcHaptics`, семантика на русском (ARB), widget-тест поведения и golden в
8 вариантах (dark/light × обычный/high-contrast × textScale 1,0/2,0), экспорт
из `lib/ui/design/design.dart`. Экраны не переводятся, кроме глобальных
тостов (`deck_actions.dart`).

Результат: **35 компонентов + 6 внутренних примитивов**, 298 golden-снимков,
123 widget-теста дизайн-системы (+ 2 теста проводки тостов), каталог-полотно
в журнале. Красная зона и экраны не изменены (`git diff` пуст), `showAppMessage`
и `showArchivedUndoSnackbar` показывают `NcToast` при прежних сигнатурах и
текстах, все старые тесты зелёные.

## Шаги, коммиты, артефакты

| Шаг | Red | Green | Что сделано |
|---|---|---|---|
| 2.1 Примитивы | `9da7782` | `0446cc6` | `NcSurface`, `NcGlass` + `NcGlassGroup`, `NcIcon3D` (резерв), `NcKeyHint`, `NcBadge`, `NcSpinner`, `NcSkeleton`; внутренние `NcTappable`/`NcPressScale`/`NcFocusRing`/`NcSpringBuilder`/`NcStagger`/`NcScrollCollapseScope`; `test/helpers/{nc_harness,nc_golden,glass_budget}.dart` |
| 2.2 Действия | `e207be2` | `60164b9` | `NcButton` (5 вариантов × 3 размера, loading, hover, AI-блик), `NcIconButton`, `NcSplitButton`, `NcFab` (схлопывание), `NcMenu`/`showNcMenu` (нужен сплит-кнопке) |
| 2.3 Ввод | `507a49d` | `b59b672` | `NcTextField`, `NcSearchField`, `NcSwitch`, `NcSegmented<T>`, `NcSlider`, `NcStepper`, `NcChip`, `NcDropdown<T>` |
| 2.4 Структура | `7adf028` | `6107531` | `NcListRow`, `NcSection`, `NcCardTile`, `NcTopBar` (стекло по скроллу, large title), `NcEmptyState`, `NcErrorState` |
| 2.5 Оверлеи | `red-2.5.txt` (в green-коммите) | `82363c7` | `NcSheet`/`showNcSheet`, `NcDialog`/`showNcDialog`, `NcToast`/`showNcToast`; **глобальный переход**: `showAppMessage`/`showArchivedUndoSnackbar` → `NcToast` (сигнатуры и undo прежние) |
| 2.6 Прогресс | `535ffe2` | `20dff64` | `NcProgressLine`, `NcSegmentedProgress` (пульс Stories), `NcRing`, `NcAnimatedNumber` |
| 2.7 Сессия | `5f33d0a` | `44e0c41` | `NcMonolith`, `NcFlip`, `NcRatingButton`, `NcRatingDock` (neighbor-squish, 2×2) |
| 2.8 Каталог/verify | — | этот коммит | `test/golden/components_catalog_test.dart` (dark/light), полотно в `journal/redesign-2/screenshots/`, гейты, журнал/STATE/лимиты/ADR |

Красная фаза каждого шага — тесты-спецификация + заглушки реализации, падения
на уровне assertion (вывод: `journal/redesign-2/red-2.N.txt`). 2.5-оверлеи
реализованы вместе с `NcMenu` в 2.2 (сплит-кнопка не могла открыть меню без
него); красным доказательством для шага 2.5 служит тест проводки
`test/widget/design/toast_wiring_test.dart` — до перехода он падал
`Found 0 widgets with type "NcToast"` (`red-2.5.txt`).

## Библиотека (`lib/ui/design/components/`)

Примитивы: `nc_surface`, `nc_glass`, `nc_icon3d`, `nc_key_hint`, `nc_badge`,
`nc_spinner`, `nc_skeleton`.
Действия: `nc_button`, `nc_icon_button`, `nc_split_button`, `nc_fab`.
Ввод: `nc_text_field`, `nc_search_field`, `nc_switch`, `nc_segmented`,
`nc_slider`, `nc_stepper`, `nc_chip`, `nc_dropdown`.
Структура: `nc_list_row`, `nc_section`, `nc_card_tile`, `nc_top_bar`,
`nc_empty_state`, `nc_error_state`.
Оверлеи: `nc_menu`, `nc_sheet`, `nc_dialog`, `nc_toast`.
Прогресс: `nc_progress_line`, `nc_segmented_progress`, `nc_ring`,
`nc_animated_number`.
Сессия: `nc_monolith`, `nc_flip`, `nc_rating_button`, `nc_rating_dock`.
Внутренние (`components/internal/`): `nc_pressable` (`NcTappable`,
`NcPressScale`, `NcFocusRing`), `nc_spring_builder`, `nc_stagger`,
`nc_scroll_collapse`, `nc_button_appearance`.

Общие контракты: тап/долгое/правый клик и фокус Enter/Space — один
`NcTappable`; кольцо фокуса 2 px `aurum` + 2 px offset; отклик — только
`NcHaptics` (throttle 40 мс); пружины — только `NcMotion`; ни один компонент
не импортирует Riverpod/роутер/домен (guard расширен:
`test/guards/architecture_test.dart`).

## Тестовая инфраструктура

- `test/helpers/nc_harness.dart` — стенд компонента: `AppTheme` (dark/light/
  high-contrast), `NcMotionScope`, `NcHapticsScope` с рекордером канала,
  локаль `ru`, `textScaler`, размер окна; `pressScaleOf`, `expectNoOvershoot`,
  `pumpNcAtTextScale2` (проверка отсутствия overflow).
- `test/helpers/glass_budget.dart` — `expectGlassBudget(tester, maxGroups: 2)`
  (считает фильтры и общие `BackdropGroup`), `expectNoGlass`.
- `test/helpers/nc_golden.dart` — загрузка Onest/Literata/JetBrainsMono/
  MaterialIcons, `ncGoldenVariants` (8 вариантов), `ncGoldenGroup` на
  компонент, каталог `test/golden/goldens/`.

## Гейты (вывод команд этой сессии)

| Гейт | Команда | Результат |
|---|---|---|
| Тесты | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2036 passed + 8 skipped** (baseline этапа 1 — 1924 + 8; +112 новых) |
| Golden (все) | `fvm flutter test --no-pub test/golden` | **298 passed** (298 PNG, 4,25 МБ) |
| Покрытие `design/` | lcov по `lib/ui/design/` | **93,8 % (2672/2848)**; `components/` — **93,1 % (2116/2272)** |
| Покрытие рукописного | `fvm dart run tool/coverage_check.dart --min=80` | **92,8 % (15825/17047)**, порог пройден |
| Анализатор | `fvm flutter analyze` | **No issues found!** |
| Формат | `fvm dart format --set-exit-if-changed lib test integration_test tool` | **530 files / 0 changed** |
| Сборка | `fvm flutter build windows --release --no-pub` | `√ Built …\Release\cardflow.exe` (60,0 с) |
| Красная зона | `git diff --stat 8e9db8a..HEAD -- <19 файлов>` | **пусто** |
| Экраны | `git diff --stat … -- lib/ui/**/*_screen.dart`, `app_shell.dart`, `review_chrome.dart` | **пусто** |
| Ключи | `test/guards/ui_key_contract_test.dart` | ключи этапа 2 (`nc-progress-fill`, `nc-segmented-progress-pulse`) добавлены в `fixtures/ui_keys.txt` (221) |

Логи: `journal/redesign-2/{full-test.txt,golden-run.txt}`.

## Каталог-полотно

`journal/redesign-2/screenshots/components-catalog-dark.png` и
`…-light.png` (1360×2900): все компоненты с подписями, тема Nocturne и
Porcelain. Источник — `test/golden/components_catalog_test.dart` (тег
`golden`); витрины в приложении нет (мёртвая функция).

## Решения и отступления (в ADR-035, раздел «Этап 2»)

1. **Зерно `NcGlass` — процедурный painter** (детерминированный `Random`,
   2–3 %), а не `grain.frag`/PNG: нет асинхронной загрузки ассета в каждом
   кадре и golden стабильны. §4.1 допускает шейдер или тайл; здесь третий
   детерминированный вариант.
2. **Резерв `NcIcon3D` без `BackdropFilter`** — «стеклянная сфера» на
   градиентах + rim light: иконка встречается в списках/пустых состояниях и не
   должна тратить бюджет стекла (§4.4). Ассеты подключаются на этапе 5.
3. **`NcToast` не перехватывает указатель** (кроме кнопки действия), а полоса
   времени обновляется шагом 200 мс, а не непрерывной анимацией: иначе
   `pumpAndSettle` старых экранных тестов ждал бы 4–8 с и тост исчезал до
   проверки текста/«Отменить».
4. **AI-блик `NcButton.ai` одноразовый 3 с** (не циклический) — та же причина
   `pumpAndSettle`; визуально блик проходит при появлении экрана.
5. **`NcRatingDock` neighbor-squish — доли `flex`** (106/97/100) по нажатию,
   а не анимация ширин: ширина в `Row` не анимируется пружиной без потери
   раскладки; этап 4 может заменить на `AnimatedContainer`-док.
6. **`NcFlip` при `disableAnimations` — кроссфейд 120 мс** (§6.4);
   в Expressive — `rotateY` на `expressive`-пружине с перспективой 0,0012.
7. **Golden-эталоны сняты на Windows** (единственная доступная платформа,
   L2); CI прогоняет тесты без тега `golden` (существующая конфигурация
   `.github/workflows/ci.yml`) — см. L98.

## Новые ограничения (KNOWN_LIMITATIONS)

L98 (golden сняты на Windows, CI их не прогоняет), L99 (`NcRatingDock`
squish — доли, не пружина), L100 (`NcTopBar`/`NcFab` проверены изолированно,
экраны подключают их на этапе 3), L101 (3D-ассетов нет — резерв), L102
(бюджет стекла проверен на компонентах, не на экранах; этап 3), L103 (строки
этапа 2 в ARB — только `commonLoading`/`commonClose`; остальные тексты
приходят параметрами из ARB экранов).

## Открытые вопросы владельцу

1. **Каталог-полотно** — достаточно ли формата 1360×2900 PNG для ревью, или
   нужна интерактивная витрина? Витрина в приложении противоречит правилу «нет
   мёртвых функций», поэтому сделан golden.
2. **`NcButton.ai`** — оставить одноразовый блик или вернуть циклический
   3-секундный (потребует перевода экранных тестов на `pump(Duration)`)?
3. **3D-иконки** — этап 5 ждёт набор ComfyUI; резерв уже выглядит целостно.

## Следующий шаг

Этап 3 «Каталог»: оболочка (`NcNavDock`/`NcNavRail`), «Мои колоды», экран
колоды, форма карточки, конструктор, статистика, настройки, провайдеры — на
`Nc*`-компонентах, с ключами §9 и бюджетом стекла на каждом экране.
