# Итерация 1 — красная фаза UI (ui-decks)

**Дата:** 2026-11-12 · **Владелец:** ui-decks · **Задача:** task-3 (итерация 1, пп. 1.6–1.8)
**TDD:** тесты написаны до реализации; red-прогоны ниже — до кода экранов/функций.
Полные логи: `build/red-widget-ui.log`, `build/red-unit-archive.log`,
`build/red-unit-filename.log` (временные, не коммитятся).

## 0. M3E runtime-спайк S2 — выполнен до экранов (успех)

Harness: `ProviderScope` не нужен для спайка; `MaterialApp` (`material_ui`) +
`M3ETheme(data: M3EThemeData.light/dark(seedColor: AppTheme.seedColor))` в
`builder` + локаль `ru` с делегатами `material_ui`
(`GlobalMaterialLocalizations.delegates`; `AppLocalizations.localizationsDelegates`
не подходит — там framework-делегаты, MaterialLocalizations не находятся).

`fvm flutter test test/widget/m3e/m3e_spike_test.dart` → **+4: All tests passed!**

Реально рендерятся в widget-тесте под `M3ETheme`:

- `M3ECard` (structured slots headline/subhead/supportingText, onPressed) — ✓;
- `M3EChip` type filter (selected/onPressed) — ✓;
- `M3ESnackbar.show(context, message, actionLabel, onAction)` — ✓ (action нажимается);
- `M3EExtendedFab` (label/icon/onPressed) — ✓;
- `M3ESplitButton<String>` (label, items `M3ESplitButtonItem(value:, child:)`,
  leadingIcon, trailingTooltip) — ✓.

Не потребовалось заменять M3E-компоненты на `material_ui`. `M3EMaterialApp`
не используется (не принимает `routerConfig`/GoRouter) — тема в `builder`.

## 1. Unit-тесты: маппинг ошибок архива и имя файла экспорта

`fvm flutter test test/unit/ui/archive_error_message_test.dart` (заглушка
`archiveErrorCodeMessage → ''`):

```
00:00 +0 -1: ... все коды ArchiveErrorCode покрыты и различаются [E]
  Expected: 'Версия архива не поддерживается. Обновите CardFlow.'
    Actual: ''
00:00 +1 -2: ... неизвестная ошибка → общая строка без текста исключения [E]
  Expected: 'Не удалось выполнить операцию с архивом. Попробуйте ещё раз.'
    Actual: ''
00:00 +1 -3: ... обычная ошибка импорта не раскрывает сообщение [E]
  Expected: 'Не удалось выполнить операцию с архивом. Попробуйте ещё раз.'
    Actual: ''
```

`fvm flutter test test/unit/ui/deck_archive_file_name_test.dart` (заглушка
`deckArchiveFileName → deckName`):

```
00:00 +0 -1: ... добавляет расширение .zip [E]
  Expected: 'Испанский.zip'
    Actual: 'Испанский'
00:00 +0 -2: ... обрезает внешние пробелы и схлопывает внутренние [E]
  Expected: 'Моя колода.zip'
    Actual: '  Моя   колода  '
00:00 +0 -3: ... убирает недопустимые для файловой системы символы [E]
  Expected: a string ending with '.zip'
    Actual: 'Моя/колода\\для:тест*?"<>|'
00:00 +0 -4: ... пустое/пробельное имя заменяется запасным из ARB [E]
  Expected: 'Колода.zip'
    Actual: '   '
00:00 +0 -5: ... имя только из недопустимых символов заменяется запасным [E]
  Expected: 'Колода.zip'
    Actual: '///:::'
00:00 +0 -6: ... слишком длинное имя обрезается до безопасной длины [E]
  Expected: a string ending with '.zip'
    Actual: 'Очень длинное название колоды аааа…'
00:00 +0 -7: ... кириллица, цифры и дефисы сохраняются [E]
  Expected: 'Колода-2 (часть 1).zip'
    Actual: 'Колода-2 (часть 1)'
```

## 2. Widget-тесты экранов «Колоды»/«Колода»/импорт-экспорт — до реализации

Экраны на момент прогона — заглушки `Scaffold(body: SizedBox.shrink())`.
Команда: `fvm flutter test test/widget/decks` → **`00:01 +0 -31: Some tests failed.`**

Фрагменты (assertion-level, ожидалось/получено):

```
00:00 +0 -1: Колоды: состояния загрузки данных loading: индикатор загрузки и заголовок из ARB
  Expected: exactly one matching candidate
    Actual: _TypeWidgetFinder:<Found 0 widgets with type "CircularProgressIndicator": []>
00:00 +0 -2: Колоды: состояния загрузки данных empty: пустое состояние с кнопкой создания
  Expected: exactly one matching candidate
    Actual: _TextWidgetFinder:<Found 0 widgets with text "Пока нет колод": []>
00:00 +0 -3: Колода: шапка и карточки заголовок, счётчики и список карточек
  Expected: exactly one matching candidate
    Actual: _TextWidgetFinder:<Found 0 widgets with text "Испанский": []>
00:00 +0 -4: Колоды: состояния загрузки данных error: сообщение из ARB, без сырого текста; retry грузит данные
  Expected: exactly one matching candidate
    Actual: _TextWidgetFinder:<Found 0 widgets with text "Не удалось загрузить колоды": []>
00:00 +0 -5: Колоды: состояния загрузки данных success: колоды с счётчиками (M3ECard)
  Expected: exactly 2 matching candidates
    Actual: _TypeWidgetFinder:<Found 0 widgets with type "M3ECard": []>
...
00:01 +0 -31: Колоды: навигация тап по карточке открывает экран колоды
  The finder "Found 0 widgets with text "Испанский": []" (used in a call to "tap()")
  could not find any matching widgets.
```

Дополнительно (после первого зелёного прогона, до правки диалогов) найдена
реальная ошибка: `TextEditingController was used after being disposed` —
контроллер освобождался сразу после `Navigator.pop`, пока диалог ещё
анимированно закрывался. Исправлено переносом контроллера в `State`
диалога `_DeckNameDialog` (dispose в `State.dispose`).

## 3. Зелёный прогон (после реализации)

`fvm flutter analyze` → **No issues found!** (9.4s, весь репозиторий).

`fvm flutter test test/widget test/unit/ui test/guards` → **`+92: All tests passed!`**
(включая `test/guards`: ru_strings, architecture, no_secrets, no_webview).

Ключевые команды шага: `fvm flutter gen-l10n`; `fvm dart format lib/ui lib/l10n
test/widget test/helpers test/unit/ui` → 25 files, 0 changed (стабильно при
повторе). Red-логи: `build/red-widget-ui.log`, `build/red-unit-archive.log`,
`build/red-unit-filename.log`.
