# Итерация 0 — Независимое ревью

**Дата:** 2026-11-11, ~19:36 MSK · **Ревьюер:** независимый ревьюер (DSH, teammate `reviewer`)
**Объект:** HEAD `5d9cd95` + рабочее дерево (на момент проверки `journal/iteration-0/summary.md` — untracked)
**Область:** SPEC A3/A4/A5/A7.2/B3/B6; `docs/agent-prompt.md` §3/§6/§7; `AGENTS.md`; ADR-001…004; `docs/dependencies.md`; `journal/iteration-0/{plan,verify,summary}.md`; `lib/` (domain/scheduling, ui/app.dart, ui/motion.dart, ui/theme, ui/m3e, main.dart); `test/**`; `pubspec.yaml`/`pubspec.lock`; `.github/workflows/ci.yml`; `tool/coverage_check.dart`; l10n.
**Режим:** read-only. Единственный записанный файл — этот `review.md`; код, тесты и документы не правились.

## 1. Вердикт

**Готово к приёмке: blocker / critical / high — 0.** Найдено 6 medium и 12 low — все дешёвые, medium рекомендуется закрыть до финального checkpoint-коммита, low — в техдолг следующих итераций либо сразу поправить документарные (L1, L2, L11).

Анти-читерство: тесты не удалялись и не подменялись, анализатор не отключён, порог покрытия не понижен, `// ignore` в рукописном коде нет, ключи не печатались, спорные утверждения журнала проверены по первоисточникам (исходники `fsrs` 2.0.1, pub.dev API, манифесты GitHub Actions, образ `windows-2025`). Один реальный дефект guard-теста, найденный Lead'ом в ходе verify (падение `no_secrets` на бинарных артефактах сборки), на момент ревью исправлен и подтверждён зелёным прогоном; в журнале он честно зафиксирован (`verify.md:44`).

## 2. Как проверялось

### 2.1 Команды, выполненные мной (только разрешённые `fvm flutter analyze` / `fvm flutter test`)

| Команда | Результат |
|---|---|
| `fvm flutter analyze` | `No issues found! (ran in 11.7s)`, exit 0 |
| `fvm flutter test` | `00:01 +58: All tests passed!`, exit 0 (58 тестов: guard 24 + домен 23 + motion/M3E 8 + локализация 3) |
| read-only пересчёт покрытия из `coverage/lcov.info` | **135/136 = 99.26%** рукописного `lib/` — совпадает с `verify.md:53` (99.3%) и `README.md:36` |

Дополнительно: наблюдал красный прогон до исправления guard-теста (19:30, `no_secrets` падал на `windows/flutter/ephemeral/*.dll.exp` с UTF-8-ошибкой) — дефект был реальным, после фикса тесты зелёные.

Не выполнялись (вне разрешённых проверок): сборки, `dart format`, `gen-l10n`, `fvm dart run tool/coverage_check.dart`, CI.

### 2.2 Статические проверки и сверка с первоисточниками

