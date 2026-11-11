# Спайк зависимостей — итерация 0

**Дата:** 2026-11-11 · **Автор:** deps-researcher (task-1) · **Статус:** завершён (веб-проверка; runtime-проверка — после установки Flutter 3.47.9)
**Связанные документы:** `docs/dependencies.md`, `docs/decisions/ADR-001-m3e-library.md`, `ADR-002-state-management.md`, `ADR-003-doc-xls.md`.

## 1. Метод и окружение

- Всё проверено **в сети** через pub.dev API: `GET https://pub.dev/api/packages/<name>` (latest.version, published, pubspec.environment, dependencies, flutter.plugin.platforms, isDiscontinued/replacedBy, число версий), `GET https://pub.dev/api/packages/<name>/score` (likes, grantedPoints, popularity, tags — включая `license:*` и `publisher:*`). Дополнительно — страницы пакетов и исходники в GitHub (README, CHANGELOG, LICENSE, `lib/`), `pub.dev/documentation/...` для API.
- Flutter/Dart: официальный `releases_windows.json` → **3.47.9 stable, Dart 3.13.7, release 2026-10-29, hash `c197ca5199e9ee5661e865596c9c07294dfab51c`** (`current_release.stable` совпадает).
- `flutter`/`dart` **не запускались** (на момент проверки SDK ещё не был распакован; запрещено условием задачи). Компиляция, `pub get`, `analyze` — не проверялись, поэтому часть пакетов помечена `needs-runtime-spike`.
- Сеть: pub.dev API отвечает медленно и нестабильно (15–40 с на ответ; большие JSON и архивы обрывались по таймауту 20 с — пришлось перекачивать `curl --compressed --max-time 180` с ретраями). GitHub raw/API — быстрые (~0,5 с). Поэтому часть метаданных получена вторым проходом; пакеты, которые не удалось получить (`dart_fsrs`), проверены как HTTP 404 (`NoSuchKey`) — пакета нет.

## 2. Вердикты по пакетам

Полная таблица с версиями, платформами, лицензиями и вердиктами — `docs/dependencies.md`. Здесь — только нетривиальные находки и доказательства.

### 2.1. Экосистема мигрировала на `material_ui` (важно)

| Пакет | Версия | Зависимость | Доказательство |
|---|---|---|---|
| go_router | 18.1.4 (2026-11-09) | `material_ui: ^1.0.0`, `cupertino_ui: ^1.0.0` | pubspec через pub.dev API; CHANGELOG `## 18.0.0 — Migrates to material_ui and cupertino_ui` |
| flutter_riverpod | 3.5.0 (2026-11-06) | `material_ui: ^1.0.0` | pubspec; CHANGELOG `## 3.5.0 — Migrated Material imports to package:material_ui/material_ui.dart and added material_ui as a dependency` |
| pdfrx | 2.12.0 (2026-11-05) | `material_ui: ^1.0.0` | pubspec |

Вывод: приложение строим на `material_ui ^1.11.0` (publisher `flutter.dev`, BSD-3-Clause, tag `platform:android,ios,windows,linux,macos,web`). Альтернатива «остаться на `package:flutter/material.dart`» = смешивать framework-Material с material_ui-виджетами внутри `MaterialApp`/роутера, что хрупко. Детали — ADR-001.

### 2.2. `drift` и EOL-пакеты sqlite-обвязки

- `drift 2.35.4` (2026-11-08) зависит от `sqlite3: ^3.4.0`; официальный setup-гайд (drift.simonbinder.eu/setup, раздел «The dependencies») для Flutter предписывает: `drift ^2.35.4`, `drift_flutter ^0.3.1`, `path_provider ^2.1.6`, dev: `drift_dev ^2.35.3`, `build_runner ^2.16.2`.
- `sqlite3 3.9.1` (2026-11-08) использует Dart **hooks** (native assets): README — «it bundles SQLite with your application and doesn't require any external dependencies or build configuration».
- `sqlite3_flutter_libs 0.6.0+eol` (2026-02-15): описание «Not used anymore, update to version 3.x of package:sqlite3 instead». `sqlcipher_flutter_libs 0.7.0+eol` — аналогично. `drift_flutter 0.3.1` всё ещё объявляет их как no-op-заглушки (`^0.6.0+eol`, `^0.7.0+eol`) — в pubspec вручную не добавлять.
- Риск: native assets SQLite на 5 платформах впервые проверится после установки Flutter → `needs-runtime-spike` (в первую очередь `flutter build windows`/`flutter run -d windows`).

