# 03 — План реализации редизайна

**Принцип:** этапы идут по зависимостям; каждый этап заканчивается зелёными
`analyze`/`test`/`format` и отдельным коммитом. Визуальная система (этап A)
— фундамент для всех экранов.

## Этап 0 — Аудит и baseline (2026-11-19)

- Прочитаны `AGENTS.md`, `SPEC.md`, ADR-001…037, `journal/STATE.md`,
  `docs/dependencies.md`, исходники `redesign/2`, снимки.
- Baseline: `git status` — чисто, кроме `?? redesign/`; `HEAD = c50dafe`;
  `analyze` — 0; тесты — **2176 passed + 16 skipped + 1 failed**
  (`no_secrets` находил ключеподобную строку в **неотслеживаемом** снимке
  дизайна `redesign/2/public/assets/aistudio/…`; снимок очищен —
  `sk-ant-…` → `sk-ant-REDACTED`, guard не ослаблен).
- Карта экранов — `01_SCREEN_MATRIX.md`.

## Этап A — Дизайн-система (фундамент)

Файлы: `lib/ui/theme/app_tokens.dart` (новый), `app_typography.dart` (новый),
`app_theme.dart` (переписан), `lib/ui/components/app_layout.dart`,
`app_surfaces.dart`, `app_dialogs.dart` (новые), `pubspec.yaml`
(шрифт Inter), `assets/fonts/Inter-Variable.ttf` + `OFL-Inter.txt`,
`docs/decisions/ADR-038-design-system-v2.md`.

Тесты: `test/unit/ui/app_theme_test.dart` (существующий контракт: шрифт
дислексии, контраст, динамическая схема), widget-тесты экранов.

Критерии: 0 литералов цвета вне `app_tokens.dart`; обе темы собираются;
M3E проецируется из Material; `analyze` 0.

## Этап B — Оболочка

Файлы: `lib/ui/shell/app_shell.dart` (переписан), `app_sidebar.dart`,
`app_top_header.dart` (новые), `lib/ui/state/decks_ui_providers.dart`
(`totalDueCardsProvider`, `allDeckSummariesProvider`, сортировка/вид).

Тесты: `test/widget/shell_test.dart` (переписан под панель/Drawer, все
разделы, глобальное действие), `test/widget/app_test.dart` (иконка настроек).

Критерии: все 19 маршрутов доступны; мобильный Drawer; нет `NavigationBar`.

## Этап C — Колоды и колода (зависит от A, B)

Файлы: `lib/ui/decks/decks_screen.dart` (переписан), `deck_screen.dart`
(переработка), `deck_actions.dart` (диалоги на `AppDialog`).

Тесты: `decks_screen_test.dart` (обновлён под новую оболочку + скролл),
`deck_screen_test.dart`, `create_deck_dialog_test.dart`, `import_export_test.dart`.

Критерии: реальные счётчики, поиск/фильтры/сортировка/вид, архив+undo,
создание/переименование/экспорт/импорт/удаление работают.

## Этап D — Обучение и все режимы (зависит от A)

Файлы: `ui/review/review_chrome.dart`, `review_toolbar.dart`,
`review_card_view.dart`, `review_session_screen.dart`,
`feed_session_screen.dart`, `feed_card_view.dart`, `practice_session_screen.dart`,
`ui/study/study_session_chrome.dart`, `multiple_choice_screen.dart`,
`typing_screen.dart`, `match_screen.dart`, `true_false_screen.dart`.

Тесты: `review_session_screen_test.dart`, `feed_session_screen_test.dart`,
`practice_session_screen_test.dart`, `study_modes_test.dart`,
`study_mode_latex_test.dart`, `match_and_true_false_test.dart`,
`card_markup_session_test.dart`.

Критерии: все режимы визуально едины; FSRS, undo, лимиты, таймеры, LaTeX,
cloze, occlusion, медиа работают.

## Этап E — ИИ-генерация (зависит от A)

Файлы: `ui/generation/generation_screen.dart`, `generation_preview_screen.dart`,
`generation_error_message.dart` (без изменений логики).

Тесты: `generation_screen_test.dart`, `generation_preview_screen_test.dart`,
`generation_entry_test.dart`, `generation_preview_partial_test.dart`.

Критерии: форма/параметры/провайдеры/количество/прогресс/отмена/ошибки/
предпросмотр/импорт — реальные; подписи секций как в макете.

## Этап F — Статистика и настройки (зависит от A, B)

Файлы: `ui/statistics/statistics_screen.dart`, `statistics_charts.dart`,
`ui/settings/settings_screen.dart`, `generation_settings_screen.dart`,
`provider_account_dialogs.dart`.

Тесты: `statistics_screen_test.dart`, `settings_screen_test.dart`,
`generation_settings_screen_test.dart`, `app_settings_applied_test.dart`.

Критерии: только реальные данные; все настройки применяются; провайдеры —
аккаунты, ключи не показываются.

## Этап G — Карточки, конструктор, диалоги (зависит от A)

Файлы: `ui/cards/card_form_screen.dart`, `occlusion_mask_editor.dart`,
`ui/session/session_constructor_screen.dart`, `ui/settings/provider_account_dialogs.dart`.

Тесты: `card_form_screen_test.dart`, `card_markup_form_test.dart`,
`session_constructor_screen_test.dart`.

## Этап H — Унификация и QA

- Проход по всем экранам: нет остатков старого оформления (`Card`,
  `AppBar`-заголовки, `ListTile`-строки без системы), нет мёртвых кнопок.
- Скриншоты 1440×900, 1024×768, 390×844 → `journal/redesign/screenshots/`,
  сравнение с референсами → `04_VISUAL_QA.md`.
- Финальные гейты: `analyze` 0, тесты зелёные, покрытие ≥80 %, `format`
  0 changed, `build windows`.

## Коммиты (английский префикс, тело по-русски)

1. `feat(ui): introduce redesign token and theme system`
2. `feat(ui): redesign application shell and navigation`
3. `feat(ui): redesign decks screens`
4. `feat(ui): redesign study experience`
5. `feat(ui): redesign generation screens`
6. `feat(ui): redesign statistics and settings`
7. `feat(ui): redesign card forms and constructor`
8. `test(ui): add redesign regression coverage`
9. `docs: document application redesign`

Push не выполняется без отдельного разрешения владельца.

## Фактическое выполнение (2026-11-19)

| Этап | Коммит | Содержание |
|---|---|---|
| A | `8c0d544` | токены, типографика Inter, тема, общие компоненты, ADR-038 |
| B | `cc84ba8` | оболочка: панель/шапка/Drawer, провайдеры, тесты оболочки |
| C | `2bfea53` | экран «Мои колоды», тесты колод |
| D | `9ae3b93` | каркас сессии и все режимы обучения |
| E | `a3f8048` | генерация и предпросмотр |
| F | `cd7af12` | статистика и настройки, провайдеры ИИ |
| G | `0f205a2` | экран колоды, форма карточки, конструктор |
| H | (этот коммит) | компонентные тесты, визуальный QA, документация |

Визуальная проверка — `04_VISUAL_QA.md`; скриншоты —
`journal/redesign/screenshots/`.
