# DSH-PROMPTS.md — промпты для агента-разработчика

> Как пользоваться. Каждый этап — отдельная сессия DSH. В начало каждой сессии вставляется **блок 0 «Общий контекст»**, за ним — промпт этапа. После этапа запускается **промпт R «Ревью снимка»**, затем, если есть находки, — **промпт F «Фикс-итерация»**. Промпты задают *что* и *где*; *как* именно реализовать (структура классов, мелкие анимации, разбиение файлов внутри `lib/ui/design/`) DSH решает сам.

---

## Блок 0 — Общий контекст (вставлять в каждую сессию)

```text
Ты — DSH, ведущий Flutter-инженер проекта CardFlow. Идёт редизайн визуального слоя «Nocturne».

ИСТОЧНИКИ ПРАВДЫ (прочитай перед планом, в этом порядке):
1. AGENTS.md — постоянные правила проекта (FVM, --no-pub, material_ui вместо flutter/material,
   M3E только через lib/ui/m3e/, ARB-строки, guard-тесты, ретроспективы).
2. REDESIGN-SPEC.md — дизайн-система: токены, стекло, движение, отклик, компоненты, экраны (§9).
3. REDESIGN-PLAN.md — этапы, зоны файлов (Красная/Жёлтая/Зелёная), критерии.
4. SPEC.md — продуктовые требования; визуальные части A4 заменены REDESIGN-SPEC (ADR-035).
5. journal/STATE.md — где остановились.

НЕПРЕРЫВАЕМЫЕ ОГРАНИЧЕНИЯ:
- Логику не менять. Красная зона (REDESIGN-PLAN.md) — ни одной правки. В экранах не меняются
  тела обработчиков, провайдеры, ref.watch/read, вызовы GoRouter, аргументы движков и
  контроллеров. Меняется только дерево build и приватные виджеты оформления.
- Все существующие ValueKey сохраняются (guard ui_key_contract_test.dart). Новые ключи можно
  добавлять — снимок fixtures/ui_keys.txt дополняется в том же коммите.
- Строгий TDD: red-коммит (падающий тест с фрагментом вывода «ожидалось X, получено Y» в журнале)
  → green-коммит (минимальная реализация) → verify. Тесты не ослабляются и не удаляются.
  Переписать тест, искавший виджет по типу (FilledButton/ListTile/AppBar), можно только в
  отдельном коммите с обоснованием; число проверок не уменьшается.
- Интерфейс только на русском: новые строки — только lib/l10n/app_ru.arb + fvm flutter gen-l10n.
  Литералы текста в виджетах запрещены. ICU-шаблонов в ARB нет.
- Никаких WebView/HTML-пакетов, никаких google_fonts (шрифты — ассеты, local-first).
- Material — только package:material_ui/material_ui.dart. M3E — только через lib/ui/m3e/.
- Сырые цвета (Color(0x…), Colors.*) — только в lib/ui/design/tokens/nc_colors.dart.
- HapticFeedback.* — только в lib/ui/design/haptics.dart (с этапа 1). Таблица откликов — REDESIGN-SPEC §7.
- Стекло — только по правилам REDESIGN-SPEC §4 (не больше 2 групп BackdropFilter на экран + 1 модальная;
  никогда под текстом карточки, в элементах списков, в полях ввода, на графиках).
- Новая зависимость — только после проверки на pub.dev (платформы, лицензия, дата релиза,
  совместимость с Flutter из .fvmrc) и записи в docs/dependencies.md.
- Повторяющиеся анимации (Aurora, пульс, breathe, shimmer) в тестах — pump(Duration), не pumpAndSettle.
- Мёртвых кнопок нет: каждый видимый элемент работает или не отображается.

КОМАНДЫ (только через FVM, всегда --no-pub для test/build):
  fvm flutter gen-l10n
  fvm flutter test --no-pub --coverage --exclude-tags golden
  fvm flutter test --no-pub --tags golden            (локально — только обновление для ревью; эталон — Linux CI)
  fvm flutter analyze
  fvm dart format lib test integration_test && fvm dart format --set-exit-if-changed lib test integration_test
  fvm flutter build windows --release --no-pub
  fvm flutter test integration_test/session_smoke_windows_test.dart -d windows --no-pub

ЦИКЛ: plan → test → implement → review → verify → remember → improve. Коммит на каждый зелёный
шаг (conventional commit, английский префикс, тело по-русски). Push — только по команде владельца.
После каждого шага — journal/STATE.md. Не заявляй «готово» без команды и её вывода в этой сессии.
Ошибка пережила 3 попытки — стоп, гипотезы в журнал, смена подхода.

СВОБОДА: структура классов внутри lib/ui/design/, конкретная реализация анимаций, разбиение
компонентов на файлы, имена приватных виджетов, способ построения шейдеров или CustomPainter —
на твоё усмотрение, если результат соответствует REDESIGN-SPEC и проходит тесты. Если видишь, что
решение из SPEC хуже альтернативы (производительность, доступность, тестируемость) — предложи
отступление в ADR, а не молча меняй.

ОТЧЁТ В КОНЦЕ СЕССИИ: что сделано (по шагам и коммитам), вывод гейтов (числа тестов, покрытие,
analyze, format, build), git diff --stat по Красной зоне (должен быть пуст), скриншоты, открытые
вопросы владельцу, новые известные ограничения (journal/KNOWN_LIMITATIONS.md).
```

---

## Промпт 1 — Этап «Фундамент»

