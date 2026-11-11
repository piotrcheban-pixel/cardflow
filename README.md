# CardFlow

Кроссплатформенное нативное приложение для интервального повторения на FSRS (Windows, macOS, Linux, Android, iOS). Flutter, локальные данные, генерация карточек через API пользователя. Источник правды о продукте — [SPEC.md](SPEC.md), процесс разработки — [docs/agent-prompt.md](docs/agent-prompt.md), текущее состояние — [journal/STATE.md](journal/STATE.md).

## Требования

- [FVM](https://fvm.app) — версия Flutter закреплена в `.fvmrc`
- Flutter 3.47.9 stable (Dart 3.13.7) — устанавливается FVM
- Windows: Visual Studio Build Tools с C++-тулчейном (+ ATL для `flutter_secure_storage` на Windows — см. `journal/KNOWN_LIMITATIONS.md`, L2b)
- Android: Android SDK + JDK; iOS/macOS: Xcode (только macOS)

## Команды

```sh
fvm install                 # поставить закреплённый Flutter (3.47.9)
fvm flutter pub get
fvm flutter gen-l10n        # lib/l10n/app_ru.arb -> lib/l10n/app_localizations*.dart
fvm flutter test            # юнит-, widget- и guard-тесты
fvm flutter test --coverage && fvm dart run tool/coverage_check.dart --min=80
fvm flutter analyze         # 0 issues
fvm dart format .
fvm flutter run -d windows  # или android/ios/linux/macos
```

## Структура

- `lib/domain/` — сущности, оценки (`Rating`), FSRS-адаптер, бизнес-правила (без Flutter).
- `lib/data/` — drift, репозитории, импорт/экспорт (итерации 1+).
- `lib/api/` — провайдеры, валидация, парсеры файлов (итерации 3a–3c).
- `lib/ui/` — экраны, тема, токены движения (`motion.dart`), M3E-слой (`m3e/`), локализация.
- `test/guards/` — обязательные guard-тесты (нет WebView, русские строки, нет секретов).
- `docs/` — ADR, схема API, парсеры, зависимости; `journal/` — состояние и журнал итераций.

## Статус

Итерация 0 (каркас) завершена: проект под 5 платформ, FVM, локализация `ru`, Material-база `material_ui`, M3E-фасад с проверенными токенами, guard-тесты, CI-матрица, доменный `FsrsScheduler` с тестами интервалов, покрытие рукописного кода 100% (135/135), `flutter analyze` — 0 issues. Дальше — итерация 1 (Колоды + drift).
