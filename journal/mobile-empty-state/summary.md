# Итерация «Фикс мобильного Empty State» — 2026-11-25

**Задача (owner-note после установки APK):** блок «ИИ не настроен — карточки можно
создавать вручную…» на главном экране на узком телефоне ломается: текст сжимается в
узкую колонку (перенос по одной букве), а кнопка «Настроить ИИ» стоит рядом с ним.
Нужно: вертикальная раскладка блока на экранах < 600 px, аудит мобильного главного
экрана (заголовок, иконка, кнопки, отступы), widget-тесты (кнопка под текстом на
390 px; нет overflow на 360×800), гейты, push, зелёный CI и скриншот 390×844.

**Факты старта:** `git status --porcelain` — только неотслеживаемые рабочие артефакты
аудита (`audit/`, `review_visual/`, `review_final/`, `PROGRESS*.md`, `TASK.txt`,
`.dsh-contrast.py`); `HEAD = origin/main = 9bb160e` (релиз v1.0.0, тег `v1.0.0`);
`journal/STATE.md` совпадает с реальностью. Схема БД и `schemaVersion` не менялись.

## Диагноз (измерено, а не на глаз)

Блок собран `Row`: `Icon` + `SizedBox` + `Expanded(Text)` + `TextButton`. `TextButton`
получает свою **неделимую** ширину первым, всё остальное забирает `Expanded` — поэтому
на телефоне текст сжимался до остатка. Зонд (`tester.getRect` + `TextPainter.lines`):

| Экран | Ширина текста | Строк | Символов в строке |
|---|---|---|---|
| 390×844 | **36,8 px** | 42 | ~2,1 |
| 360×800 | **6,8 px** | 77 | ~1,2 (по одной букве) |
| 390×844 при кегле 150 % | **0 px** | 77 | + `RenderFlex overflowed by 53 pixels` |

Второй вклад вносил `AppEmptyState(hero: true)`: внутренний отступ панели 40 px с
каждой стороны — 80 из 390 px (пятая часть экрана) уходило на пустоту, контенту
оставалось 278 px.

## Шаг 1. Раскладка блока по ширине (STEP 1)

`lib/ui/decks/decks_screen.dart`, `_FirstLaunchEmptyState`:

- проверка `MediaQuery.sizeOf(context).width < AppSizes.mobileBreakpoint` (600) —
  не `LayoutBuilder` по контейнеру: на десктопе тело блока ограничено 560 px
  (`ConstrainedBox`), и контейнерный порог ошибочно рушил бы блок в колонку и на ПК;
- мобильный вариант — `Column(crossAxisAlignment: start)`: строка «иконка +
  `Expanded(Text)`» на всю ширину, ниже — `TextButton` «Настроить ИИ» по левому краю
  (высоту цели касания 44 px даёт тема);
- десктопный вариант — прежний `Row` (`Expanded(aiNote)` + действие справа);
- плашка получила внутренний отступ 12 px (`Padding`): до этого иконка и строка
  действия упирались в её край.

Новый токен `lib/ui/theme/app_tokens.dart`: `AppSizes.mobileBreakpoint = 600` с
документирующим комментарием (прежний порог 600 в коде был «магическим числом»).

## Шаг 2. Аудит мобильного главного экрана (STEP 2)

- `lib/ui/components/app_surfaces.dart`, `AppEmptyState`: на мобильной ширине
  hero-панель держит 20 px по горизонтали и 24 px по вертикали (было 40/38), обычная
  панель — 20 px вместо 32. Контент на 390 px вырос с 278 до 318 px (81 % экрана).
- Заголовок «Добро пожаловать в CardFlow» на 360/390 переносится на две строки
  («Добро пожаловать в» / «CardFlow»), иконка-бейдж и три действия — внутри панели,
  горизонтального переполнения нет.
- Проверено глазами на реальных шрифтах (Inter + MaterialIcons) при 360×800,
  390×844 и 1440×900 — см. `after-360x800.png`, `after-390x844.png`,
  `after-1440x900.png` в этой папке. `after-390x844-shell.png` — тот же экран
  через **production-роутер** (`createAppRouter`), то есть как в приложении: с
  верхней панелью и «бургером»; ошибок раскладки нет (`ERRORS=0`).
- Замечание: на 360×800 экран пустого состояния выше вьюпорта на ~40 px — третье
  действие «Импорт» требует короткой прокрутки (в шапке тот же путь доступен через
  меню «⋮»); на 390×844 весь экран помещается без прокрутки. Вертикальные отступы не
  увеличивались.

### Шаг 2a. Тот же дефект рядом: баннер основного провайдера

`lib/ui/settings/provider_banner.dart` (`PrimaryProviderBanner`) собран **тем же**
`Row`-ом (`Icon` + `Expanded(Text)` + `TextButton` «Исправить») и живёт на **том же**
главном экране — он показывается, когда основной аккаунт настроен неполностью
(`providerBroken`). Замеры до фикса: на 390×844 текст занимал **146,1 px** при
кнопке 159,9 px, при кегле 150 % — **78,6 px** при кнопке 227,4 px.

