# Итерация «Релиз v1.0.0» — 2026-11-25

**Задача:** подготовить проект к версии `1.0.0`, собрать Windows-артефакт,
перевести Android-сборку CI на `--release` и опубликовать APK в Artifacts,
закоммитить, поставить тег `v1.0.0` и дождаться зелёного CI.

**Факты старта:** `git status --porcelain` — только неотслеживаемые рабочие
артефакты аудита (`audit/`, `review_visual/`, `review_final/`, ~186 МБ
скриншотов/утилит, они не входят в релизный коммит); `HEAD = 013b921`,
ветка `main`, `origin/main = 36f8738` (локально на 10 коммитов впереди);
тегов в репозитории нет; версия в `pubspec.yaml` уже `1.0.0+1`
(изменена коммитом `91726d9`), `schemaVersion` БД не менялся.

## Шаг 1. Подготовка кода

- `pubspec.yaml`: `version: 1.0.0+1` — уже целевая, правка не потребовалась.
- `fvm flutter clean` — build/, .dart_tool/ и ephemeral-файлы удалены.
- `fvm flutter pub get` — `Got dependencies!` (по `pubspec.lock`, без правок).

## Шаг 2. Сборка Windows (.exe)

```
fvm flutter build windows --release --no-pub
131,7 s
√ Built build\windows\x64\runner\Release\cardflow.exe
```

`cardflow.exe` — 91 648 Б, `FileVersion`/`ProductVersion` = `1.0.0+1`
(версия из pubspec попала в бинарник). Рядом — `pdfium.dll`, `sqlite3.dll`,
Flutter- и плагин-DLL, каталог `data/`.

## Шаг 3. Android в CI

- `.github/workflows/ci.yml`, job `build-mobile`: шаг
  `flutter build apk --debug` заменён на `flutter build apk --release`.
- Добавлен шаг `Загрузка APK` (`actions/upload-artifact@v5`, имя артефакта
  `cardflow-android-release-apk`, путь
  `build/app/outputs/flutter-apk/app-release.apk`, `if-no-files-found: error`).
- Подпись релиза уже настроена в `android/app/build.gradle.kts`
  (`buildTypes.release.signingConfig = signingConfigs.getByName("debug")`) —
  правка не потребовалась, APK из CI устанавливается на телефон как есть.

## Гейты на релизном снимке (2026-11-25)

| Проверка | Результат |
|---|---|
| `fvm dart format --set-exit-if-changed lib test integration_test tool` | 598 файлов, **0 changed** |
| `fvm flutter analyze --no-pub` | **No issues found!** (15,1 с) |
| `fvm flutter test --no-pub --exclude-tags golden` | **2678 passed + 16 skipped**, `All tests passed!` |
| `fvm flutter build windows --release --no-pub` | `cardflow.exe`, FileVersion `1.0.0+1` |

Живых API-запросов не было; схема БД, `schemaVersion` и `format_version`
не менялись.

## Ограничения

- Android SDK/JDK локально отсутствуют: APK собирается только в CI
  (`build-mobile` → `cardflow-android-release-apk` в Artifacts прогона).
- APK подписан debug-ключом Flutter: для установки и ручной проверки этого
  достаточно, для публикации в Google Play нужен собственный upload-ключ.
- iOS без подписи (`--no-codesign`), как и раньше.