```text
ЭТАП 1 — ФУНДАМЕНТ «NOCTURNE». Журнал: journal/redesign-1/.

ЦЕЛЬ: ввести систему токенов, тему, шрифты, движение, отклик, фон и переходы так, чтобы ВСЁ
приложение стало выглядеть в стиле Nocturne только за счёт ThemeData, без правки экранов.
Экраны на этом этапе НЕ редактируются.

ШАГ 1.0 — СПАЙКИ И ADR (до плана):
- Проверь в закреплённой версии Flutter: RoundedSuperellipseBorder/ClipRSuperellipse,
  BackdropGroup + BackdropFilter.grouped, ImageFilter.compose(ColorFilter.matrix, blur),
  FragmentProgram в flutter test (если не грузится — заглушка шума тайловым PNG).
- Проверь кириллицу (включая ё, Ё, «», —, №) в Onest, Literata, JetBrains Mono — программным
  тестом через FontLoader + TextPainter (нет tofu: ширина глифа ≠ ширине .notdef).
- Создай docs/decisions/ADR-035-nocturne-design-system.md: что заменяет в SPEC A4 (hex только в
  токенах; шкала оценок ember→amber→jade→glacier вместо primary для Good; dynamic color меняет
  только акцент; superellipse вместо expressive-форм; стекло по правилам; M3E-фасад сохраняется).
- Итог спайков — journal/redesign-1/spikes.md.

ШАГ 1.1 — GUARD-ТЕСТЫ (red, затем green):
- tool/extract_ui_keys.dart: собирает все строковые литералы ключей из ValueKey<String>('…')
  и шаблоны вида 'deck-card-${…}' (нормализуй интерполяции в «*») из lib/ui/**.
  Запусти ОДИН раз ДО любых правок lib/ui → test/guards/fixtures/ui_keys.txt (отсортировано).
- test/guards/ui_key_contract_test.dart: каждый ключ из снимка присутствует в lib/ui/**.
- test/guards/design_tokens_test.dart: в lib/ui/** нет Color(0x / Colors. / Color.fromARGB /
  Color.fromRGBO вне lib/ui/design/tokens/nc_colors.dart. Сейчас нарушений быть не должно —
  проверь (тест сразу зелёный и служит ограждением; зафиксируй это в журнале).
- test/guards/no_network_fonts_test.dart: google_fonts отсутствует в pubspec.lock.
- Расширь test/guards/architecture_test.dart: lib/ui/design/** не импортирует lib/ui/state/,
  lib/ui/router/, lib/domain/, lib/data/, lib/api/ (дизайн-система чистая).

ШАГ 1.2 — ТОКЕНЫ (TDD) в lib/ui/design/tokens/:
- nc_colors.dart: палитры dark (Nocturne), light (Porcelain), high-contrast-модификаторы,
  dynamic-accent (HCT: тон 80/40, chroma ≤ 48; используй material_color_utilities только если
  он уже в pubspec.lock транзитивно И разрешён архитектурой, иначе — своя простая конверсия с ADR).
  Значения — строго из REDESIGN-SPEC §1.2–1.4.
- nc_typography.dart (§2), nc_spacing.dart (§3.1), nc_radii.dart (§3.2), nc_depth.dart (§3.3),
  nc_glass.dart (§4.1 — материалы как immutable-данные).
- Тесты: test/unit/ui/design/nc_colors_test.dart (значения, контраст WCAG ≥ 4,5 для пар
  textPrimary/Secondary/Tertiary на ink0–ink3 и on-цвета на акцентах, обе темы, high-contrast),
  dynamic-accent (primary #FF4081 → акцент ≠ #E4C88F, ink0 = #07080B), типографика (семейства,
  размеры, tabularFigures у mono), радиусы, глубина.

ШАГ 1.3 — ШРИФТЫ:
- assets/fonts/Onest/, Literata/, JetBrainsMono/ (variable, где есть; лицензии OFL в
  assets/fonts/LICENSES/). pubspec.yaml → fonts. LicenseRegistry.addLicense при старте
  (в main или app.dart — только регистрация лицензий, без логики).
- Тест применения: textTheme ролей = семейства из §2.2; при dyslexiaFont = true все роли (включая
  Literata-роли и mono) = OpenDyslexic. Существующий тест ADR-019 о шрифте дислексии — зелёный.

ШАГ 1.4 — NcTheme и AppTheme:
- lib/ui/design/nc_theme.dart: ThemeExtension<NcTheme> (цвета, типографика, глубина, стекло,
  флаги highContrast/glassEnabled) + NcTheme.of(context).
- lib/ui/theme/app_theme.dart: ПУБЛИЧНЫЙ API ПРЕЖНИЙ (light/dark с scheme, highContrast,
  dyslexiaFont; seedColor и dyslexiaFontFamily остаются — их могут читать тесты). Внутри:
  ручной ColorScheme по REDESIGN-SPEC §1.5 (scheme из DynamicColorBuilder → только акцент),
  TextTheme из токенов, темы компонентов (см. REDESIGN-PLAN 1.4), elevation 0, surfaceTint
  transparent, scaffoldBackgroundColor transparent (фон даёт Aurora), pageTransitionsTheme.
- Тесты: test/unit/ui/theme/app_theme_test.dart — роли, high contrast, dynamic accent,
  прозрачный scaffold, extension присутствует в обеих темах.

ШАГ 1.5 — ДВИЖЕНИЕ И ОТКЛИК:
- lib/ui/motion.dart: существующие константы и методы НЕ менять (их проверяют тесты). Добавить
  press/snap/gentle/celebrate (§6.1), длительности/кривые/stagger (§6.2). Тест: ratio каждой
  пружины = табличному (через SpringDescription.withDampingRatio).
- lib/ui/design/motion_scope.dart (или аналог): NcMotion.of(context) → набор пружин и флагов
  (ambient, stagger, celebrate, flipAsCrossfade) из effectiveAppSettingsProvider.motion и
  MediaQuery.disableAnimations. ВНИМАНИЕ: design/ не импортирует state/ — значение передаётся
  сверху (InheritedWidget, который ставит app.dart в builder).
- lib/ui/design/haptics.dart: NcHaptics (enabled-флаг из того же InheritedWidget, throttle 40 мс,
  методы по смыслу: flip, rating(Rating → по SPEC A7.2; Rating из domain — разрешённый импорт?
  если architecture_test запрещает domain в design — передавай enum-подобный NcHapticKind и
  делай маппинг Rating → kind в экранах). Тесты через TestDefaultBinaryMessengerBinding и
  SystemChannels.platform ('HapticFeedback.vibrate' с типом).
- Экраны пока НЕ переводить на NcHaptics (это этап 4/3), только инфраструктура.

ШАГ 1.6 — ФОН И ПЕРЕХОДЫ:
- lib/ui/design/ambient/: NcAmbientBackground (CustomPainter, RepaintBoundary, ≤ 30 Гц,
  пауза в background lifecycle, статичен при Standard/disableAnimations/в тестах), вариант
  intensity (1.0 каталог, 0.45 сессии) и tone (aurum/iris) как параметры; зерно (шейдер или тайл).
- lib/ui/design/transitions/nc_page_transitions.dart: PageTransitionsBuilder из §6.5 для всех
  TargetPlatform; на iOS сохраняется back-swipe.
- app.dart (Жёлтая зона): в builder MaterialApp.router обернуть child: NcMotionScope/NcHapticsScope
  (значения из settings) → NcAmbientBackground → M3ETheme (как сейчас). Больше ничего не менять.
- Тесты: фон статичен в тесте (нет активного тикера после pump), переходы — fade+scale
  (проверка Transform/FadeTransition в дереве на середине анимации).

ШАГ 1.7 — VERIFY:
- Полный прогон гейтов. Golden-эталоны (если есть) перегенерировать ОДНИМ коммитом
  test(golden): rebaseline Nocturne foundation, diff-картинки — в журнал.
- Скриншоты каждого экрана (dark/light, 390×844 и 1440×900) — journal/redesign-1/screenshots/.
- git diff --stat по Красной зоне — пусто, вывод в журнал.

ФАЙЛЫ, КОТОРЫЕ МОЖНО МЕНЯТЬ НА ЭТАПЕ:
  lib/ui/theme/app_theme.dart, lib/ui/motion.dart (только добавления), lib/ui/app.dart (только
  builder/theme/регистрация лицензий), lib/ui/design/** (новое), pubspec.yaml (fonts, assets,
  shaders, проверенные deps), assets/fonts/**, shaders/**, docs/**, test/**, tool/extract_ui_keys.dart,
  journal/**.
НЕЛЬЗЯ: любые *_screen.dart, *_view.dart, review_toolbar.dart, app_shell.dart, вся Красная зона.

ГОТОВО, КОГДА: все старые тесты зелёные без ослабления, новые guard/unit-тесты зелёные, analyze 0,
format 0, build windows ок, приложение запускается и выглядит в Nocturne (скриншоты), ADR-035 принят.
```

