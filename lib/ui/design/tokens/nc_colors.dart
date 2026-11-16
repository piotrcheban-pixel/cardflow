import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

/// Палитра Nocturne (REDESIGN-SPEC §1, ADR-035).
///
/// **Единственное место в `lib/ui/`, где разрешены сырые цвета**
/// (`Color(0x…)`, `Colors.*`); это проверяет `test/guards/design_tokens_test.dart`.
/// Виджеты берут цвет только через `NcTheme.of(context)` или
/// `Theme.of(context).colorScheme`.
///
/// Две полноценные темы: тёмная «Nocturne» (основная, §1.2) и светлая
/// «Porcelain» (§1.3). Повышенный контраст (§1.4) усиливает текст и hairline,
/// сдвигает акцент и заменяет стекло сплошной поверхностью. Dynamic color
/// меняет **только акцент**: тон системного primary сохраняется, яркость
/// фиксируется (80 — тёмная тема, 40 — светлая), chroma ограничивается 48.
@immutable
class NcColors {
  /// Создаёт палитру целиком (используется фабриками [dark] и [light]).
  const NcColors({
    required this.brightness,
    required this.ink0,
    required this.ink1,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.ink5,
    required this.hairline,
    required this.hairlineStrong,
    required this.rimLight,
    required this.scrim,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnAccent,
    required this.aurum,
    required this.aurumBright,
    required this.aurumDeep,
    required this.aurumSoft,
    required this.aurumGlow,
    required this.iris,
    required this.irisDeep,
    required this.irisSoft,
    required this.irisGlow,
    required this.ember,
    required this.emberSoft,
    required this.onEmber,
    required this.amber,
    required this.amberSoft,
    required this.onAmber,
    required this.jade,
    required this.jadeSoft,
    required this.onJade,
    required this.glacier,
    required this.glacierSoft,
    required this.onGlacier,
    required this.heat,
    required this.auroraAurum,
    required this.auroraIris,
    required this.auroraGlacier,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
  });

  /// Прозрачный цвет (без литералов в виджетах).
  static const Color transparent = Color(0x00000000);

  /// Чистый чёрный и белый — только для «стеклянных» световых слоёв.
  static const Color black = Color(0xFF000000);

  /// Чистый белый.
  static const Color white = Color(0xFFFFFFFF);

  /// Прежний бренд-сид SPEC A4.1 (`AppTheme.seedColor`) — историческая точка
  /// для M3E/`ColorScheme.fromSeed` в тестах и хелперах.
  static const Color legacySeed = Color(0xFF4F6BED);

  /// Тёплая тень Porcelain (REDESIGN-SPEC §3.3): в светлой теме тени не чёрные.
  static const Color warmShadow = Color(0xFF3A2E1A);

  /// Рамка молочного стекла Porcelain (§1.3: `#000000` 6 %).
  static const Color glassBorderLight = Color(0x0F000000);