### 2.3. `intl` запинен SDK

`packages/flutter_localizations/pubspec.yaml` в теге `3.47.9` объявляет `intl: ^0.20.3`; `material_ui 1.11.0` — `intl: ^0.20.2`. Совместимая версия — ровно **intl 0.20.3**.

### 2.4. `excel` мёртв, `excel_plus` — замена

- `excel 4.0.6` — последний релиз **2024-08-20** (>2 лет), последний коммит репо 2025-07-15, 1245 likes, pub points 115. По правилу «нет релизов >2 лет» — отклонён.
- `excel_plus 2.29.2` — 2026-11-01, MIT, publisher `almasum.dev`, 72 likes, 160 pts, sdk `^3.11.4`, чистый Dart. README: читает/пишет `.xlsx`, **читает legacy `.xls` (BIFF8, Excel 97-2003) встроенным парсером**, API совместим с `excel` (`Excel.decodeBytes`). → кандидат для XLSX (`needs-runtime-spike`), см. ADR-003 про `.xls`.

### 2.5. PDF

- `pdfrx 2.12.0` (2026-11-05), MIT, publisher `espresso3389.jp`, 357 likes, 160 pts, tags: все 6 платформ, `platform:android,ios,windows,linux,macos,web`. README: «The plugin supports Android, iOS, Windows, macOS, Linux, and Web»; «Flutter 3.47 / Dart 3.13 or later, iOS 15+/macOS 12+»; PDFium упакован через `pdfium_flutter`/`pdfium_dart` (Android/Linux/Windows — Dart native assets; iOS/macOS — XCFramework/SPM). **Windows: «You must enable Developer Mode to build pdfrx on Windows»**. Извлечение текста: `PdfDocument` → `page.loadText() → Future<PdfPageRawText?>` и `page.loadStructuredText() → Future<PdfPageText>` (bounding boxes) — см. pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html. Для доступа к `PdfDocument` до первого виджета — вызвать `pdfrxFlutterInitialize()` один раз на старте.
- Лицензия PDFium — BSD-3-Clause (LICENSE `pdfium.googlesource.com/pdfium`: «Copyright 2014 The PDFium Authors … Redistribution and use in source and binary forms …»).
- `syncfusion_flutter_pdf 35.1.46` (2026-11-11, publisher `syncfusion.com`, 794 likes, license-tag `unknown`): README — «**This is a commercial package.** To use this package, you need to have either a Syncfusion commercial license or Free Syncfusion Community license». → без явного согласия владельца не добавляем; выбран pdfrx.

### 2.6. `flutter_secure_storage` 11.2.0

2026-09-16, BSD-3-Clause, publisher `steenbakker.dev`, 4511 likes, 160 pts, платформы android/ios/linux/macos/web/windows. README: min Android SDK **23**; Android Auto Backup по умолчанию ломает ключи (`InvalidKeyException: Failed to unwrap key`) → в `AndroidManifest.xml` `android:allowBackup="false"` (совпадает с SPEC A8.6).

### 2.7. Остальные замечания

