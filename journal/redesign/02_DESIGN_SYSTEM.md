# 02 — Дизайн-система CardFlow v2

**Решение:** [ADR-038](../docs/decisions/ADR-038-design-system-v2.md).
**Исходные значения:** `journal/redesign/00_REFERENCE_AUDIT.md`.

## 1. Цвет

Роли — стандартный `ColorScheme` Material 3, значения заданы явно
(`lib/ui/theme/app_tokens.dart`); никаких `fromSeed` в обычном режиме.

### Светлая тема

| Роль | Hex | Где |
|---|---|---|
| primary | `#3525CD` | основные действия, активный пункт, акценты |
| onPrimary | `#FFFFFF` | подпись на primary |
| primaryContainer | `#4F46E5` | hover основных кнопок, прогресс |
| primaryFixed / onPrimaryFixed | `#E2DFFF` / `#0F0069` | оценка «Легко», рекомендации |
| secondary | `#006C49` | успех, «Хорошо», положительные дельты |
| secondaryContainer / on | `#6CF8BB` / `#00714D` | оценка «Хорошо», «Все повторено» |
| tertiary | `#95002B` | просрочка, «Снова»-акценты, ошибки в темах |
| tertiaryContainer / on | `#BF0F3C` / `#FFD0D2` | предупреждения, акцентные бейджи |
| error / errorContainer | `#BA1A1A` / `#FFDAD6` | ошибки, оценка «Снова» |
| surface | `#F8F9FF` | фон приложения |
| surfaceContainerLowest | `#FFFFFF` | панели, карточки, поля, панель/шапка |
| surfaceContainerLow | `#EFF4FF` | чипы, вложенные блоки, зона загрузки |
| surfaceContainer | `#E5EEFF` | активная навигация, трек прогресса |
| surfaceContainerHigh/Highest | `#DCE9FF` / `#D3E4FE` | hover, выключенный переключатель |
| onSurface / onSurfaceVariant | `#0B1C30` / `#464555` | основной/второстепенный текст |
| outline / outlineVariant | `#777587` / `#C7C4D8` | третичный текст / все границы и разделители |
| inverseSurface / on | `#213145` / `#EAF1FF` | снекбар/тост |

### Тёмная тема

`#818CF8` / `#6366F1` / `#34D399` / `#065F46` / `#FB7185` / `#E11D48` /
`#F87171` / `#450A0A` / `#090E1A` / `#111827` / `#172033` / `#1E293B` /
`#273549` / `#334155` / `#F1F5F9` / `#CBD5E1` / `#94A3B8` / `#293548` /
`#E2E8F0`.

Правило контраста: заливка основного действия в тёмной теме —
`primaryContainer` (`#6366F1`) с **белой** подписью (`AppColors.primaryAction`
/ `onPrimaryAction`), потому что белый на `#818CF8` даёт ≈2.6:1. `onPrimary`
тёмной схемы — `#14122B` для компонентов, читающих роль напрямую.

Специальные роли оценок (`AppColors.rating*`):
Again — errorContainer/onErrorContainer; Hard — surfaceContainer/onSurface;
Good — secondaryContainer/onSecondaryContainer; Easy — primaryFixed/onPrimaryFixed.

Обратная связь режимов «Тест», «Ввод», «Верно/Неверно»
(`AppColors.feedbackCorrect/Almost/Wrong*`): зелёная/янтарная/красная пары
«фон + текст» для светлой и тёмной темы; раньше были литералами в трёх
экранах, теперь единый токен-контракт.

## 2. Типографика

Inter (переменный, `assets/fonts/Inter-Variable.ttf`, SIL OFL 1.1;
`assets/fonts/OFL-Inter.txt`). Шкала — `lib/ui/theme/app_typography.dart`:

| Роль темы | Размер/интерлиньяж | Вес | Трекинг | Применение |
|---|---|---|---|---|
| displayLarge | 36/44 | 700 | −0.9 | крупные заголовки |
| displayMedium | 28/34 | 700 | −0.56 | заголовок страницы (32 на ПК) |
| headlineLarge/Medium/Small | 24/32, 20/28, 16/24 | 600 | −0.48/−0.3/−0.16 | заголовки секций |
| titleLarge/Medium/Small | 18/26, 16/24, 14/20 | 600 | −0.2/−0.16/−0.1 | карточки, диалоги |
| bodyLarge/Medium/Small | 15/22, 13/18, 12/16 | 400 | 0 | текст |
| labelLarge/Medium/Small | 13/16, 11/14, 11/14 | 600/600/500 | +0.1/+0.33/+0.2 | кнопки, надзаголовки, чипы |