- Импорты: `package:flutter/material.dart` в `lib/` и `test/` — **нет**; `material_3_expressive` — только `lib/ui/m3e/m3e.dart:8`; `lib/domain/**` импортирует только `package:fsrs/fsrs.dart` и локальные файлы (пакет `fsrs` — чистый Dart, зависимости только `meta`).
- `pubspec.lock`: пакетов `webview_flutter*`, `flutter_inappwebview*`, `flutter_html*` — нет (включая транзитивные); guard зелёный.
- `lib/`/`test/` рукописные: `// ignore` — нет (только сгенерированные `lib/l10n/app_localizations*.dart`); `TODO`/`FIXME`/`UnimplementedError` — нет.
- Локализация: `lib/l10n/app_localizations.dart:95` — `supportedLocales = [Locale('ru')]`; `lib/ui/app.dart:19-24` — `locale: ru`, делегаты `material_ui`; widget-тест проверяет «Отмена/Вставить/ОК»; в ARB латиница — только бренд `CardFlow` (allow-list).
- FSRS-адаптер сверен с исходником `fsrs 2.0.1` (pub-кэш): `Rating` 1..4 (`value`), `State` только `learning(1)/review(2)/relearning(3)` — состояния `New` нет, комментарий адаптера верен; `reviewCard` требует UTC (`ArgumentError` при non-UTC) и копирует карточку (`copyWith`) — иммутабельность `SchedulingCard` не нарушается; поведение шагов обучения в исходнике совпадает с ожиданиями тестов (Again → 1 мин; Hard при step=0 и 2 шагах → (1+10)/2 = 5,5 мин; Good → 10 мин; Easy → review, интервал из начальной стабильности w[3]=16.1507 → 16 дней); fuzzing off → детерминизм; `defaultParameters` — 21 вес.
- UTC: `scheduler.dart:92,105-113` нормализует `now`/`due`/`lastReview` через `toUtc()`; `scheduling_card.dart:44-54` добавлены assert'ы UTC + тесты; `fromJson` — `toUtc()`.
- CI: YAML разобран `python 3.14 + PyYAML 6.0.3` → `YAML OK`, 4 job'а; версии actions проверены по первоисточникам: `actions/checkout@v7` (существует), `actions/setup-java@v6.2.0` (существует), `subosito/flutter-action@v2.23.0` (релиз существует), `kuhnroyal/flutter-fvm-config-action@v3.3` (релиз существует, output `FLUTTER_VERSION` — совпадает с использованием в workflow), `actions/upload-artifact@v5` (тег существует, актуальный — v7); `fvm flutter test --help` подтверждает `-x, --exclude-tags`; `flutter analyze --help` подтверждает, что `--[no-]fatal-infos` по умолчанию **on**.
- Зависимости: конфликт `desktop_drop`/`file_picker` подтверждён pub.dev API (`desktop_drop 0.9.2` → `cross_file ^0.4.0`; `file_picker 13.3.3` → `cross_file ^0.3.5+4`) — обоснование выбора 0.8.4 в `docs/dependencies.md:43` и L8 корректно; `drift_flutter`, `enough_convert`, `sqlite3_flutter_libs` действительно не добавлены и это объяснено (§7); S3-утверждение о native assets `sqlite3`/`pdfium` на Windows подтверждается артефактами `.dart_tool/hooks_runner/` (`sqlite3.dll`, `pdfium.dll` собраны).
- `KNOWN_LIMITATIONS.md` L2b: «CI windows-раннер содержит ATL» — проверено по актуальному образу `Windows Server 2025` (20261101.318.1): в нём есть `Microsoft.VisualStudio.Component.VC.ATL 17.14.36510.44`, т.е. ожидание для CI реалистично.
- FVM: `.fvmrc` = `{"flutter":"3.47.9"}`, `.fvm/versions/3.47.9` — junction на `C:\Users\piotr\fvm\versions\3.47.9`, `fvm flutter --version` = 3.47.9 / Dart 3.13.7; `pubspec.lock` sdks: `dart >=3.13.7 <4.0.0`, `flutter >=3.47.0`.

## 3. Жёсткие требования — статус

| Требование | Статус | Доказательство |
|---|---|---|
| Только русский UI, литералы только из ARB | соблюдено | `lib/ui/app.dart:43-45` — текст из `AppLocalizations`; guard `ru_strings` зелёный |
| Латиница только в allow-list брендов/форматов | соблюдено | ARB: единственная строка `CardFlow` (allow-list); guard + самопроверки |
| `supportedLocales == [ru]` | соблюдено | `lib/l10n/app_localizations.dart:95`; widget-тест |
| Нет WebView/HTML, включая транзитивные | соблюдено | guard `no_webview` (lock/yaml/импорты) зелёный; ручной grep lock пуст |
| Секреты не в коде/логах/БД | соблюдено (в рамках итерации 0 кода с ключами нет) | guard `no_secrets`; ключи в окружении absent |
| `lib/domain` без импортов Flutter | соблюдено | импорты domain — только `fsrs` и локальные файлы |
| Material-база — `material_ui`, `package:flutter/material.dart` запрещён | соблюдено | `app.dart:1`, `app_theme.dart:1`; grep по `lib/` и `test/` — 0 вхождений `flutter/material.dart` |
| `material_3_expressive` только через `lib/ui/m3e/` | соблюдено | единственное вхождение — `lib/ui/m3e/m3e.dart:8` |
| Нет мёртвых кнопок/заглушек | соблюдено | UI — `HomeShell` без кнопок; заглушек/TODO в `lib/` нет |

