# Шаг 1.4 — `NcTheme` и `AppTheme`: red-фаза и изменение контракта

**Дата:** 2026-11-17 · `fvm flutter test --no-pub --exclude-tags golden`

## 1. Почему переписан один существующий тест

`test/unit/ui/app_theme_test.dart` проверял тезис «динамическая схема
подставляется как есть» (`AppTheme.light(scheme:) .colorScheme.primary ==
scheme.primary`). Это прямо противоречит REDESIGN-SPEC §1.4 и ADR-035 §3:
в Nocturne dynamic color меняет **только акцент** — из системного `primary`
строится HCT-цвет (тон 40 в светлой теме, chroma ≤ 48), поверхности, Iris и
оценки остаются брендовыми. Оставить «как есть» нельзя: тогда весь фон стал бы
оттенком системного сида и Nocturne перестал бы существовать.

Переписан `test(theme)`-ом в том же коммите, что и реализация, с обоснованием
в комментарии теста и в ADR-035. Проверка **усилена** (было 1 утверждение,
стало 3): акцент ≠ брендовый, `surface` = `ink1`, `scaffoldBackgroundColor`
прозрачный. Число тестов в файле не уменьшилось (3 → 3).

## 2. Red-фаза (фактический вывод)

Полный прогон до переписывания теста:

```
test/unit/ui/app_theme_test.dart: AppTheme — настройки A6.6
    динамическая схема подставляется как есть [E]
  Expected: Color:<Color(alpha: 1.0000, red: 0.5333, green: 0.3961,
            blue: 0.1608, colorSpace: ColorSpace.sRGB)>
    Actual: Color:<Color(alpha: 1.0000, red: 0.4784, green: 0.3451,
            blue: 0.1137, colorSpace: ColorSpace.sRGB)>
  test\unit\ui\app_theme_test.dart 39:7
```

Ожидалось: `primary` = `scheme.primary` (системный `#FF4081`-производный цвет,
`#885E29`-подобный тон 40). Получено: `primary` из HCT-конверсии Nocturne
(`#7A581D`-подобный). Разница — ровно та, что описана в ADR-035 §3.

**Важно:** больше ни один тест приложения не упал от смены темы
(`1888 passed + 8 skipped`, единственный `-1` — переписанный тест). Это
подтверждает цель этапа: экраны перекрашиваются только темой, без правок.

## 3. Новые тесты шага

- `test/unit/ui/theme/app_theme_nocturne_test.dart` — 15 тестов: роли
  `ColorScheme` §1.5 (тёмная/светлая), контраст `onPrimary/primary` и
  `onSurface/surface`, прозрачный `scaffold`, нулевые elevation,
  superellipse-форма карточки, `NcTheme` как расширение, `TextTheme` из
  токенов (Onest/Literata), дислексия во всех ролях, повышенный контраст,
  dynamic color (тон 80/40, chroma ≤ 48, поверхности не меняются).
- `test/unit/ui/design/nc_theme_test.dart` — 10 тестов: `NcTheme.of`/`maybeOf`,
  fallback без расширения, `copyWith`, `lerp` (цвета и флаги),
  `NcColors.lerp`, контейнеры §1.5 и их dynamic-перекраска.
- `test/unit/ui/app_theme_test.dart` — 3 теста (переписан третий, см. §1).

## 4. Burn-down guard-долга

`lib/ui/theme/app_theme.dart` больше не содержит `Color(0xFF4F6BED)`
(значение переехало в `NcColors.legacySeed`), поэтому строка удалена из
`test/guards/fixtures/design_tokens_baseline.txt` — guard прошёл, подтвердив,
что долг закрывается только вместе с фикстурой.