---

## Промпт 2 — Этап «Компоненты»

```text
ЭТАП 2 — КОМПОНЕНТЫ NOCTURNE. Журнал: journal/redesign-2/.

ЦЕЛЬ: библиотека lib/ui/design/components/ по REDESIGN-SPEC §8. Экраны не переводятся (кроме
глобального перехода тостов в шаге 2.5). Экспорт всех компонентов — lib/ui/design/design.dart.

ДЛЯ КАЖДОГО КОМПОНЕНТА (TDD):
1. Red: widget-тест поведения (тап, disabled, loading, фокус клавиатурой + Enter/Space,
   Semantics с текстом из ARB, textScale 2.0 без overflow, Standard motion без overshoot)
   + golden (тег golden): dark/light × обычный/high-contrast × textScale 1.0/2.0.
2. Green: реализация только на токенах (NcTheme.of), пружины — из NcMotion.of, отклик — NcHaptics.
3. Компонент не знает о Riverpod, роутере, домене (architecture_test).

ПОРЯДОК И СОСТАВ (каждая группа — отдельные red/green коммиты):
2.1 NcSurface, NcGlass (BackdropGroup/grouped, откат в сплошной ink3 при highContrast или
    glassEnabled=false; tint 80 % если Aurora выключена), NcIcon3D (ассет assets/icons3d/<name>.webp,
    резерв — стеклянная сфера с плоским глифом; excludeFromSemantics), NcKeyHint (виден только при
    наличии аппаратной клавиатуры/десктопе — реши сам, как детектировать; тест на обе ветки),
    NcBadge, NcSpinner, NcSkeleton.
    + test/helpers/glass_budget.dart: expectGlassBudget(tester, maxGroups: 2) — используется
    во всех экранных тестах этапов 3–5.
2.2 NcButton (primary/secondary/ghost/destructive/ai; l/m/s; prominent → glow; loading без
    скачка ширины), NcIconButton (tooltip обязателен — assert), NcSplitButton (API, совместимый
    по смыслу с M3ESplitButton: label, leadingIcon, items<T>, onPressed, onSelected,
    trailingTooltip; пункты принимают Widget, чтобы сохранялись ключи вроде decks-create-generate),
    NcFab (extended ↔ circle по ScrollNotification через NotificationListener снаружи или
    controller — на твой выбор).
2.3 NcTextField (обёртка над TextField из material_ui с InputDecoration из токенов; forward всех
    нужных параметров: controller, focusNode, key, onSubmitted, maxLines, obscureText, errorText,
    helperText, keyboardType, textInputAction, autofocus), NcSearchField, NcSwitch, NcSegmented<T>
    (API как у SegmentedButton: segments, selected Set<T>, onSelectionChanged — облегчит перенос
    тестов), NcSlider (onChangeEnd сохраняется), NcStepper (ключи minus/plus/value передаются
    снаружи), NcChip (filter/tag/status), NcDropdown<T>.
2.4 NcListRow, NcSection, NcCardTile (onPressed, onLongPress, onSecondaryTap для ПК, semanticLabel),
    NcTopBar (implements PreferredSizeWidget для замены AppBar; large title + схлопывание;
    стекло по скроллу через ScrollController/NotificationListener), NcEmptyState, NcErrorState.
2.5 NcMenu, showNcSheet<T> (тонкая обёртка над showModalBottomSheet<T>: тот же тип результата,
    isScrollControlled, showDragHandle → своя ручка; ≥ 1024 px — диалог 560), showNcDialog<T>,
    NcDialog, NcToast + showNcToast.
    ГЛОБАЛЬНЫЙ ПЕРЕХОД: в lib/ui/decks/deck_actions.dart (Жёлтая зона) функции showAppMessage и
    showArchivedUndoSnackbar показывают NcToast. Сигнатуры, тексты, «Отменить» и поведение undo —
    прежние; существующие тесты на снекбар обязаны остаться зелёными (если искали SnackBar по типу —
    отдельный коммит с переписанным тестом по тексту/ключу и обоснованием). Если M3ESnackbar
    используется где-то ещё — перечисли места в журнале, переведёшь на этапах 3–5.
2.6 NcProgressLine, NcSegmentedProgress (ключ пульса передаётся снаружи, чтобы сохранить
    feed-progress-pulse), NcRing, NcAnimatedNumber (счёт 0→N; Standard → без анимации).
2.7 NcMonolith, NcFlip (контроллер или value 0..1 снаружи, пружина параметром; блик-sheen по углу;
    flipAsCrossfade при disableAnimations), NcRatingButton, NcRatingDock (4 кнопки; интервал
    сверху — строка снаружи (готовый текст), ключи кнопок и интервалов передаются снаружи;
    neighbor-squish; при textScale ≥ 1.6 — сетка 2×2). Цвета оценок — через NcRatingTone
    (again/hard/good/easy), без импорта domain.Rating в design/.
2.8 test/golden/components_catalog_test.dart — одно полотно со всеми компонентами (dark и light)
    для ревью владельцем. НИКАКИХ debug-маршрутов/витрин в приложении.

ФАЙЛЫ, КОТОРЫЕ МОЖНО МЕНЯТЬ:
  lib/ui/design/** (новое), lib/ui/decks/deck_actions.dart (только тело showAppMessage /
  showArchivedUndoSnackbar), lib/l10n/app_ru.arb (семантические подписи компонентов, если нужны:
  например «Закрыть», «Очистить поиск»), test/**, docs/**, journal/**, pubspec.yaml
  (только проверенные deps, напр. material_symbols_icons/flutter_animate — по REDESIGN-SPEC §12).
НЕЛЬЗЯ: экраны, Красная зона, app_theme.dart (кроме исправления найденных багов токенов отдельным
  коммитом с тестом).

ГОТОВО, КОГДА: покрытие lib/ui/design/ ≥ 90 %, все компоненты с golden, каталог-полотно в журнале,
тосты по всему приложению — NcToast, Красная зона не тронута, гейты зелёные.
```