- `desktop_drop 0.9.2` (2026-10-20, Apache-2.0, publisher `mixin.dev`): sdk `^3.13.5`, flutter `>=3.47.7` — совпадает с 3.47.9/3.13.7; платформы все 6. Выбран вместо `super_drag_and_drop 0.9.1` (2025-06, Rust-зависимость `super_native_extensions`).
- `file_picker 13.3.3` (2026-11-10, MIT) — новая модульная раскладка (`android_file_picker`, `windows_file_picker`, …), все платформы.
- `json_schema 5.2.2` (2025-10-08) — pub.dev license-tag отсутствует; в репозитории `workiva/json_schema` LICENSE = **Boost Software License 1.0**, но последний релиз 13 мес. назад и активность низкая (последний merge 2026-03, до этого релиз 2025-10) → `needs-runtime-spike`, fallback `json_schema_builder 0.1.7` (BSD-3-Clause, 2026-09-01).
- `flutter_math_fork 0.7.4` (2025-05-21, Apache-2.0, publisher `simpleclub.com`): последний коммит репо 2026-06 (README), релиз поддержки Flutter 3.32 — на 3.47 не проверялся → `needs-runtime-spike`; альтернативы нет (SPEC/AGENTS: только `flutter_math_fork`).
- `enough_convert 1.7.1` (2026-09-30, MPL-2.0, publisher `enough.de`, 25 likes, 150 pts, 11 версий, `sdk >=3.11.0 <4`, чистый Dart без зависимостей) — покрывает Windows-1251 **и KOI8-R/U**, ISO-8859, DOS, GBK, Big5. Выбран для A8.3 (TXT/MD/RTF, BOM→UTF-8→cp1251/koi8-r). Проверка показала: пакет `charset 2.0.1` (Apache-2.0, 2023) содержит windows-1251, но **KOI8-R в нём нет** (в `lib/src/` нет koi8-таблиц) → как единственная зависимость не подходит; fallback — `charset` + собственные 128-символьные таблицы KOI8-R. MPL-2.0 — OSI-лицензия, копилефт на уровне файлов самой библиотеки, наш код не затрагивает; допустима для MVP (`needs-runtime-spike` на фикстурах).
- `fsrs_dart 0.1.0` — зависимости `code_assets`, `native_toolchain_rust`, `ffi`, `hooks` → Rust-сборка; 0 likes, версия 0.1.0 → отклонён. `dart_srs 1.0.1` (2026-05-24, MIT, 1 like) — свой SRS-движок (FSRS-6-style), storage-agnostic; отклонён в пользу reference-порта.
- Guard `no_webview`: транзитивно появятся `web`, `web_socket_channel`, `flutter_web_plugins`, `file_picker_web` — это веб-интероп (dart:js), **не** WebView. Блокировать: `webview_flutter*`, `flutter_inappwebview*`, `flutter_html*`.

## 3. FSRS: выбранный пакет и точный публичный API

**Выбран `fsrs 2.0.1`** — https://pub.dev/packages/fsrs (репозиторий https://github.com/open-spaced-repetition/dart-fsrs, MIT, 160/160 pts, 22 likes, sdk `^3.3.0`, чистый Dart, все платформы; последний релиз 2025-06-20, последний коммит 2025-06-20 — репозиторий «заморожен», но реализует стабильный FSRS-6: 21 вес, порт py-fsrs). Пакет — **один файл** `lib/fsrs.dart`, импорт `import 'package:fsrs/fsrs.dart';`.

### 3.1. Типы и сигнатуры (выписано из исходника `lib/fsrs.dart`, не из README)

```dart
// Константа весов FSRS-6 — 21 значение, экспортируется из библиотеки
const defaultParameters = <double>[0.2172, 1.1771, 3.2602, 16.1507, 7.0114, 0.57,
  2.0966, 0.0069, 1.5261, 0.112, 1.0178, 1.849, 0.1133, 0.3127, 2.2934, 0.2191,
  3.0004, 0.7536, 0.3332, 0.1437, 0.2];

enum Rating { again(1), hard(2), good(3), easy(4); final int value;
  static Rating fromValue(int value); }            // Rating.values = [again, hard, good, easy]

enum State { learning(1), review(2), relearning(3); final int value;
  static State fromValue(int value); }             // ВНИМАНИЕ: State.new НЕТ

class Scheduler {
  final List<double> parameters;      // 21 вес
  final double desiredRetention;      // по умолчанию 0.9
  final List<Duration> learningSteps; // по умолчанию [1 мин, 10 мин]
  final List<Duration> relearningSteps; // по умолчанию [10 мин]
  final int maximumInterval;          // по умолчанию 36500 дней
  final bool enableFuzzing;           // по умолчанию true

  Scheduler({
    List<double> parameters = defaultParameters,
    double desiredRetention = 0.9,
    List<Duration> learningSteps = const [Duration(minutes: 1), Duration(minutes: 10)],
    List<Duration> relearningSteps = const [Duration(minutes: 10)],
    int maximumInterval = 36500,
    bool enableFuzzing = true,
  });
  factory Scheduler.customRandom(Random random, {...});   // для тестов

  ({Card card, ReviewLog reviewLog}) reviewCard(
    Card card,
    Rating rating, {
    DateTime? reviewDateTime,   // ОБЯЗАН быть UTC, иначе ArgumentError
    int? reviewDuration,        // миллисекунды
  });

  double getCardRetrievability(Card card, {DateTime? currentDateTime});
  Map<String, dynamic> toMap();
  static Scheduler fromMap(Map<String, dynamic> sourceMap);
}

class Card {
  final int cardId;          // int, не String!
  State state;               // по умолчанию State.learning
  int? step;                 // у learning по умолчанию 0
  double? stability;
  double? difficulty;
  DateTime due;              // UTC; по умолчанию now().toUtc()
  DateTime? lastReview;

  Card({required int cardId, State state = State.learning, int? step,
        double? stability, double? difficulty, DateTime? due, DateTime? lastReview});
  static Future<Card> create({...});   // генерирует cardId = epoch ms (+ задержка 1 мс); нам не нужен
  Card copyWith({...});
  Map<String, dynamic> toMap();        // ключи: cardId, state (int), step, stability, difficulty, due (ISO), lastReview (ISO)
  static Card fromMap(Map<String, dynamic> sourceMap);
}

class ReviewLog {
  final int cardId;
  final Rating rating;
  final DateTime reviewDateTime;
  final int? reviewDuration;
  const ReviewLog({required this.cardId, required this.rating,
                   required this.reviewDateTime, this.reviewDuration});
  Map<String, dynamic> toMap();        // rating — int 1..4, reviewDateTime — ISO
  static ReviewLog fromMap(Map<String, dynamic> sourceMap);
}
```

