# Известные ограничения CardFlow

Формат: ограничение → причина → чем компенсировано в коде/тестах → когда снимается.
Каждое ограничение подтверждено фактом в текущей сессии; «проверено живьём» без доказательства не пишется.

## Окружение

| # | Ограничение | Причина | Компенсация | Снятие |
|---|---|---|---|---|
| L1 | Живые вызовы OpenAI / Gemini / Anthropic не проверялись | в окружении нет ключей API (проверено в итерации 0: present = нет) | mock/integration-тесты на адаптеры и пайплайн; live-тесты под тегом `live` и skip без ключей | когда владелец даст ключ |
| L2 | Сборки Android/iOS/macOS/Linux локально не выполняются | на хосте нет Android SDK/JDK, Xcode/macOS, Linux | CI-матрица (ubuntu/windows/macos); Windows-тулчейн проверен bare-проектом | на соответствующих раннерах |
| L2b | Локально `flutter build windows` для CardFlow падает: `atlstr.h: No such file or directory` (плагин `flutter_secure_storage_windows`). **В CI `build windows` проходит** (windows-latest содержит ATL) | в VS Build Tools 2026 не установлен компонент «C++ ATL» (`vswhere -requires Microsoft.VisualStudio.Component.VC.ATL` → пусто); установка требует прав администратора. Bare Flutter-проект собирается успешно (тулчейн/MSVC/Developer Mode работают) | сборка Windows вынесена в CI (windows-latest содержит ATL); локально проверены `flutter test`/`analyze`/`coverage` | владелец установит ATL-компонент в VS Installer либо CI даст артефакт |
| L3 | ~~CI фактически не запускался~~ **снято 2026-11-11**: репозиторий GitHub создан, CI запускается; первый прогон выявил 2 дефекта (guard-тест путей на CI — исправлен; отсутствие `libsecret-1-dev` — добавлено). Повторный прогон — см. `journal/iteration-0/verify.md` §10 | — | — |
| L4 | Хуки `block-hardcoded-secret`, `block-destructive-command`, `confirm-git-push`, GateGuard не срабатывают | в конфигурации DSH-профиля хуки не подключены (проверено) | правила соблюдаются вручную; guard-тест `no_secrets_test.dart` | когда владелец подключит хуки |
| L5 | Навыки `tdd-workflow`, `dart-flutter-patterns`, `flutter-dart-code-review`, `material-3-skill`, `api-design`, `security-review`, `verification-loop`, `coding-standards` недоступны | в каталоге навыков сессии их нет (проверено) | работа по правилам `docs/agent-prompt.md` | когда навыки появятся в каталоге |
| L6 | Golden-тесты не прогоняются локально | в итерации 0 golden-тестов нет; стандартные шрифты Flutter не содержат кириллицы | при появлении golden: тег `golden`, явный шрифт с кириллицей, Linux CI | на Linux CI |
| L6b | M3E-виджеты (`M3EMaterialApp`, `M3ETheme`) ещё не используются в UI | в итерации 0 нет ни одного экрана с компонентами; спайк S2 завершается в итерации 1 | фасад `lib/ui/m3e/`, токены сверены тестом; fallback-план в ADR-001 | итерация 1 (экран «Колоды») |
| L6c | Dynamic color (A4.1) ещё не подключён в UI | настройка внешнего вида — итерация 7; пакет `dynamic_color` 2.1.0 (Apache-2.0, material.io) добавлен заранее | тема пока строится из бренд-сида (`ColorScheme.fromSeed`); переключатель будет в настройках | итерация 7 |

## Продукт (перенесено из SPEC / ADR)

| # | Ограничение | Причина | Компенсация | Снятие |
|---|---|---|---|---|
| L7 | Форматы `.doc` / `.xls` не поддерживаются | нет зрелого Dart-пакета для чтения CFB (ADR-003); `.xls`-кандидаты (`excel_plus`) — спайк итерации 3a | понятное сообщение «Формат не поддерживается. Сохраните файл как DOCX или XLSX и попробуйте снова» | по решению владельца |
| L8 | Drag-n-drop на ПК реализуется `desktop_drop 0.8.4`, а не 0.9.2 | несовместимость `cross_file` между `desktop_drop >=0.9` и `file_picker >=12` (docs/dependencies.md §7) | выбран один DnD-пакет (SPEC A3); API стабилен | пересмотр в итерации 3c (A6.8) |