---

## Промпт 3 — Этап «Каталог» (экраны вне сессии)

```text
ЭТАП 3 — КАТАЛОГ: ОБОЛОЧКА И ЭКРАНЫ УПРАВЛЕНИЯ. Журнал: journal/redesign-3/.

ЦЕЛЬ: перевести на компоненты Nc экраны из REDESIGN-SPEC §9.1–9.4, 9.14–9.17 и стили контента
карточек (§9.20). Один экран — один шаг: red (тесты) → green → скриншоты.

ОБЩИЕ ПРАВИЛА ПЕРЕНОСА ЭКРАНА:
- Перед правкой экрана выпиши в журнал его обработчики и провайдеры (что вызывается по каждой
  кнопке) — после правки они должны вызываться ТЕ ЖЕ и с ТЕМИ ЖЕ аргументами. Тела методов
  _startSession, _openCardForm, _archiveDeck, _showContextMenu (логика выбора), _save, _toggle*,
  _setLimitKind и т. п. не меняются; меняется только то, что они рисуют (тип листа/диалога —
  на showNcSheet/showNcDialog с тем же типом результата).
- Red-тесты экрана: (а) все 🔑-ключи экрана из REDESIGN-SPEC §9 находятся; (б) новые элементы
  облика из §9 (сводка «К повторению: N», стат-пилюли, бейджи, подсказки) отрисованы с данными
  фейков; (в) expectGlassBudget ≤ 2; (г) textScale 2.0 без overflow (телефон 360×740);
  (д) ширины 390/800/1440 — нужная раскладка (1/2/3 колонки, док/рейл/сайдбар); (е) golden
  dark+light; (ж) guard: в файле экрана нет AppBar/ListTile/SwitchListTile/FilledButton/
  SegmentedButton/Card/M3ECard/M3ESplitButton/M3EExtendedFab/CircularProgressIndicator
  (test/guards/nocturne_migration_test.dart со списком переведённых файлов — пополняется шаг за шагом).
- Списки длиннее экрана — в тестах helper scrollTo (ретроспектива 6), сверху вниз (ретроспектива 7).
- Прямые HapticFeedback в переводимых экранах → NcHaptics с ТЕМ ЖЕ типом отклика.

ШАГИ И ФАЙЛЫ:
3.1 Оболочка — lib/ui/shell/app_shell.dart. NcNavDock (<600), NcNavRail (600–1023), сайдбар
    (≥1024). railBreakpoint = 600 сохраняется, добавь wideBreakpoint = 1024. _goBranch не меняется.
    Добавь ключи shell-nav-decks/statistics/settings (дополни снимок). Тесты 7-й итерации на
    NavigationBar/NavigationRail — переписать на ключи отдельным коммитом.
3.2 «Мои колоды» — lib/ui/decks/decks_screen.dart + виджеты диалогов в lib/ui/decks/deck_actions.dart
    (_DeckNameDialog, подтверждение удаления, предпросмотр импорта). Сводка в шапке — вычисление
    из уже полученного списка deckSummaries (сумма dueCards, длина списка), без новых провайдеров.
    Аватар колоды: NcIcon3D deck_gem_(hash(deck.id) % 8 + 1), тон по тому же hash — чистая функция
    в lib/ui/design/ (deckAvatarFor(String id)), с unit-тестом стабильности. Hero-теги
    deck-avatar-<id>, deck-title-<id>. Dismissible с ключом deck-card-<id> остаётся внешним виджетом.
    Пустое состояние: вторая кнопка «Сгенерировать карточки» → context.push(AppRoutes.generationPath)
    (тот же вызов, что уже есть в split-меню).
3.3 Экран колоды — lib/ui/decks/deck_screen.dart. Лист режимов → сетка плиток (ключи review-mode-*,
    enabled/подписи/счётчики — те же выражения, что сейчас). Лимит-диалог — NcDialog с прежними
    ключами. Парящий тулбар с deck-add-card / deck-generate-action. _DeckCardTile → NcListRow
    с глифом типа и точкой состояния (card.cardType, card.state — только чтение).
3.4 Форма карточки — lib/ui/cards/card_form_screen.dart, lib/ui/cards/occlusion_mask_editor.dart
    и стили lib/ui/cards/content/{card_content_view,card_image_view,card_text,cloze_text,
    inline_latex_text,latex_text,occlusion_image_view}.dart (НЕ latex_spans.dart).
    Guard-тесты LaTeX (study_mode_latex_test, card_text_test) — зелёные. Живое превью полей —
    CardContentView на NcMonolith (только чтение текущего текста контроллера).
    Кнопка «Сохранить» остаётся в bottomNavigationBar (ретроспектива 3c).
3.5 Конструктор — lib/ui/session/session_constructor_screen.dart (+ _PresetNameDialog → NcDialog).
3.6 Статистика — lib/ui/statistics/statistics_screen.dart, lib/ui/statistics/statistics_charts.dart.
    Painter'ы получают цвета из NcTheme (heat0–4, aurum). Правила подписей месяцев и нулевого
    столбика из итерации 7 — тесты зелёные. Слабые темы: «Тренировать» — тот же переход.
3.7 Настройки — lib/ui/settings/settings_screen.dart. Каждый ключ settings-* на месте; применение
    настроек проверяется на корне приложения (CardFlowApp) — интеграционный тест: тема, high
    contrast (стекло → сплошное), dyslexia (OpenDyslexic во всех ролях), textScale, motion
    (Aurora статична при standard), haptics (NcHaptics молчит при false).
3.8 Провайдеры — lib/ui/settings/generation_settings_screen.dart, lib/ui/settings/provider_account_dialogs.dart,
    lib/ui/settings/provider_labels.dart (ТОЛЬКО providerProtocolIcon). Ряд действий — Wrap
    (ретроспектива 7), проверка ключа — NcSpinner/бейдж; значения ключей никогда не отображаются.
3.9 Verify — полный прогон, Windows-смоук, скриншоты всех экранов этапа (обе темы, 3 ширины),
    git diff --stat Красной зоны — пусто.

МОЖНО МЕНЯТЬ: перечисленные в 3.1–3.8 файлы (Жёлтая зона — только оформление), lib/ui/design/**
  (доработка компонентов — с тестами), lib/l10n/app_ru.arb, test/**, docs/**, journal/**.
НЕЛЬЗЯ: Красная зона; экраны сессий (review/*, study/*), generation/* — это этапы 4 и 5.

ГОТОВО, КОГДА: экраны 3.1–3.8 соответствуют REDESIGN-SPEC §9, guard миграции зелёный для всех
файлов этапа, Hero колоды работает туда и обратно, интеграционный тест применения настроек зелёный,
гейты зелёные.
```