Числа — `FontFeature.tabularFigures` (`AppTypography.numeric`, KPI, счётчики).
Надзаголовки — `AppTypography.overline` (11/14, uppercase, 0.66 px).
OpenDyslexic перекрывает семейство в `AppTheme._build`, шкала сохраняется.

## 3. Радиусы, отступы, размеры

- Радиусы (`AppRadii`): xs 6, sm 8, control 10, input 12, card 16, panel 20,
  pill 999.
- Отступы (`AppSpacing`): 4/8/12/16/20/24/32/40/48; базовый шаг 4.
- Оболочка (`AppSizes`): панель 240, шапка 56, контент 1280, форма 896,
  карточка сессии 640, диалог 512, кнопка 40/44, иконки 20/18/16,
  тач-таргет ≥44.
- Сетки: колоды 1/2/3 колонки (порог 768/1024), KPI 2/4 (порог 768),
  отступы 16.

## 4. Тени

Светлая тема: карточка — `0 1px 3px rgba(...,0.10)` + `0 1px 2px -1px
rgba(...,0.10)` (в `AppShadows.card` — мягкий вариант 0.04/6/2 для плотного
интерфейса); диалог — 32 px blur, смещение 12; тёмная тема — тени не
рисуются, глубину дают границы `outlineVariant`.

## 5. Компоненты (`lib/ui/components/`)

| Компонент | Контракт |
|---|---|
| `AppPageScaffold` | шапка + прокручиваемый список секций, ширина и отступы страницы |
| `AppPageHeader` | надзаголовок/крошки, заголовок, пояснение, адаптивные действия |
| `AppContentWidth` | центр + максимальная ширина |
| `AppPanel` | поверхность r16 на `Material` (фон, splash, границы), тень снаружи, `onTap`/`onLongPress`, семантика |
| `AppSectionCard` | панель с иконкой, заголовком, пояснением, разделителем |
| `AppStatTile` | KPI: надзаголовок, значение, единица, хелпер, иконка-бейдж |
| `AppStatusChip` | pill, тона neutral/info/success/warning/danger |
| `AppIconBadge` | квадрат с тонированным фоном и иконкой |
| `AppProgressBar` | 6 px, скругление pill, внутри — `LinearProgressIndicator` (тесты/скринридеры видят знакомый тип) |
| `AppDashedBorder` | пунктирная рамка зоны загрузки (`foregroundPainter`, без новых зависимостей) |
| `AppEmptyState` / `AppErrorState` | пусто/ошибка с действиями |
| `AppSkeleton` / `AppLoadingPlaceholder` | статичные заглушки загрузки |
| `AppDialog` / `showAppDialog` | диалог 512, шапка/тело/действия в контексте диалога |
| `AppSheetHeader` / `showAppSheet` | нижний лист ≤560, drag handle |

Кнопки/поля/переключатели — Material с компонентными темами
(`FilledButton` 40 px r10, `OutlinedButton`, `TextField` заполненный r12,
`Switch` 44×24-подобный, `Slider` 4 px). M3E-компоненты — только из
`lib/ui/m3e/`.

## 6. Адаптивность

Порог постоянной панели — 1024 (`AppSizes.sidebarBreakpoint`); ниже — Drawer.
Порог сетки колод — 768/1024. Заголовки страниц: 32 px ≥640, 28 px ниже.
Действия шапки на узком экране переносятся под заголовок (`Wrap`).
Проверенные ширины: 1440×900, 1024×768, 390×844, 360×800; текст — до
масштаба 1.3 (настройка), OpenDyslexic, повышенный контраст.

## 7. Движение и доступность

- Быстрые переходы 120/180/260 мс (`AppDurations`), `Curves.easeOut`.
- Пружины `lib/ui/motion.dart` не менялись; переворот карточки и раскрытие
  ответа — как раньше.
- Нет бесконечных анимаций: скелетоны статичны, прогресс анимируется один раз.
- `Semantics`: заголовки/панели с `button`, `selected` в навигации, подписи
  прогресса и статусов; тач-таргет ≥44; контраст основного текста ≥4.5:1
  (тёмная заливка кнопок — `primaryContainer`).
- Шрифт дислексии, масштаб текста, dynamic color и повышенный контраст
  продолжают работать (ADR-019 §2, A6.6).
