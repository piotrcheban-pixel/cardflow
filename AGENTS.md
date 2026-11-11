# AGENTS.md — устойчивые правила CardFlow

CardFlow — кроссплатформенное нативное Flutter-приложение для интервального повторения (FSRS). Единственный источник правды о продукте — `SPEC.md` в корне; процесс — `docs/agent-prompt.md`. Этот файл — краткие постоянные соглашения, не журнал.

## Окружение и команды

- Flutter закреплён через **FVM** (`.fvmrc`), версия — в `docs/dependencies.md`.
- Все команды — только через FVM: `fvm flutter pub get`, `fvm flutter test`, `fvm flutter analyze`, `fvm dart format .`, `fvm flutter gen-l10n`, `fvm flutter test --coverage`.
- Новые зависимости — только после проверки на pub.dev и записи в `docs/dependencies.md`; запрещённые WebView/HTML-пакеты — стоп.
- `docs/decisions/ADR-*.md` — принятые решения; при конфликте SPEC с реальностью — ADR, а не правка SPEC.

## Архитектура (`lib/`)

- `domain/` — сущности, оценки `Rating` (Again/Hard/Good/Easy), FSRS-адаптер, бизнес-правила. **Без импортов Flutter.**
- `data/` — drift, репозитории, импорт/экспорт.
- `api/` — провайдеры, DTO, валидация, промпты, парсеры файлов.
- `ui/` — экраны, виджеты, локализация. Компоненты M3 Expressive — только через слой `lib/ui/m3e/` (библиотеку можно заменить). Токены движения — `lib/ui/motion.dart`.
- Модели immutable (`freezed`/`const`), роутинг `GoRouter` (см. ADR), HTTP `Dio`. Состояние — Riverpod 3 без кодогенерации (ADR-002).
- **Material-виджеты — только `package:material_ui/material_ui.dart`** (ADR-001), `package:flutter/material.dart` в `lib/` запрещён. M3E-компоненты — только через `lib/ui/m3e/`, библиотека `material_3_expressive` больше нигде не импортируется.
- Никаких литералов пользовательского текста в виджетах: только `AppLocalizations` из `lib/l10n/app_ru.arb`.

## Жёсткие запреты

- Локаль только `ru`; `supportedLocales: [Locale('ru')]`; системные строки Flutter — через `GlobalMaterialLocalizations`.
- Никаких WebView/HTML-обёрток, включая транзитивные зависимости (guard-тест по `pubspec.lock`). LaTeX — только `flutter_math_fork`.
- Ключи API — только `flutter_secure_storage`; вне кода, логов, БД, экспорта, git. В логах редактировать `Authorization`, `x-api-key`, `x-goog-api-key`. Значения ключей не выводить в терминал; проверка — present/absent.
- Сырые ошибки API/исключения пользователю не показывать — только сообщения из ARB.
- Никаких мёртвых кнопок и заглушек: функция либо работает, либо её нет (фича-флаг выключен).
- Нельзя ослаблять/удалять тесты, отключать анализатор, ставить `// ignore:` без ADR, понижать порог покрытия.

## Тесты и качество

- TDD: падающий тест → минимальная реализация → зелёный. Покрытие рукописного кода ≥80% (сгенерированное не считается).
- Guard-тесты: `test/guards/no_webview_test.dart`, `ru_strings_test.dart`, `no_secrets_test.dart`, `architecture_test.dart` (framework-Material в `lib/` запрещён, M3E — только в `lib/ui/m3e/`, domain без Flutter).
- Golden-тесты — под тегом `golden`, шрифты с кириллицей подкладываются явно; генерируются/прогоняются на Linux CI.
- Live-тесты API — под тегом `live`, только при наличии ключей в окружении (иначе skip).
- `flutter analyze` — 0 issues; `dart format` применён.

## Процесс

- Цикл итерации: plan → test → implement → review → verify → remember → improve. После каждого шага — обновить `journal/STATE.md`.
- Коммит после каждого зелёного шага (conventional commit: английский префикс, тело по-русски). Push — только в конце итерации по подтверждению.
- Внешний блокер (нет ключа, нет платформы, нет CI) — известное ограничение в `journal/KNOWN_LIMITATIONS.md` + mock-тест, а не остановка.
- Одна и та же ошибка пережила 3 попытки — стоп, гипотезы в журнал, смена подхода.
- Не заявлять «готово» без команды и её вывода в текущей сессии.
- **Ретроспектива итерации 0 (улучшение процесса с итерации 1):** красная фаза должна сохранять фрагмент вывода с *ожидаемым* поведением (assertion-level, «ожидалось: X, получено: Y»), а не только ошибку компиляции; и — отдельный коммит на каждый зелёный шаг (red / green / verify / docs), а не один коммит на итерацию.

## Факты хоста (обновлять при изменении)

- Windows 11; Android SDK/JDK/Xcode отсутствуют → локально проверяем `flutter test/analyze` и `flutter build windows`; остальные сборки — CI/известное ограничение.
- FVM 4.3.2; Flutter 3.47.9 (Dart 3.13.7). Все команды — через `fvm` (`fvm flutter …`).
- Windows-сборка CardFlow пока падает из-за отсутствия ATL в VS Build Tools (`atlstr.h` у `flutter_secure_storage_windows`); bare Flutter-проект собирается успешно → это ограничение хоста, не кода (KNOWN_LIMITATIONS L2b).
- Хуки DSH (block-hardcoded-secret, block-destructive-command, confirm-git-push, GateGuard) на момент итерации 0 не подключены — известное ограничение; создавать/обходить их самостоятельно нельзя.