---

## Промпт 4 — Этап «Сессии»

```text
ЭТАП 4 — СЕССИИ: МОНОЛИТ, ОЦЕНКИ, ЛЕНТА, ИГРОВЫЕ РЕЖИМЫ. Журнал: journal/redesign-4/.

ЦЕЛЬ: REDESIGN-SPEC §9.5–9.13 и сигнатурные моменты §6.3 (1–3, 5). Это самый чувствительный этап:
движки и контроллеры (Красная зона) обслуживают FSRS и журнал повторений — их поведение должно
остаться побайтно тем же.

ПЕРЕД НАЧАЛОМ:
- Прогони и сохрани в журнал базовую линию: все тесты test/widget/review/**, test/widget/study/**,
  test/integration/** и Windows-смоук. Это эталон «до».
- Для каждого экрана выпиши: какие методы движка/контроллера вызываются (start, reveal, rate, undo,
  visit, toggleReveal, …), какие таймеры (бюджет минут, авто-продвижение) и какие клавиши
  (Space, 1–4, numpad). После правки — те же вызовы в том же порядке (тест-шпион на фейковом
  репозитории, где он уже есть; если нет — добавь тест до правки).

ШАГИ И ФАЙЛЫ:
4.1 Каркас — lib/ui/review/review_chrome.dart: ReviewSessionAppBar (тот же конструктор и
    PreferredSizeWidget; внутри — прогресс-линия + стеклянная капсула), confirmReviewExit →
    showNcDialog (результат bool прежний), showReviewSourceExcerpt → showNcSheet, ReviewEmptyView,
    ReviewCompletedView (празднование §6.3-5: трофей, NcAnimatedNumber, искры только в Expressive,
    двойной отклик mediumImpact → 110 мс → lightImpact через NcHaptics), ReviewLoadErrorView,
    ReviewTimeUpView, ReviewPlanMissingView. Публичные конструкторы не меняются.
4.2 Классика — lib/ui/review/review_card_view.dart (NcMonolith + NcFlip; ключи review-card,
    review-card-face; Semantics прежняя; пружина приходит параметром, как сейчас),
    lib/ui/review/review_toolbar.dart (ReviewToolbar с прежним конструктором (preview, enabled,
    onRating) внутри рисует NcRatingDock; reviewIntervalLabel не меняется; ключи review-rating-*,
    review-interval-*), lib/ui/review/review_session_screen.dart (только build/оформление: кнопка
    «Показать ответ» до переворота вызывает тот же _reveal; вспышка Aurora после оценки — через
    NcAmbient-контроллер в дереве; _playHaptic → NcHaptics с той же таблицей SPEC A7.2).
4.3 Лента — lib/ui/review/feed_card_view.dart (свечение края, штамп, морфинг r.xl → r.m → pill;
    пороги из feed_swipe.dart и feedLongSwipeFraction не меняются; отклик на пересечение 80 px и
    60 % — один раз за жест), lib/ui/review/feed_progress_bar.dart (NcSegmentedProgress, ключ
    feed-progress-pulse, пульс только в Expressive — как сейчас animatePulse),
    lib/ui/review/feed_session_screen.dart (_FeedBottomBar на стекле; ключи feed-*).
4.4 Тренировка — lib/ui/review/practice_session_screen.dart (бейдж «Тренировка», без интервалов,
    _PracticeCompletedView).
4.5 Тест — lib/ui/study/multiple_choice_screen.dart; Ввод — lib/ui/study/typing_screen.dart
    (AnswerDiffView: только стили; LaTeX-guard зелёный).
4.6 Пары — lib/ui/study/match_screen.dart (_ShakeTile можно переписать как оформление; таймер и
    ходы — те же значения); Верно/Неверно — lib/ui/study/true_false_screen.dart.
4.7 Итоги — lib/ui/study/study_session_chrome.dart (StudyProgressBar, StudyResultsView — публичные
    API прежние; трофей при точности ≥ 90 %, иначе target — чисто визуальный выбор).
4.8 Verify — полный прогон, сравнение с базовой линией «до» (тот же набор зелёных + новые),
    Windows-смоук, профилирование переворота и свайпа (flutter run --profile -d windows;
    ≤ 16 мс на кадр; отчёт journal/redesign-4/perf.md), тесты Standard motion и disableAnimations
    (переворот → кроссфейд, нет искр/каскада/пульса), expectGlassBudget на каждом экране.

ТЕСТЫ (red до кода, на каждый экран):
- ключи 🔑 из REDESIGN-SPEC §9.5–9.13; клавиши Space/1–4/numpad вызывают те же действия;
- док оценок появляется только после раскрытия; до раскрытия есть «Показать ответ»;
- при enabled=false кнопки оценки неактивны;
- отклик: шпион SystemChannels.platform фиксирует тип для каждой оценки (SPEC A7.2) и для порогов свайпа;
- textScale 2.0: док 2×2, без overflow; ширина 1440 — монолит ≤ 640;
- golden: монолит (лицо/оборот/середина переворота), док, лента с частичным свайпом влево/вправо,
  каждый режим в состоянии «вопрос» и «ответ/обратная связь», итоги — dark/light.

МОЖНО МЕНЯТЬ: перечисленные файлы 4.1–4.7 (Жёлтая зона — только оформление), lib/ui/design/**
  (доработка с тестами), lib/l10n/app_ru.arb (например, «Показать ответ», «Новый рекорд», если их нет),
  test/**, docs/**, journal/**.
НЕЛЬЗЯ (Красная зона): review_session_engine.dart, feed_session_engine.dart, practice_session_engine.dart,
  feed_swipe.dart, review_interval_format.dart, session_media.dart, study_session_controller.dart,
  state/**, router/**. Не менять порядок вызовов rate/undo/visit, длительность авто-продвижения,
  таймер бюджета минут.

ГОТОВО, КОГДА: все сессии соответствуют SPEC §9.5–9.13, базовая линия тестов сохранена полностью,
Windows-смоук зелёный, perf-отчёт в журнале, HapticFeedback только в design/haptics.dart.
```

