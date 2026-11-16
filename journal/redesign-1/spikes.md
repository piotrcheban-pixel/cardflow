# Спайки этапа 1 «Фундамент Nocturne»

**Дата:** 2026-11-17 · **Окружение:** Windows 11, FVM 4.3.2, Flutter 3.47.9
(Dart 3.13.7). Прогоны — `fvm flutter test --no-pub`.

Спайк нужен, чтобы до плана знать: доступны ли API формы/стекла/шейдеров в
закреплённой версии Flutter, как Flutter ведёт себя с переменными шрифтами и
как проверять кириллицу программно. Скрипты запускались из `work/spike/`
(каталог в `.gitignore`, в репозиторий не входит).

## S1. Формы: `RoundedSuperellipseBorder` и `ClipRSuperellipse`

| Проверка | Результат |
|---|---|
| `RoundedSuperellipseBorder` в SDK | есть: `packages/flutter/lib/src/painting/rounded_rectangle_border.dart:226` |
| `ClipRSuperellipse` | есть: `packages/flutter/lib/src/widgets/basic.dart` |
| `RSuperellipse` в `dart:ui` | есть (`basic_types.dart` экспортирует) |
| widget-тест: `ShapeDecoration(shape: RoundedSuperellipseBorder(...))` + `ClipRSuperellipse` | рендерится, `takeException()` = null |

**Вывод:** внешние пакеты не нужны, `r.*` строятся на встроенном API.

## S2. Стекло: `BackdropGroup` + `BackdropFilter.grouped` + `ImageFilter.compose`

| Проверка | Результат |
|---|---|
| `BackdropGroup` | есть: `widgets/basic.dart:471` |
| `BackdropFilter.grouped` | есть: `widgets/basic.dart:674` |
| `ImageFilter.compose(outer: ColorFilter.matrix(saturation), inner: ImageFilter.blur(σ))` | создаётся и рендерится в дереве |
| widget-тест стеклянной панели под `BackdropGroup` | рендерится, исключений нет |

Замечание: `ui.ImageFilter.matrix` принимает `Float64List` (не `List<double>`),
`ui.ColorFilter.matrix` — `List<double>`. Учтено в `NcGlass`.

**Не проверено:** реальная стоимость прохода размытия на Windows/Android
(нет Android SDK; замер кадров — этап 4). На этапе 1 стекло не рисуется.

## S3. `FragmentProgram` в `flutter test`

Создан `shaders/grain.frag` (минимальный runtime effect) + запись в
`pubspec.yaml` → `flutter: shaders:`. Тест:

```
SPIKE: FragmentProgram загрузился (FragmentProgram)
```

**Вывод:** шейдер компилируется тестовым билдом и грузится в `flutter test`.
Но для зерна выбран **тайловый PNG** (§4.5 допускает оба варианта):
растровый тайл детерминирован в golden-тестах на всех ОС CI, не требует
прогрева шейдера и не зависит от GPU. `grain.frag` в репозиторий не входит.

## S4. Кириллица в Onest / Literata / JetBrains Mono

### S4.1. Покрытие по `cmap` (fontTools 4.65.0)

| Семейство | Файл, КБ | Глифов / cmap | Оси | Нет из требуемого набора |
|---|---|---|---|---|
| Onest | 193 | 876 / 780 | `wght 100…900` (по умолч. 400) | `∑ ∫ √ ∞ π Δ` |
| Literata | 955 | 1789 / 1163 | `opsz 7…72` (12), `wght 200…900` | — |
| JetBrains Mono | 187 | 1179 / 976 | `wght 100…800` | — |

Набор: `А–я`, `ё`, `Ё`, `«» „“ ”`, `– —`, `№ …`, цифры, латиница, `%‰°₽$€`,
`· • → ← ≈ ≠ ≤ ≥ ± × ÷`.

Onest не содержит математических символов `∑ ∫ √ ∞ π Δ`. В интерфейсе они не
используются: формулы рендерит `flutter_math_fork` (KaTeX-шрифты), а `mono`-роли
их содержат. Зафиксировано как факт, не как дефект.

### S4.2. Программный тест через `FontLoader` + `TextPainter`

Первая версия проверяла «tofu» по равенству ширины глифа ширине `.notdef`
(`U+E000`) — **метод негоден**:

- Literata: ложные срабатывания на `г` и `–` (advance = 50.00 = ширине `.notdef`);
- JetBrains Mono: моноширинный — **все** символы имеют одинаковую ширину
  (60.00), «tofu» получился для всей кириллицы, хотя `cmap` её содержит.

Вторая версия растеризует символ (`PictureRecorder` → `Canvas` →
`picture.toImage` → `rawRgba`) и сравнивает байты с растром `U+E000`:

```
SpikeOnest: tofu=нет
SpikeLiterata: tofu=нет
SpikeMono: tofu=нет
```

**Вывод:** постоянный тест `test/unit/ui/design/nc_fonts_test.dart` строится на
растровом сравнении (ширина как критерий отброшена).

## S5. Переменные шрифты и `FontWeight`

Ширина строки `Аа` при 100 px, Onest / Literata (px):

| Запись | Onest | Literata |
|---|---|---|
| `FontWeight.w400` | 122.50 | 126.40 |
| `FontWeight.w600` | 126.10 | 130.35 |
| `FontWeight.w800` | 129.70 | 137.10 |
| `FontVariation('wght', 400)` | 122.50 | 126.40 |
| `FontVariation('wght', 600)` | 126.10 | 130.35 |
| `FontVariation('wght', 800)` | 129.70 | 137.10 |
| `FontWeight.w800` + `FontVariation('wght', 400)` | 122.50 | 126.40 |
| `FontVariation('wght', 650)` | 127.10 | 131.70 |

**Выводы:**
1. `FontWeight` **проецируется в ось `wght`** — синтетического жирнения нет
   (значения совпадают с явным `FontVariation`).
2. `FontVariation` **перекрывает** `FontWeight` — можно задавать 450/650.
3. Literata: `opsz` влияет на метрики (`opsz 18` → 302.00, `opsz 72` → 304.36
   для «Слово»), значит оптические размеры задаются `FontVariation('opsz', …)`.

## S6. Признак тестового окружения

`Platform.environment['FLUTTER_TEST']` под `fvm flutter test`:

```
FLUTTER_TEST=true
executable=…\flutter_tester.exe
```

**Вывод:** глобальную повторяющуюся анимацию (дрейф Aurora в `builder`)
включать только вне `flutter test` — иначе 353 `pumpAndSettle` в 28 файлах не
завершатся. Флаг читается в `NcAmbientBackground`; для проверки дрейфа есть
`debugAnimateInTests`.

## Итог спайков

| Риск | Статус |
|---|---|
| superellipse/стекло/шейдеры требуют пакетов | снят — всё встроено, шейдер компилируется |
| кириллица в шрифтах | снят — покрытие подтверждено `cmap` и растром |
| «ширина = tofu» | снят — метод заменён растровым |
| веса переменных шрифтов | снят — `FontWeight` = ось `wght`, `FontVariation` перекрывает |
| глобальная анимация ломает тесты | снят — `FLUTTER_TEST` |
| стоимость стекла на Windows/Android | остаётся: замер — этап 4 (нет Android SDK) |
