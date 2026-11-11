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
| `environment:sdk` | `^3.13.0` | требование `material_ui` 1.11.0 (`sdk: ^3.13.0`) |
| `environment:flutter` | `>=3.47.0` | требование `material_ui` 1.11.0 / `material_3_expressive` 1.2.0 / `pdfrx` 2.12.0 |

> Все команды — только через FVM (`fvm flutter pub get`, `fvm flutter test`, …), см. `AGENTS.md`.

## 1. Ключевое архитектурное решение по базе Material

`go_router` 18.1.4, `flutter_riverpod` 3.5.0 и `pdfrx` 2.12.0 **уже зависят от `material_ui` ^1.0.0** (первоисточники: pubspec пакетов + CHANGELOG go_router «18.0.0 — Migrates to material_ui and cupertino_ui», CHANGELOG flutter_riverpod «3.5.0 — Migrated Material imports to package:material_ui/material_ui.dart»). Поэтому приложение строим на официальном пакете `material_ui` 1.11.0 (publisher `flutter.dev`), а не на `package:flutter/material.dart`. Это описано в **ADR-001**.

## 2. Основные зависимости (runtime)

| Пакет | Версия (constraint) | Зачем (SPEC) | Платформы | Лицензия | Вердикт |
|---|---|---|---|---|---|
| [material_ui](https://pub.dev/packages/material_ui) | `^1.11.0` | база Material (офиц. decoupled-библиотека); нужна `go_router`/`flutter_riverpod`/`pdfrx`; содержит официальные M3E-токены (`Springs`, `MaterialShapes`, `StyleVariant`) | Android, iOS, Linux, macOS, Windows, Web | BSD-3-Clause | approved · needs-runtime-spike (миграция импортов + l10n-делегаты) |
| [material_3_expressive](https://pub.dev/packages/material_3_expressive) | `^1.2.0` | M3 Expressive-компоненты за `lib/ui/m3e/` (ADR-001) | Android, iOS, Linux, macOS, Windows, Web | MIT | approved · needs-runtime-spike |
| [fsrs](https://pub.dev/packages/fsrs) | `^2.0.1` | FSRS-6: 21 вес, `desiredRetention`, `learningSteps` (A3, A7) | чистый Dart (все) | MIT | **approved** (API выписан в спайке) |
| [drift](https://pub.dev/packages/drift) | `^2.35.4` | типобезопасная SQLite + миграции (A3, A5) | чистый Dart (все) | MIT | approved |
| [drift_flutter](https://pub.dev/packages/drift_flutter) | `^0.3.1` | открытие БД на Flutter-платформах (офиц. рекомендация drift 2.35.4) | flutter-пакет (все) | MIT | approved · тянет EOL-заглушки `sqlite3_flutter_libs ^0.6.0+eol`/`sqlcipher_flutter_libs ^0.7.0+eol` — вручную не добавлять |
| [sqlite3](https://pub.dev/packages/sqlite3) | `^3.9.1` | нативная SQLite через FFI + Dart hooks (native assets) | все | MIT | approved · needs-runtime-spike (native assets на 5 платформах) |
| [dio](https://pub.dev/packages/dio) | `^5.11.1` | HTTP + перехватчики/ретраи (A8.2, A8.6) | чистый Dart | MIT | approved |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | `^11.2.0` | ключи API только здесь (A1.3, A8.6) | Android, iOS, Linux, macOS, Windows, Web | BSD-3-Clause | approved · minSdk 23; Android `allowBackup=false` |
| [json_schema](https://pub.dev/packages/json_schema) | `^5.2.2` | локальная валидация ответа модели по A8.4 | чистый Dart | Boost-1.0 (LICENSE в репо; pub.dev license-tag отсутствует) | needs-runtime-spike; fallback `json_schema_builder ^0.1.7` |
| [flutter_math_fork](https://pub.dev/packages/flutter_math_fork) | `^0.7.4` | единственный разрешённый LaTeX-рендер (A1/AGENTS) | Android, iOS, Linux, macOS, Windows, Web | Apache-2.0 | approved · needs-runtime-spike (релиз 2025-05-21, проверить на Flutter 3.47) |
| [archive](https://pub.dev/packages/archive) | `^4.6.0` | `.zip` экспорт/импорт; ZIP-контейнер DOCX/PPTX/ODT/XLSX (A8.3) | чистый Dart | MIT | approved |
| [xml](https://pub.dev/packages/xml) | `^7.1.0` | разбор XML внутри DOCX/PPTX/ODT/XLSX (A8.3) | чистый Dart | MIT | approved |
| [excel_plus](https://pub.dev/packages/excel_plus) | `^2.29.2` | XLSX (замена устаревшего `excel`); читает и legacy `.xls` (BIFF8) — кандидат для ADR-003 | чистый Dart | MIT | approved · needs-runtime-spike (A8.3 «формулы по кэшированному значению», фикстуры) |
| [file_picker](https://pub.dev/packages/file_picker) | `^13.3.3` | пикер файлов (A6.8/A8.3) | Android, iOS, Linux, macOS, Windows, Web | MIT | approved |
| [desktop_drop](https://pub.dev/packages/desktop_drop) | `^0.9.2` | drag-n-drop на ПК (A3) | Android, iOS, Linux, macOS, Windows, Web | Apache-2.0 | approved (выбран вместо `super_drag_and_drop`) |
| [url_launcher](https://pub.dev/packages/url_launcher) | `^6.3.3` | «Где взять ключ», лицензии — системный браузер (A3) | Android, iOS, Linux, macOS, Windows, Web | BSD-3-Clause | approved |
| [pdfrx](https://pub.dev/packages/pdfrx) | `^2.12.0` | текстовый слой PDF через PDFium/FFI (A8.3) | Android, iOS, Linux, macOS, Windows, Web | MIT (PDFium — BSD-3-Clause) | approved · needs-runtime-spike (Windows: Developer Mode для сборки) |
| [go_router](https://pub.dev/packages/go_router) | `^18.1.4` | роутинг (AGENTS) | все (flutter) | BSD-3-Clause | approved · требует `material_ui ^1.0.0` |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | `^3.5.0` | управление состоянием, manual providers без кодогенерации (ADR-002) | все (flutter) | MIT | **approved** |
| [riverpod](https://pub.dev/packages/riverpod) | `^3.5.0` | `ProviderContainer`/провайдеры в чистых Dart-тестах domain | чистый Dart | MIT | approved |
| [path_provider](https://pub.dev/packages/path_provider) | `^2.1.6` | каталоги БД/медиа | Android, iOS, Linux, macOS, Windows | BSD-3-Clause | approved |
| [uuid](https://pub.dev/packages/uuid) | `^4.6.0` | `TEXT PRIMARY KEY` id (A5) | чистый Dart | MIT | approved |
| [crypto](https://pub.dev/packages/crypto) | `^3.0.8` | `content_hash` (A5, дедупликация A8.5) | чистый Dart | BSD-3-Clause | approved |
| [intl](https://pub.dev/packages/intl) | `^0.20.3` | даты/числа/ICU-плюрализация | чистый Dart | BSD-3-Clause | approved · **жёстко** `^0.20.3`: `flutter_localizations` 3.47.9 пинит этот constraint |
| [path](https://pub.dev/packages/path) | `^1.9.1` | пути к файлам | чистый Dart | BSD-3-Clause | approved |
| [collection](https://pub.dev/packages/collection) | `^1.19.1` | утилиты коллекций | чистый Dart | BSD-3-Clause | approved |
| [enough_convert](https://pub.dev/packages/enough_convert) | `^1.7.1` | кодировки для TXT/MD/RTF (A8.3): Windows-1251 (cp1251) и **KOI8-R**/KOI8-U, ISO-8859, DOS, GBK, Big5 | чистый Dart | MPL-2.0 | approved · needs-runtime-spike (проверить cp1251 и KOI8-R на фикстурах) |
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
| [test](https://pub.dev/packages/test) | `^1.33.0` | юнит-тесты domain | BSD-3-Clause | approved |
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

## 5. Предлагаемый блок `pubspec.yaml` (для Lead; сам pubspec не правится в этой задаче)

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
7. **needs-runtime-spike** (проверить после установки Flutter 3.47.9): `fvm flutter pub get` (весь граф), `material_ui`+`material_3_expressive` (сборка минимального экрана, ru-локаль), `drift`+`sqlite3` (открытие БД на Windows), `pdfrx` (извлечение текста `PdfPage.loadText()`), `json_schema` (валидация A8.4), `flutter_math_fork` (рендер формулы с кириллицей), `excel_plus` (чтение XLSX-фикстуры, кэшированные значения формул), `enough_convert` (cp1251 и KOI8-R), `fsrs` (интервалы для 4 оценок).
8. **Версии — стабильные на 2026-11-11**; при `pub get` допустимы только патч-обновления в рамках указанных caret-constraint'ов. Любой breakout — через ADR.
