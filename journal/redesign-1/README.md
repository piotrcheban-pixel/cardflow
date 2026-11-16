# Редизайн «Nocturne» — этап 1 «Фундамент»

**Дата:** 2026-11-17 · **Режим:** ИТЕРАЦИИ (автономно) · **Старт:** `7458346`
(`docs: record green CI for 7.17`), рабочее дерево чистое.
**Окружение:** Windows 11, FVM 4.3.2, Flutter 3.47.9 / Dart 3.13.7. Android
SDK/JDK/Xcode нет (L2): локально проверены `test/analyze/format/format` и
`build windows`.

## Цель этапа и результат

Цель — ввести токены, тему, шрифты, движение, отклик, фон и переходы так,
чтобы **всё приложение** выглядело в Nocturne только за счёт `ThemeData`,
без правки экранов.

Результат: ни один `*_screen.dart`/`*_view.dart` не изменён (проверка ниже),
Красная зона пуста, все 1924 теста зелёные, приложение сборкой проверено и
снято 60 скриншотов (15 экранов × 2 темы × 2 размера). Экраны получили
ночной холст, слоновую кость вместо белого, золотой акцент, шрифты Onest/
Literata/JetBrains Mono, фон Aurora, новые переходы и настройки движения/
отклика в дереве.

## Шаги, коммиты, артефакты

| Шаг | Коммит | Что сделано |
|---|---|---|
| 1.0 Спайки + ADR | `8158fc6` | `docs/decisions/ADR-035-nocturne-design-system.md` (замена SPEC A4 в визуальном слое), `journal/redesign-1/spikes.md` |
| 1.1 Guard-тесты | `1daef8c` | `tool/extract_ui_keys.dart` + снимок 219 ключей; `ui_key_contract_test`, `design_tokens_test`, `no_network_fonts_test`, `haptics_test`; правило изоляции `design/` в `architecture_test`; red-фаза мутациями — `journal/redesign-1/red-output.md` |
| 1.2 Токены | `3559557` | `lib/ui/design/tokens/` — `nc_colors` (Nocturne/Porcelain/high-contrast/dynamic HCT), `nc_typography`, `nc_spacing`, `nc_radii`, `nc_depth`, `nc_glass` + 59 unit-тестов (значения, контраст WCAG) |
| 1.3 Шрифты | `bed3196` | `assets/fonts/{Onest,Literata,JetBrainsMono}/` (переменные, OFL 1.1), `assets/fonts/LICENSES/`, `LicenseRegistry` при старте, `nc_fonts_test` (растровая проверка кириллицы) |
| 1.4 `NcTheme` + `AppTheme` | `1787097` | `ThemeExtension<NcTheme>`, ручной `ColorScheme` §1.5, `TextTheme` из токенов, elevation 0, прозрачный `scaffold`, 18 тем компонентов; переписан один старый тест (обоснование — `step-1.4-theme.md`) |
| 1.5 Движение и отклик | `42f13df`, `e4fb90f` | `AppMotion` расширен (press/snap/gentle/celebrate, длительности, кривые), `NcMotion`/`NcMotionScope`, `NcHaptics`/`NcHapticsScope` (throttle 40 мс, окно повтора, двойной успех) |
| 1.6 Фон и переходы | `a4a5e4c` | `NcAmbientBackground` (Aurora + зерно, статичен при Standard/disableAnimations/high-contrast/в тестах), `NcPageTransitionsBuilder`, подключение в `app.dart` (`NcMotionScope → NcHapticsScope → NcAmbientBackground → M3ETheme`), `cupertino_ui` запинен |
| 1.7 Verify | этот коммит | гейты, скриншоты, Красная зона, журнал/STATE/лимиты |

## Гейты (вывод команд этой сессии)