  /// Тёмная тема «Nocturne» (§1.2) либо её повышенный контраст (§1.4).
  ///
  /// [dynamicAccent] — системный `primary` из `DynamicColorBuilder`: из него
  /// строится акцент Aurum (HCT, тон 80, chroma ≤ 48), остальные цвета
  /// остаются брендовыми.
  static NcColors dark({bool highContrast = false, Color? dynamicAccent}) {
    final bool dynamic = dynamicAccent != null;
    final Color aurum = !dynamic
        ? (highContrast ? _retone(_aurum, 90) : _aurum)
        : _dynamicAccent(dynamicAccent, tone: 80);
    final Color aurumBright = dynamic || highContrast
        ? _deriveBright(aurum, dark: true)
        : _aurumBright;
    final Color aurumDeep = dynamic || highContrast
        ? _deriveDeep(aurum, dark: true)
        : _aurumDeep;
    return NcColors(
      brightness: Brightness.dark,
      ink0: _ink0Dark,
      ink1: _ink1Dark,
      ink2: _ink2Dark,
      ink3: _ink3Dark,
      ink4: _ink4Dark,
      ink5: _ink5Dark,
      hairline: highContrast ? const Color(0x3DFFFFFF) : _hairlineDark,
      hairlineStrong: highContrast
          ? const Color(0x47FFFFFF)
          : _hairlineStrongDark,
      rimLight: const Color(0x1AFFFFFF),
      scrim: _scrimDark,
      textPrimary: _textPrimaryDark,
      textSecondary: highContrast
          ? const Color(0xFFD8D4CC)
          : _textSecondaryDark,
      textTertiary: highContrast ? const Color(0xFFB3AFA7) : _textTertiaryDark,
      textDisabled: _textDisabledDark,
      textOnAccent: _textOnAccentDark,
      aurum: aurum,
      aurumBright: aurumBright,
      aurumDeep: aurumDeep,
      aurumSoft: aurum.withValues(alpha: 0.14),
      aurumGlow: aurum.withValues(alpha: 0.28),
      iris: _irisDark,
      irisDeep: _irisDeepDark,
      irisSoft: _irisDark.withValues(alpha: 0.14),
      irisGlow: _irisDark.withValues(alpha: 0.30),
      ember: _emberDark,
      emberSoft: _emberDark.withValues(alpha: 0.14),
      onEmber: _onEmberDark,
      amber: _amberDark,
      amberSoft: _amberDark.withValues(alpha: 0.14),
      onAmber: _onAmberDark,
      jade: _jadeDark,
      jadeSoft: _jadeDark.withValues(alpha: 0.14),
      onJade: _onJadeDark,
      glacier: _glacierDark,
      glacierSoft: _glacierDark.withValues(alpha: 0.14),
      onGlacier: _onGlacierDark,
      heat: _heatDark,
      auroraAurum: aurum.withValues(alpha: 0.09),
      auroraIris: _irisDark.withValues(alpha: 0.08),
      auroraGlacier: _glacierDark.withValues(alpha: 0.05),
      primaryContainer: dynamic
          ? Color.alphaBlend(aurum.withValues(alpha: 0.14), _ink2Dark)
          : _primaryContainerDark,
      onPrimaryContainer: _onPrimaryContainerDark,
      secondaryContainer: _secondaryContainerDark,
      onSecondaryContainer: _onSecondaryContainerDark,
      tertiaryContainer: _tertiaryContainerDark,
      onTertiaryContainer: _onTertiaryContainerDark,
      errorContainer: _errorContainerDark,
      onErrorContainer: _onErrorContainerDark,
      inverseSurface: _inverseSurfaceDark,
      onInverseSurface: _onInverseSurfaceDark,
      inversePrimary: _inversePrimaryDark,
    );
  }

  /// Светлая тема «Porcelain» (§1.3) либо её повышенный контраст (§1.4).
  static NcColors light({bool highContrast = false, Color? dynamicAccent}) {
    final bool dynamic = dynamicAccent != null;
    final Color aurum = !dynamic
        ? (highContrast ? _retone(_aurumLight, 28) : _aurumLight)
        : _dynamicAccent(dynamicAccent, tone: 40);
    final Color aurumBright = dynamic || highContrast
        ? _deriveBright(aurum, dark: false)
        : _aurumBrightLight;
    final Color aurumDeep = dynamic || highContrast
        ? _deriveDeep(aurum, dark: false)
        : _aurumDeepLight;
    return NcColors(
      brightness: Brightness.light,
      ink0: _ink0Light,
      ink1: _ink1Light,
      ink2: _ink2Light,
      ink3: _ink3Light,
      ink4: _ink4Light,
      ink5: _ink5Light,
      hairline: highContrast ? const Color(0x3D000000) : _hairlineLight,
      hairlineStrong: highContrast
          ? const Color(0x47000000)
          : _hairlineStrongLight,
      rimLight: const Color(0xCCFFFFFF),
      scrim: _scrimLight,
      textPrimary: _textPrimaryLight,
      textSecondary: highContrast
          ? const Color(0xFF3F3C37)
          : _textSecondaryLight,
      textTertiary: highContrast ? const Color(0xFF55524C) : _textTertiaryLight,
      textDisabled: _textDisabledLight,
      textOnAccent: _textOnAccentLight,
      aurum: aurum,
      aurumBright: aurumBright,
      aurumDeep: aurumDeep,
      aurumSoft: aurum.withValues(alpha: 0.14),
      aurumGlow: aurum.withValues(alpha: 0.28),
      iris: _irisLight,
      irisDeep: _irisDeepLight,
      irisSoft: _irisLight.withValues(alpha: 0.14),
      irisGlow: _irisLight.withValues(alpha: 0.30),
      ember: _emberLight,
      emberSoft: _emberLight.withValues(alpha: 0.14),
      onEmber: _textOnAccentLight,
      amber: _amberLight,
      amberSoft: _amberLight.withValues(alpha: 0.14),
      onAmber: _textOnAccentLight,
      jade: _jadeLight,
      jadeSoft: _jadeLight.withValues(alpha: 0.14),
      onJade: _textOnAccentLight,
      glacier: _glacierLight,
      glacierSoft: _glacierLight.withValues(alpha: 0.14),
      onGlacier: _textOnAccentLight,
      heat: _heatLight,
      auroraAurum: aurum.withValues(alpha: 0.09),
      auroraIris: _irisLight.withValues(alpha: 0.08),
      auroraGlacier: _glacierLight.withValues(alpha: 0.05),
      primaryContainer: dynamic
          ? Color.alphaBlend(aurum.withValues(alpha: 0.14), _ink2Light)
          : _primaryContainerLight,
      onPrimaryContainer: _onPrimaryContainerLight,
      secondaryContainer: _secondaryContainerLight,
      onSecondaryContainer: _onSecondaryContainerLight,
      tertiaryContainer: _tertiaryContainerLight,
      onTertiaryContainer: _onTertiaryContainerLight,
      errorContainer: _errorContainerLight,
      onErrorContainer: _onErrorContainerLight,
      inverseSurface: _inverseSurfaceLight,
      onInverseSurface: _onInverseSurfaceLight,
      inversePrimary: _inversePrimaryLight,
    );
  }

