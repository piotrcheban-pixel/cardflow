# ADR-001 — Material 3 Expressive: официальная база `material_ui` + одна community-библиотека `material_3_expressive`

**Дата:** 2026-11-11 · **Статус:** принято (итерация 0) · **Связано:** SPEC A3, A4 (A4.1–A4.6), A7.2; `AGENTS.md`; ADR-002; `docs/dependencies.md`; `journal/iteration-0/dependency-spike.md` §4

## Контекст

SPEC A3 задаёт правило: «M3 Expressive: официальные компоненты, если доступны; иначе **одна** community-библиотека (проверить `m3e_design`, `m3e_collection`, `material_3_expressive`)». `AGENTS.md`/промпт добавляют требование изоляции: компоненты держать за одним слоем `lib/ui/m3e/`, библиотеку можно заменить, две библиотеки в одном виджете не смешивать, токены движения — `lib/ui/motion.dart`.

Нужны конкретные вещи из SPEC A4.5: Button groups (neighbor-squish), Split button, Toolbars (плавающая панель), Progress indicators (waveform), FAB/Extended FAB (shape morph); A4.3 — 35 Expressive-форм; A4.4 — пружины (Expressive 380/0.8, Standard 700/0.9, Effects 1.0) и haptic; A4.1/A4.2 — dynamic color, типографика; A7.2 — кнопки оценок с прогнозом.

## Что проверено (факты)

### 1. В Flutter 3.47.9 официальных M3E-компонентов НЕТ