## 4. Находки

### 4.1 Blocker / Critical / High

**Нет.**

### 4.2 Medium

**M1. Guard `no_secrets` молча пропускает не-UTF-8 файлы — ослабление детектора.**
`test/guards/no_secrets_test.dart:96-102` — `readAsStringSync()` обёрнут в `try/on FileSystemException { continue; }`, а в `excludedScanDirs` добавлен `'ephemeral'` (`:58`). Исправление было необходимым (реальное падение на `windows/flutter/ephemeral/*.exp`), но теперь **любой** файл, не декодирующийся как UTF-8 (UTF-16/cp1251/бинарный «текст»), молча выпадает из скана — ключ, положенный мимо кодировки, guard не увидит. Почему это medium: ослабляет обязательный guard из `docs/agent-prompt.md:94`, при этом риск невелик (исходники проекта — UTF-8).
Как исправить: (1) расширить `binaryExtensions` реальными артефактами (`.exp`, `.lib`, `.pdb`, `.obj`, `.dylib` уже есть) и исключать только их; (2) на ошибке декодирования не молчать — собрать список `skipped` и вывести/провалить тест, если расширение не входит в известный бинарный набор; (3) альтернатива — декодировать с `allowMalformed` и искать ASCII-шаблоны в latin1-представлении.

**M2. Жёсткие архитектурные правила не покрыты guard-тестами (только ревью).**
`AGENTS.md:14,19` и `ADR-001:70,72` фиксируют: «Material — только `material_ui`; M3E — только через `lib/ui/m3e/`; `domain/` без Flutter». Сейчас это выполняется, но проверяется только вручную; теста, который упадёт при импорте `package:flutter/material.dart` в `lib/` или `material_3_expressive` вне `lib/ui/m3e/`, нет. ADR допускает «analyzer-правило/ревью», однако для итераций 1–7 с большим объёмом UI это главный риск регрессии.
Как исправить: добавить `test/guards/architecture_test.dart` (обход `lib/**/*.dart`): запрет `package:flutter/material.dart`; `material_3_expressive` — только в `lib/ui/m3e/`; в `lib/domain/` — запрет любых `package:flutter/*` (белый список: `dart:*`, `package:meta`, `package:fsrs`); M3E/материал-импорты UI — только `material_ui` или фасад. Плюс самопроверки детектора по аналогии с другими guard-тестами.

**M3. ADR-004 утверждает проверку, которой нет в тестах.**
`docs/decisions/ADR-004-fsrs-config.md:32`: «это проверено тестом (`previewIntervals` == результат `review` по `due` для тех же входов)». В `test/unit/domain/fsrs_scheduler_test.dart` такого сравнения нет: тесты отдельно проверяют значения `previewIntervals` (1 мин / 5,5 мин / 10 мин / 16 дн) и отдельно `review()` для 3 из 4 оценок (Hard через `review()` не проверяется вовсе). Утверждение фактически верно по конструкции кода, но заявлено как доказанное тестом.
Как исправить: добавить тест `for (final r in Rating.values) expect(preview[r], review(card, r).card.due.difference(now))` (карточка new + карточка learning/review) — либо переформулировать ADR без ссылки на несуществующий тест.

**M4. CI ослабляет анализатор относительно требования «0 issues».**
`.github/workflows/ci.yml:44` — `flutter analyze --no-fatal-infos`, тогда как `flutter analyze --help` показывает `fatal-infos (defaults to on)`, а `AGENTS.md:37`, `docs/agent-prompt.md:110` требуют «0 issues». Сейчас issues действительно 0 (проверено), поэтому гейт не «красный», но info-уровень в CI пройдёт молча — расхождение с политикой проекта.
Как исправить: убрать `--no-fatal-infos` (оставить `flutter analyze`); если появятся легитимные info от generated-кода — исключать источник, а не флаг.