Поведение `reviewCard` (из исходника):
- `card = card.copyWith();` — **входная карточка не мутируется**, возвращается новая (`record.card`).
- `reviewDateTime ??= DateTime.now().toUtc();` — все даты только UTC.
- Для нового (learning, step=0, stability/difficulty == null): `stability = _initialStability(rating)`, `difficulty = _initialDifficulty(rating)`; интервал:
  - `Again` → `learningSteps[0]` (1 мин, step=0);
  - `Hard` → при step=0 и 2 шагах `(learningSteps[0]+learningSteps[1])~/2` (5,5 мин); при 1 шаге `learningSteps[0]*1.5`;
  - `Good` → если step+1 == learningSteps.length → переход в `State.review` и интервал `_nextInterval(stability)`; иначе следующий learning-step (10 мин);
  - `Easy` → сразу `State.review` + `_nextInterval(stability)`.
- Для Review-state: интервалы в днях, `enableFuzzing` добавляет ±fuzz (диапазоны от 2.5 дней).
- `_nextInterval` ограничен `maximumInterval` и минимум 1 день.
- Счётчиков `reps/lapses` в `Card` нет — считать по `review_logs` приложению.

### 3.2. Фрагмент для кода планировщика (адаптер)

```dart
import 'package:fsrs/fsrs.dart';

// 1) Планировщик: настройки — из app_settings/настроек колоды.
final scheduler = Scheduler(
  desiredRetention: 0.9,                        // из настроек «Удержание»
  learningSteps: const [Duration(minutes: 1), Duration(minutes: 10)],
  relearningSteps: const [Duration(minutes: 10)],
  maximumInterval: 36500,
  enableFuzzing: true,                          // в runtime; для прогноза/тестов — false
);

// 2) Наша карточка (A5) TEXT id ⟶ FSRS int cardId:
//    cardId детерминированно выводим из TEXT id (например, первые 8 байт SHA-256,
//    big-endian → int) — маппинг хранится в fsrs_json; стабильность важнее значения.
//    Новая карточка (A5 state='new'):
Card newCard(int fsrsId) => Card(cardId: fsrsId); // State.learning, step=0, due=now UTC

// Восстановление существующей:
// final card = Card.fromMap(jsonDecode(cards.fsrsJson)); // даты — UTC ISO

// 3) Оценка. Rating из A7.2: «Не знаю»→again, «Сложно»→hard, «Знаю»→good, «Легко»→easy
final now = DateTime.now().toUtc();
final result = scheduler.reviewCard(
  card,
  Rating.good,
  reviewDateTime: now,
  reviewDuration: elapsedMs,
);
final nextCard = result.card;          // сохранить nextCard.toMap() в cards.fsrs_json
final log = result.reviewLog;          // rating.value → review_logs.rating (1..4)

// 4) Прогноз интервалов над 4 кнопками (A7.2) — БЕЗ записи в БД:
//    предсказывающий планировщик без fuzz, чтобы цифры были стабильны:
final previewScheduler = Scheduler(
  desiredRetention: scheduler.desiredRetention,
  learningSteps: scheduler.learningSteps,
  relearningSteps: scheduler.relearningSteps,
  maximumInterval: scheduler.maximumInterval,
  enableFuzzing: false,
);
final Map<Rating, Duration> forecast = {
  for (final r in Rating.values)
    r: previewScheduler.reviewCard(card, r, reviewDateTime: now).card.due.difference(now),
};
// Для новой карточки при steps [1м,10м] прогноз: again≈1м, hard≈5.5м, good≈10м,
// easy≈(интервал FSRS-6 от initial stability) — конкретные числа зависят от весов/retention.
// Для review-карточки: again/hard дают короткий relearning, good/easy — дни.

// 5) Сериализация:
// scheduler.toMap()/Scheduler.fromMap(map) — настройки (веса, retention, steps);
// card.toMap()/Card.fromMap(map) — состояние карточки;
// log.toMap()/ReviewLog.fromMap(map) — запись лога.
```

