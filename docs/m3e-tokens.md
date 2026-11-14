# Токены M3 Expressive в CardFlow

Документ фиксирует **фактические** токены дизайн-системы, которые использует приложение, и
отклонения от официальных значений M3 (SPEC A4: «значения токенов сверяются при спайке с актуальными
токенами M3; при расхождении приоритет у официальных токенов, отступление фиксируется в
`docs/m3e-tokens.md`»).

Источники:

- **SPEC A4.1–A4.6** — требования (цвет/типографика/формы/motion/компоненты/доступность).
- **`material_3_expressive` 1.2.0** — `M3EMotion` (`lib/foundations/interaction/m3e_motion.dart`
  установленного пакета), значения которого зеркалят опубликованный набор M3 Expressive. Эталон
  сверки читается **только тестом** `test/unit/ui/m3e_tokens_test.dart` (через слой `lib/ui/m3e/`);
  в рантайме UI значения берутся из `AppMotion`.
- **`lib/ui/motion.dart` (`AppMotion`)** — единственный источник пружин в приложении.
- **`lib/ui/theme/app_theme.dart` (`AppTheme`)** — единственный файл, где допустим сырой цвет
  (бренд-сид).

## 1. Пружины (SPEC A4.4)

Физика задаётся парой *stiffness + damping ratio*; `SpringDescription.withDampingRatio(mass: 1, …)`.
Абсолютный `damping` не используется: при stiffness 380 он даёт ratio ≈ 0.02 (SPEC A4.4).

| Режим | Где в приложении | Stiffness | Damping ratio | Эталон `M3EMotion` | Отклонение |
|---|---|---|---|---|---|
| Expressive (spatial) | Раскрытие карточки (`ReviewCardView`, `FeedCardView`), возврат карточки ленты пружиной, завершение сессии | 380 | 0.8 | `expressiveSpatialDefault` | нет |
| Standard (spatial) | Настройки, списки, импорт, служебные переходы | 700 | 0.9 | `spatialDefault` | нет |
| Effects | Цвет, прозрачность, тени (без overshoot) | 1600 | 1.0 | `effectsDefault` | нет |

Карта кода: `AppMotion.expressiveSpring()` / `standardSpring()` / `effectsSpring()`; в UI выбор
режима — `MotionPreference` из `AppSettings` (ADR-019 §2): «Стандартная» подменяет выразительную
пружину стандартной (`AppMotion.standardSpring()`), «Выразительная» оставляет `null`, т.е. дефолтную
expressive-пружину экрана.

Длительности/easing-кривые `M3EMotion` (`short*`/`medium*`/`long*`, `standard`, `emphasized*`) в
CardFlow отдельно не дублируются: анимации, которым нужна кривая, берут её из `material_ui`
(`Curves`, `Duration` в виджетах), а пространственные переходы — из пружин выше.

## 2. Почему `AppMotion`, а не `M3EMotion` в рантайме

Библиотека подключается **только** через слой `lib/ui/m3e/`, который реэкспортирует компоненты
(`M3ECard`, `M3EChip`, `M3ESnackbar`, `M3EExtendedFab`, `M3ESplitButton`, `M3ETheme`/`M3EThemeData`) —
ADR-001. Значения пружин живут в `AppMotion`, а `M3EMotion` — эталон в тесте
`test/unit/ui/m3e_tokens_test.dart`: он сравнивает stiffness/damping трёх режимов и проверяет, что
`SpringDescription` из `AppMotion` даёт ровно тот damping ratio, что заявлен у `M3EMotion`. Если
библиотека обновит токены, тест покраснеет — расхождение обязано проявиться здесь как отклонение
(проверка автоматическая, тогда как спецификация A4.4 предполагала ручную сверку при спайке).

## 3. Цвет (SPEC A4.1)

- Сырых hex в UI нет: единственное определение цвета — `AppTheme.seedColor` (`0xFF4F6BED`), из него
  строится `ColorScheme.fromSeed`; виджеты берут только роли (`colorScheme.primary` и т.д.).
  Проверено поиском в финальном аудите MVP: `Color(0x…` и `Colors.*` встречаются только в
  `lib/ui/theme/app_theme.dart`; отдельного guard-теста на сырые цвета нет — держится ревью экранов
  (`architecture_test.dart` защищает архитектурные импорты, не цвета).
- Роли оценок (SPEC A7.2): «Не знаю» — `errorContainer`, «Сложно» — `secondaryContainer`,
  «Знаю» — `primary`, «Легко» — `tertiaryContainer`; прогноз интервала — над кнопками.
- `contrastLevel`: `1` при включённом «Повышенном контрасте», иначе `0` (ADR-019 §2).
- **Dynamic color** (`dynamic_color` 2.1.0): при включённом переключателе схема платформы заменяет
  seed-схему; у схемы платформы нет параметра контраста — совместное действие не проверено на
  реальной ОС (**L6c/L43**). Fallback — seed-схема.