**M5. `docs/dependencies.md` расходится с фактическим `pubspec.yaml`/lock.**
- `:40` — `xml: ^7.1.0`, фактически `pubspec.yaml:54` `xml: ^7.0.1`, в lock 7.0.1 (версия 7.1.0 существует, но не взята).
- `:42` — `file_picker: ^13.3.3`, фактически `pubspec.yaml:57` — точный пин `13.3.3` (причина пина — защита от `cross_file`-конфликта с `desktop_drop 0.8.4` — не задокументирована).
- `dynamic_color 2.1.0` есть в `pubspec.yaml:50` и в фактическом списке §7, но **нет строки** в §2/§4 (пакет, версия, зачем, платформы, лицензия, вердикт) — нарушение `AGENTS.md:9`.
- §2 `:48` (`riverpod`), `:53` (`path`), `:70` (`test`) перечислены как зависимости, но прямыми не являются (riverpod/test объяснены в §7, `path` — нет).
Как исправить: привести таблицу §2 к фактическому pubspec; добавить строку `dynamic_color` с обоснованием (A4.1 dynamic color, план — итерация 7) и лицензией; зафиксировать причину exact-пина `file_picker`.

**M6. Маппинг/переходы FSRS протестированы неполно (только «новая карточка»).**
`lib/domain/scheduling/fsrs_mapper.dart:44-48` — ветка `fromFsrsState(State.relearning)` не покрыта (в `coverage/lcov.info` строка 47 = 0), т.е. обратный маппинг переучивания не проверен ни одним тестом. Также `review()` в `test/unit/domain/fsrs_scheduler_test.dart` вызывается только для `CardState.newState`: переходы learning→review, review→(next), relearning→… на уровне адаптера не проверены (часть уйдёт в итерацию 2, но маппинг — предмет итерации 0). Нет теста, что локальный `now` нормализуется адаптером в UTC (`_resolveNow`).
Как исправить: 3–4 unit-теста: `fromFsrsState` для всех трёх состояний; `review()` для карточки с `state: learning, step: 1` (Good → review), `state: review` (stability/difficulty заданы → новый due), `state: relearning` (Again → relearning/step 0); тест `preview/review` с `now` в локальной зоне → ожидаемый UTC-`due`.

### 4.3 Low

**L1. Неверная разбивка guard-тестов в журнале.**
`journal/iteration-0/verify.md:39`: «24 passed (no_webview 11, ru_strings 7, no_secrets 6)». Фактически: `no_webview` 8, `ru_strings` 9, `no_secrets` 7 (сумма 24 верна, атрибуция — нет). Числа не скопированы из вывода, а посчитаны с ошибкой. Исправить на 8/9/7.

**L2. Устаревшее число тестов в `STATE.md`.**
`journal/STATE.md:16`: «FSRS … — 17 тестов»; фактически 23 доменных теста (17 в `fsrs_scheduler_test.dart` + 6 в `rating_test.dart`), всего 58 (`verify.md:42`). Исправить.

**L3. Красная фаза зафиксирована только как ошибка компиляции.**
`verify.md:17-28`: `flutter test` падал с `Error when reading 'lib/ui/app.dart'`/`Couldn't find constructor 'CardFlowApp'` — это отказ компиляции из-за отсутствия файлов, а не падение assertions «по ожидаемой причине»; сырого лога нет. Для Dart-TDD это нормально, но B6 («тест был красным по ожидаемой причине») подтверждён косвенно. Рекомендация: в будущих итерациях сохранять фрагмент вывода с ожидаемым сообщением каждого падающего теста (или фиксировать «ожидалось: X, получено: Y»).

**L4. Гранулярность коммитов не соответствует процессу.**
`git log` — 3 коммита на всю итерацию (`20698fe`, `ba4f37a`, `5d9cd95`); `AGENTS.md:42` требует «коммит после каждого зелёного шага». Формальное отклонение; на качество не влияет, но затрудняет археологию. В следующих итерациях — отдельные коммиты red/green/ci/docs.

**L5. UTC-инвариант держится на `assert` (в release отключён); мёртвая ветка.**
`scheduling_card.dart:44-54` — проверки UTC через `assert`, в AOT/release они не выполняются; если контракт жёсткий (SPEC A5, fsrs бросает `ArgumentError`), надёжнее валидировать в теле конструктора исключением (или зафиксировать assert-only как осознанное решение в ADR). `scheduler.dart:119-125` — ветка `isNew` (`state == learning && lastReview == null`) после `reviewCard` недостижима (lastReview всегда устанавливается); удалить или пояснить.