---

## Промпт 5 — Этап «AI-студия, 3D и полировка»

```text
ЭТАП 5 — AI-СТУДИЯ, 3D-ИКОНКИ И ФИНАЛЬНАЯ ПОЛИРОВКА. Журнал: journal/redesign-5/.

ЦЕЛЬ: REDESIGN-SPEC §9.18–9.19, §5 (ассеты ComfyUI), §6.3-4/6, §10–11; закрыть редизайн.

5.1 ГЕНЕРАЦИЯ — lib/ui/generation/generation_screen.dart.
    Файл большой: разрешено вынести ПРИВАТНЫЕ ВИДЖЕТЫ ОФОРМЛЕНИЯ (_FileTile, _KeyBanner, _ProgressView,
    _LiveCardsStrip, зона прикрепления, hero) в lib/ui/generation/generation_widgets.dart
    (через part/part of — чтобы сохранить приватность — или как публичные stateless-виджеты
    с параметрами-данными). _GenerationScreenState: меняются только методы build/_buildForm/
    _buildActions/_buildBody/_buildConfigError в части дерева; _pickFiles, _handleDrop, _removeFile,
    _cancel, запуск пайплайна, PopScope-логика, оценка токенов — НЕ меняются.
    Iris-режим Aurora (tone: iris, breathe во время _generating), hero-сфера ai_orb, зона с
    marching ants (только Expressive; в тестах статично), бейджи форматов, чипы провайдеров
    (ключи generation-provider-*), NcButton.ai для generation-start, прогресс-орбита, живая лента
    с вылетом карточек. Все ключи generation-* на месте. Ошибки — только строки ARB (мапперы в
    Красной зоне не трогать).
5.2 ПРЕДПРОСМОТР — lib/ui/generation/generation_preview_screen.dart. Круглые чекбоксы, инлайн-
    редактирование (тот же контроллер _EditableCard), картинки с меню «Убрать/Заменить» (те же
    методы), ошибки фрагментов, отклонённые, нижняя стеклянная панель с тремя действиями.
    issueLabel не меняется.
5.3 3D-ИКОНКИ. Получи от владельца ассеты ComfyUI (если их нет в assets/icons3d/ — оставь резерв,
    зафиксируй в KNOWN_LIMITATIONS и переходи дальше). Тест icons3d_inventory_test.dart:
    каждое имя из REDESIGN-SPEC §5.3 есть в 1x/2x/3x, WebP, квадрат, альфа-канал, ≤ 120 КБ на файл
    (3.0x). Подключи тонирование аватаров колод (§5.4). Golden с реальными иконками.
5.4 МИКРОВЗАИМОДЕЙСТВИЯ. Hero колоды (если не завершён), NcAnimatedNumber в счётчиках колоды и
    статистике, каскады списков (stagger ≤ 8 элементов), hover-подъём и кольцо фокуса на ПК
    во всех интерактивных компонентах, вспышка Aurora после оценки (если не сделана на этапе 4).
5.5 КЛАВИАТУРНЫЙ СЛОЙ ПК (только если владелец подтвердил О-2 в REDESIGN-PLAN; иначе пропусти
    и запиши в журнал). Ctrl/⌘+K → командная палитра (glass.thick, NcSearchField, список действий).
    Действия — ТОЛЬКО существующие: переходы context.go/push на AppRoutes.decksPath, statisticsPath,
    settingsPath, generationPath, constructorPath, generationSettingsPath и открытие колоды по
    имени из deckSummariesProvider (/decks/<id>). Shortcuts/Actions ставятся в app_shell.dart
    (Жёлтая зона). router/** не меняется. Новые строки — в ARB. Тесты: сочетание открывает палитру,
    фильтрация по вводу, Enter выполняет переход (MockGoRouter или реальный роутер теста).
5.6 АУДИТ.
    - Доступность: программная проверка контраста всех пар токенов; textScale 2.0 на всех экранах
      (сводный тест); обход фокуса Tab на ключевых экранах; Semantics-дерево без 3D-иконок;
      отчёт journal/redesign-5/a11y.md.
    - Производительность: бюджет стекла на всех экранах (сводный тест), Aurora ≤ 30 Гц и пауза в
      background, прогрев шейдеров, cacheWidth у иконок; профиль на Windows (+ Android-эмулятор в CI,
      если доступно), отчёт journal/redesign-5/perf.md.
    - Бандл: шрифты + иконки ≤ 6 МБ (вывод du в журнал).
    - Guard: nocturne_migration_test покрывает ВСЕ экраны; design_tokens_test зелёный.
5.7 M3E. Перечисли оставшиеся использования material_3_expressive. Подготовь ADR-036 с вариантами
    (оставить фасад / удалить зависимость) — решение за владельцем, по умолчанию фасад остаётся.
5.8 ДОКУМЕНТАЦИЯ. AGENTS.md — новый раздел «Дизайн-система Nocturne» (токены и единственный файл
    цветов, правила стекла, NcHaptics, NcMotion, guard-тесты, как добавлять компонент, как добавлять
    3D-иконку); docs/m3e-tokens.md → docs/design-tokens.md (ссылкой на REDESIGN-SPEC);
    README.md — скриншоты Nocturne; REDESIGN-PLAN.md — отметки о выполнении этапов.

МОЖНО МЕНЯТЬ: lib/ui/generation/generation_screen.dart, generation_preview_screen.dart,
  новый generation_widgets.dart, lib/ui/shell/app_shell.dart (только Shortcuts/палитра),
  lib/ui/design/**, все экраны — только для полировки оформления из 5.4 (без изменения логики),
  assets/icons3d/**, pubspec.yaml (assets), lib/l10n/app_ru.arb, test/**, docs/**, AGENTS.md, README.md,
  journal/**.
НЕЛЬЗЯ: Красная зона, включая generation_error_message.dart, generation_failure_message.dart,
  parser_error_message.dart; пайплайн генерации и всё в lib/api, lib/domain, lib/data.

ГОТОВО, КОГДА: все экраны REDESIGN-SPEC §9 переведены и проверены golden-тестами в обеих темах;
ни одного сырого цвета вне токенов; Красная зона не изменилась с начала редизайна
(git diff <тег redesign-start>..HEAD по её файлам пуст — вывод в журнал); CI 9/9 после push
по команде владельца; документация обновлена.
```