Замечания для интеграции:
- **timezone:** только UTC. В БД A5 `due`, `reviewed_at` — INTEGER epoch ms → `DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)`, обратно `dt.millisecondsSinceEpoch`. Нельзя передавать `DateTime.now()` (local) в `reviewCard` — бросит `ArgumentError`.
- **маппинг состояний A5** `new | learning | review | relearning`: в FSRS нет `new`. `new` — уровень приложения: карточка ещё не оценивалась (fsrs_json == null). При первой оценке создаём `Card(...)`, дальше берём `result.card`. `state` в A5 = `new`, если fsrs_json null, иначе `fsrsCard.state.name` (`learning|review|relearning`).
- **fuzz в тестах:** для детерминированных тестов интервалов — `Scheduler(enableFuzzing: false)` (или `Scheduler.customRandom(Random(seed))`, помечен `@visibleForTesting`).
- **desiredRetention** — из настроек пользователя (A6.6); **learningSteps** — из настроек обучения; при изменении шагов старые карточки обрабатываются корректно (в коде есть edge-case для `card.step >= learningSteps.length`).
- **прогноз** считается тем же `reviewCard`, что и оценка (SPEC A7.2), поэтому цифры над кнопками будут ровно теми интервалами, которые применились бы; для тестов достаточно проверить монотонность `again < hard < good < easy` по `due`.
- `Card.cardId` — int; в A5 id TEXT. Варианты: (а) детерминированный int из TEXT id (SHA-256→8 байт), (б) отдельная int-колонка. Выбор — за Lead/адаптером; пробрасываемо в `fsrs_json` (`cardId` уже в toMap).

## 4. M3 Expressive: проверка официальной поддержки (для ADR-001)

Проверено в исходниках Flutter 3.47.9 (GitHub tag `3.47.9`):
- Дерево `packages/flutter/lib/src/material/` (184 записи): **нет** `button_group.dart`, `floating_toolbar.dart`, `loading_indicator.dart`, `split_button.dart`, `wavy_progress_indicator.dart`, `fab_menu.dart`; `motion.dart` содержит только `Durations`/`Curves` (нет spring-токенов); в `button_style.dart`/`theme_data.dart`/`progress_indicator.dart` нет `StyleVariant`/`expressive`/`wavy`/`spring`.
- Официальный umbrella-issue flutter/flutter **#168813** «Bring Material 3 Expressive to Flutter»: state **open**, updated **2026-08-17**, 84 комментария, labels `c: new feature, p: material_ui, …`. Ключевые апдейты в теле issue: май 2025 — «we are not actively developing Material 3 Expressive, and we will not be accepting contributions»; июль 2025 — «material and cupertino libraries are being decoupled into standalone packages… all new work for Material 3 Expressive will happen in the new packages once established in flutter/packages».
- В `flutter/packages` появился первый-party пакет **`material_ui`** (publisher `flutter.dev`): 1.11.0 (2026-11-09), BSD-3-Clause, sdk `^3.13.0`, flutter `>=3.47.0`, 297 likes, 160 pts, все платформы + web. CHANGELOG: 1.2.0 — `StyleVariant` (M3/M3E); 1.5.0 — M3E IconButton; 1.8.0 — `RoundedPolygon`, `CornerRounding`, `MaterialShapes`, `MaterialShapeBorder`; 1.11.0 — `Springs` (M3E spring-токены standard/expressive motion schemes), M3E ElevatedButton. Файлы `lib/src/material_shapes.dart`, `material_shape_border.dart`, `shapes/`, `generated/`; локаль `material_ru.arb` есть.
- Итог: официальные **компоненты** M3E (Button groups, Split button, Floating toolbar, Waveform progress, FAB menu, shape morph) в 3.47.9 отсутствуют; официально доступны только токены/формы/variant-поддержка в `material_ui`.