**L6. Слепое пятно учёта покрытия: файлы, не попавшие в lcov, не считаются.**
`tool/coverage_check.dart:49-58` считает только записи из `coverage/lcov.info`; `lib/main.dart` (8 строк, тестами не импортируется) в отчёт не входит — из 91.7%→99.3% он «невидим». Порог 80% при этом не нарушен (с `main.dart`: 135/144 ≈ 93,8%). Как исправить: перечислить ожидаемые рукописные файлы `lib/**/*.dart` (без generated) и падать, если файл не измерен, либо явно задокументировать исключение entrypoint'ов.

**L7. Детекторы `ru_strings` покрывают не все формы литералов.**
`test/guards/ru_strings_test.dart:78-89` ловит только `Text('<литерал>')`; не ловятся `Text.rich`, `SelectableText`, `RichText`/`TextSpan`, `Tooltip(message:)`, литералы в тернарниках/интерполяции внутри `Text(...)`. `:61-75` — allow-list токены вырезаются без границ слов (`MD`, `PDF`…), а `_icuKeywords` вырезают standalone `one/two` вне ICU → возможны false negative (например, текст `one two` пройдёт). Сейчас UI чист, но guard — основная защита для экранов итераций 1–7. Добавить regex на `Text.rich`/`SelectableText`/`RichText`, `\b`-границы, вырезать ICU-ключевые слова только внутри плюральных ветвей, + самопроверки.

**L8. Детектор `no_webview` не ловит часть YAML-форм.**
`test/guards/guard_utils.dart:63-77` — регэксп `^\s+<name>(_[a-z0-9_]+)?\s*:` требует некавыченный ключ в начале строки; обходятся кавычки (`"webview_flutter": ^4.0.0`) и flow-style (`dependencies: {webview_flutter: ...}`). Надёжнее разобрать `pubspec.yaml` и `pubspec.lock` через `package:yaml` (уже в графе как транзитивная) и сверять имена зависимостей; сканирование импортов оставить.

**L9. Android-подготовка под жёсткие требования 3.4/секреты не сделана и не отражена в ограничениях.**
`android/app/src/main/AndroidManifest.xml:3` — launcher-label `"cardflow"` (шаблонное lower-case; для бренда корректнее `CardFlow`/ресурс), и нет `android:allowBackup="false"`/`dataExtractionRules` — `docs/agent-prompt.md:51`/`AGENTS.md:26` требуют исключить secure storage из Android Auto Backup. Т.к. `flutter_secure_storage` пока не используется (итерация 3b), это не блокер, но пункт не записан в `KNOWN_LIMITATIONS.md`; добавить строку known limitation либо выполнить конфигурацию сейчас.

**L10. `dynamic_color` объявлен, но не используется; A4.1 dynamic color не отражён в ограничениях.**
`pubspec.yaml:50` `dynamic_color: ^2.1.0`, при этом `lib/ui/theme/app_theme.dart:18-24` строит тему только из `ColorScheme.fromSeed`, пакет нигде не вызывается. В `KNOWN_LIMITATIONS.md` отложен только M3E-виджет (`L6b`); про dynamic color A4.1 записи нет. Добавить строку (срок — итерация 7, экран настроек/темы) или реализовать при первом реальном экране.