  /// Яркость темы.
  final Brightness brightness;

  /// Фон приложения под Aurora (§1.2 `ink0`).
  final Color ink0;

  /// Базовая поверхность, фон под листами.
  final Color ink1;

  /// Плитки, строки списков, поля ввода.
  final Color ink2;

  /// Карточка-«монолит», сплошная замена стекла.
  final Color ink3;

  /// Нажатое и выбранное состояние, hover поля.
  final Color ink4;

  /// Трек слайдера, неактивный сегмент.
  final Color ink5;

  /// Разделители, рамки плиток (8 %).
  final Color hairline;

  /// Рамка стекла, фокус без акцента (14 %).
  final Color hairlineStrong;

  /// Верхний блик стекла и монолита (градиент 0→24 px).
  final Color rimLight;

  /// Затемнение под модальными окнами.
  final Color scrim;

  /// Заголовки, вопрос, основной текст.
  final Color textPrimary;

  /// Подписи, подзаголовки.
  final Color textSecondary;

  /// Метаданные, плейсхолдеры, подсказки клавиш.
  final Color textTertiary;

  /// Неактивные кнопки (не для информации).
  final Color textDisabled;

  /// Текст на золотой кнопке.
  final Color textOnAccent;

  /// Главное действие, активная вкладка, ключевая цифра.
  final Color aurum;

  /// Верх градиента CTA, блик.
  final Color aurumBright;

  /// Низ градиента CTA, нажатое состояние.
  final Color aurumDeep;

  /// Фон выбранного чипа, badge «к повторению» (14 %).
  final Color aurumSoft;

  /// Цветная тень главного CTA (28 %).
  final Color aurumGlow;

  /// Всё про нейросеть: генерация, «Почему?», провайдеры.
  final Color iris;

  /// Градиент кнопки «Сгенерировать».
  final Color irisDeep;

  /// Фон зоны прикрепления, чипы провайдера (14 %).
  final Color irisSoft;

  /// Свечение «AI-ауры» (30 %).
  final Color irisGlow;

  /// «Не знаю», ошибка, удаление.
  final Color ember;

  /// Фон ошибки (14 %).
  final Color emberSoft;

  /// Текст на `ember`.
  final Color onEmber;

  /// «Сложно», предупреждение.
  final Color amber;

  /// Фон предупреждения (14 %).
  final Color amberSoft;

  /// Текст на `amber`.
  final Color onAmber;

  /// «Знаю», успех, «верно».
  final Color jade;

  /// Фон успеха (14 %).
  final Color jadeSoft;

  /// Текст на `jade`.
  final Color onJade;

  /// «Легко», информация.
  final Color glacier;

  /// Фон информации (14 %).
  final Color glacierSoft;

  /// Текст на `glacier`.
  final Color onGlacier;

  /// Тепловая карта: `heat0` (нет повторений) … `heat4` (максимум).
  final List<Color> heat;

  /// Пятно Aurora: золото 9 %.
  final Color auroraAurum;

  /// Пятно Aurora: Iris 8 %.
  final Color auroraIris;

  /// Пятно Aurora: glacier 5 %.
  final Color auroraGlacier;

  /// `ColorScheme.primaryContainer` — фон контейнера главного действия.
  final Color primaryContainer;

  /// Текст на `primaryContainer`.
  final Color onPrimaryContainer;