Кандидаты-сообщества (pub.dev API, на 2026-11-11):

| Пакет | Версия | Дата | sdk / flutter | Лицензия | Likes / pts | Зависимости | Вывод |
|---|---|---|---|---|---|---|---|
| material_3_expressive | 1.2.0 | 2026-10-23 | `^3.13.0` / `>=3.47.0` | MIT | 54 / 160 | material_ui ^1.8.0, motor ^1.1.0, material_new_shapes ^1.0.0, dynamic_color ^2.1.0 | **выбран** |
| m3e_collection | 0.3.7 | 2025-11-12 | `>=3.5.0 <4` / — | MIT | 33 / 150 | 16 суб-пакетов 0.1–0.3 | отклонён |
| m3e_design | 0.2.1 | 2025-10-25 | `>=3.5.0 <4` / — | MIT | 2 / 130 | dynamic_color, flutter | отклонён (только токены) |
| m3_expressive | 1.0.0 | 2026-04-17 | `>=3.0 <4` / `>=3.10` | MIT | 5 / 150 | flutter, vector_math | отклонён (подмножество) |
| expressive_m3 | 0.2.0 | 2026-07-01 | `^3.6.0` / `>=3.27` | MIT | 2 / 140 | animations, material_new_shapes | отклонён |
| m3e_core / m3e_buttons / m3e_card_list | 1.1.5 / 1.0.4 / 1.0.0 | 2026-10-30 / 10-30 / 08-16 | `^3.11` / `>=3.47` | MIT | 33/9/9, 160 pts | material_ui, motor, … | отклонены (несколько пакетов, узкое покрытие) |

Качество `material_3_expressive 1.2.0` (проверено в репо `paadevelopments/material_3_expressive`): MIT LICENSE (Copyright 2026 Paa Developments); 44 виджета / 39 модулей; **90+ файлов тестов** (`test/button_group_spec_test.dart`, `split_button_spec_test.dart`, `toolbar_spec_test.dart`, `loading_indicator_test.dart`, `progress_indicator_spec_test.dart`, `fab_menu_spec_test.dart`, `shape_catalog_test.dart`, …); CHANGELOG с PR-ссылками и исправлениями (1.2.0, 1.1.7, …); требует Flutter >=3.47/Dart ^3.13 — ровно наш пин; зависит от official `material_ui ^1.8.0`. Покрывает требования SPEC A4.5: Button groups (+ neighbor-squish, тест `button_group_icon_squish_test.dart`), Split button, Toolbar, FAB/FAB menu, Loading indicator, Progress/wavy, Material shapes. Не verified publisher (единственный мейнтейнер) → изоляция за `lib/ui/m3e/` + fallback-план в ADR-001.

## 5. State management (для ADR-002)

| Кандидат | Версия | Дата релиза | Лицензия | Ограничения | Кодогенерация | Likes / pts | Требует material_ui |
|---|---|---|---|---|---|---|---|
| flutter_riverpod (+ riverpod) | 3.5.0 | 2026-11-06 | MIT | sdk `^3.12.0`; flutter `>=3.0.0` | **нет** (manual providers); опционально riverpod_generator 4.0.10 | 2920 / 160 (riverpod 4043) | да (`^1.0.0`) |
| flutter_bloc (+ bloc) | 9.1.1 / 9.2.1 | 2025-05-02 / 2026-05-12 | MIT | sdk `>=2.14.0 <4` | нет | 8091 / 160 | нет |
| provider | 6.1.5+1 | 2025-08-19 | MIT | sdk `>=2.12.0 <4` | нет | 11012 / 150 | нет |

Выбран `flutter_riverpod ^3.5.0` (manual providers, без кодогенерации) — обоснование в ADR-002. Блокером не является: `riverpod` core — чистый Dart (`sdk:dart`), `ProviderContainer` работает в unit-тестах domain без Flutter.

## 6. `.doc` / `.xls` (для ADR-003)

