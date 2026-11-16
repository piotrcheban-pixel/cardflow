import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'nc_colors.dart';

/// Материалы стекла как данные (REDESIGN-SPEC §4.1, ADR-035).
///
/// Стекло — только для парящего хрома и модальных слоёв (§4.2): не больше двух
/// групп `BackdropFilter` на экран (+1 модальная), никогда под текстом карточки,
/// в элементах списков, в полях ввода и на графиках (§4.3). При повышенном
/// контрасте материал становится сплошным `ink3` ([NcGlassMaterials.solid]).
@immutable
class NcGlassMaterial {
  const NcGlassMaterial({
    required this.blurSigma,
    required this.tint,
    required this.saturation,
    required this.borderColor,
    required this.noiseOpacity,
    required this.rimLightOpacity,
    this.isSolid = false,
  });

  /// Толщина размытия фона (Blur σ).
  final double blurSigma;

  /// Цвет и прозрачность заливки поверх размытия.
  final Color tint;

  /// Множитель насыщенности под стеклом (§4.1: 1,10 / 1,15 / 1,20).
  final double saturation;

  /// Цвет рамки (`hairlineStrong`).
  final Color borderColor;

  /// Непрозрачность зерна поверх стекла (2–3 %).
  final double noiseOpacity;

  /// Непрозрачность верхнего блика (rim light).
  final double rimLightOpacity;

  /// Сплошной материал (повышенны контраст или выключенная Aurora).
  final bool isSolid;

  /// Фильтр: `ImageFilter.compose(ColorFilter.matrix(saturation), blur)`.
  ui.ImageFilter get filter => ui.ImageFilter.compose(
    outer: ui.ColorFilter.matrix(NcGlassMaterials.saturationMatrix(saturation)),
    inner: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
  );

  /// Плавный переход материала (sigma, цвет тинта, насыщенность, блик).
  static NcGlassMaterial lerp(NcGlassMaterial a, NcGlassMaterial b, double t) =>
      NcGlassMaterial(
        blurSigma: a.blurSigma + (b.blurSigma - a.blurSigma) * t,
        tint: Color.lerp(a.tint, b.tint, t)!,
        saturation: a.saturation + (b.saturation - a.saturation) * t,
        borderColor: Color.lerp(a.borderColor, b.borderColor, t)!,
        noiseOpacity: a.noiseOpacity + (b.noiseOpacity - a.noiseOpacity) * t,
        rimLightOpacity:
            a.rimLightOpacity + (b.rimLightOpacity - a.rimLightOpacity) * t,
        isSolid: t < 0.5 ? a.isSolid : b.isSolid,
      );
}

/// Набор материалов стекла для одной темы.
@immutable
class NcGlassMaterials {
  const NcGlassMaterials({
    required this.thin,
    required this.regular,
    required this.thick,
  });

  /// Тёмная тема Nocturne (§4.1: tint `ink1` 52/62 %, `ink2` 74 %).
  static final NcGlassMaterials dark = _build(
    colors: NcColors.dark(),
    tints: <double>[0.52, 0.62, 0.74],
    borders: NcColors.dark().hairlineStrong,
  );

  /// Светлая тема Porcelain: молочное стекло (tint `#FFFFFF` 60–72 %,
  /// рамка `#000000` 6 %, блик `#FFFFFF` 80 %) — §1.3.
  static final NcGlassMaterials light = NcGlassMaterials(
    thin: NcGlassMaterial(
      blurSigma: 16,
      tint: NcColors.white.withValues(alpha: 0.60),
      saturation: 1.10,
      borderColor: NcColors.glassBorderLight,
      noiseOpacity: 0.02,
      rimLightOpacity: 0.80,
    ),
    regular: NcGlassMaterial(
      blurSigma: 28,
      tint: NcColors.white.withValues(alpha: 0.66),
      saturation: 1.15,
      borderColor: NcColors.glassBorderLight,
      noiseOpacity: 0.025,
      rimLightOpacity: 0.80,
    ),
    thick: NcGlassMaterial(
      blurSigma: 44,
      tint: NcColors.white.withValues(alpha: 0.72),
      saturation: 1.20,
      borderColor: NcColors.glassBorderLight,
      noiseOpacity: 0.03,
      rimLightOpacity: 0.80,
    ),
  );

  /// `glass.thin` — верхняя панель, капсула действий, тосты.
  final NcGlassMaterial thin;

  /// `glass.regular` — док навигации, док оценок, тулбар колоды.
  final NcGlassMaterial regular;

  /// `glass.thick` — нижние листы, диалоги, меню, палитра.
  final NcGlassMaterial thick;

  /// Сплошная замена стекла для повышенного контраста (§1.4, §4.4):
  /// `ink3` с рамкой `hairlineStrong`, без размытия и зерна.
  static NcGlassMaterial solid(NcColors colors) => NcGlassMaterial(
    blurSigma: 0,
    tint: colors.ink3,
    saturation: 1,
    borderColor: colors.hairlineStrong,
    noiseOpacity: 0,
    rimLightOpacity: 0.06,
    isSolid: true,
  );

  /// Плавный переход материалов между темами (`ThemeData.lerp`).
  static NcGlassMaterials lerp(
    NcGlassMaterials a,
    NcGlassMaterials b,
    double t,
  ) => NcGlassMaterials(
    thin: NcGlassMaterial.lerp(a.thin, b.thin, t),
    regular: NcGlassMaterial.lerp(a.regular, b.regular, t),
    thick: NcGlassMaterial.lerp(a.thick, b.thick, t),
  );

  /// Плавный переход одного материала.
  static NcGlassMaterial materialLerp(
    NcGlassMaterial a,
    NcGlassMaterial b,
    double t,
  ) => NcGlassMaterial.lerp(a, b, t);

  /// Матрица насыщенности 4×5 для `ColorFilter.matrix`.
  static List<double> saturationMatrix(double saturation) {
    const double lumR = 0.2126;
    const double lumG = 0.7152;
    const double lumB = 0.0722;
    final double s = saturation;
    return <double>[
      lumR * (1 - s) + s,
      lumG * (1 - s),
      lumB * (1 - s),
      0,
      0,
      lumR * (1 - s),
      lumG * (1 - s) + s,
      lumB * (1 - s),
      0,
      0,
      lumR * (1 - s),
      lumG * (1 - s),
      lumB * (1 - s) + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  static NcGlassMaterials _build({
    required NcColors colors,
    required List<double> tints,
    required Color borders,
  }) => NcGlassMaterials(
    thin: NcGlassMaterial(
      blurSigma: 16,
      tint: colors.ink1.withValues(alpha: tints[0]),
      saturation: 1.10,
      borderColor: borders,
      noiseOpacity: 0.02,
      rimLightOpacity: 0,
    ),
    regular: NcGlassMaterial(
      blurSigma: 28,
      tint: colors.ink1.withValues(alpha: tints[1]),
      saturation: 1.15,
      borderColor: borders,
      noiseOpacity: 0.025,
      rimLightOpacity: 0.06,
    ),
    thick: NcGlassMaterial(
      blurSigma: 44,
      tint: colors.ink2.withValues(alpha: tints[2]),
      saturation: 1.20,
      borderColor: borders,
      noiseOpacity: 0.03,
      rimLightOpacity: 0.10,
    ),
  );
}