- Дерево `packages/flutter/lib/src/material/` в теге `3.47.9` (184 файла): отсутствуют `button_group.dart`, `floating_toolbar.dart`, `loading_indicator.dart`, `split_button.dart`, `wavy_progress_indicator.dart`, `fab_menu.dart`.
- `motion.dart` во framework содержит только `Durations`/`Curves`; в `button_style.dart`/`theme_data.dart`/`progress_indicator.dart` нет `StyleVariant`, `expressive`, `wavy`, `spring`.
- Официальный umbrella-issue [flutter/flutter#168813](https://github.com/flutter/flutter/issues/168813): **open**, updated 2026-08-17. В теле: май 2025 — «we are not actively developing Material 3 Expressive, and we will not be accepting contributions»; июль 2025 — Material/Cupertino выносятся в standalone-пакеты, «all new work for Material 3 Expressive will happen in the new packages once established in flutter/packages».

### 2. Официальная поддержка M3E теперь в first-party пакете `material_ui` — но частичная

`material_ui` 1.11.0 (2026-11-09, publisher `flutter.dev`, BSD-3-Clause, sdk `^3.13.0`, flutter `>=3.47.0`, 297 likes, 160 pts, все платформы, локализация `material_ru.arb`) — decoupled Material-библиотека (по сути `package:flutter/material.dart` в отдельном пакете). M3E-часть по CHANGELOG:

- 1.2.0 — `StyleVariant` (M3 / M3 Expressive);
- 1.5.0 — M3E-поддержка `IconButton`;
- 1.8.0 — `RoundedPolygon`, `CornerRounding`, `MaterialShapes`, `MaterialShapeBorder` (Expressive-формы, A4.3);
- 1.11.0 — **`Springs`** (официальные M3E spring-токены standard/expressive motion schemes) и M3E-поддержка `ElevatedButton`.

**Компонентов из A4.5 (button groups, split button, floating toolbar, waveform progress, FAB menu) в `material_ui` 1.11.0 нет** — они ещё не перенесены.

Официальные spring-токены (сгенерированы из Material token database; файл `lib/src/generated/motion_defaults_m3e.g.dart`, класс `Springs`) — **точно совпадают со SPEC A4.4**:

| Токен `Springs.*` | stiffness | damping ratio | В SPEC A4.4 |
|---|---|---|---|
| `expressiveDefaultSpatial` | 380.0 | 0.8 | «Expressive (spatial): 380 / 0.8» ✓ |
| `standardDefaultSpatial` | 700.0 | 0.9 | «Standard (spatial): 700 / 0.9» ✓ |
| `expressiveDefaultEffects` / `standardDefaultEffects` | 1600.0 | 1.0 | «Effects: без overshoot, ratio 1.0» ✓ |
| также `expressive{Slow,Fast}Spatial` (200/0.8, 800/0.6), `standard{Slow,Fast}Spatial` (300/0.9, 1400/0.9), `*Effects` (800/1.0, 3800/1.0) | | | |

Важно (подтверждает предупреждение SPEC A4.4): в Material-токене `damping` — это **ratio**, а не абсолютный коэффициент `SpringDescription.damping`; официальные константы построены как `SpringDescription.withDampingRatio(mass: 1.0, stiffness: S, ratio: ζ)`, поэтому абсолютный damping = `ζ * 2 * sqrt(S)` (например, 47.62 для 700/0.9). В `lib/ui/motion.dart` использовать `SpringDescription.withDampingRatio(...)` или константы `Springs.*`.

### 3. Экосистема уже зависит от `material_ui`

`go_router 18.1.4` (CHANGELOG «18.0.0 — Migrates to material_ui and cupertino_ui»), `flutter_riverpod 3.5.0` (CHANGELOG «3.5.0 — Migrated Material imports to `package:material_ui/material_ui.dart`»), `pdfrx 2.12.0` объявляют `material_ui: ^1.0.0`. Значит, актуальные версии ключевых пакетов уже нельзя использовать без `material_ui` в графе.

### 4. Community-кандидаты (pub.dev API, 2026-11-11)

| Пакет | Версия / дата | Flutter constraint | Лицензия | likes / pts | Оценка |
|---|---|---|---|---|---|
| `material_3_expressive` | 1.2.0 / 2026-10-23 | `>=3.47.0`, sdk `^3.13.0` | MIT | 54 / 160 | **44 виджета/39 модулей, 90+ тестов в репо, CHANGELOG с PR, зависит от official `material_ui ^1.8.0`** |
| `m3e_collection` | 0.3.7 / 2025-11-12 | не задан | MIT | 33 / 150 | агрегатор 16 суб-пакетов 0.1–0.3; README репозитория — «Starter monorepo»; 12 мес. без релиза → отклонён |
| `m3e_design` | 0.2.1 / 2025-10-25 | не задан | MIT | 2 / 130 | только токены/ThemeExtension, компонентов нет → отклонён |
| `m3_expressive` | 1.0.0 / 2026-04-17 | `>=3.10.0` | MIT | 5 / 150 | подмножество (morph-фигуры, индикаторы, swipe) → отклонён |
| `expressive_m3` | 0.2.0 / 2026-07-01 | `>=3.27.0` | MIT | 2 / 140 | подмножество; 0.2.x → отклонён |
| `m3e_core`/`m3e_buttons`/`m3e_card_list` | 1.1.5/1.0.4/1.0.0, 2026-08…10 | `>=3.47.0` | MIT | 33/9/9, 160 pts | несколько пакетов, узкое покрытие → нарушает «одна библиотека» |

`material_3_expressive` покрывает требования A4.5: `M3EButton` (5 размеров, press shape morph, sparkle ripple), button groups с neighbor-squish (`button_group_icon_squish_test.dart`), split button (`split_button_spec_test.dart`), toolbar (`toolbar_spec_test.dart`), FAB/FAB menu (`fab_menu_spec_test.dart`), loading indicator и progress (в т.ч. wavy: `loading_indicator_test.dart`, `progress_indicator_spec_test.dart`, wavy slider), `M3EMaterialNewShapes`/shape morph (A4.3), `M3ETheme` с motion-токенами через `motor`, `M3EHaptics` (A4.4/A7.2), `M3EMaterialApp` (dynamic color, A4.1). MIT LICENSE в репо (Copyright 2026 Paa Developments). Требования Flutter `>=3.47.0` / Dart `^3.13.0` — **ровно наш пин**.

## Варианты

1. **Только официальные компоненты Flutter 3.47.9** — невозможен: компонентов A4.5 нет; делать вид, что «доступны», нельзя.
2. **`material_ui` + собственные компоненты M3E в `lib/ui/m3e/`** (без community-библиотеки). Полный контроль, только first-party-зависимости; но ~6+ нетривиальных компонентов (button groups с morph/overflow, split button, floating toolbar, waveform progress, FAB menu, shape morph) и их тесты/голдены — большой объём ручной работы в MVP.
3. **`material_ui` + ровно одна community-библиотека `material_3_expressive ^1.2.0`, изолированная за `lib/ui/m3e/`** — компоненты готовы и протестированы автором, версия библиотеки совпадает с пином Flutter; риск — молодой проект/единственный мейнтейнер, снимается изоляцией и fallback-планом.
4. **framework-Material + community-библиотека без `material_ui`** (`m3e_collection`/`m3_expressive`) — избегает `material_ui`, но смешивает framework-Material с `material_ui`-виджетами, которые тянут `go_router`/`pdfrx`, и остаётся без официальных M3E-токенов/форм; кандидаты старше и слабее.
5. Несколько пакетов (`m3e_core` + `m3e_buttons` + …) — нарушает «одна библиотека».

## Решение

Принимаем **вариант 3**:

1. **База Material — официальный `material_ui ^1.11.0`** (publisher `flutter.dev`, BSD-3-Clause). Импорт Material-виджетов — только `package:material_ui/material_ui.dart`; `package:flutter/material.dart` в `lib/` запрещён (проверяется analyzer-правилом/ревью). Это даёт: официальные M3E spring-токены `Springs`, `MaterialShapes`/`RoundedPolygon`/`CornerRounding`, `StyleVariant`, dynamic color, ru-локализацию Material — и совместимость с `go_router`/`flutter_riverpod`/`pdfrx`.
2. **M3E-компоненты — ровно одна библиотека `material_3_expressive ^1.2.0`** (MIT, Flutter >=3.47/Dart ^3.13). Другие M3E-библиотеки не подключаются.
3. **Изоляция:** импорт `package:material_3_expressive/material_3_expressive.dart` разрешён **только** в `lib/ui/m3e/*` (реэкспорт-фасад + обёртки). Остальной UI использует либо `lib/ui/m3e/`, либо `material_ui`, но не библиотеку напрямую. Токены движения/пружин — `lib/ui/motion.dart` (значения из `Springs.*` и SPEC A4.4). Две M3E-библиотеки в одном виджете не смешиваются (SPEC/AGENTS).
4. **Fallback-план (если runtime-спайк провалится):** перейти на вариант 2 — заменить тело `lib/ui/m3e/` собственными компонентами поверх `material_ui` (`Springs`, `MaterialShapes`, `StyleVariant`), без изменения остального UI. Если провалится и `material_ui`-миграция (например, конфликт l10n/совместимости) — вернуться к framework-Material и `m3e_collection 0.3.7`/`m3_expressive 1.0.0` как единственной M3E-библиотеке; это отдельный ADR (потребует понижения `go_router`/`flutter_riverpod` до материало-независимых версий).
5. **Runtime-спайк до кода UI** (needs-runtime-spike S2 из `dependency-spike.md`): `pub get` → минимальный `M3EMaterialApp` + ru-локаль + 4 кнопки оценок → проверить сборку/рендер/haptics на Windows; зафиксировать результат в `journal/iteration-0/`.

### Обязательные шаги миграции при внедрении

- `flutter create` создаёт проект на framework-Material; после появления `pubspec.yaml` — `dart fix --apply --code=migrate_design_widgets` (data-driven fix из `material_ui`) и замена импортов на `package:material_ui/material_ui.dart`.
- Локализация: делегаты системных строк — `GlobalMaterialLocalizations.delegates` из `material_ui` (README пакета); `supportedLocales: [Locale('ru')]`; свой ARB — через gen-l10n без изменений.
- Пакеты, которые ещё импортируют framework-Material, оборачивать `MaterialUiCompatibilityBridge` (README `material_ui`), но в выбранном стеке таких быть не должно (проверить при спайке).
- Конфликт имён: `material_ui` экспортирует свои `RoundedPolygon`/`CornerRounding`, а `material_3_expressive` реэкспортирует их из `material_new_shapes` → при импорте обоих в одном файле — `hide CornerRounding, RoundedPolygon` (описано в README/MIGRATION библиотеки). Внутри `lib/ui/m3e/` это решается фасадом.

## Последствия

**Плюсы:** соответствие SPEC A3/A4 (M3 Expressive, dynamic color, пружины, форм-морф, haptics); официальные spring-токены 1:1 со SPEC A4.4 (не нужно вендорить/выдумывать); компоненты A4.5 готовы и покрыты тестами автора; единый Material-базис с `go_router`/`riverpod`/`pdfrx`; библиотека заменяема за счёт `lib/ui/m3e/`; лицензии MIT/BSD-3 — допустимы.

**Минусы/риски:** (а) `material_3_expressive` — молодой проект без verified publisher (единственный мейнтейнер): риск API-изменений/заброшенности → изоляция + fallback на вариант 2; (б) `material_ui` — новая decoupled-библиотека (1.11.0): возможны шероховатости миграции (l10n, `dart fix`, compatibility bridge) → обязательный runtime-спайк, при провале — ADR о возврате к framework-Material; (в) `material_ui` требует ровно Flutter >=3.47/Dart ^3.13 — версия Flutter закреплена (3.47.9), апгрейд — только с проверкой; (г) увеличивается размер графа (cupertino_ui, motor, material_new_shapes, dynamic_color — все MIT/Apache-2.0/BSD-3, проверены).

**Обязательства:** `lib/ui/m3e/` — единственная точка импорта community-M3E; в `AGENTS.md` добавить правило «Material-импорты — только `material_ui`; M3E-компоненты — только через `lib/ui/m3e/`»; при изменении версии `material_ui`/`material_3_expressive` — прогон минимального M3E-экрана и golden-теста; отступление от токенов — только с записью в `docs/m3e-tokens.md`.

## Источники

- Flutter 3.47.9 material sources: https://github.com/flutter/flutter/tree/3.47.9/packages/flutter/lib/src/material
- M3E umbrella issue: https://github.com/flutter/flutter/issues/168813
- material_ui: https://pub.dev/packages/material_ui · https://github.com/flutter/packages/tree/main/packages/material_ui · Springs: `lib/src/generated/motion_defaults_m3e.g.dart` · CHANGELOG: https://github.com/flutter/packages/blob/main/packages/material_ui/CHANGELOG.md
- Material 3 spring tokens: https://m3.material.io/styles/motion/overview/specs
- material_3_expressive: https://pub.dev/packages/material_3_expressive · https://github.com/paadevelopments/material_3_expressive (README/CHANGELOG/LICENSE)
- m3e_collection: https://pub.dev/packages/m3e_collection · m3e_design: https://pub.dev/packages/m3e_design · m3_expressive: https://pub.dev/packages/m3_expressive · expressive_m3: https://pub.dev/packages/expressive_m3 · m3e_core: https://pub.dev/packages/m3e_core
- go_router CHANGELOG (миграция 18.0.0): https://github.com/flutter/packages/blob/main/packages/go_router/CHANGELOG.md
- flutter_riverpod CHANGELOG 3.5.0: https://github.com/rrousselGit/riverpod/blob/master/packages/flutter_riverpod/CHANGELOG.md
