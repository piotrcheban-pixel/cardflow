# CI-хотфикс: "No space left on device" (после итерации 2)

**Дата:** 2026-11-13 · **Коммит:** `7d124aa` · **Статус:** фикс готов и закоммичен; push — по команде владельца.

## Диагноз

Прогон CI после push итерации 2 упал не по коду и не по существу workflow:
на раннере закончилось место. В логе раннера —
`/home/runner/actions-runner/cached/.../Worker_*.log` — ошибка
`No space left on device`. Логи недоступны из сессии (репозиторий private,
`gh` CLI на хосте нет, GitHub API без токена), поэтому причина принята по
сообщению владельца и по типовой природе ошибки: переполнение диска раннера.

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

- **Реальный прогон CI** — нет: push выполняется только по команде владельца.
  До нового прогона нельзя утверждать, что зелёный.
- **Android-сборка** (`flutter build apk`) — на хосте нет Android SDK/JDK;
  проверка только на CI.
- **Достаточность освобождённого места** — по df-выводу нового прогона.
- **Лог исходного падения** — недоступен (private repo, нет токена/gh).

## Следующее действие

Push фикса `7d124aa` (по команде владельца) → дождаться нового прогона:
- зелёный CI → итерация 3a «Парсеры» по `journal/STATE.md`;
- если Android упадёт снова — открыть лог job'а; при `invalid source release: 21`
  перевести `java-version` в `build-mobile` на `'17'` (отдельный коммит + проверка YAML).