Поиски pub.dev: `ole`, `cfb`, `compound file`, `doc binary`, `word 97`, `ole2`, `msdoc`, `xls reader`, `spreadsheet`, `docx reader`.
- `.doc`: парсера legacy Word (CFB/OLE2 + Word binary) на pub.dev **нет**. Единственный CFB-пакет `cfb` 0.0.1 (2020-08-01, sdk `>=2.7.0 <3.0.0`, 1 like, license unknown, README-заглушка) — мёртв и несовместим с Dart 3. Остальные результаты — коммерческие SDK (`flutter_document_reader_*` и т.п.) или просмотрщики/`.docx`.
- `.xls`: есть два кандидата уровня «прочитать BIFF8» — `excel2003 1.0.0` (2026-03-06, MIT по LICENSE-файлу; README-бейдж Apache-2 устарел; 2 likes; pure Dart, только чтение .xls) и `excel_plus 2.29.2` (2026-11-01, MIT, publisher `almasum.dev`, 72 likes, 160 pts; `Excel.decodeBytes` читает .xls). Оба не проверялись на фикстурах → `needs-runtime-spike`; в MVP по SPEC остаётся известное ограничение ADR-003 с сообщением «Формат не поддерживается. Сохраните файл как DOCX или XLSX и попробуйте снова».

## 7. needs-runtime-spike — что проверить после установки Flutter 3.47.9

| # | Проверка | Критерий |
|---|---|---|
| S1 | `fvm flutter pub get` с предложенным pubspec | граф разрешается без конфликтов (`intl 0.20.3`, `material_ui 1.11.0`, `material_3_expressive 1.2.0`) |
| S2 | `material_ui` + `material_3_expressive`: минимальный экран, `M3EMaterialApp`, ru-локаль | сборка/запуск, русские системные строки, нет падений `Theme.of` |
| S3 | drift + sqlite3 native assets: открыть БД, CRUD на Windows | БД создаётся, миграция применяется; при провале — `drift_flutter`/`sqlite3_flutter_libs`-путь |
| S4 | pdfrx: `PdfDocument.openFile` + `page.loadText()` на PDF с текстом | текст извлекается; пустой текстовый слой → сообщение «В файле нет текстового слоя…» |
| S5 | json_schema 5.2.2: валидация схемы A8.4 (union-типы + `additionalProperties: false`) | валидный/невалидный JSON различаются |
| S6 | flutter_math_fork: рендер формулы `$\frac{a}{b}$` на Flutter 3.47 | рендерится без исключений |
| S7 | excel_plus: чтение XLSX-фикстуры (значения, формулы по кэшу) | строки/столбцы извлекаются, `\t`-склейка |
| S8 | enough_convert: декодирование cp1251 и KOI8-R TXT | русский текст читается корректно в обеих кодировках |
| S9 | fsrs: тест маппинга Again/Hard/Good/Easy и монотонности интервалов | `again < hard < good < easy` (due), UTC-контракт |
| S10 | `flutter build windows` (VS Build Tools есть), pdfrx требует Developer Mode | сборка проходит или фиксируется ограничение |

## 9. Факты после записи документов (наблюдение 2026-11-11 19:06–19:08, файлы Lead; не правились — вне write-scope)

Lead параллельно создал Flutter-проект. На момент проверки: `pubspec.yaml` (mtime 19:06:48), `pubspec.lock` (19:06:37), `.dart_tool/package_config.json` (19:06:37) существуют → `pub get` выполнялся, **но lock старше pubspec** (после `pub get` в pubspec добавлены `desktop_drop: 0.8.4` и `super_drag_and_drop: ^0.1.9+3`, которых в lock/package_config нет) → требуется повторный `fvm flutter pub get`.

Разрешённые версии **совпадают с рекомендациями** этого спайка: `material_ui 1.11.0`, `material_3_expressive 1.2.0`, `fsrs 2.0.1`, `drift 2.35.4`, `sqlite3 3.9.1`, `dio 5.11.1`, `flutter_secure_storage 11.2.0`, `go_router 18.1.4`, `flutter_riverpod 3.5.0` (+`riverpod 3.5.0` транзитивно), `json_schema 5.2.2`, `pdfrx 2.12.0`, `excel_plus 2.29.2`, `flutter_math_fork 0.7.4`, `intl 0.20.3`, `freezed 4.0.3`, `cupertino_ui 1.1.6`, `motor 1.1.0`. `pubspec.lock` sdk: dart `>=3.13.7 <4.0.0`, flutter `>=3.47.0`.

