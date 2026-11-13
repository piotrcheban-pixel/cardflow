# Независимое ревью фикса L26 — PDFium bootstrap в CI

**Снимок:** `HEAD` = `dd74d8f1d13fdf5d59a44ac33eca19d59551863e` (`dd74d8f`), база `a406993` (= `origin/main`; локальный `main` ahead 4 — фикс **не запушен**).
**Ревьюируемые коммиты:** `803cb4f` (red: guard-тест), `6a43b93` (green: CI-шаг PDFium), `e6e273f` (format), `dd74d8f` (журнал).
**Диапазон:** `git diff a406993..HEAD` — 3 файла, +284/−0: [`.github/workflows/ci.yml`](.github/workflows/ci.yml) +31, [`journal/iteration-3a/fix-l26.md`](journal/iteration-3a/fix-l26.md) +142, [`test/guards/ci_pdfium_test.dart`](test/guards/ci_pdfium_test.dart) +111. Рабочее дерево на момент начала ревью — clean; отчёт создан как единственный новый файл и **не коммичен**.
**Дата:** 2026-11-13.

## Вердикт: **С FINDINGS** (не LGTM до исправления B1)

| Severity | Кол-во |
|---|---|
| blocker | **1** |
| critical | 0 |
| high | **1** |
| medium | 2 |
| low | 5 |

Механизм фикса **корректен и подтверждён независимо** (сверены исходники `pdfium_dart` 0.4.1 / `pdfrx_engine` 0.9.1 / `pdfium_flutter` 0.4.1, реальные архивы pinned-релиза и их ELF/Mach-O; см. «Проверено»). Но в текущем виде первый же push, по анализу дефолтов windows-раннера, даст **красный `test (windows-latest)`** из-за LF-предположений guard-теста (B1), а сам guard защищает от тихого сужения покрытия лишь частично (H1). PDF-тесты на Linux/macOS по анализу должны пройти; фактическое подтверждение — только первым CI-прогоном после правок.

---

## Blocker

### B1. Guard-тест упадёт на `test (windows-latest)`: LF-маркеры не переживают checkout с `core.autocrlf=true`