**L11. Устаревшие/несуществующие ссылки в документах.**
`journal/iteration-0/dependency-spike.md:269-281` — §9 «Найденные несоответствия (для исправления Lead'ом)» уже исправлены (material-импорт main.dart, удалён `super_drag_and_drop`, добавлен `environment.flutter`, `freezed_annotation` перенесён), но пометок «исправлено» нет. `journal/iteration-0/plan.md:37` ссылается на несуществующий `test/unit/domain/scheduler_rating_test.dart` (фактически `rating_test.dart` + `fsrs_scheduler_test.dart`). `.gitignore:9` игнорирует `.metadata`, который Flutter рекомендует коммитить (используется для миграций и upgrade). Пометить исправленным/поправить имена.

**L12. Прослеживаемость «задача → тест» для не-поведенческих задач.**
`plan.md:36-40` задачи 0.3 (5 платформ), 0.5 (AGENTS.md), 0.7 (CI-файл) закрыты фактом наличия файлов, но не тестами; B6 «каждая задача закрыта тестом, который был красным до реализации» к ним неприменим буквально. Явно зафиксировать в verify/summary исключение («инфраструктурные задачи подтверждаются командами/файлами, а не падающими тестами»), чтобы чек-лист B6 читался без двусмысленности.

## 5. Анти-читеринг и доказательность

- Тесты не удалялись и не ослаблялись по существу: в `test/guards/*` есть самопроверки детекторов (транзитивный пакет, английский текст, литерал в `Text(...)`, фейковые ключи), фейковый ключ собирается в рантайме, порог покрытия не понижен (`--min=80`), анализатор не отключён (`analysis_options.yaml` — стандартный `flutter_lints`), `// ignore` в рукописном коде нет.
- Единственное фактическое ослабление — M1 (молчаливый пропуск не-UTF-8 файлов), внесённое при исправлении реального падения; требует сузить, а не откатывать.
- Все ключевые числа журнала перепроверены: 58 тестов (мой прогон), analyze 0 issues (мой прогон), 99.3% = 135/136 (пересчёт из lcov), `58 passed` в `verify.md:34`, 99.3% в `README.md:36` и `docs/dependencies.md:167+` — совпадают; разбивка guard-тестов (L1) — единственное расхождение и оно не влияет на вывод.
- Внешние утверждения проверены по первоисточникам: исходники `fsrs 2.0.1`; pub.dev API (`desktop_drop 0.9.2`, `file_picker 13.3.3`); GitHub Actions (существование тегов и output'ов actions); образ `windows-2025` (ATL присутствует); `flutter analyze/test --help` (флаги/дефолты). Выдуманных команд/версий в CI не обнаружено; iOS собирается без подписи (`--no-codesign`), матрица ubuntu/windows/macos на месте, FVM→`flutter-version` связка корректна.
- Лимиты ревью: сборки, `dart format`, `gen-l10n` и фактический CI-прогон не воспроизводились (запрет/нет remote); утверждения о них проверены только по журналу и статически (L3 относится к этому же классу).

## 6. Что осталось до приёмки итерации 0

1. **Обязательно:** финальный checkpoint-коммит с `journal/iteration-0/summary.md` и этим `review.md`; обновить `STATE.md` (шаг 7 → «ревью принято, итерация закрыта»).
2. **Обязательно:** поправить числа в журнале — L1 (`verify.md:39`: 8/9/7) и L2 (`STATE.md:16`: 23 доменных теста / 58 всего), иначе B6 «нет утверждений без доказательств» формально нарушен.
3. **Рекомендуется до приёмки (дёшево):** M1 (сузить пропуск в `no_secrets`), M3 (добавить тест `preview==review` или переформулировать ADR-004), M4 (убрать `--no-fatal-infos`), M5 (синхронизировать `docs/dependencies.md`), M6 (тесты маппинга/переходов FSRS); M2 оформить как задачу итерации 1 (guard архитектурных импортов).
4. **Техдолг (можно в следующие итерации):** L3–L12; L9 (Android backup/label) — не позже итерации 3b (secure storage), L10 — итерации 7.
5. Остаётся в силе известное ограничение: сборки Windows локально нет из-за отсутствия ATL (L2b), CI не запускался (нет remote, L3) — для приёмки итерации 0 допустимо как внешние блокеры, зафиксированные в `KNOWN_LIMITATIONS.md`.

**Итог: ревью завершено. Blocker/critical/high не найдено — итерация 0 готова к приёмке после закрытия пунктов 1–2 (и, желательно, medium-находок M1–M6).**

## 7. Реакция Lead и статус находок (2026-11-11, ~19:45 MSK)

Ревью принято: blocker/critical/high = 0. Medium M1–M6 закрыты до финального checkpoint-коммита; документарные low (L1, L2, L11, L12) исправлены; остальные low либо исправлены, либо зафиксированы как техдолг с адресом.

| Находка | Статус | Что сделано / где |
|---|---|---|
| M1 — `no_secrets` молча пропускал не-UTF-8 | **исправлено** | `readAsBytesSync` + `decodeForScan` (UTF-8, при ошибке latin1 — декодирует любые байты); расширены `binaryExtensions` (`.exp/.lib/.pdb/.obj/.ilk/.res/.snapshot`); самопроверка на cp1251-байтах |
| M2 — нет guard-теста архитектурных правил | **исправлено** | `test/guards/architecture_test.dart`: запрет `package:flutter/material.dart` в `lib/`, `material_3_expressive` только в `lib/ui/m3e/`, domain без Flutter/material_ui/M3E; самопроверки детектора |
| M3 — ADR-004 ссылался на несуществующий тест | **исправлено** | тесты «прогноз == фактический due» для 4 оценок (new и review-карточка) в `fsrs_scheduler_test.dart`; ADR-004 теперь подтверждён |
| M4 — CI `--no-fatal-infos` | **исправлено** | `.github/workflows/ci.yml`: `flutter analyze` без флага (fatal-infos по умолчанию вкл.) |
| M5 — дрейф `docs/dependencies.md` | **исправлено** | `xml ^7.0.1`, `file_picker` — подтверждён caret `^13.3.3` и причина ограничения, добавлена строка `dynamic_color` (Apache-2.0, material.io, Android/Linux/macOS/Windows, план — итерация 7), `riverpod`/`path` помечены транзитивными, строка `test` убрана (API даёт `flutter_test`) |
| M6 — неполные тесты FSRS | **исправлено** | `fromFsrsState` для всех трёх состояний (включая relearning), переходы learning→review / review→relearning / relearning→review, нормализация локального `now` в UTC |
| L1 — разбивка guard-тестов | **исправлено** | `verify.md`: фактически 34 guard-теста (architecture 6, no_webview 9, ru_strings 11, no_secrets 8), всего 75 |
| L2 — «17 тестов» в STATE | **исправлено** | `STATE.md`: 75 тестов, домен FSRS — тесты маппинга/интервалов/переходов |
| L3 — красная фаза только compile-level | **зафиксировано** | оговорка в `verify.md` §2; процессное улучшение: с итерации 1 assertion-level red с фрагментом вывода |
| L4 — гранулярность коммитов | **принято как отклонение** | итерация 0: bootstrap → scaffold+green → hardening/docs → финальный checkpoint; с итерации 1 — коммит на каждый зелёный шаг |
| L5 — UTC-инвариант на assert; мёртвая ветка | **исправлено частично** | мёртвая ветка `isNew` удалена (`scheduler.dart`); assert-only зафиксирован как осознанное решение в doc-комментарии `SchedulingCard` (в release инвариант обеспечивает адаптер) |
| L6 — слепое пятно покрытия | **исправлено** | `tool/coverage_check.dart` выводит рукописные файлы, отсутствующие в lcov (`lib/main.dart`, `lib/ui/m3e/m3e.dart` — entrypoint/export-only, без исполняемых строк) |
| L7 — узкие детекторы `ru_strings` | **исправлено** | ловятся `SelectableText(...)` и `Text.rich(TextSpan(text: ...))`; allow-list — по границам слов (`MD` разрешён, `MDX` — нет); самопроверки |
| L8 — YAML-формы в `no_webview` | **исправлено** | `findForbiddenPackages` ловит блочный, кавычечный и flow-style YAML; самопроверки |
| L9 — Android label/allowBackup | **исправлено** | `AndroidManifest.xml`: `android:label="CardFlow"`, `android:allowBackup="false"`, `android:fullBackupContent="false"` |
| L10 — `dynamic_color` без записи в ограничениях | **исправлено** | `KNOWN_LIMITATIONS.md` L6c (динамическая тема — итерация 7) |
| L11 — устаревшие ссылки | **исправлено** | `dependency-spike.md` §9 — пометка «исправлено»; `plan.md` — корректные пути тестов; `.metadata` больше не игнорируется и коммитится |
| L12 — прослеживаемость инфраструктурных задач | **исправлено** | пометка в `verify.md` §8: задачи 0.3/0.5/0.7 подтверждаются командами/файлами (B6 к ним неприменим буквально) |

Финальные гейты после правок: `fvm flutter test` — **75 passed**; `fvm flutter analyze` — **No issues found**; `fvm dart format` — 0 changed; покрытие рукописного `lib/` — **100% (135/135)**, вне подсчёта только entrypoint/export-only файлы. Повторного независимого ревью не требовалось: все правки — точечные ответы на findings, blocker/critical/high не появлялись.