  /// `ColorScheme.secondaryContainer` — фон «нейросетевых» контейнеров.
  final Color secondaryContainer;

  /// Текст на `secondaryContainer`.
  final Color onSecondaryContainer;

  /// `ColorScheme.tertiaryContainer` — фон успешных контейнеров.
  final Color tertiaryContainer;

  /// Текст на `tertiaryContainer`.
  final Color onTertiaryContainer;

  /// `ColorScheme.errorContainer` — фон контейнера ошибки.
  final Color errorContainer;

  /// Текст на `errorContainer`.
  final Color onErrorContainer;

  /// `ColorScheme.inverseSurface` — поверхность в противоположной теме.
  final Color inverseSurface;

  /// Текст на `inverseSurface`.
  final Color onInverseSurface;

  /// `ColorScheme.inversePrimary` — акцент на `inverseSurface`.
  final Color inversePrimary;

  /// Основной акцент экрана (сейчас — Aurum; dynamic color меняет его).
  Color get accent => aurum;

  /// Список полей для `==` и `hashCode`.
  List<Object> get _fields => <Object>[
    brightness,
    ink0,
    ink1,
    ink2,
    ink3,
    ink4,
    ink5,
    hairline,
    hairlineStrong,
    rimLight,
    scrim,
    textPrimary,
    textSecondary,
    textTertiary,
    textDisabled,
    textOnAccent,
    aurum,
    aurumBright,
    aurumDeep,
    aurumSoft,
    aurumGlow,
    iris,
    irisDeep,
    irisSoft,
    irisGlow,
    ember,
    emberSoft,
    onEmber,
    amber,
    amberSoft,
    onAmber,
    jade,
    jadeSoft,
    onJade,
    glacier,
    glacierSoft,
    onGlacier,
    Object.hashAll(heat),
    auroraAurum,
    auroraIris,
    auroraGlacier,
    primaryContainer,
    onPrimaryContainer,
    secondaryContainer,
    onSecondaryContainer,
    tertiaryContainer,
    onTertiaryContainer,
    errorContainer,
    onErrorContainer,
    inverseSurface,
    onInverseSurface,
    inversePrimary,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NcColors) return false;
    final List<Object> a = _fields;
    final List<Object> b = other._fields;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  /// Плавный переход между палитрами для `ThemeData.lerp` (AnimatedTheme).
  ///
  /// Яркость переключается дискретно на середине; `heat` интерполируется
  /// поэлементно.
  static NcColors lerp(NcColors a, NcColors b, double t) {
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    List<Color> lerpHeat(List<Color> x, List<Color> y) {
      final int length = x.length < y.length ? x.length : y.length;
      return <Color>[for (var i = 0; i < length; i++) l(x[i], y[i])];
    }

    return NcColors(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      ink0: l(a.ink0, b.ink0),
      ink1: l(a.ink1, b.ink1),
      ink2: l(a.ink2, b.ink2),
      ink3: l(a.ink3, b.ink3),
      ink4: l(a.ink4, b.ink4),
      ink5: l(a.ink5, b.ink5),
      hairline: l(a.hairline, b.hairline),
      hairlineStrong: l(a.hairlineStrong, b.hairlineStrong),
      rimLight: l(a.rimLight, b.rimLight),
      scrim: l(a.scrim, b.scrim),
      textPrimary: l(a.textPrimary, b.textPrimary),
      textSecondary: l(a.textSecondary, b.textSecondary),
      textTertiary: l(a.textTertiary, b.textTertiary),
      textDisabled: l(a.textDisabled, b.textDisabled),
      textOnAccent: l(a.textOnAccent, b.textOnAccent),
      aurum: l(a.aurum, b.aurum),
      aurumBright: l(a.aurumBright, b.aurumBright),
      aurumDeep: l(a.aurumDeep, b.aurumDeep),
      aurumSoft: l(a.aurumSoft, b.aurumSoft),
      aurumGlow: l(a.aurumGlow, b.aurumGlow),
      iris: l(a.iris, b.iris),
      irisDeep: l(a.irisDeep, b.irisDeep),
      irisSoft: l(a.irisSoft, b.irisSoft),
      irisGlow: l(a.irisGlow, b.irisGlow),
      ember: l(a.ember, b.ember),
      emberSoft: l(a.emberSoft, b.emberSoft),
      onEmber: l(a.onEmber, b.onEmber),
      amber: l(a.amber, b.amber),
      amberSoft: l(a.amberSoft, b.amberSoft),
      onAmber: l(a.onAmber, b.onAmber),
      jade: l(a.jade, b.jade),
      jadeSoft: l(a.jadeSoft, b.jadeSoft),
      onJade: l(a.onJade, b.onJade),
      glacier: l(a.glacier, b.glacier),
      glacierSoft: l(a.glacierSoft, b.glacierSoft),
      onGlacier: l(a.onGlacier, b.onGlacier),
      heat: lerpHeat(a.heat, b.heat),
      auroraAurum: l(a.auroraAurum, b.auroraAurum),
      auroraIris: l(a.auroraIris, b.auroraIris),
      auroraGlacier: l(a.auroraGlacier, b.auroraGlacier),
      primaryContainer: l(a.primaryContainer, b.primaryContainer),
      onPrimaryContainer: l(a.onPrimaryContainer, b.onPrimaryContainer),
      secondaryContainer: l(a.secondaryContainer, b.secondaryContainer),
      onSecondaryContainer: l(a.onSecondaryContainer, b.onSecondaryContainer),
      tertiaryContainer: l(a.tertiaryContainer, b.tertiaryContainer),
      onTertiaryContainer: l(a.onTertiaryContainer, b.onTertiaryContainer),
      errorContainer: l(a.errorContainer, b.errorContainer),
      onErrorContainer: l(a.onErrorContainer, b.onErrorContainer),
      inverseSurface: l(a.inverseSurface, b.inverseSurface),
      onInverseSurface: l(a.onInverseSurface, b.onInverseSurface),
      inversePrimary: l(a.inversePrimary, b.inversePrimary),
    );
  }

