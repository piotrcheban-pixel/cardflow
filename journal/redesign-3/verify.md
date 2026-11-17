# Этап 3 «Каталог» — Verify (3.9)

**Дата:** 2026-11-17 · **Старт этапа:** `4b4cc21` · **Режим:** ИТЕРАЦИИ.

## Гейты

| Гейт | Команда | Результат |
|---|---|---|
| Полный прогон | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2121 passed + 8 skipped** (baseline 2036 + 8) |
| Покрытие | `fvm dart run tool/coverage_check.dart` | **93,1 % (16799/18043)**, порог 80 % пройден |
| Golden | `fvm flutter test --no-pub --tags golden` | **336 passed** (экраны этапа 3 + библиотека этапа 2) |
| Analyzer | `fvm flutter analyze` | **No issues found** |
| Формат | `fvm dart format --set-exit-if-changed lib test integration_test` | **541 файл / 0 changed** (полный `dart format .` — 547 / 0) |
| Windows-сборка | `fvm flutter build windows --release --no-pub` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (67,2 с) |
| Windows-смоук | `fvm flutter test integration_test/session_smoke_windows_test.dart -d windows --no-pub` | **All tests passed!** (39 с) |
| Ключи UI | `ui_key_contract_test` (в полном прогоне) | 238 ключей, снимок обновлён в шагах |
| Guard миграции | `legacy_material_guard_test` | 13 файлов этапа без AppBar/ListTile/SwitchListTile/FilledButton/SegmentedButton/Card/M3E-виджетов/CircularProgressIndicator/NavigationBar/NavigationRail |
| Guard дизайн-токенов | `design_tokens_test` | baseline burn-down: `Colors.black54` удалён из фикстуры |
| LaTeX-guard | `card_text_test`, `latex_render_fix_test`, `study_mode_latex_test` | зелёные |
| Красная зона | `git diff --stat 4b4cc21..HEAD -- <19 файлов>` | **пусто** |

## Скриншоты и каталог

- `journal/redesign-3/screenshots/` — **48 PNG**: 8 экранов (`shell`, `decks`,
  `deck`, `card-form`, `constructor`, `statistics`, `settings`, `providers`)
  × 2 темы (Nocturne/Porcelain) × 3 ширины (390 / 800 / 1440).
- Golden эталонов экранов — 16 PNG в `test/golden/goldens/screens/`
  (`decks/deck/card-form/constructor/statistics/settings/providers` × dark/light);
  шрифты Onest/Literata/JetBrainsMono и KaTeX подкладываются явно
  (`test/helpers/katex_fonts.dart`).

## Windows-смоук: изменение

Смоук переведён с `pumpAndSettle` на фиксированные кадры (`settle(tester)` —
8 × 250 мс): в реальном процессе фон Aurora дрейфует бесконечно (в
`flutter test` он статичен из-за `FLUTTER_TEST=true`), из-за чего любой
`pumpAndSettle` в `integration_test` на Windows не завершался (8-минутный
таймаут). Это ограничение тестовой инфраструктуры, продукт не менялся.
Также шаг «назад» использует `Icons.arrow_back_rounded` (`NcIconButton`
оболочки), а плитка колоды прокручивается в видимую область перед тапом.

## Коммиты этапа (23)

`aaa3ec1`, `e3d4acb`, `9672704` (3.1); `e4fc69e`, `7211b11`, `266ca6a` (3.2);
`b335ac2`, `752ed65`, `eabf8f6` (3.3); `38511f6`, `e6d8514` (3.4);
`a463fae`, `6d1cc47`, `94e74ff` (3.5); `0f8d86a`, `f1285b7`, `df12936` (3.6);
`4e93db2`, `7287a2b`, `5d7fb08` (3.7); `c7000cd`, `e8c5077`, `214bba5` (3.8);
коммит журнала/verify — этот.

## Известные ограничения этапа

L104–L110 в `journal/KNOWN_LIMITATIONS.md`: миниатюры карточек в списке,
свёрнутый предпросмотр формы, мгновенное раскрытие occlusion, Hero без
перф-замера, Windows-golden без CI-job, ключи никогда не показываются,
подсказка ⌘K — этап 5.
