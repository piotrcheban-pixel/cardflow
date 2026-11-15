# Зависимости CardFlow

**Дата проверки:** 2026-11-11 · **Автор:** deps-researcher (task-1, итерация 0)
**Метод:** каждый пакет проверен по pub.dev API (`https://pub.dev/api/packages/<name>`, `https://pub.dev/api/packages/<name>/score`), странице пакета и исходникам репозитория. Версии — реально существующие на 2026-11-11, не по памяти.
**Доказательства и ссылки:** `journal/iteration-0/dependency-spike.md`.

## 0. Закреплённая версия Flutter / Dart

| Что | Значение | Источник |
|---|---|---|
| Flutter | **3.47.9 stable** (релиз 2026-10-29, hash `c197ca5199e9ee5661e865596c9c07294dfab51c`) | [releases_windows.json](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json) |
| Dart | **3.13.7** (поставляется с Flutter 3.47.9) | там же, поле `dart_sdk_version` |
| FVM | 4.3.2, конфиг `.fvmrc` = `{"flutter": "3.47.9"}` | проверено в рабочем дереве |
| `environment:sdk` | `^3.13.7` | фактический pubspec (итерация 0); удовлетворяет требованию `material_ui` 1.11.0 (`sdk: ^3.13.0`) |
| `environment:flutter` | `>=3.47.0` | фактический pubspec; требование `material_ui` 1.11.0 / `material_3_expressive` 1.2.0 / `pdfrx` 2.12.0 |

> Все команды — только через FVM (`fvm flutter pub get`, `fvm flutter test`, …), см. `AGENTS.md`.

## 1. Ключевое архитектурное решение по базе Material

`go_router` 18.1.4, `flutter_riverpod` 3.5.0 и `pdfrx` 2.12.0 **уже зависят от `material_ui` ^1.0.0** (первоисточники: pubspec пакетов + CHANGELOG go_router «18.0.0 — Migrates to material_ui and cupertino_ui», CHANGELOG flutter_riverpod «3.5.0 — Migrated Material imports to package:material_ui/material_ui.dart»). Поэтому приложение строим на официальном пакете `material_ui` 1.11.0 (publisher `flutter.dev`), а не на `package:flutter/material.dart`. Это описано в **ADR-001**.

> **Статус реализации (итерация 0):** миграция выполнена — `lib/ui/app.dart` и `lib/ui/theme/app_theme.dart` импортируют `package:material_ui/material_ui.dart`, локализация — `GlobalMaterialLocalizations.delegates` из `material_ui`; widget-тест проверяет русские системные строки («Отмена», «Вставить», «ОК»). `M3EMaterialApp` пока не используется: первый M3E-экран появится в итерации 1 (spike S2 продолжается там).

## 2. Основные зависимости (runtime)