**Где:** [`test/guards/ci_pdfium_test.dart:18`](test/guards/ci_pdfium_test.dart#L18) — `readRepoFile('.github/workflows/ci.yml')` читается как есть; [`test/guards/ci_pdfium_test.dart:22`](test/guards/ci_pdfium_test.dart#L22) — `indexOf('\n  test:\n')`; также [`…:26`](test/guards/ci_pdfium_test.dart#L26) и [`…:74`](test/guards/ci_pdfium_test.dart#L74) — такие же LF-маркеры; ожидание [`…:34`](test/guards/ci_pdfium_test.dart#L34) `isNotEmpty`.

**Суть.** В репозитории **нет `.gitattributes`** (проверено: `git ls-tree HEAD .gitattributes` пуст; локально `core.autocrlf=false` выставлен только в `.git/config` этого клона). На GitHub-hosted `windows-latest` Git for Windows ставится silent-инсталляцией с дефолтом `AutoCRLF=CRLFAlways` (`core.autocrlf=true`) — [installer/install.iss](https://raw.githubusercontent.com/git-for-windows/build-extra/main/installer/install.iss): ветка default `RdbCRLF[GC_CRLFAlways].Checked:=True` → `GitSystemConfigSet('core.autocrlf','true')`; `images/windows/scripts/build/Install-Git.ps1` раннера autocrlf не переопределяет. `actions/checkout` autocrlf не трогает (в исходниках actions/checkout совпадений `autocrlf|crlf|line ending` — 0). Жалобы/обходы это подтверждают: actions/checkout issues [#135](https://github.com/actions/checkout/issues/135), [#226](https://github.com/actions/checkout/issues/226) («default git behavior of automatically changing line endings upon checkout… for CI it's really unfortunate», обход — `git config --global core.autocrlf false` **до** checkout). Значит на windows-раннере `ci.yml` в worktree, с высокой вероятностью, будет с CRLF, и `indexOf('\n  test:\n')` не найдёт начало job'а (`start=-1` → `testJobSection()` вернёт `''`).

**Почему это важно.** Упадут **2 из 3** guard-тестов (первый — `isNotEmpty`, второй — `greaterThan(0)`; третий, читающий `.dart`-файлы, пройдёт, в нём нет многострочных паттернов). То есть фикс L26 ломает **ранее зелёный** `test (windows-latest)`, и критерий приёмки №2 («остальные 7 job'ов не сломались — все 9 job success») не выполняется даже при успешных PDF-тестах. Это ровно тот класс ошибки, который ревью должно ловить до push.

**Доказательство (эксперимент на копии, без записи в репозиторий).** Точная логика guard'а воспроизведена в памяти на LF- и CRLF-копии `ci.yml`:

| Вход | `job_len` | test1 | test2 |
|---|---|---|---|
| LF (как в git) | 3959 | pass | pass |
| CRLF (как на windows-раннере) | **0** | **fail** | **fail** |

**Минимальный фикс (одна строка).** Нормализовать переводы строк при чтении:
```dart
final String workflow =
    readRepoFile('.github/workflows/ci.yml').replaceAll('\r\n', '\n');
```
(и по желанию так же для двух PDF-тестов в третьем guard'е — там это не обязательно). Дополнительно рекомендуется добавить в репозиторий `.gitattributes` (`* text=auto eol=lf`) — это устраняет весь класс CRLF-сюрпризов на Windows-раннере и локальных Windows-клонах, а не только этот guard. Регрессионная проверка: guard должен проходить на windows-latest в следующем прогоне; можно добавить юнит-проверку хелпера на строке с `\r\n` (вынести `testJobSection` в top-level функцию).

---

## High

### H1. «PDF-тесты не пропускаются молча» защищено частично: guard не проверяет матрицу ОС и команду тестов

**Где:** [`ci_pdfium_test.dart:32-60`](test/guards/ci_pdfium_test.dart#L32-L60) (test1), [`…:62-81`](test/guards/ci_pdfium_test.dart#L62-L81) (test2), [`…:83-110`](test/guards/ci_pdfium_test.dart#L83-L110) (test3 «не пропускаются молча»); не проверяются [`ci.yml:84`](.github/workflows/ci.yml#L84) (`os: [ubuntu-latest, windows-latest, macos-latest]`) и [`ci.yml:148-152`](.github/workflows/ci.yml#L148-L152) (`flutter test --exclude-tags golden --coverage`).

**Что guard реально ловит** (проверено матрицей мутаций): удаление/переименование шага, смену URL/tag, удаление `if: runner.os != 'Windows'`, перестановку шага после тестов, появление шага после маркера `build-mobile:`, `skip:`/`markTestSkipped`, ровно `tags: ['pdf']`, удаление/переименование самих PDF-тестов (readRepoFile бросит).

**Чего он не ловит (тихое сужение покрытия при зелёном CI):**
1. **Удаление ОС из матрицы** (`os: [ubuntu-latest, macos-latest]` или только ubuntu) — guard зелёный, PDF-тесты молча перестают идти на 1–2 ОС. Это прямо противоречит цели фикса «PDF-тесты реально идут на всех 3 ОС».
2. **Изменение команды тестов**: `--exclude-tags golden,pdf`, `--tags`, `--name/--plain-name`, запуск подкаталога (`flutter test test/unit`) — guard не читает run-блок тестов; PDF-тесты могут быть исключены/отфильтрованы, guard зелёный.
3. **Другие формы skip/тега**: `@Tags(['pdf'])`-аннотация, `tags: <String>['pdf']`, `testOn(...)`, `skip` в `dart_test.yaml` (сейчас файла нет — но и проверки нет), ранний `return` внутри тел тестов под платформенным условием (`if (Platform.isLinux) return;`) — не ловятся.
4. **Комментарий вместо шага**: если все строки шага закомментировать (`#`), `contains`/`indexOf` по-прежнему проходят — guard зелёный (но CI станет красным, это не тихий skip; тем не менее guard «шаг есть» формально врёт).

**Почему важно.** Заявленная формулировка «Второй guard запрещает «зелёный, потому что выключили»» (шапка файла, [`…:15-16`](test/guards/ci_pdfium_test.dart#L15-L16)) **сильнее**, чем фактическая проверка. Текущий снимок честный (см. отдельный раздел), но именно этот guard — единственный механизм, который должен удерживать честность в будущем; сейчас он не удержит три самых вероятных способа «зелёного без PDF».

**Минимальный фикс (дешёвый, в стиле текущего guard'а):**
- в test1: `expect(job, contains('os: [ubuntu-latest, windows-latest, macos-latest]'))` (или отдельная проверка всех трёх label в тексте job'а `test`);
- новый guard «команда тестов не исключает PDF»: найти строку `flutter test` в job'е `test`, проверить `contains('--exclude-tags golden')`, `isNot(contains('pdf'))`, `isNot(contains('--tags'))`, `isNot(contains('--name'))`, `isNot(contains('--plain-name'))`;
- в test3: добавить `isNot(contains('@Tags'))`, `isNot(contains('testOn('))`, `isNot(contains('dart_test.yaml'))` (если файла нет) и/или заменить `contains("tags: ['pdf']")` на `isNot(RegExp(r'tags\s*:'))`; проверить, что оба теста содержат `parse(`/`openData` (не только строку `pdfrxInitialize()`);
- либо честно **сузить формулировку** в шапке guard'а и L26 до того, что реально проверяется. *Нужно решение Lead: усиливать guard или корректировать формулировку.*

**Текущий снимок (проверено, не finding):** PDF-тесты действительно не фиксируются и не исключаются — в матрице все 3 ОС, команда исключает только `golden`, в двух PDF-файлах нет `skip`/`tags`/`testOn`/`markTestSkipped` (проверено `git grep`), `dart_test.yaml` отсутствует, `setUpAll` вызывает `pdfrxInitialize()`. То есть в **этом** снимке картина честная; риск — будущее.

---

## Medium

### M1. Windows: PDFium «находится сам» — механизм неявный, не пинован и не подтверждён логами

**Где:** [`ci.yml:126`](.github/workflows/ci.yml#L126) (шаг пропускается на Windows; `*)`-ветка [`ci.yml:133`](.github/workflows/ci.yml#L133) на Windows недостижима), [`fix-l26.md:36`](journal/iteration-3a/fix-l26.md#L36) и [`fix-l26.md:89`](journal/iteration-3a/fix-l26.md#L89) («загрузчик находит `pdfium.dll`»).

**Факты.** В run [`43484685899`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43484685899) `test (windows-latest)` — success, **595 тестов**, включая все 9 PDF-тестов (6 в `pdf_parser_test.dart` + 3 в `file_parsing_pipeline_test.dart`, подтверждено по логу job'а через read-only GitHub API), т.е. на Windows PDFium действительно загрузился без `PDFIUM_PATH`. Но **каким путём** — из лога не видно: в шаге нет ни `PDFIUM_PATH`, ни явного пути; в локальном окружении тот же тест проходит за счёт `.dart_tool/native_assets.yaml` → `.dart_tool/lib/pdfium.dll` (gitignored артефакт от прежних `dart run`/сборок; в CI чистый checkout — такого файла нет). Отдельно: в CI-шаге `flutter test` не собирает native assets (иначе Linux/macOS не падали бы с «Native assets file not found»), значит на windows-раннере модуль находится чем-то из окружения раннера (search path/образ) — это **внешняя недокументированная зависимость**.

**Почему важно.** (а) Это единственный путь L26, который не пинован и не воспроизводим по логам; при изменении образа windows-раннера/окружения PDF-тесты упадут красным (не молча — это плюс), но разберётся ли команда, непонятно. (б) В журнале/документации фикса сейчас утверждается «Windows работает, загрузчик находит pdfium.dll» без обоснования — это не соответствует уровню доказательности остальных пунктов.

**Нужно решение Lead:** либо (предпочтительно) **бутстрапить PDFium и на Windows** тем же способом (`pdfium-win-x64.tgz` → `bin/pdfium.dll`, `PDFIUM_PATH`) — тогда все 3 ОС явные и пинованные, guard правится в одном месте (проверка `if` меняется: Linux/macOS/Windows — все; на Windows asset `pdfium-win-x64.tgz`, путь `bin/pdfium.dll`); либо оставить как есть, но в L26/доках явно записать «Windows: неявный поиск `pdfium.dll`, не пинован; механизм не подтверждён логами».

### M2. Документация содержит фактические противоречия с реализацией — обязательны к правке после ревью

**Где и что:**
1. [`docs/decisions/ADR-010-parsers.md:101-102`](docs/decisions/ADR-010-parsers.md#L101-L102): «в изоляте вызывается `pdfrxInitialize()` (Dart-инициализация, PDFium из `pdfium_dart` native assets)» — **неверно для `flutter test`**: native assets тестовому раннеру недоступны (это и есть причина L26); фикс грузит PDFium по явному `PDFIUM_PATH` из `$RUNNER_TEMP`. Надо переписать §9 и §9-дополнение (п.10) и §«Известные ограничения» ([`:159`](docs/decisions/ADR-010-parsers.md#L159), [`:117`](docs/decisions/ADR-010-parsers.md#L117)).
2. [`journal/KNOWN_LIMITATIONS.md:59`](journal/KNOWN_LIMITATIONS.md#L59): L26 сейчас **предписывает** «при падении на ОС — платформенный skip + это ограничение» — это прямо противоречит выбранному направлению A (skip/тег отклонены). Кроме того, «только pdfrx в CI ещё не проверялись» устарело: проверено (падение), фикс есть.
3. [`journal/STATE.md:10-11`](journal/STATE.md#L10-L11): тот же устаревший план «При падении только PDF-тестов… платформенный skip». Обновить вместе с L26; [`:32`](journal/STATE.md#L32) «Не проверено: CI-прогон 3a (L26)» — уточнить статус.
4. [`docs/parsers.md:98-103`](docs/parsers.md#L98-L103): «pdfrx/PDFium в тестах на Linux/macOS CI проверяется прогоном итерации 3a» — уточнить факт/фикс и остаточные ограничения.
5. [`docs/dependencies.md:236-240`](docs/dependencies.md#L236-L240): «pdfrx… работает в `flutter test` **на Windows**» + «CI: прогон итерации 3a ещё не выполнялся» — устарело: прогон был (2 setUpAll fail), фикс — pinned-PDFium шаг; нужно описать механизм и остаточные риски L26. Также [`:222`](docs/dependencies.md#L222) «Риск CI» → сослаться на фикс; [`:228`](docs/dependencies.md#L228) «595 тестов» → 598 после +3 guard-тестов.
6. [`fix-l26.md`](journal/iteration-3a/fix-l26.md) — список «Что остаётся непокрытым» неполон (см. отдельный раздел ниже) и есть неточности: [`fix-l26.md:104`](journal/iteration-3a/fix-l26.md#L104) «шаги… побайтово равны HEAD» (правильно: «равны состоянию до фикса, `a406993`»); [`fix-l26.md:89`](journal/iteration-3a/fix-l26.md#L89) про Windows «загрузчик находит» (см. M1); [`fix-l26.md:73`](journal/iteration-3a/fix-l26.md#L73) «~4 МБ на два job'а» (фактически ≈3.65+3.38 ≈ 7.0 МБ суммарно, ~3.5 МБ на job).

**Почему важно.** Ревью проводится до обновления доков (так задумано), поэтому это не ошибка снимка, а список обязательных правок; без них ADR-010 будет прямо противоречить коду/CI, а L26 — содержать отменённую политику skip.

---

## Low

### L1. Нет проверки целостности скачиваемого PDFium
[`ci.yml:137-139`](.github/workflows/ci.yml#L137-L139): `curl -fsSL --retry 3` + `tar -xzf` без sha256; тег `chromium/8125` пинован, но ассеты релиза технически заменяемы, а в тестовый процесс грузится нативный код. Для сравнения, `pdfium_flutter` проверяет SHA256 XCFramework (`PDFIUM_HASH` в podspec). **Fix:** захардкодить sha256 для обоих активов (digests есть у GitHub API: linux `e1c3ce6e270cb5e0c20816b379ad9f2c1309972697c505f508de92bf5e7d6659`, mac `4939bd935ac83ddc09a3a4f038bc43a19cea1660316a3667f26cb07a070e139d`) и проверять после `curl`; альтернатива — хотя бы L26-запись о риске (тот же класс доверия, что и build-hook).

### L2. Сетевой шаг без таймаутов; guard не фиксирует `--retry`/`set -euo pipefail`
[`ci.yml:129`](.github/workflows/ci.yml#L129), [`ci.yml:137-138`](.github/workflows/ci.yml#L137-L138): нет `--connect-timeout/--max-time/--retry-delay` — зависшее соединение может съесть бюджет job'а (дефолтный timeout 360 мин). Guard не поймает удаление `--retry 3`/`set -euo pipefail` (шаг всё равно упадёт на проверке файла — т.е. красный, не тихий). **Fix:** `curl --connect-timeout 10 --max-time 120 --retry 3 --retry-delay 2`; при желании — assert `set -euo pipefail` в guard'е.

### L3. Пин `chromium/8125` теперь живёт в трёх местах и не сверяется автоматически
CI (`ci.yml:138`) ↔ `pdfium_dart` 0.4.1 build-hook (`_pdfiumRelease`, строка 10) ↔ `pdfium_flutter` 0.4.1 podspec/Package.swift (`PDFium-chromium-8125-…`, XCFramework). На pub.dev уже видны 0.4.2/2.12.1. При обновлении зависимости CI может остаться на 8125 и тесты будут зелёными, тестируя более старый PDFium, чем приложение (или упадут при смене API). Guard жёстко фиксирует 8125 (это осознанно), но документация должна зафиксировать обязанность синхронизации 3 мест (и запись в `docs/dependencies.md` §10). **Нужно решение:** документировать (минимум) или добавить проверку согласованности с `pubspec.lock`/hook-константой (сложнее; не блокер).

### L4. Хрупкость/ложные срабатывания guard'а
[`ci_pdfium_test.dart:21-30`](test/guards/ci_pdfium_test.dart#L21-L30), [`:45`](test/guards/ci_pdfium_test.dart#L45), [`:54-59`](test/guards/ci_pdfium_test.dart#L54-L59), [`:74`](test/guards/ci_pdfium_test.dart#L74), [`:83-110`](test/guards/ci_pdfium_test.dart#L83-L110): текстовый поиск и жёсткие маркеры (`\n  test:\n`, `\n  build-desktop:`, `\n  build-mobile:`), точная строка `if: runner.os != 'Windows'` (валидная эквивалентная запись `${{ runner.os != 'Windows' }}` даст ложное падение), жёсткий список двух PDF-файлов (рефакторинг/переименование = падение guard'а — это осознанный tripwire, но стоит помнить), `RegExp(r'\bskip\s*:')` может ловить комментарии/строки (аллергия на безобидные правки). YAML в CI не валидируется; guard читает текст, а не YAML. Приемлемо для guard'а, но если планируется развивать — стоит распарсить YAML (`yaml` как dev-зависимость) или вынести хелпер и покрыть юнит-тестами.

### L5. Точность журнала/доказательств Lead
Кроме M2-пунктов: [`fix-l26.md:115`](journal/iteration-3a/fix-l26.md#L115) «598 тестов» — независимо не перепроверял (полный прогон не запускал); перепроверено: guard-тест 3/3, format 143/0, analyze 0 (см. «Проверено»). [`fix-l26.md:127-130`](journal/iteration-3a/fix-l26.md#L127-L130) критерии приёмки не включают регрессию «guard на Windows» (B1) и не фиксируют, что фикс ещё не запушен; после исправления стоит добавить в журнал run-id зелёного прогона. Также в журнале не отражено, что `test (windows-latest)` run 3a — 595 passed (включая 9 PDF-тестов): полезное доказательство честности сравнимо с ubuntu/macos 586+2.

---

## Проверено (независимо, команды/результаты)

**Снимок/дифф**
- `git rev-parse HEAD` = `dd74d8f1d1…`; `git status --porcelain` — пусто; `git status -sb` — `main...origin/main [ahead 4]`, `origin/main` = `a406993`.
- `git diff --unified=0 a406993..HEAD -- .github/workflows/ci.yml` — **+31/−0** (два хунка: шапка-комментарий и шаг; ни одна строка не удалена/изменена).
- Семантическое сравнение YAML: `jobs.quality`, `jobs.build-desktop`, `jobs.build-mobile` **побайтово равны** версии `a406993`; в `jobs.test` старые шаги сохранены в прежнем порядке, добавлен ровно один шаг.
- `e6e273f` — только форматирование guard-теста (7+/3−, без семантики).

**YAML/basics**
- Независимый YAML 1.2-загрузчик (bool-резолвер только true/false): `on` — строка, структура валидна.
- SchemaStore `github-workflow.json` (jsonschema 4.26.0): **validation passed**.
- `actionlint 1.7.12 -no-color -shellcheck=`: **0 findings**.
- `bash -n` всех 23 `run`-блоков (через stdin, без записи файлов): **0 ошибок**.
- URL/pinned: `_pdfiumRelease = 'chromium%2F8125'` (`pdfium_dart-0.4.1/hook/build.dart:10`); имена ассетов конструируются как `pdfium-${archivePlatform}-${archiveArch}.tgz`, для macOS `archiveLibraryPath = lib/libpdfium.dylib`, Linux `lib/libpdfium.so` — совпадает с CI.
- GitHub API (`repos/bblanchon/pdfium-binaries/releases/tags/chromium%2F8125`, read-only): тег существует, 47 ассетов; `pdfium-linux-x64.tgz` 3 828 800 B, `pdfium-mac-arm64.tgz` 3 540 999 B; **sha256 скачанных локально архивов совпадают с digest API**.
- Архивы (in-memory): `lib/libpdfium.so` / `lib/libpdfium.dylib` на месте; `VERSION` → `MAJOR=158 MINOR=0 BUILD=8125 PATCH=0` (совпадает с build-hook). Linux `.so`: ELF x86-64, max GLIBC 2.16, DT_NEEDED libc/libm/libgcc_s/libpthread (ubuntu-24.04 совместим). macOS `.dylib`: Mach-O arm64, minos 13.0, `LC_CODE_SIGNATURE` присутствует (подпись есть → arm64-загрузка не должна блокироваться).

**Механизм pdfrx/PDFium (исходники pub cache)**
- `pdfrx_engine.dart:3`: `pdfrxInitialize` — Dart-вариант при `dart.library.io` (flutter test).
- `pdfrx_initialize_dart.dart:45`: `Platform.environment['PDFIUM_PATH']` → `Pdfrx.pdfiumModulePath` (если файл существует).
- `pdfium_dart/lib/src/pdfium_loader.dart:31`: при `modulePath != null` — сразу `DynamicLibrary.open(modulePath)` (до веток «Unsupported platform»/native assets).
- `pdfrx_engine/src/native/worker.dart:84-93`: worker-изолят получает `modulePath` из main-изолята → явный путь работает и для FFI в worker'е.
- `lib/api/parsers/pdf_parser.dart`: `pdfrxInitialize()` вызывается и внутри `parse` (изолят) → env читается и там.
- macOS app-путь отличается по артефакту: `pdfium_flutter` 0.4.1 подтягивает XCFramework `PDFium-chromium-8125-20261029-150241` (espresso3389) — та же версия chromium/8125, но другой бинарь, чем bblanchon mac-arm64, который тестируется. Это нужно отразить в доках (нюанс, не ошибка).

**CI-логи**
- Локальные run3a: ubuntu-24.04 (x64) и macos-26-arm64; оба — `586 tests passed, 2 failed`, падения = `(setUpAll)` двух PDF-файлов; Linux — отсутствующий `…/engine/linux-x64/lib/libpdfium.so` + `Native assets file not found`; macOS — `Unsupported platform`.
- Run 43484685899, `test (windows-latest)` (через read-only GitHub API): **595 passed**, PDF-тесты идут и зелёные (6+3), без skip; шаг PDFium в job'е отсутствует (как и должно быть). Это же объясняет арифметику: 586+9 = 595; +3 guard = 598 после фикса.

**Локальная перепроверка (Windows)**
- `fvm flutter test test/guards/ci_pdfium_test.dart` → **3/3 passed**.
- `fvm flutter test test/unit/api/parsers/pdf_parser_test.dart test/integration/file_parsing_pipeline_test.dart` → **9/9 passed** без `PDFIUM_PATH` и **9/9 passed** с `PDFIUM_PATH=<pdfium.dll>` (механизм env-переменной рабочий; локально без env подхватывается через `.dart_tool/native_assets.yaml`).
- `fvm flutter analyze` → **No issues found** (4.5 s).
- `fvm dart format --output=none --set-exit-if-changed .` → **143 файла, 0 changed**.
- `git status --porcelain` после прогонов — clean (изменённых файлов нет).
- Проверки состава: `flutter test` есть только в `jobs.test` (`ci.yml:152`); `.gitattributes` нет; `dart_test.yaml` нет; в PDF-тестах нет `skip`/`tags`/`testOn`/`markTestSkipped` (`git grep` — пусто); тестов в PDF-файлах 6+3.

**Guard — матрица мутаций (in-memory копия `ci.yml`, логика guard'а воспроизведена точно)**
| Мутация | Guard падает? |
|---|---|
| удалить шаг / переименовать | да |
| сменить URL/tag (не 8125) | да |
| убрать/изменить `if:` | да |
| переставить шаг после «Тесты (кроме golden)» | да |
| добавить шаг в `build-mobile` (после маркера) | да |
| CRLF-копия workflow | **да (B1)** |
| удалить/переименовать PDF-тест-файл | да (readRepoFile) |
| `skip:` / `markTestSkipped` / `tags: ['pdf']` | да |
| убрать ОС из матрицы | **нет (H1)** |
| `--exclude-tags golden,pdf` / `--tags` / `--name` в команде тестов | **нет (H1)** |
| `@Tags(['pdf'])` / `tags: <String>['pdf']` / `testOn(...)` | **нет (H1)** |
| закомментировать все строки шага (`#`) | нет (строки текста остаются) |
| убрать `set -euo pipefail` / `--retry 3` | нет (L2) |
| шаг дополнительно в `quality`/`build-desktop` | нет (безвредно для CI, лишняя загрузка) |
| `if: ${{ runner.os != 'Windows' }}` (эквивалент) | ложное падение (L4) |

---

## Документация: обязательные правки после ревью

### `journal/KNOWN_LIMITATIONS.md` L26 — переформулировать по факту

L26 должен содержать:
1. **Факт из run 43484685899:** `test (ubuntu-latest)`/`test (macos-latest)` — 586 passed / 2 failed, падения только `(setUpAll)` двух PDF-тестов; `test (windows-latest)` — 595 passed (PDF-тесты шли); причина — PDFium недоступен в `flutter test` (Linux: нет `libpdfium.so` в кэше engine + нет native assets; macOS: чистый Dart-загрузчик не поддерживает платформу).
2. **Фикс:** job `test` на Linux/macOS скачивает pinned PDFium `bblanchon/pdfium-binaries chromium/8125` (тот же upstream-билд, что build-hook `pdfium_dart` 0.4.1; для iOS/macOS-app — XCFramework `v158.0.8125.0-…`, та же версия) в `$RUNNER_TEMP`, проверяет наличие `lib/libpdfium.so`/`lib/libpdfium.dylib`, экспортирует `PDFIUM_PATH`; `pdfrxInitialize()` грузит модуль по явному пути. **Skip/тег не используются** (отклонены). Коммит `6a43b93`; guard — `test/guards/ci_pdfium_test.dart`.
3. **Статус до подтверждения:** фикс локальный (`main` ahead 4, не запушен); L26 снимается **только зелёным прогоном** всех 9 job'ов на коммите с фиксом (run-id вписать); до этого — «ожидает подтверждения», а не «снято».
4. **Что остаётся непокрытым/риски (обязательно):**
   - сеть: шаг требует GitHub releases (нет кэша; retry 3; падение = красный, не skip); тот же источник, что у build-hook (но для macOS-app — другой репозиторий XCFramework);
   - macOS — только arm64 (`macos-latest` = `macos-26-arm64`; проверено); x64-ветки нет; при смене label на Intel — править (лучше выбирать asset по `runner.arch`);
   - **Windows** — шаг пропущен, `pdfium.dll` находится неявно; механизм не пинован/не подтверждён логами (M1) — «нужно решение»;
   - iOS-тестов нет вообще; `build ios` проверяет только сборку с XCFramework (chromium/8125), не runtime;
   - нет проверки целостности (sha256) скачиваемого архива (L1);
   - пин `chromium/8125` дублируется в CI / `pdfium_dart` 0.4.1 / `pdfium_flutter` 0.4.1 — синхронизировать при обновлении зависимостей (L3);
   - guard защищает инварианты шага и отсутствие skip/тегов в двух файлах, но **не** матрицу ОС и **не** команду тестов (H1) — до усиления guard не заявлять «тихий skip невозможен»; после B1 — нормализация CRLF.
   - L23 (реальные файлы) и L25 (25 МБ/OOM) — отдельные, не смешивать с L26; PDF-парсер production-код не менялся.
5. **Компенсация:** PDF-тесты не тегируются/не скипаются; guard; при недоступности PDFium — красный job, а не тихий пропуск.
6. **Снятие:** зелёный прогон CI после push (все 9 job success; PDF-тесты реально исполняются на 3 ОС).

### `docs/parsers.md`
- В разделе ограничений ([`:98-103`](docs/parsers.md#L98-L103)): заменить «проверяется прогоном итерации 3a» на факт: PDF-тесты идут на всех 3 ОС; Linux/macOS получают PDFium шагом CI (`PDFIUM_PATH`, pinned 8125), Windows — нативно; остаточные риски — L26.
- В «Лимиты и изоляты» ([`:65-68`](docs/parsers.md#L65-L68)) — одна строка: в `flutter test` native assets PDFium недоступны → CI-бутстрап (ссылка на L26); приложение — native assets/XCFramework.

### `docs/dependencies.md` §9–§10
- §10 ([`:236`](docs/dependencies.md#L236)): «работает в `flutter test` на Windows» → «на всех 3 ОС CI (Linux/macOS — явный `PDFIUM_PATH` из pinned-релиза; Windows — нативный поиск, см. L26)».
- §10 ([`:240`](docs/dependencies.md#L240)): заменить «прогон ещё не выполнялся» на факты run 43484685899 → фикс `6a43b93` → подтверждение следующим зелёным прогоном; остаточные риски — L26.
- §10 ([`:228`](docs/dependencies.md#L228)): 595 → **598** (после +3 guard-тестов); [`:238`](docs/dependencies.md#L238) покрытие 95.3% остаётся (не перепроверял — Lead).
- §9 ([`:222`](docs/dependencies.md#L222)): «Риск CI» — сослаться на L26-фикс и раздел §10.
- Добавить заметку о версионной связке: `pdfrx` 2.12.0 → `pdfium_dart` 0.4.1 (bblanchon `chromium/8125`) + `pdfium_flutter` 0.4.1 (XCFramework `chromium-8125`); CI пин — тот же; при обновлении зависимостей синхронизировать 3 места (L3).

### `docs/decisions/ADR-010-parsers.md`
- §9 ([`:99-103`](docs/decisions/ADR-010-parsers.md#L99-L103)): переписать «PDFium из `pdfium_dart` native assets» → «в приложении PDFium из native assets (Windows/Linux/Android) или XCFramework (iOS/macOS); в `flutter test` native assets нет, поэтому CI Linux/macOS задаёт `PDFIUM_PATH` на pinned bblanchon chromium/8125 (L26)»; `pdfrxFlutterInitialize()` не нужен; политика «PDF-тесты не скипаются/не тегируются; инварианты CI защищены guard-тестом; Windows — неявный путь, см. M1».
- §9-дополнение п.10 ([`:151-153`](docs/decisions/ADR-010-parsers.md#L151-L153)) — оставить, добавить ссылку на CI-политику.
- «Минусы/риски» ([`:117`](docs/decisions/ADR-010-parsers.md#L117)): «pdfrx тянет нативные PDFium (сборка/тесты на 3 ОС CI — проверяется)» → «проверено на CI (Linux/macOS — после L26-фикса; Windows — нативно)».
- «Известные ограничения» ([`:159`](docs/decisions/ADR-010-parsers.md#L159)) — заменить предложение на актуальное.

### `journal/STATE.md` и `journal/iteration-3a/fix-l26.md`
- [`STATE.md:10-11`](journal/STATE.md#L10-L11) — убрать «платформенный skip», записать: L26-фикс подготовлен, guard + CI-шаг, ждёт push/зелёного прогона; [`STATE.md:32`](journal/STATE.md#L32) — обновить «Не проверено»; строку «Факты» (ahead + список коммитов) — обновить.
- `fix-l26.md`: исправить `:104` («равны HEAD» → «равны `a406993`»), `:73` (≈7 МБ суммарно / ~3.5 МБ на job), `:89`/`:36` (Windows-механизм не обоснован — см. M1), добавить запись о CRLF-фиксе guard'а (B1) и run-id зелёного прогона как критерий снятия; неполный список «что остаётся непокрытым» дополнить пунктами из L26-секции выше.
- При желании — `journal/iteration-3a/summary.md:31,49` и `verify.md:64`: после зелёного прогона добавить строку о фактическом подтверждении L26.

---

## Не проверено / риски

- **Полный прогон 598 тестов / покрытие 95.3% / `flutter build windows --release`** — не перезапускал (сознательно, чтобы не гонять долгие прогоны); независимо перепроверены только guard-тест (3/3), PDF-тесты (9/9), analyze (0), format (143/0).
- **Linux/macOS-исполнение фикса не проверено фактически** (нет таких ОС локально): механизм подтверждён по исходникам и бинарникам (env → explicit `DynamicLibrary.open`; ELF/Mach-O совместимы), но зелёный `test (ubuntu/macos)` — только после push. Критерии приёмки №1–2 пока не выполнены (фикс не запушен).
- **B1 не воспроизведён на реальном windows-latest** — подтверждён анализом дефолтов Git for Windows + actions/checkout + симуляцией логики guard'а; первый CI-прогон после push подтвердит/опровергнет.
- **Windows-механизм загрузки PDFium** в CI не установлен (M1); локально работает через `.dart_tool/native_assets.yaml` (ignored).
- **macOS dylib реально не загружался** (подпись/arch/minos проверены статически; quarantine через curl не ставится — рассуждение, не эксперимент).
- Сетевой путь CI к GitHub releases **не проверялся для job'а test**, но косвенно подтверждён зелёными `build windows`/`build macos` в run 3a (те же GitHub releases, другой репозиторий/ассет).
- Вне scope: production-код парсеров/остальная часть итерации 3a (ревью ранее — `journal/iteration-3a/review.md`); L23/L25 не меняются.
- Секреты/токены не выводились; доступ к GitHub API — read-only через git credential (как у Lead), значения не печатались.

## Итог

Фикс L26 **по сути правильный** и минимально инвазивный: pinned-версия совпадает с build-hook, ассеты/архитектуры/архивные пути подтверждены независимо (включая sha256 через GitHub API), механизм `PDFIUM_PATH` подтверждён по исходникам pdfrx/pdfium_dart и локально; прочие job'ы не изменены; guard ловит основные регрессии шага. **До push нужны:** B1 (CRLF-нормализация guard'а — иначе `test (windows-latest)` красный), решение по H1 (усилить guard или сузить формулировку) и M1 (Windows-механизм: документировать или бутстрапить), затем — обновление L26/доков (M2) и запуск CI; L26 снимается только по зелёному прогону.