Исправлено тем же правилом: ниже `AppSizes.mobileBreakpoint` баннер вертикальный
(«иконка + текст», ниже — «Исправить» по левому краю), отступ 12 px со всех сторон;
на десктопе — прежний `Row`. Тесты (+3) в `test/widget/settings/provider_audit_test.dart`:
390×844 — текст ≥ 220 px и действие под текстом; 150 % — без overflow и текст
≥ 160 px; 1440×900 — баннер горизонтальный. Существующие F7/D13/D14/D22 не
изменялись.

## Шаг 3. Тесты (STEP 3)

`test/widget/decks/decks_mobile_empty_state_test.dart` (+8 тестов):

1. 390×844 — `action.top >= note.bottom` (кнопка **под** текстом), кнопка по левому краю;
2. 390×844 — ширина текста ≥ 240 px (до фикса 36,8 px);
3. 360×800 — ширина текста ≥ 220 px (до фикса 6,8 px), кнопка под текстом,
   `takeException()` = null;
4. 1440×900 — блок остаётся горизонтальным (`action.left >= note.right - 1`) —
   защита от «всегда Column»;
5. 390×844 при кегле 150 % — без `RenderFlex overflow`, кнопка под текстом, текст
   ≥ 200 px (до фикса здесь был overflow 53 px);
6/7. 360×800 и 390×844 — заголовок, иконка и три действия внутри экрана, цель
   касания ≥ 40 px, нет исключений;
8. 390×844 — левый край контента панели ≤ 16 (страница) + 20 (панель), ширина
   контента ≥ 78 % экрана (отступы не «гигантские»).

Красная фаза до правки (assertion-level, из прогона):

```
Expected: a value greater than or equal to <240>
  Actual: <36.8000030517578125>   ← 390×844
Expected: a value greater than or equal to <220>
  Actual: <6.8000030517578125>    ← 360×800
Expected: a value less than or equal to <37>
  Actual: <124.7>                 ← отступы панели (мерилось неверно, исправлено
                                    на ближайший DecoratedBox: 56 → 36)
```

Существующие тесты не ослаблены и не менялись.

## Шаг 4. Тот же дефект у баннера провайдера (находка аудита)

См. «Шаг 2a» выше — `PrimaryProviderBanner` исправлен тем же правилом, +3 теста.

**Скриншот без устройства:** временный harness (не закоммичен) рендерил
`appWithRouter` в `RepaintBoundary` при `tester.view.physicalSize` 390×844
(`devicePixelRatio: 1`), `toImage(pixelRatio: 2)` — внутри `tester.runAsync`;
шрифты — `FontLoader` из `assets/fonts/Inter-Variable.ttf` и
`materialicons-regular.otf` из SDK. `tester.binding.setSurfaceSize` для этого не
годится: он меняет поверхность, но **не** `MediaQuery`, из-за чего первый зонд
показывал фантомный `RenderFlex overflowed by 24 pixels` (тулбар в десктопной ветке
при мобильном размере). Урок — в `AGENTS.md` (ретроспектива итерации).

## Гейты (2026-11-25)

| Гейт | Результат |
|---|---|
| `fvm dart format lib test integration_test` | 594 файла, 0 changed (после записи) |
| `fvm flutter analyze --no-pub` | **No issues found!** (101,7 с) |
| `fvm flutter test --no-pub --coverage --exclude-tags golden` | **2686 passed + 16 skipped + 0 failed** (baseline 2678 + 8) |
| Покрытие (`tool/coverage_check.dart`) | **90,8 % (22842/25165)**, порог 80 % пройден |
| `fvm flutter build windows --release --no-pub` | `cardflow.exe` — см. журнал ниже |

Схема БД, `schemaVersion` и `format_version` не менялись; живых API-запросов нет.

## Push и CI

`9bb160e..37894ad`: `1104519` (red-фаза теста), `e10fe70` (фикс блока ИИ),
`0b52c0e` (журнал/AGENTS/скриншоты), `a0aaf3e` (баннер провайдера),
`37894ad` (скриншот через production-роутер). Run
[`45619796606`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/45619796606)
(`37894ad`) — **9/9 job success** (`format + analyze`, `test` × 3 ОС,
`build desktop` × 3, `build mobile` Android + iOS). Прогон `45617686487`
отменён `concurrency` при следующем push.

## Изменённые файлы

- `lib/ui/decks/decks_screen.dart` — раскладка AI-блока по ширине + отступ плашки;
- `lib/ui/settings/provider_banner.dart` — мобильная раскладка баннера провайдера;
- `lib/ui/components/app_surfaces.dart` — мобильные отступы `AppEmptyState`;
- `lib/ui/theme/app_tokens.dart` — `AppSizes.mobileBreakpoint`;
- `test/widget/decks/decks_mobile_empty_state_test.dart` — новый набор (+8);
- `test/widget/settings/provider_audit_test.dart` — мобильный баннер (+3);
- `AGENTS.md` — ретроспектива итерации;
- `journal/STATE.md` — состояние;
- `journal/mobile-empty-state/*.png` — скриншоты 360×800, 390×844, 1440×900.