| Пакет | Версия (constraint) | Зачем (SPEC) | Платформы | Лицензия | Вердикт |
|---|---|---|---|---|---|
| [material_ui](https://pub.dev/packages/material_ui) | `^1.11.0` | база Material (офиц. decoupled-библиотека); нужна `go_router`/`flutter_riverpod`/`pdfrx`; содержит официальные M3E-токены (`Springs`, `MaterialShapes`, `StyleVariant`) | Android, iOS, Linux, macOS, Windows, Web | BSD-3-Clause | approved · needs-runtime-spike (миграция импортов + l10n-делегаты) |
| [material_3_expressive](https://pub.dev/packages/material_3_expressive) | `^1.2.0` | M3 Expressive-компоненты за `lib/ui/m3e/` (ADR-001) | Android, iOS, Linux, macOS, Windows, Web | MIT | approved · needs-runtime-spike |
| [fsrs](https://pub.dev/packages/fsrs) | `^2.0.1` | FSRS-6: 21 вес, `desiredRetention`, `learningSteps` (A3, A7) | чистый Dart (все) | MIT | **approved** (API выписан в спайке) |
| [drift](https://pub.dev/packages/drift) | `^2.35.4` | типобезопасная SQLite + миграции (A3, A5) | чистый Dart (все) | MIT | approved |
| [drift_flutter](https://pub.dev/packages/drift_flutter) | `^0.3.1` | открытие БД на Flutter-платформах (офиц. рекомендация drift 2.35.4) | flutter-пакет (все) | MIT | approved · **не добавлен в итерации 0** (вручную не подключали: тянет EOL-заглушки; решение по открытию БД и native assets — итерация 1) |
| [sqlite3](https://pub.dev/packages/sqlite3) | `^3.9.1` | нативная SQLite через FFI + Dart hooks (native assets) | все | MIT | approved · needs-runtime-spike (native assets на 5 платформах) |
| [dio](https://pub.dev/packages/dio) | `^5.11.1` | HTTP + перехватчики/ретраи (A8.2, A8.6) | чистый Dart | MIT | approved |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | `^11.2.0` | ключи API только здесь (A1.3, A8.6) | Android, iOS, Linux, macOS, Windows, Web | BSD-3-Clause | approved · minSdk 23; Android `allowBackup=false` |
| [json_schema](https://pub.dev/packages/json_schema) | `^5.2.2` | локальная валидация ответа модели по A8.4 | чистый Dart | Boost-1.0 (LICENSE в репо; pub.dev license-tag отсутствует) | **approved** · runtime-спайк итерации 3b S1: каноническая схема A8.4 валидируется, нарушения ловятся (`ValidationResults.errors`); fallback `json_schema_builder` не нужен |
| [flutter_math_fork](https://pub.dev/packages/flutter_math_fork) | `^0.7.4` | единственный разрешённый LaTeX-рендер (A1/AGENTS); проверка формул при генерации (A8.4) | Android, iOS, Linux, macOS, Windows, Web | Apache-2.0 | approved · спайк итерации 3b S2: `Math.tex(expression).parseError` проверяет валидность LaTeX без рендера и биндинга (`\frac{`/неизвестная команда → ошибка); сам рендер с кириллицей — итерации 5/6 |
| [archive](https://pub.dev/packages/archive) | `^4.6.0` | `.zip` экспорт/импорт; ZIP-контейнер DOCX/PPTX/ODT/XLSX (A8.3) | чистый Dart | MIT | approved |
| [xml](https://pub.dev/packages/xml) | `^7.0.1` (факт; кандидат был 7.1.0 ниже sdk-constraint) | разбор XML внутри DOCX/PPTX/ODT/XLSX (A8.3) | чистый Dart | MIT | approved |
| [excel_plus](https://pub.dev/packages/excel_plus) | `^2.29.2` | XLSX (замена устаревшего `excel`); читает и legacy `.xls` (BIFF8) — кандидат для ADR-003 | чистый Dart | MIT | approved · needs-runtime-spike (A8.3 «формулы по кэшированному значению», фикстуры) |
| [file_picker](https://pub.dev/packages/file_picker) | `^13.3.3` | пикер файлов (A6.8/A8.3) | Android, iOS, Linux, macOS, Windows, Web | MIT | approved · версия ниже 12 конфликтует с `desktop_drop 0.9.x`; берём 13.3.3 + `desktop_drop 0.8.4` (см. §7) |
| [desktop_drop](https://pub.dev/packages/desktop_drop) | **`^0.8.4`** (факт; кандидат был `^0.9.2`) | drag-n-drop на ПК (A3/A6.8) | Android, iOS, Linux, macOS, Windows, Web | Apache-2.0 | approved с ограничением: `desktop_drop >=0.9.0` требует `cross_file ^0.4.0`, а `file_picker >=12` — `cross_file ^0.3.5+4`; совместная версия невозможна. Взят 0.8.4 (`cross_file ^0.3.4+2`). `super_drag_and_drop` 0.9.1 не разрешился (старый `super_native_extensions`); его ветка 0.1.9+3 неприемлема. **Итерация 3c:** 0.8.4 используется в A6.8 (`DropTarget`), API стабилен, widget-тесты зелёные; реальный drag — L33, ограничение L8 остаётся |
| [url_launcher](https://pub.dev/packages/url_launcher) | `^6.3.3` | «Где взять ключ», лицензии — системный браузер (A3) | Android, iOS, Linux, macOS, Windows, Web | BSD-3-Clause | approved |
| [pdfrx](https://pub.dev/packages/pdfrx) | `^2.12.0` | текстовый слой PDF через PDFium/FFI (A8.3) | Android, iOS, Linux, macOS, Windows, Web | MIT (PDFium — BSD-3-Clause) | approved · needs-runtime-spike (Windows: Developer Mode для сборки) |
| [go_router](https://pub.dev/packages/go_router) | `^18.1.4` | роутинг (AGENTS) | все (flutter) | BSD-3-Clause | approved · требует `material_ui ^1.0.0` |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | `^3.5.0` | управление состоянием, manual providers без кодогенерации (ADR-002) | все (flutter) | MIT | **approved** |
| [riverpod](https://pub.dev/packages/riverpod) | `^3.5.0` (транзитивно) | `ProviderContainer`/провайдеры в чистых Dart-тестах domain | чистый Dart | MIT | approved · приходит транзитивно с `flutter_riverpod`; в pubspec не добавлялся |
| [path_provider](https://pub.dev/packages/path_provider) | `^2.1.6` | каталоги БД/медиа | Android, iOS, Linux, macOS, Windows | BSD-3-Clause | approved |
| [uuid](https://pub.dev/packages/uuid) | `^4.6.0` | `TEXT PRIMARY KEY` id (A5) | чистый Dart | MIT | approved |
| [crypto](https://pub.dev/packages/crypto) | `^3.0.8` | `content_hash` (A5, дедупликация A8.5) | чистый Dart | BSD-3-Clause | approved |
| [intl](https://pub.dev/packages/intl) | `^0.20.3` | даты/числа/ICU-плюрализация | чистый Dart | BSD-3-Clause | approved · **жёстко** `^0.20.3`: `flutter_localizations` 3.47.9 пинит этот constraint |
| [dynamic_color](https://pub.dev/packages/dynamic_color) | `^2.1.0` | dynamic color (A4.1): Android 12+ / Linux / macOS / Windows; публикатор material.io, Apache-2.0 | Android, Linux, macOS, Windows (на iOS — no-op) | Apache-2.0 | approved · **пока не используется**, подключается в итерации 7 (KNOWN_LIMITATIONS L6c) |
| [path](https://pub.dev/packages/path) | `^1.9.1` (транзитивно) | пути к файлам | чистый Dart | BSD-3-Clause | approved · транзитивная зависимость; прямой необходимости в pubspec пока нет |
| [collection](https://pub.dev/packages/collection) | `^1.19.1` | утилиты коллекций | чистый Dart | BSD-3-Clause | approved |
| [enough_convert](https://pub.dev/packages/enough_convert) | `^1.7.1` | кодировки для TXT/MD/RTF (A8.3): Windows-1251 (cp1251) и **KOI8-R**/KOI8-U, ISO-8859, DOS, GBK, Big5 | чистый Dart | MPL-2.0 | approved · **добавлен в итерации 3a**; покрыт тестами (spike S-ENC, RTF/TXT-тесты) |
| `flutter` | SDK | UI | — | BSD-3-Clause | approved |
| `flutter_localizations` | SDK | системные строки Flutter/Material для `ru` | — | BSD-3-Clause | approved · делегаты — из `material_ui` (см. ADR-001) |
| [freezed_annotation](https://pub.dev/packages/freezed_annotation) | `^3.1.0` | аннотации для `*.freezed.dart` | чистый Dart | MIT | approved (runtime-зависимость) |
| [json_annotation](https://pub.dev/packages/json_annotation) | `^4.12.0` | аннотации для `*.g.dart` | чистый Dart | BSD-3-Clause | approved (runtime-зависимость) |

## 3. Dev-зависимости

| Пакет | Версия | Зачем | Лицензия | Вердикт |
|---|---|---|---|---|
| [drift_dev](https://pub.dev/packages/drift_dev) | `^2.35.3` | генерация drift-кода | MIT | approved |
| [build_runner](https://pub.dev/packages/build_runner) | `^2.17.1` | кодогенерация | BSD-3-Clause | approved |
| [freezed](https://pub.dev/packages/freezed) | `^4.0.3` | immutable-модели | MIT | approved (sdk `>=3.13.0` — совпадает с пином) |
| [json_serializable](https://pub.dev/packages/json_serializable) | `^6.15.2` | JSON-сериализация | BSD-3-Clause | approved |
| [flutter_lints](https://pub.dev/packages/flutter_lints) | `^6.0.0` | анализатор | BSD-3-Clause | approved |
| [mocktail](https://pub.dev/packages/mocktail) | `^1.0.5` | моки (без кодогенерации) | MIT | approved |

## 4. Отклонённые / заменённые пакеты

| Пакет | Факт | Причина отказа |
|---|---|---|
| [excel](https://pub.dev/packages/excel) `4.0.6` | последний релиз **2024-08-20** (>2 лет); последний коммит репо 2025-07 | мёртв по правилу «нет релизов >2 лет» → заменён `excel_plus ^2.29.2` |
| [syncfusion_flutter_pdf](https://pub.dev/packages/syncfusion_flutter_pdf) `35.1.46` | README: «This is a commercial package… need either a Syncfusion commercial license or Free Syncfusion Community license»; pub.dev license-tag `unknown` | платная лицензия → **только по согласию владельца**; для MVP выбран pdfrx |
| [super_drag_and_drop](https://pub.dev/packages/super_drag_and_drop) `0.9.1` | релиз 2025-06-11; тянет Rust-нативные `super_native_extensions` | старше и тяжелее; выбран `desktop_drop` 0.9.2 (2026-10-20, все платформы) |
| [sqlite3_flutter_libs](https://pub.dev/packages/sqlite3_flutter_libs) `0.6.0+eol` | описание: «Not used anymore, update to version 3.x of package:sqlite3» | EOL; не добавлять вручную (транзитивно-заглушка от `drift_flutter`) |
| [sqlcipher_flutter_libs](https://pub.dev/packages/sqlcipher_flutter_libs) `0.7.0+eol` | EOL | шифрование БД в SPEC не требуется |
| [fsrs_dart](https://pub.dev/packages/fsrs_dart) `0.1.0` | 2026-09-16, 0 likes, зависимости `code_assets`, `native_toolchain_rust`, `ffi` | Rust-сборка на 5 платформ = риск; версия 0.1.0. Отклонён |
| [dart_srs](https://pub.dev/packages/dart_srs) `1.0.1` | MIT, 2026-05-24, «FSRS-6-style», 1 like, storage-agnostic | свой движок сессий; не reference-реализация. Отклонён (SPEC называет `fsrs`) |
| `dart_fsrs` | на pub.dev **не существует** (HTTP 404 `NoSuchKey`) | — |
| [cfb](https://pub.dev/packages/cfb) `0.0.1` | 2020-08-01, `sdk: >=2.7.0 <3.0.0`, 1 like, license unknown, описание-заглушка | несовместим с Dart 3, мёртв → ADR-003 |
| [charset](https://pub.dev/packages/charset) `2.0.1` | Apache-2.0, 2023-06-25, 27 likes; покрывает windows-1251 и ISO-8859, но **KOI8-R в исходниках нет** (проверено по `lib/src/`: таблиц koi8 нет) | не покрывает требование A8.3 (cp1251 **и** koi8-r) → заменён `enough_convert`; fallback: `charset` + собственные 128-символьные таблицы KOI8-R |
| [m3e_design](https://pub.dev/packages/m3e_design) `0.2.1` / [m3e_collection](https://pub.dev/packages/m3e_collection) `0.3.7` / [m3_expressive](https://pub.dev/packages/m3_expressive) `1.0.0` / [expressive_m3](https://pub.dev/packages/expressive_m3) `0.2.0` / [m3e_core](https://pub.dev/packages/m3e_core) `1.1.5` | см. ADR-001 | не выбраны как M3E-база |
| [webview_flutter](https://pub.dev/packages/webview_flutter), [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview), [flutter_html](https://pub.dev/packages/flutter_html) | — | **запрещены SPEC A3/AGENTS**, включая транзитивные |

## 5. Предлагаемый блок `pubspec.yaml` (исходная рекомендация спайка)

> **Фактический `pubspec.yaml` после итерации 0 — в разделе 7.** Этот блок — исходная рекомендация; от неё есть отступления (desktop_drop, drift_flutter, enough_convert, annotations перенесены в dependencies), зафиксированные в §7.

```yaml
environment:
  sdk: ^3.13.0
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # Material base + M3 Expressive (ADR-001)
  material_ui: ^1.11.0
  material_3_expressive: ^1.2.0

  # Domain / DB / state
  fsrs: ^2.0.1
  drift: ^2.35.4
  drift_flutter: ^0.3.1
  sqlite3: ^3.9.1
  flutter_riverpod: ^3.5.0
  riverpod: ^3.5.0

  # API / files
  dio: ^5.11.1
  flutter_secure_storage: ^11.2.0
  json_schema: ^5.2.2
  archive: ^4.6.0
  xml: ^7.1.0
  excel_plus: ^2.29.2
  pdfrx: ^2.12.0
  enough_convert: ^1.7.1

  # UI / navigation / platform
  flutter_math_fork: ^0.7.4
  go_router: ^18.1.4
  file_picker: ^13.3.3
  desktop_drop: ^0.9.2
  url_launcher: ^6.3.3

  # Utils
  path_provider: ^2.1.6
  path: ^1.9.1
  collection: ^1.19.1
  uuid: ^4.6.0
  crypto: ^3.0.8
  intl: ^0.20.3
  freezed_annotation: ^3.1.0
  json_annotation: ^4.12.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  drift_dev: ^2.35.3
  build_runner: ^2.17.1
  freezed: ^4.0.3
  json_serializable: ^6.15.2
  flutter_lints: ^6.0.0
  test: ^1.33.0
  mocktail: ^1.0.5
```

## 6. Примечания и риски

1. **`material_ui` — не «ещё один пакет», а замена `package:flutter/material.dart`.** Импорты Material — только `package:material_ui/material_ui.dart`; для совместимости со старыми пакетами, ждущими framework-Material, в README предусмотрен `MaterialUiCompatibilityBridge`. Миграция — `dart fix --apply --code=migrate_design_widgets`. Подробности и альтернативы — ADR-001.
2. **Локализация.** `material_ui` содержит `material_ru.arb`; делегаты для системных строк — `GlobalMaterialLocalizations.delegates` из `material_ui` (README пакета). Проверить в спайке: `supportedLocales: [Locale('ru')]`, русские системные строки.
3. **`intl` нельзя поднимать выше `^0.20.3`** — `flutter_localizations` из Flutter 3.47.9 объявляет `intl: ^0.20.3`; `material_ui` объявляет `intl: ^0.20.2`. Совместимая версия ровно 0.20.3.
4. **`sqlite3_flutter_libs` больше не нужен** (EOL). `drift_flutter 0.3.1` всё ещё объявляет его как no-op-заглушку `^0.6.0+eol`; это нормально, но в `pubspec.yaml` его добавлять не надо. Нативная SQLite теперь ставится `sqlite3 ^3.9.1` через Dart hooks (native assets) — проверить `flutter build windows` после установки Flutter.
5. **Guard `no_webview`:** транзитивно приходят пакеты `web`, `web_socket_channel`, `flutter_web_plugins`, `file_picker_web` — это dart:js/веб-интероп, **не** WebView. Блокировать нужно только `webview_flutter`, `flutter_inappwebview` (`flutter_inappwebview_*`), `flutter_html` (`flutter_html_*`).
6. **pdfrx и Windows:** для сборки на Windows **обязательно включён Developer Mode** (README pdfrx); сборка требует C-тулчейна (VS Build Tools на хосте есть по факту итерации 0). Зафиксировать в `KNOWN_LIMITATIONS.md`, если Developer Mode выключен.
7. **needs-runtime-spike** (проверить после установки Flutter 3.47.9): `fvm flutter pub get` (весь граф), `material_ui`+`material_3_expressive` (сборка минимального экрана, ru-локаль), `drift`+`sqlite3` (открытие БД на Windows), `pdfrx` (извлечение текста `PdfPage.loadText()`), `json_schema` (**выполнено — итерация 3b S1**), `flutter_math_fork` (**проверка формул — выполнено, итерация 3b S2**; рендер с кириллицей — итерации 5/6), `excel_plus` (чтение XLSX-фикстуры, кэшированные значения формул), `enough_convert` (cp1251 и KOI8-R), `fsrs` (интервалы для 4 оценок).
8. **Версии — стабильные на 2026-11-11**; при `pub get` допустимы только патч-обновления в рамках указанных caret-constraint'ов. Любой breakout — через ADR.

## 7. Фактическое состояние после итерации 0 (2026-11-11)

Источник — `pubspec.yaml` / `pubspec.lock` рабочего дерева; проверено `fvm flutter pub get` (успех) и `fvm flutter analyze` (0 issues), `fvm flutter test` (58 тестов зелёные, покрытие рукописного `lib/` — 99.3%).

**Фактические версии DIRECT-зависимостей (из pubspec.lock):**

`material_ui 1.11.0`, `material_3_expressive 1.2.0`, `fsrs 2.0.1`, `drift 2.35.4`, `sqlite3 3.9.1`, `flutter_riverpod 3.5.0`, `riverpod 3.5.0` (транзитивно), `go_router 18.1.4`, `dio 5.11.1`, `flutter_secure_storage 11.2.0`, `json_schema 5.2.2`, `archive 4.6.0`, `xml 7.0.1`, `excel_plus 2.29.2`, `pdfrx 2.12.0`, `file_picker 13.3.3`, `desktop_drop 0.8.4`, `url_launcher 6.3.3`, `flutter_math_fork 0.7.4`, `path_provider 2.1.6`, `dynamic_color 2.1.0`, `uuid 4.6.0`, `crypto 3.0.8`, `collection 1.19.1`, `intl 0.20.3`, `freezed_annotation 3.1.0`, `json_annotation 4.12.0`; dev: `build_runner 2.17.1`, `drift_dev 2.35.3`, `freezed 4.0.3`, `json_serializable 6.15.2`, `mocktail 1.0.5`, `flutter_lints 6.0.0`.

**Отступления от исходной рекомендации §2/§5 и причины:**

| Отступление | Причина | Статус |
|---|---|---|
| `desktop_drop` 0.8.4 вместо 0.9.2 | конфликт `cross_file`: `desktop_drop >=0.9.0` → `^0.4.0`, `file_picker >=12` → `^0.3.5+4`; версии несовместимы. 0.8.4 использует `cross_file ^0.3.4+2` | зафиксировано; пересмотр в итерации 3c (DnD-экран) |
| `drift_flutter` не добавлен | тянет EOL-заглушки (`sqlite3_flutter_libs 0.6.0+eol`); открытие БД — вручную через `sqlite3` 3.9.1 (native assets) | **подтверждено в итерации 1 (ADR-005):** спайк S3 успешен, `openAppDatabase()` работает; CI-сборки — до пуша |
| `sqlite3_flutter_libs` не добавлен | EOL (описание пакета); SQLite ставится пакетом `sqlite3 ^3.9.1` через Dart build hooks | проверено: `dart run tool/coverage_check.dart` собрал native assets на Windows |
| `enough_convert` не добавлен | нужен только парсерам кодировок в итерации 3a | **добавлен в итерации 3a** (2026-11-13) |
| `freezed_annotation`, `json_annotation` | перенесены из dev_dependencies в dependencies: сгенерированный код импортирует их из `lib/` | исправлено в pubspec |
| `flutter` SDK-пакет: Material-импорты | `lib/` использует `package:material_ui/material_ui.dart` (ADR-001); `package:flutter/material.dart` в `lib/` не встречается | выполнено, проверено ревью |
| `desktop_drop`/`super_drag_and_drop` | выбран один пакет (SPEC A3), `super_drag_and_drop` удалён из pubspec | выполнено |
| `test ^1.33.0` не добавлен | `flutter_test` уже даёт test API; отдельный `test` не нужен | осознанное отступление |

**Runtime-спайки, выполненные в итерации 0:** S1 (`pub get` графа — успех), S2 частично (M3E-библиотека компилируется, токены `M3EMotion` совпадают со SPEC A4.4 в тесте; `M3EMaterialApp` — итерация 1), S3 частично (native assets `sqlite3` собрались при `dart run`), S9 (FSRS: интервалы 4 оценок, см. тесты). **S6 (`json_schema`, валидация A8.4) выполнен в итерации 3b — см. §11; S7 (`flutter_math_fork`) — проверка формул выполнена в 3b, рендер с кириллицей — итерации 5/6.** Не выполнены: S4, S5, S8, S10 — вынесены в итерации 1/3a/3b/5 (см. `journal/iteration-0/dependency-spike.md` §7 и `journal/KNOWN_LIMITATIONS.md`).

## 8. Фактическое состояние после итерации 1 (2026-11-12)

Источник — `pubspec.yaml`/`pubspec.lock` рабочего дерева; проверено в сессии итерации 1 (команды и вывод — `journal/iteration-1/verify.md`).

**Изменения зависимостей:** добавлен прямой `path ^1.9.1` (BSD-3-Clause; был транзитивным) — нужен для склейки путей к БД/медиа (`lib/data/db/database_opener.dart`, `lib/data/transfer/media_store.dart`); в §2 указан как «прямой необходимости пока нет» — теперь необходимость появилась. Новых сторонних пакетов в итерации 1 **не добавлялось**.

**Runtime-спайки итерации 1:**

| Спайк | Результат |
|---|---|
| S2 — M3 Expressive на реальном экране | **успешен:** под M3ETheme работают `M3ECard`, `M3EChip` (filter), `M3ESnackbar`, `M3EExtendedFab`, `M3ESplitButton`; `M3EMaterialApp` не используется — не принимает `routerConfig`/GoRouter (ADR-007). Замен на `material_ui` не потребовалось. |
| S3 — нативный SQLite | **успешен:** `sqlite3` 3.9.1 (libsqlite3 3.54.1) native assets работают и в `dart run`, и в `flutter test`; `drift` `NativeDatabase` + `path_provider` без `drift_flutter` (ADR-005). |
| S2b — `file_picker` 13.3.3 | **API-drift:** `saveFile` — статический, сам записывает байты и возвращает `Uri?` (на mobile `content://`); параметры `type`/`allowedExtensions` помечены deprecated и не используются. Контракт `FileGateway.saveZipFile(...)` (ADR-006 п.9) учитывает это. |

**Фактические версии direct-зависимостей:** без изменений относительно §7 плюс `path 1.9.1`. `drift` 2.35.4 / `drift_dev` 2.35.3, `sqlite3` 3.9.1 (libsqlite3 3.54.1), `archive` 4.6.0, `file_picker` 13.3.3 — фактические из pubspec.lock.

**CI:** прогон для итерации 1 не выполнялся (push — только по команде владельца). Сборки под 5 платформ с native assets — известное ограничение L9/L9b до прогона CI.

## 9. Фактическое состояние после начала итерации 3a (2026-11-13)

**Добавлено:** `enough_convert ^1.7.1` (MPL-2.0) — кодировки TXT/MD/RTF (A8.3): Windows-1251 и KOI8-R; в §2 значился как «добавить в итерации 3a» — добавлен. `fvm flutter pub get` → `+ enough_convert 1.7.1`, граф зависимостей разрешён.

**Runtime-спайки итерации 3a** (`journal/iteration-3a/spikes.md`, `test/spike/parser_spike_test.dart`, 5/5 зелёные; файл спайка после прогона удалён):

| Спайк | Результат |
|---|---|
| S-ENC — `enough_convert` 1.7.1 | **успешен:** `Windows1251Codec` и `Koi8rCodec` (именно так; не `Koi8RCodec`) encode/decode roundtrip для русского текста; `name` = `windows-1251`, `KOI8-R`. Encode ограничен картой символов (для фикстур учесть), decode — без ограничений |
| S-OOXML — `archive` 4.6.0 + `xml` 7.0.1 | **успешен:** zip-контейнер DOCX/PPTX/ODT разбирается; в `xml` 7 у `XmlElement` нет значения в `.value` — текст берётся `element.innerText` |
| S-XLSX — `excel_plus` 2.29.2 | **успешен:** `Excel.decodeBytes` читает минимальный XLSX; формула приходит как `FormulaCellValue`, `toString()` = формула, а **`cachedValue`** = значение из `<v>` (SPEC A8.3: «формулы — по кэшированному значению») |
| S-PDF — `pdfrx` 2.12.0 | **успешен:** `pdfrxInitialize()` (Dart-вариант, без Flutter-binding) + `PdfDocument.openData` + `page.loadText()` → текст «Hello CardFlow PDF» из программно собранного PDF |
| S-PDF-isolate — `Isolate.run` | **успешен:** извлечение текста PDF работает внутри отдельного изолята (`pdfrxInitialize` внутри изолята) — A8.3 «тяжёлые файлы в изоляте» выполнимо для всех форматов |

**CI/L26 (подтверждено прогоном 43484685899):** тесты PDF-парсера в `flutter test` на Linux/macOS не получают PDFium из native assets; исправлено CI-бутстрапом pinned PDFium (`bblanchon/pdfium-binaries` `chromium/8125`, sha256, `PDFIUM_PATH`) на всех трёх ОС — см. §10, ADR-010 §11 и `journal/iteration-3a/fix-l26.md`.

## 10. Фактическое состояние после итерации 3a (2026-11-13)

**Новых пакетов, кроме `enough_convert ^1.7.1` (добавлен на шаге спайков), не добавлялось.** Парсеры A8.3 собраны на уже проверенных зависимостях: `archive` 4.6.0 + `xml` 7.0.1 (DOCX/PPTX/ODT, ZIP-хелпер), `excel_plus` 2.29.2 (XLSX), `pdfrx` 2.12.0 (PDF), `enough_convert` 1.7.1 (cp1251/KOI8-R), собственный минимальный RTF-конвертер (внешних пакетов нет — требование SPEC A8.3).

**Runtime-проверки итерации 3a** (`fvm flutter test --exclude-tags golden`, локально Windows, **603 теста**):

| Пакет | Результат |
|---|---|
| `enough_convert` 1.7.1 | Windows-1251 и KOI8-R encode/decode — работает; RTF `'hh` с codepage 1251/20866/21866 и TXT-определение кодировки покрыты тестами |
| `archive` 4.6.0 | `ZipDecoder` в строгом режиме (`verify: true, throwOnError: true`) корректно отвергает повреждённый/обрезанный ZIP (`SecureZip`); `ZipEncoder` — фикстуры в тестах |
| `xml` 7.0.1 | разбор OOXML/ODF, `innerText` (в 7.x `.value` у элемента нет); поиск по локальным именам и `r:id` — работает |
| `excel_plus` 2.29.2 | `FormulaCellValue.cachedValue` (кэш формулы), `DateCellValue`/`DateTimeCellValue`, inlineStr, несколько листов — работает; формула без кэша отдаётся как `=формула` (ADR-010 §5) |
| `pdfrx` 2.12.0 | `pdfrxInitialize()` + `PdfDocument.openData` + `page.loadText()` — работает в `flutter test` на Windows, в том числе внутри `Isolate.run`; скан → `scannedPdf`, запароленный PDF (V1/R2 RC4 40-bit фикстура) → `unreadableFile`, многостраничный PDF — ок |

**Покрытие нового кода** (`fvm dart run tool/coverage_check.dart --min=80`): итого **95.3% (3152/3309)**; по новым файлам: `file_parsing_service` 100%, `odt_parser` 100%, `parsed_document_builder` 100%, `xml_local_names` 100%, `parsed_document` 100%, `pdf_parser` 85.3%, `docx_parser` 98.7%, `pptx_parser` 98.2%, `zip_xml` 96.8%, `txt_parser` 96.3%, `xlsx_parser` 94.7%, `rtf_parser` 89.0%, `document_format` 94.1%.

**CI:** прогон итерации 3a [`43484685899`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43484685899) выявил L26 (PDFium не грузился в `flutter test` на Linux/macOS); фикс — PDFium-бутстрап на всех трёх ОС (pinned `chromium/8125` + sha256 + `PDFIUM_PATH`) и guard `test/guards/ci_pdfium_test.dart` (ADR-010 §11). **Зелёный прогон после фикса — [43491786199](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43491786199)**: 9/9 job success, PDF-тесты реально прошли на ubuntu/macos/windows (по 603 теста), PDFium грузился из `PDFIUM_PATH`; L26 снят.

## 11. Фактическое состояние после итерации 3b (2026-11-13)

**Новых пакетов не добавлялось.** API-слой генерации собран на уже проверенных зависимостях:
`dio` 5.11.1 (HTTP, собственный цикл ретраев + redaction-перехватчик), `json_schema` 5.2.2 (валидация A8.4),
`flutter_math_fork` 0.7.4 (проверка формул A8.4), `flutter_secure_storage` 11.2.0 (ключи API). Собственных
реализаций: каноническая схема и проекции под провайдеров (`lib/api/generation/`), retry-политика,
санитайзеры логов, хранилище ключей поверх secure storage — внешние пакеты не добавлялись.

**Runtime-спайки итерации 3b** (`journal/iteration-3b/spikes.md`):

| Спайк | Результат |
|---|---|
| S1 — `json_schema` 5.2.2 против A8.4 | **успешен:** `JsonSchema.create(map)` + `validate(json).isValid`/`.errors`; валидная карточка → true, лишнее свойство/отсутствующий `required`/неверный тип → false с путями ошибок; работает в чистом Dart (`fvm dart run`) |
| S2 — `flutter_math_fork` 0.7.4, проверка LaTeX | **успешен:** `Math.tex(expression).parseError` — публичное поле; валидная формула → null, `\frac{`/`\unknowncommand{x}` → ошибка; без `WidgetsBinding`, в `flutter test` |
| S3 — fake `HttpClientAdapter` Dio 5.11.1 | **успешен:** `ResponseBody.fromString`/`fromBytes` + `validateStatus`; Dio сам бросает `DioException` для не-2xx → retry/429/5xx/401/отмена тестируются без сети |

**Проверки итерации 3b:** полный прогон, покрытие, Windows-сборка и сверка критериев C1–C15 —
`journal/iteration-3b/verify.md`; итог — `journal/iteration-3b/summary.md`.


## 12. Фактическое состояние после итерации 7 (2026-11-14)

**Новых пакетов нет.** Статистика и настройки собраны на существующих зависимостях: drift
(`app_settings`), Riverpod без кодогенерации, `dynamic_color` 2.1.0 (впервые задействован — ADR-019),
`url_launcher` 6.3.3 (политика приватности), стандартные `material_ui`-виджеты и `CustomPainter`
(без графических библиотек). Ключ проверяется существующими адаптерами провайдеров и
`GenerationHttpClient`.

**Продуктовый ассет (не пакет):** `assets/fonts/OpenDyslexic-Regular.otf` (SIL Open Font License 1.1,
`assets/fonts/OFL.txt`), объявлен в `pubspec.yaml` как семейство `OpenDyslexic`; используется только
при включённом переключателе (ADR-019 §6). `flutter pub get` граф не изменил; `fvm flutter analyze` — 0.

## 13. Фактическое состояние после итерации 7.5 (2026-11-14)

**Новый dev-пакет — `integration_test` (Flutter SDK):** нужен, чтобы проверить реальное платформенное
поведение `flutter_secure_storage` (L28) на Windows: в обычном `flutter test` плагин не
зарегистрирован. Пакет входит в Flutter SDK (лицензия BSD-3-Clause, версия привязана к Flutter
3.47.9), не добавляется в runtime-граф, не входит в `flutter test` и в CI-матрицу.

Проверка пакета: `fvm flutter pub get` → `Changed 6 dependencies!` (SDK-пакет + транзитивные
`integration_test`/`flutter_driver` из SDK); `fvm flutter test integration_test/secure_api_key_store_windows_test.dart -d windows`
→ **`All tests passed!`** (запись → чтение → совпадение → удаление на реальном DPAPI-хранилище,
сборка Windows — 39,4 с).

Итерация сама новых runtime-зависимостей не вводит: каталог провайдеров — статические данные,
аккаунты — строка `app_settings`, ключи — существующий `flutter_secure_storage` 11.2.0, сеть —
существующий `dio` 5.11.1.

## 14. Фактическое состояние после итерации 7.9 (2026-11-15)

**Новый прямой runtime-пакет — `image ^4.12.0`.** Проверка pub.dev/факт: MIT, чистый Dart,
Android/iOS/Linux/macOS/Windows/Web, активные релизы (2026). Пакет уже приходил
транзитивно через `pdfrx_engine 0.9.1`; теперь объявлен явно, потому что
`lib/api/parsers/pdf_scan_renderer.dart` кодирует растр PDF-страницы в PNG
(`encodePng`) — это публичный API пакета, а не деталь транзитивной зависимости.
`fvm flutter pub get` → `Changed 1 dependency!` (version constraint закреплён).
Документация — ADR-023 §1.

**Внешний сервис без пакета и ключа:** Openverse API
(`https://api.openverse.org/v1/images/`) — открытый эндпоинт для поиска CC-изображений,
анонимный лимит ~1 запрос/с, ключ не требуется. Сеть — существующий `dio 5.11.1`;
`ImageSearchService` троттлит поисковые запросы и не логирует тела. Новых пакетов
для поиска нет.

**PDFium** остаётся прежним пином (`pdfrx 2.12.0` / `pdfium_dart 0.4.1`,
`bblanchon/pdfium-binaries chromium/8125`); рендер страниц использует тот же
PDFium, что и текстовый парсер, отдельного нативного ассета не добавлено.
Рендер в `Isolate.run` проверен на Windows тестом
`test/unit/api/parsers/pdf_scan_renderer_test.dart`.
