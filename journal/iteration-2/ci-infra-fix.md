# CI-хотфикс: "No space left on device" (после итерации 2)

**Дата:** 2026-11-13 · **Коммит:** `7d124aa` · **Статус:** фикс готов и закоммичен; push — по команде владельца.

## Диагноз

Прогон CI после push итерации 2 упал не по коду и не по существу workflow:
на раннере закончилось место. Источник — прогон
[`43451932776`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43451932776)
(commit `1b7d156`, push в `main`, 13.11.2026, 3 попытки). Данные получены
read-only через GitHub API (сохранённые учётные данные git credential manager;
секреты не выводились, `gh` CLI на хосте нет).

**Job `build android`, аннотация check-run:**

```
Unhandled exception. System.IO.IOException: No space left on device :
'/home/runner/actions-runner/cached/2.338.2/_diag/Worker_20261113-160553-utc.log'
   at GitHub.Runner.Worker.Program.Main(String[] args)
```

Это падение **самого раннера** (GitHub Runner Worker) при записи своего
диагностического лога: диск раннера был заполнен. Шаги #1–#7 (`checkout`,
`fvm`, `setup-java`, `flutter-action`, `pub get`, `gen-l10n`) прошли, шаг #8
`Сборка Android (debug, без подписи)` завершился failure, job-лог Android
оборван на этапе распаковки кэшей `subosito/flutter-action` (16:06:34) —
раннер не смог дописать лог; загрузка job-лога через API: 404/пустой blob.
Остальные job'ы прогона зелёные: `format + analyze`, `test (ubuntu)` /
`test (windows)`, `build linux` / `build windows` / `build macos` / `build ios`.

**Вторая независимая проблема (не диск):** job `test (macos-latest)` не
получил раннер — аннотация `The job was not acquired by Runner of type hosted
even after multiple attempts` + notice про capacity constraints macOS arm64;
job был в очереди ~15 мин и завершился cancelled вместе с прогоном. К диску
отношения не имеет; при новом прогоне может проявиться снова (GitHub capacity),
это отдельный внешний риск для «зелёного CI».

**Вывод:** инфраструктурная ошибка диска, а не `invalid source release: 21`;
цель фикса (освободить диск до `flutter pub get`) совпадает с местом падения
по времени — раннер заполнился уже на распаковке кэшей Flutter после
`setup-java`.

## Изменения (`.github/workflows/ci.yml`)

