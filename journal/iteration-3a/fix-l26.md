# L26 — PDF-тесты в CI на Linux/macOS: PDFium bootstrap

**Дата:** 2026-11-13 · **Связано:** L26 (`journal/KNOWN_LIMITATIONS.md`), ADR-010 §9, SPEC A8.3
**Снимок до фикса:** `a406993` (итерация 3a) · **CI-прогон с падением:** [`43484685899`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43484685899)

## Red: что именно падало

`test (ubuntu-latest)` и `test (macos-latest)` — failure на шаге #8 «Тесты (кроме golden)»:
**586 passed / 2 failed**. Оба падения — `(setUpAll)` двух файлов:

- `test/unit/api/parsers/pdf_parser_test.dart: (setUpAll)`;
- `test/integration/file_parsing_pipeline_test.dart: (setUpAll)`.

Причина (из логов job'ов): `setUpAll` вызывает `await pdfrxInitialize();`, и PDFium не загружается.

**Linux (ubuntu-latest):**
```
Failed to load PDFium module:
Tried to load the default PDFium module ".../engine/linux-x64/lib/libpdfium.so"
but it failed: Failed to load dynamic library '...': cannot open shared object file: No such file or directory.
Then tried to load the bundled native asset, but that also failed: Exception: Native assets file not found.
```

**macOS (macos-latest):**
```
Failed to load PDFium module:
Tried to load the default PDFium module but it failed: Unsupported operation: Unsupported platform.
Then tried to load the bundled native asset, but that also failed: Exception: Native assets file not found.
```

**Почему так:** `pdfrx`/`pdfium_dart` 0.4.1 в `flutter test`:
- Linux — ищет `libpdfium.so` в кэше Flutter engine (его там нет в тестовом окружении) и в
  `.dart_tool/native_assets.yaml` (в CI-тесте файла нет);
- macOS — чистый Dart-загрузчик `pdfium_dart` не поддерживает macOS («Unsupported platform»), а
  bundled native asset отсутствует;
- Windows — работает (локально и в CI `test (windows-latest)` зелёный): загрузчик находит `pdfium.dll`.

Т.е. это ровно известный риск L26 — PDFium не доступен тестовому раннеру на Linux/macOS, хотя
`pdfrx` заявлен и работает на Windows; PDF-парсер при этом исправен (все 586 остальных тестов на обеих
ОС зелёные, сборки всех платформ тоже).

## Красная фаза фикса (тест)

Добавлен guard-тест `test/guards/ci_pdfium_test.dart`: workflow обязан скачивать PDFium и экспортировать
`PDFIUM_PATH` до шага тестов; PDF-тесты не должны скипаться (`skip`/`markTestSkipped`/тег `pdf`).

Прогон до правки workflow — **красный**, как ожидалось:

```
00:00 +1 -2: Some tests failed.
Failing tests:
  test/guards/ci_pdfium_test.dart: workflow: job test скачивает PDFium из pinned-релиза для Linux/macOS
    Which: does not contain 'PDFium для PDF-тестов' (нет шага бутстрапа PDFium в job test)
  test/guards/ci_pdfium_test.dart: workflow: PDFium-шаг стоит до шага тестов и не в build-job
    Expected: a value greater than <0>  Actual: <-1>
```

(Третий guard — «PDF-тесты не пропускаются молча» — проходит уже сейчас: он фиксирует политику
«зелёный = реальный прогон, а не выключенные тесты».)

## Выбранное направление

**Вариант A (CI-шаг с PDFium)**, а не skip/тег:

- PDF-тесты **реально выполняются** на всех трёх ОС — критерий честности сильнее, чем skip;
- используется **тот же релиз PDFium**, который `pdfium_dart` 0.4.1 скачивает своим build-hook
  (`bblanchon/pdfium-binaries`, `chromium/8125`, `VERSION BUILD=8125`), т.е. версия API совпадает;
- `pdfrxInitialize()` уже поддерживает `PDFIUM_PATH` (pdfrx_engine читает env и передаёт путь в
  `getPdfium(modulePath: ...)`) — код приложения менять не нужно, фикс локализован в CI;
- проверено локально: с `PDFIUM_PATH=<pdfium.dll>` PDF-тесты проходят через явный путь модуля
  (механизм env-переменной рабочий); архивы `pdfium-linux-x64.tgz` / `pdfium-mac-arm64.tgz` содержат
  ровно `lib/libpdfium.so` и `lib/libpdfium.dylib` (пути в шаге CI проверены);
- цена — ~4 МБ загрузки на два тестовых job'а, один шаг в workflow; сборки (build-*) не затрагиваются —
  им бутстрап не нужен (тесты там не гоняются).

Skip/тег отклонены: они скрывают регрессии PDF-парсера на 2/3 CI-матрицы; вариант A даёт реальное
покрытие при минимальном риске (pinned-релиз, тот же, что в build-hook).

## Green: изменение workflow (коммит `6a43b93`)

В job `test` (единственный, который гоняет тесты) после `subosito/flutter-action`
добавлен шаг **«PDFium для PDF-тестов (Linux/macOS)»** (`if: runner.os != 'Windows'`):

- `curl -fsSL --retry 3` качает `pdfium-linux-x64.tgz` / `pdfium-mac-arm64.tgz` из
  `https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F8125/...`;
- `tar -xzf` во `$RUNNER_TEMP/pdfium`, проверяется наличие `lib/libpdfium.so` /
  `lib/libpdfium.dylib`;
- путь экспортируется как `PDFIUM_PATH=...` в `$GITHUB_ENV` → доступен шагу тестов;
- на Windows шаг пропускается (там `pdfium.dll` находится сам).

`pdfrxInitialize()` (pdfrx_engine) читает `PDFIUM_PATH` и передаёт путь в
`getPdfium(modulePath: ...)` → `DynamicLibrary.open` по явному пути; на macOS это
обходит ветку «Unsupported platform», на Linux — отсутствие `libpdfium.so` в кэше
Flutter engine и `Native assets file not found`. Код приложения/парсеров не менялся.

**Проверка YAML и окружения (локально):**

| Проверка | Результат |
|---|---|
| PyYAML, семантика YAML 1.2 (`on` — строка) | OK |
| JSON Schema SchemaStore `github-workflow.json` | OK |
| `actionlint` 1.7.12 (`-shellcheck=`) | 0 findings |
| `bash -n` всех `run`-блоков | OK |
| Состав job'ов и шаги `quality`/`build-desktop`/`build-mobile` побайтово равны HEAD | OK |
| Шаг `PDFium для PDF-тестов` — только в job `test`, до шага тестов | OK |
| Ассеты `chromium/8125` существуют: `pdfium-linux-x64.tgz` (3.65 МБ), `pdfium-mac-arm64.tgz` (3.38 МБ) | OK |
| Внутри архивов: `lib/libpdfium.so` / `lib/libpdfium.dylib`, `VERSION BUILD=8125` (совпадает с build-hook `pdfium_dart` 0.4.1) | OK |
| `PDFIUM_PATH=<pdfium.dll>` → PDF-тесты локально проходят через явный путь модуля (механизм env-переменной) | OK |
| Guard-тест `test/guards/ci_pdfium_test.dart` (красный до шага) | **3/3 зелёные** |

## Verify (локально, Windows, снимок `6a43b93` + формат)

| Команда | Результат |
|---|---|
| `fvm flutter test --exclude-tags golden --coverage` | **598 тестов, all passed** (+3 guard-теста L26 к 595) |
| `fvm dart run tool/coverage_check.dart --min=80` | **95.3% (3152/3309)**, порог пройден |
| `fvm flutter analyze` | 0 issues |
| `fvm dart format --output=none --set-exit-if-changed .` | 0 changed (143 файла) |
| `fvm flutter build windows --release` | `√ Built ... cardflow.exe` (8.6 s) |

Локально на Windows PDF-тесты идут через тот же механизм и при заданном `PDFIUM_PATH`,
и без него (Windows-загрузчик находит `pdfium.dll`); Linux/macOS-ветка проверяется
только CI-прогоном — это и есть критерий приёмки фикса.

## Критерий приёмки фикса

1. `test (ubuntu-latest)` и `test (macos-latest)` — **success**, PDF-тесты реально выполняются
   (не skip: guard-тест это фиксирует).
2. Остальные 7 job'ов не сломались — все 9 job success в одном прогоне.
3. `KNOWN_LIMITATIONS.md` L26 переформулирован по факту: что остаётся непокрытым и почему это
   осознанный выбор.

## Что остаётся непокрытым после фикса (осознанно)

- **Сетевой доступ CI к GitHub releases** — шаг требует скачать pinned PDFium; при недоступности
  GitHub releases job упадёт (не молчаливый skip — так и задумано, «красный, а не выключенный»).
  Это тот же источник, откуда `pdfium_dart` build-hook берёт PDFium для сборок, поэтому риск общий.
- **macOS arm64 только** (`macos-latest` = arm64): `pdfium-mac-x64.tgz` не скачивается, т.к. Intel-
  macOS-раннеров в матрице нет; при возврате `macos-13` понадобится ветка x64.
- **iOS tests** не гоняются (в матрице нет iOS-теста; iOS проверяется сборкой `build ios`, где PDFium
  линкуется XCFramework-ом — это отдельный путь, не тестовый).
- Реальные Word/LibreOffice/PDF-файлы (L23) и 25 МБ/OOM (L25) — по-прежнему непокрыты, не связано с L26.