---

## Промпт R — Ревью снимка (после каждого этапа)

```text
РЕВЬЮ ЭТАПА N РЕДИЗАЙНА. Работай только на неизменяемом снимке (последний green/verify-коммит),
код не правь. Результат — journal/redesign-N/review.md: находки critical/high/medium/low,
у каждой — файл:строка, сценарий воспроизведения, предлагаемый тест.

ЧЕК-ЛИСТ:
1. Логика: git diff <начало этапа>..HEAD по Красной зоне пуст. В Жёлтой зоне — сравни тела
   обработчиков до/после (onPressed/onTap/onSelected/_методы): совпадают ли вызовы провайдеров,
   движков, роутера, аргументы и порядок?
2. Ключи: ui_key_contract зелёный; новые ключи добавлены в снимок; ни один тест не потерял проверок.
3. Тесты: red-коммиты предшествуют green; в журнале есть фрагменты «ожидалось/получено»;
   переписанные тесты имеют обоснование; нет pumpAndSettle на экранах с повторяющимися анимациями.
4. Токены: нет Color(0x/Colors. вне nc_colors.dart; нет «магических» отступов и радиусов, которых
   нет в токенах (допустимы производные: концентрический радиус); шрифты из токенов.
5. Стекло: бюджет ≤ 2 (+1 модальная); стекла нет под текстом карточки, в списках, в полях, на
   графиках; откат при high contrast работает.
6. Движение: пружины только из AppMotion/NcMotion; Standard и disableAnimations выключают
   ambient/stagger/celebrate/parallax; переворот при disableAnimations — кроссфейд.
7. Отклик: HapticFeedback только в design/haptics.dart; таблица SPEC A7.2 и REDESIGN-SPEC §7
   соблюдена; при haptics=false отклика нет.
8. Русский язык: новые строки только в app_ru.arb; ru_strings guard зелёный; нет литералов в
   виджетах; Semantics на русском.
9. Доступность: контраст, textScale 2.0, фокус, семантика 3D-иконок (исключены).
10. Мёртвые элементы: каждая видимая кнопка что-то делает; нет «витрин» и заглушек.
11. Производительность: нет BackdropFilter в itemBuilder; RepaintBoundary у фона и стекла;
    тикеры останавливаются в dispose и при паузе приложения.
12. Платформы: ПК (hover, правый клик, клавиатура), телефон (жесты, safe area), планшет (рейл).
```