1. Во все 4 job'а сразу после `actions/checkout` добавлен шаг `Free disk space`
   (`if: runner.os == 'Linux' || runner.os == 'macOS'`) — до `flutter pub get`:
   - Linux: `rm -rf` для `/usr/share/dotnet`, `/usr/local/lib/android`,
     `/opt/ghc`, `/usr/local/share/boost`, `/opt/hostedtoolcache/CodeQL`,
     `docker image prune --all --force` (две последние операции — под guard'ами);
   - macOS: `rm -rf` для `/Users/runner/Library/Android/sdk`,
     `/Users/runner/Library/Caches/Homebrew`, `/usr/local/share/dotnet`;
   - до и после очистки — `df -h` в лог для диагностики.
2. Исключение: в `build-mobile`/android-job Android SDK **сохраняется**
   (`KEEP_ANDROID_SDK: ${{ matrix.name == 'android' }}`). Удаление
   `/usr/local/lib/android` там сломало бы `flutter build apk` — фикс не должен
   менять одну инфраструктурную ошибку на другую.
3. `build-mobile`/android: новый шаг `Free disk space (Android Gradle cache)`
   перед сборкой — `rm -rf "$HOME/.gradle/caches"` + `df -h`.
4. Существующие шаги не тронуты: сравнение с `HEAD` по каждому job'у показало
   побайтовое совпадение всех старых шагов и сохранение порядка.

## Проверка YAML (в этой сессии)

| Проверка | Результат |
|---|---|
| PyYAML `safe_load` с семантикой YAML 1.2 (ключ `on` — строка) | OK |
| JSON Schema `https://json.schemastore.org/github-workflow.json` (jsonschema 4.26) | OK, ошибок нет |
| `actionlint` v1.7.12 (`-shellcheck=`, локальный бинарь) | 0 findings |
| `bash -n` для всех 21 извлечённого `run`-блока (Git Bash) | OK |
| Структурные assert'ы: шаг очистки — второй в job'е, стоит до `pub get`; нужные пути/`df -h`/`docker prune` присутствуют; Gradle-шаг до `flutter build apk` | все OK |
| `java-version: '21'` не менялся | да — по условию задачи, меняем только при повторном падении Android с `invalid source release: 21` |

Скрипт проверки — временный (`%TEMP%\cardflow-ci-validate\validate_ci.py`),
в репозиторий не коммитится; команды воспроизводимы.

## Не проверено и почему

- **Реальный прогон CI после фикса** — нет: push выполняется только по команде
  владельца. До нового прогона нельзя утверждать, что CI зелёный.
- **Достаточность освобождённого места** — проверится `df -h` нового прогона.
- **Android-сборка** (`flutter build apk`) — на хосте нет Android SDK/JDK;
  проверка только на CI.
- **Текст самой ошибки `flutter build apk`** — в логе отсутствует: раннер
  упал от ENOSPC и не дописал job-лог (шаг #8 без лога); достоверна только
  аннотация про `No space left on device`.
- **`test (macos-latest)`** — внешний GitHub-capacity: job не получил раннер
  (`not acquired ... even after multiple attempts`), к фиксу диска отношения
  не имеет; риск повторения — см. `journal/KNOWN_LIMITATIONS.md` L22.

## Следующее действие

Push фикса `7d124aa` (по команде владельца) → дождаться нового прогона:
- зелёный CI → итерация 3a «Парсеры» по `journal/STATE.md`;
- если Android упадёт снова — открыть лог job'а; при `invalid source release: 21`
  перевести `java-version` в `build-mobile` на `'17'` (отдельный коммит + проверка YAML).

## Итог: новый прогон зелёный (2026-11-13)

После push (`ff32590`) запущен прогон
[`43468349877`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43468349877).

**Попытки:** attempt 1 — 8/9 success, `build ios` cancelled (L22: hosted macOS
arm64 runner не получен за ~15 мин); повторный запуск job'а → attempt 2 —
снова cancelled (L22, тот же текст аннотации); повтор → attempt 3 — снова
cancelled; повтор → **attempt 4 — success, все 9 job'ов зелёные**. Label
`macos-latest` не менялся (по указанию владельца — только перезапуск).

| Job | attempt 4 |
|---|---|
| format + analyze (ubuntu) | success |
| test (ubuntu-latest) | success |
| test (windows-latest) | success |
| test (macos-latest) | success |
| build linux | success |
| build windows | success |
| build macos (macos-latest) | success |
| **build android** | **success** — `✓ Built build/app/outputs/flutter-apk/app-debug.apk` |
| build ios | success |

**Доказательство работы фикса в `build android` (лог job'а):**

```
== df -h до очистки ==
/dev/root        72G   60G   13G  83% /
Android SDK сохранён: нужен для flutter build apk
== df -h после очистки ==
/dev/root        72G   49G   23G  69% /
...
Run flutter build apk --debug
Running Gradle task 'assembleDebug'...  544.6s
✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

Освобождено **+10 ГБ** (13G → 23G свободно), Gradle-сборка прошла с первого
раза — ранее при тех же 13G свободного места раннер падал с ENOSPC. Шаг
`Free disk space (Android Gradle cache)` выполнился перед сборкой (на свежем
раннере кэша ещё не было — `df` не изменился, как и ожидалось).

**Снято:** L21 (фикс диска проверен зелёным прогоном), L22 (macOS-раннеры
получены после перезапусков; коду/конфигурации не требовалось изменений).