## 4. Типографика (SPEC A4.2)

| Роль | Где |
|---|---|
| `headlineMedium` / `headlineSmall` | лицевая сторона карточки (вопрос) |
| `bodyLarge` | обратная сторона (ответ), увеличенный межстрочный |
| `labelSmall` / `labelMedium` (`onSurfaceVariant`) | метаданные: теги, интервал, подписи прогресса |
| `titleMedium` / `titleLarge` | заголовки экранов, элементы списка настроек |

- Шрифт для дислексии: `AppTheme.dyslexiaFontFamily = 'OpenDyslexic'` (ассет
  `assets/fonts/OpenDyslexic-Regular.otf`, SIL OFL). Применяется через
  `textTheme.apply(fontFamily:)` **внутри** `ThemeData`, и M3E-тема проецируется из Material-темы
  (`M3EThemeData.fromMaterial`), иначе `M3EResolvedTheme` перекрыл бы шрифт (ретроспектива итерации 7).
- Масштаб текста: `MediaQuery.textScaler`, диапазон 0.8–1.4 (ADR-019 §2). Реальные размеры на
  устройствах не проверялись (**L43**).

## 5. Формы (SPEC A4.3)

| Элемент | Значение | Где |
|---|---|---|
| Карточка классики | `RoundedRectangleBorder(28)` | `lib/ui/review/review_card_view.dart` |
| Карточка ленты | 28 → 16 при свайпе, pill (999) при подтверждении | `lib/ui/review/feed_card_view.dart` |
| Кнопки оценки | `StadiumBorder` (pill) | `lib/ui/review/review_toolbar.dart` |
| Прогресс сессии | `LinearProgressIndicator` c радиусом 3 (морфинг квадрат→круг — SPEC A4.3, реализован линейным индикатором с закруглением) | `lib/ui/review/review_session_screen.dart`, `feed_progress_bar.dart` |
| Поля ввода | `OutlineInputBorder(12/16)` | формы карточек, настройки, генерация |
| Меню/панели | `BorderRadius.circular(20)` | экран генерации |

Отклонение: полный набор 35 Expressive-форм и «цветок»-морфинг прогресса из A4.3 **не реализованы**
как библиотека форм — используются радиусы выше. Это осознанный минимум MVP: M3E-библиотека не даёт
публичного набора форм, а собственный слой форм не окупается. Фиксируется как низкий риск дизайна,
не как ограничение функциональности.

## 6. Haptics (SPEC A4.4, A7.2)

| Действие | Haptic |
|---|---|
| Раскрытие карточки (тап/пробел) | `selectionClick` |
| «Не знаю» (Again) | `heavyImpact` |
| «Сложно» (Hard) / «Знаю» (Good) | `lightImpact` |
| «Легко» (Easy) | `selectionClick` |
| Завершение сессии / ленты | `mediumImpact` |

Карта кода: `reviewHapticFor(Rating)` в `lib/ui/review/review_session_engine.dart`; вызовы — экраны
сессии/ленты. Настройка «Haptics» выключает **все** вызовы (ADR-019 §2); проверено тестами
`test/unit/ui/review_haptics_test.dart` и widget-тестами экранов.

## 7. Компоненты M3E в использовании (SPEC A4.5)

`M3ECard` (колоды/колода), `M3EChip` (фильтр-чипы), `M3ESnackbar` (сообщения об ошибках/undo),
`M3EExtendedFab` (главное действие «Колод»), `M3ESplitButton` (меню импорта/генерации),
`M3ETheme`/`M3EThemeData.fromMaterial` (тема в `MaterialApp.builder`).

Не используется: `M3EMaterialApp` — у 1.2.0 нет `routerConfig`/GoRouter (ADR-007). Кнопки оценки —
обычные Material-кнопки на ролях темы, а не M3E-компоненты: нужна строгая пара «4 кнопки + прогноз»
с клавишами 1–4.

## 8. Доступность (SPEC A4.6)

- Семантические метки на русском (`Semantics`/`semanticsLabel`), тексты — только из ARB.
- Матрица `Semantics` тепловой карты отдаёт сводку года/недели, отдельные дни не озвучиваются —
  **L46**.
- Screen-reader-прогон на реальном устройстве не выполнялся (**L12/L39/L43**).

## 9. Что не проверено

- Рендер golden-тестами: каталог `test/golden/` пуст (сознательно в MVP — **L6**); тяжёлые
  визуальные проверки выполняются на Linux CI при появлении.
- Dynamic color, OpenDyslexic и масштаб текста на реальных ОС/экранах — **L43**, ручная приёмка
  владельца.
- Высококонтрастный режим ОС и «усиление границ» из A4.1 на живой системе не наблюдались (**L43**).
