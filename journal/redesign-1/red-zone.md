# Красная зона и экраны: проверка этапа 1

**Дата:** 2026-11-17 · Диапазон: `7458346..HEAD` (старт редизайна → verify).

## Красная зона (REDESIGN-PLAN: «ни одной правки»)

19 файлов:

- `lib/ui/state/app_providers.dart`
- `lib/ui/state/decks_ui_providers.dart`
- `lib/ui/state/review_limits.dart`
- `lib/ui/router/app_router.dart`
- `lib/ui/review/review_session_engine.dart`
- `lib/ui/review/feed_session_engine.dart`
- `lib/ui/review/practice_session_engine.dart`
- `lib/ui/review/feed_swipe.dart`
- `lib/ui/review/review_interval_format.dart`
- `lib/ui/review/session_media.dart`
- `lib/ui/study/study_session_controller.dart`
- `lib/ui/generation/generation_error_message.dart`
- `lib/ui/generation/generation_failure_message.dart`
- `lib/ui/generation/parser_error_message.dart`
- `lib/ui/decks/archive_error_message.dart`
- `lib/ui/decks/deck_archive_file_name.dart`
- `lib/ui/settings/external_link_launcher.dart`
- `lib/ui/settings/about_links.dart`
- `lib/ui/cards/content/latex_spans.dart`

Вывод команды:

```text
git diff --stat 7458346..HEAD -- <19 файлов Красной зоны>
```

**Пусто: изменений нет (0 файлов, 0 строк).**

## Экраны, кадры сессий и оболочка (этап 1 их не трогает)

```text
git diff --stat 7458346..HEAD -- 'lib/ui/**/*_screen.dart' 'lib/ui/**/*_view.dart' \
  lib/ui/review/review_toolbar.dart lib/ui/shell/app_shell.dart
```

**Пусто: изменений нет (0 файлов, 0 строк).**

## Полный дифф этапа (56 файлов, +6615 / −36)

```text
 assets/fonts/JetBrainsMono/JetBrainsMono-Variable.ttf | Bin 0 -> 187208 bytes
 assets/fonts/LICENSES/JetBrainsMono-OFL.txt            |  93 +++
 assets/fonts/LICENSES/Literata-OFL.txt                 |  93 +++
 assets/fonts/LICENSES/Onest-OFL.txt                    |  93 +++
 assets/fonts/Literata/Literata-Variable.ttf            | Bin 0 -> 955132 bytes
 assets/fonts/Onest/Onest-Variable.ttf                  | Bin 0 -> 193056 bytes
 assets/textures/grain.png                              | Bin 0 -> 15314 bytes
 docs/decisions/ADR-035-nocturne-design-system.md       | 141 +++++
 docs/dependencies.md                                   |   2 +
 lib/main.dart                                          |   5 +
 lib/ui/app.dart                                        |  33 +-
 lib/ui/design/**                                       | ~2100 +++++
 lib/ui/motion.dart                                     | 122 +++-
 lib/ui/theme/app_theme.dart                            | 351 ++++++++++-
 pubspec.yaml / pubspec.lock                            |  28 +-
 test/**                                                | ~2900 +++++
 tool/extract_ui_keys.dart                              | 331 ++++++++++
 journal/redesign-1/**                                  |  —
```

`lib/` изменён ровно в четырёх существующих файлах — `main.dart`,
`ui/app.dart`, `ui/motion.dart`, `ui/theme/app_theme.dart` (все разрешены
планом этапа); остальное — новый `lib/ui/design/**`.

## Вывод

Ни одного изменения в Красной зоне и ни одного изменения в экранах: цель
этапа — «всё приложение выглядит в Nocturne за счёт `ThemeData`» — достигнута
без правок визуального слоя экранов.