| Гейт | Команда | Результат |
|---|---|---|
| Baseline до правок | `fvm flutter test --no-pub --exclude-tags golden` | **1771 passed + 8 skipped**, 1 падение — живой Wikimedia (сеть, L92); STATE 7.17 фиксирует 1772 + 8 |
| Тесты | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **1924 passed + 8 skipped**, 0 падений (+152 к baseline) |
| Покрытие | `fvm dart run tool/coverage_check.dart --min=80` | **92.8 % (13706/14775)** рукописного кода, порог пройден |
| Анализатор | `fvm flutter analyze` | **No issues found!** |
| Формат | `fvm dart format --set-exit-if-changed lib test integration_test tool` | **0 changed** |
| Сборка | `fvm flutter build windows --release --no-pub` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (61,1 с) |
| Красная зона | `git diff --stat 7458346..HEAD -- <19 файлов>` | **пусто** |
| Экраны | `git diff --stat … -- lib/ui/**/*_screen.dart lib/ui/**/*_view.dart review_toolbar.dart app_shell.dart` | **пусто** |
| CI (GitHub Actions) | push `7458346..9a19d97` → run [`43970683883`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43970683883) | **9/9 job success** (`format + analyze`, `test` × Ubuntu/Windows/macOS, `build` desktop × Linux/Windows/macOS, `build` mobile Android/iOS) |
| CI (docs-коммит) | `734c120` → run [`43973443414`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43973443414) | **9/9 job success** (проверено API по commit SHA: `status=completed`, `conclusion=success`) |

Изменённые файлы `lib/`: `main.dart`, `ui/app.dart`, `ui/motion.dart`,
`ui/theme/app_theme.dart` (все — разрешённые) и новые `lib/ui/design/**`.
`pubspec.yaml`: `fonts`, `assets`, `material_color_utilities ^0.13.0`,
`cupertino_ui 1.1.6`; `pubspec.lock`: только `dependency: transitive → direct`
для двух пакетов, версий не менялось.

## Скриншоты

`journal/redesign-1/screenshots/` — 60 PNG, 390 × 844 и 1440 × 900, обе темы:
`decks`, `deck`, `card-form`, `constructor`, `statistics`, `settings`,
`providers`, `generation`, `review`, `feed`, `practice`, `test`, `typing`,
`match`, `true-false`. Харнесс — `tool/screenshots/redesign1_test.dart`;
он грузит **реальные** Onest/Literata/JetBrains Mono из ассетов (старый
харнесс подставлял Segoe UI), поэтому на снимках настоящая типографика
Nocturne.

## Что важно знать о stage-1-облике

Экраны на этом этапе — Material/M3E-виджеты, перекрашенные темой. Поэтому на
скриншотах видны артефакты, которые **снимаются** этапами 2–3:

- `M3EChip` (фильтры колод) и `M3EExtendedFab`/`M3ESplitButton` берут цвета из
  своей M3E-темы, а не из `ColorScheme`: выбранный чип выглядит
  фиолетовым (`secondaryContainer`), FAB в Porcelain — бледным. Их заменят
  `NcChip`, `NcFab`, `NcSplitButton` (этапы 2–3).
- Поля ввода остаются `RRect`-скруглёнными: Material `InputBorder` не умеет
  superellipse (`NcTextField` — этап 2).
- Роли оценок FSRS (`primary`/`tertiary`/`error`) пока Material-роли; шкала
  ember→amber→jade→glacier включается на этапе 4 вместе с доком оценок.

## Открытые вопросы владельцу

1. **О-1 (тема по умолчанию):** не менял — «Системная» уважается, логика
   `AppSettings` не тронута. Nocturne доступен как тёмная тема.
2. **О-4 (M3E-фасад):** сохранён; после этапа 1 M3E всё ещё используется
   экранами (чипы/FAB/сплит/прогресс). Решение об удалении — этап 5.
3. **Роли оценок до этапа 4:** «Знаю» сейчас золотое (`primary`), а в §1.2 оно
   должно быть `jade`. Это осознанно отложено: смена ролей — часть переделки
   экранов сессий (этап 4), а не темы; на этап 1 требование плана — «`primary`
   остаётся акцентом».
4. **Golden-тесты:** на старте в `test/golden/` нет файлов, поэтому
   rebaseline не понадобился. Эталонные скриншоты этапа — в `journal/`.

## Новые известные ограничения

См. `journal/KNOWN_LIMITATIONS.md`: **L93** (M3E-компоненты не подчиняются
теме), **L94** (Material-поля без superellipse), **L95** (дрейф Aurora не
виден в тестах), **L96** (бюджет стекла не измерен — нет Android SDK),
**L97** (guard-долг: 29 литералов цвета и 7 файлов с `HapticFeedback.` в
baseline, burn-down в этапах 3–4).