Найденные несоответствия (для исправления Lead'ом):
1. `freezed_annotation ^3.1.0` и `json_annotation ^4.12.0` находятся в **dev_dependencies** — сгенерированный код (`*.freezed.dart`, `*.g.dart`) импортирует их из `lib/`, поэтому они должны быть в `dependencies` (иначе анализатор/сборка падают на `depend_on_referenced_packages`).
2. Добавлены **оба** drag-n-drop пакета; SPEC A3 требует один. `super_drag_and_drop: ^0.1.9+3` — устаревший constraint (актуальная версия 0.9.1; 0.1.x не в lock), `desktop_drop: 0.8.4` — не последняя (0.9.2). Рекомендация: оставить только `desktop_drop: ^0.9.2`, `super_drag_and_drop` убрать.
3. `drift_flutter` не добавлен — допустимо: можно открывать БД вручную по официальному рецепту drift (`NativeDatabase.createInBackground`, `sqlite3.tempDirectory` для Android) и не тянуть EOL-заглушки; решить в шаге 0.3 и записать в `docs/dependencies.md` (если решено иначе — ADR не нужен, это деталь реализации).
4. `lib/main.dart` — пока шаблон: импортирует `package:flutter/material.dart` и содержит английские строки («Flutter Demo», «Increment»). По ADR-001 миграция на `package:material_ui/material_ui.dart` + все строки в `app_ru.arb` (guard `ru_strings` иначе красный).
5. Для парсеров итерации 3a понадобится `enough_convert ^1.7.1` (cp1251 + KOI8-R) — в pubspec пока нет.
6. В `environment` нет `flutter: ">=3.47.0"` — не обязательно (material_ui требует при разрешении), но полезно для CI-диагностики.

## 10. Источники (проверяемые ссылки)

pub.dev API: `https://pub.dev/api/packages/<name>` и `https://pub.dev/api/packages/<name>/score` — для каждого пакета из `docs/dependencies.md` (это первичный источник версий/дат/лицензий/платформ).
- Flutter releases: https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json
- Flutter 3.47.9 material src: https://github.com/flutter/flutter/tree/3.47.9/packages/flutter/lib/src/material
- M3E umbrella issue: https://github.com/flutter/flutter/issues/168813
- material_ui: https://pub.dev/packages/material_ui · https://github.com/flutter/packages/tree/main/packages/material_ui
- material_3_expressive: https://pub.dev/packages/material_3_expressive · https://github.com/paadevelopments/material_3_expressive
- fsrs: https://pub.dev/packages/fsrs · https://github.com/open-spaced-repetition/dart-fsrs · API docs https://pub.dev/documentation/fsrs/latest/fsrs/Scheduler-class.html
- fsrs_dart: https://pub.dev/packages/fsrs_dart · dart_srs: https://pub.dev/packages/dart_srs
- drift setup: https://drift.simonbinder.eu/setup/ · sqlite3: https://pub.dev/packages/sqlite3 · sqlite3_flutter_libs (EOL): https://pub.dev/packages/sqlite3_flutter_libs
- pdfrx: https://pub.dev/packages/pdfrx · https://github.com/espresso3389/pdfrx · PdfPage API: https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html
- syncfusion_flutter_pdf: https://pub.dev/packages/syncfusion_flutter_pdf
- excel: https://pub.dev/packages/excel · excel_plus: https://pub.dev/packages/excel_plus · excel2003: https://pub.dev/packages/excel2003 · cfb: https://pub.dev/packages/cfb
- json_schema: https://pub.dev/packages/json_schema · LICENSE: https://github.com/workiva/json_schema/blob/master/LICENSE
- enough_convert: https://pub.dev/packages/enough_convert · charset (fallback): https://pub.dev/packages/charset
- flutter_math_fork: https://pub.dev/packages/flutter_math_fork · https://github.com/simpleclub/flutter_math
- go_router: https://pub.dev/packages/go_router · flutter_riverpod: https://pub.dev/packages/flutter_riverpod
- flutter_secure_storage: https://pub.dev/packages/flutter_secure_storage
- flutter_localizations intl pin: https://github.com/flutter/flutter/blob/3.47.9/packages/flutter_localizations/pubspec.yaml