  // --- Сырые значения палитры (единственное место в lib/ui/) --------------

  static const Color _ink0Dark = Color(0xFF07080B);
  static const Color _ink1Dark = Color(0xFF0C0E13);
  static const Color _ink2Dark = Color(0xFF12151C);
  static const Color _ink3Dark = Color(0xFF191D26);
  static const Color _ink4Dark = Color(0xFF222734);
  static const Color _ink5Dark = Color(0xFF2C3242);
  static const Color _hairlineDark = Color(0x14FFFFFF);
  static const Color _hairlineStrongDark = Color(0x24FFFFFF);
  static const Color _scrimDark = Color(0x8F000000);
  static const Color _textPrimaryDark = Color(0xFFF2EEE7);
  static const Color _textSecondaryDark = Color(0xFFABA79F);
  static const Color _textTertiaryDark = Color(0xFF8A8780);
  static const Color _textDisabledDark = Color(0xFF4C4B48);
  static const Color _textOnAccentDark = Color(0xFF17120A);
  static const Color _aurum = Color(0xFFE4C88F);
  static const Color _aurumBright = Color(0xFFF3DDB0);
  static const Color _aurumDeep = Color(0xFFB8955A);
  static const Color _irisDark = Color(0xFFA99BFF);
  static const Color _irisDeepDark = Color(0xFF6E5CE6);
  static const Color _emberDark = Color(0xFFF0806B);
  static const Color _onEmberDark = Color(0xFF1C0B07);
  static const Color _amberDark = Color(0xFFE9B25E);
  static const Color _onAmberDark = Color(0xFF1C1305);
  static const Color _jadeDark = Color(0xFF66D3A3);
  static const Color _onJadeDark = Color(0xFF04170F);
  static const Color _glacierDark = Color(0xFF7FC4F5);
  static const Color _onGlacierDark = Color(0xFF05131D);
  static const List<Color> _heatDark = <Color>[
    Color(0xFF14171E),
    Color(0xFF2E2A20),
    Color(0xFF5C4C2E),
    Color(0xFF9C7E48),
    Color(0xFFE4C88F),
  ];
  static const Color _primaryContainerDark = Color(0xFF2A2519);
  static const Color _onPrimaryContainerDark = Color(0xFFF3DDB0);
  static const Color _secondaryContainerDark = Color(0xFF221D3D);
  static const Color _onSecondaryContainerDark = Color(0xFFD9D2FF);
  static const Color _tertiaryContainerDark = Color(0xFF12291F);
  static const Color _onTertiaryContainerDark = Color(0xFFB5EFD3);
  static const Color _errorContainerDark = Color(0xFF2E1611);
  static const Color _onErrorContainerDark = Color(0xFFFFD3C9);
  static const Color _inverseSurfaceDark = Color(0xFFF2EEE7);
  static const Color _onInverseSurfaceDark = Color(0xFF0C0E13);
  static const Color _inversePrimaryDark = Color(0xFFB8955A);