---

## Промпт F — Фикс-итерация (после ревью)

```text
ФИКС-ИТЕРАЦИЯ ЭТАПА N. Вход: journal/redesign-N/review.md.
Для КАЖДОЙ находки critical/high/medium: сначала тест, воспроизводящий дефект (red, с фрагментом
вывода в журнале), затем минимальная правка (green). Все high/medium закрываются одним
fix-коммитом с отдельным тестом на каждую находку (ретроспектива 3c); low — либо в том же коммите,
либо в KNOWN_LIMITATIONS с обоснованием. Логику и Красную зону не трогать. Если находка требует
правки логики — не исправляй: опиши в журнале и задай вопрос владельцу. Финал — полный прогон гейтов
и обновлённые скриншоты затронутых экранов.
```

---

## Приложение — короткие промпты для точечных задач

**A. Добавить новую 3D-иконку**
```text
Добавь 3D-иконку <name> из assets/icons3d/ (1x/2x/3x). Впиши её в инвентарь REDESIGN-SPEC §5.3
(строка: файл, объект, где используется) и в icons3d_inventory_test. Используй через
NcIcon3D('<name>') в <экран>, замени резерв. Golden затронутого экрана — перегенерировать
отдельным коммитом. Логику не менять.
```

**B. Перенести один экран отдельно** (если этап нужно дробить)
```text
Переведи <файл экрана> на компоненты Nocturne по REDESIGN-SPEC §9.<n>. Сначала red-тесты
(ключи, облик, бюджет стекла, textScale 2.0, 3 ширины, golden dark/light, guard миграции),
затем оформление. Обработчики и провайдеры экрана не меняются — выпиши их до и после в журнал.
Красная зона — без правок.
```

**C. Подобрать параметры анимации**
```text
Настрой <анимацию> экрана <экран>: используй только токены AppMotion/NcMotion; если ни один не
подходит — предложи новый токен с обоснованием (ADR-035, раздел «Изменения токенов»), добавь тест
ratio, проверь Standard/disableAnimations. Запиши до/после (видео или серию кадров pump(Duration))
в журнал.
```