  static const Color _ink0Light = Color(0xFFF5F2EC);
  static const Color _ink1Light = Color(0xFFFAF8F4);
  static const Color _ink2Light = Color(0xFFFFFFFF);
  static const Color _ink3Light = Color(0xFFFFFFFF);
  static const Color _ink4Light = Color(0xFFEEEAE2);
  static const Color _ink5Light = Color(0xFFE2DDD3);
  static const Color _hairlineLight = Color(0x14000000);
  static const Color _hairlineStrongLight = Color(0x24000000);
  static const Color _scrimLight = Color(0x6616151A);
  static const Color _textPrimaryLight = Color(0xFF16151A);
  static const Color _textSecondaryLight = Color(0xFF5C5952);
  static const Color _textTertiaryLight = Color(0xFF726E67);
  static const Color _textDisabledLight = Color(0xFFA9A49B);
  static const Color _textOnAccentLight = Color(0xFFFFFFFF);

  /// §1.3 задаёт `#8E6B2E`; на холсте Porcelain это 4,38 : 1 (< 4,5 §10),
  /// поэтому значения затемнены минимально (ADR-035, отступления, п. 6).
  static const Color _aurumLight = Color(0xFF886529);
  static const Color _aurumBrightLight = Color(0xFFA67C33);
  static const Color _aurumDeepLight = Color(0xFF6B4E1C);
  static const Color _irisLight = Color(0xFF5B48D6);
  static const Color _irisDeepLight = Color(0xFF4A37C8);
  static const Color _emberLight = Color(0xFFBC4129);
  static const Color _amberLight = Color(0xFF946210);
  static const Color _jadeLight = Color(0xFF1A7A53);
  static const Color _glacierLight = Color(0xFF276EA5);
  static const List<Color> _heatLight = <Color>[
    Color(0xFFE8E3D9),
    Color(0xFFDCCBA4),
    Color(0xFFC3A670),
    Color(0xFFA5854A),
    Color(0xFF886529),
  ];
  static const Color _primaryContainerLight = Color(0xFFEFE3CB);
  static const Color _onPrimaryContainerLight = Color(0xFF3A2C10);
  static const Color _secondaryContainerLight = Color(0xFFE4E0FF);
  static const Color _onSecondaryContainerLight = Color(0xFF241A66);
  static const Color _tertiaryContainerLight = Color(0xFFD6F2E4);
  static const Color _onTertiaryContainerLight = Color(0xFF0B3A26);
  static const Color _errorContainerLight = Color(0xFFFBE0DA);
  static const Color _onErrorContainerLight = Color(0xFF4A1108);
  static const Color _inverseSurfaceLight = Color(0xFF16151A);
  static const Color _onInverseSurfaceLight = Color(0xFFF5F2EC);
  static const Color _inversePrimaryLight = Color(0xFFA67C33);

  /// Акцент из системного `primary` (REDESIGN-SPEC §1.4).
  static Color _dynamicAccent(Color source, {required double tone}) {
    final Hct base = Hct.fromInt(source.toARGB32());
    // Round-trip HCT → 8-битный sRGB может добавить ~0,1 к chroma, поэтому
    // граница чуть ниже 48, чтобы фактическое значение оставалось ≤ 48.
    final double chroma = base.chroma.clamp(0.0, maxDynamicChroma - 0.5);
    return Color(Hct.from(base.hue, chroma, tone).toInt());
  }

  /// Меняет только яркость цвета в HCT (для повышенного контраста).
  static Color _retone(Color source, double tone) {
    final Hct base = Hct.fromInt(source.toARGB32());
    return Color(Hct.from(base.hue, base.chroma, tone).toInt());
  }

  /// Верх градиента CTA: светлее акцента на 8 ступеней.
  static Color _deriveBright(Color accent, {required bool dark}) =>
      _shiftTone(accent, dark ? 8 : 10);

  /// Низ градиента CTA: темнее акцента.
  static Color _deriveDeep(Color accent, {required bool dark}) =>
      _shiftTone(accent, dark ? -18 : -14);

  static Color _shiftTone(Color accent, double delta) {
    final Hct base = Hct.fromInt(accent.toARGB32());
    return Color(
      Hct.from(
        base.hue,
        base.chroma,
        (base.tone + delta).clamp(0.0, 100.0),
      ).toInt(),
    );
  }
}

/// Верхняя граница chroma динамического акцента (REDESIGN-SPEC §1.4).
const double maxDynamicChroma = 48;
