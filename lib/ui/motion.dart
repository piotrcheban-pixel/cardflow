import 'package:flutter/animation.dart';

/// Токены движения CardFlow: M3 Expressive (SPEC A4.4) и Nocturne
/// (REDESIGN-SPEC §6, ADR-035).
///
/// Физика задаётся парой stiffness + damping ratio, а не абсолютным
/// коэффициентом затухания: конструктор `SpringDescription(damping: …)`
/// принимает абсолютный коэффициент и для stiffness 380 даёт ratio ≈ 0.02.
/// Здесь всегда используется [SpringDescription.withDampingRatio].
///
/// Значения M3E сверены с токенами M3E (`M3EMotion.expressiveSpatialDefault` и
/// др.), см. `lib/ui/m3e/` и `docs/decisions/ADR-001-m3e-library.md`. Токены
/// Nocturne добавлены в редизайне 1 и **не меняют** существующие.
abstract final class AppMotion {
  /// Stiffness выразительной (spatial) пружины hero-моментов.
  static const double expressiveStiffness = 380;

  /// Damping ratio выразительной пружины: лёгкий overshoot.
  static const double expressiveDampingRatio = 0.8;

  /// Stiffness стандартной (spatial) пружины служебных переходов.
  static const double standardStiffness = 700;

  /// Damping ratio стандартной пружины: без отскока.
  static const double standardDampingRatio = 0.9;

  /// Stiffness effects-пружины (цвет, прозрачность, тени).
  static const double effectsStiffness = 1600;

  /// Damping ratio effects-пружины: критическое затухание, без overshoot.
  static const double effectsDampingRatio = 1.0;

  /// Stiffness пружины нажатия: сжатие до [pressScale] и возврат.
  static const double pressStiffness = 1200;

  /// Damping ratio пружины нажатия.
  static const double pressDampingRatio = 0.70;

  /// Stiffness пружины возврата (переключатели, сегменты, карточка ленты).
  static const double snapStiffness = 900;

  /// Damping ratio пружины возврата.
  static const double snapDampingRatio = 0.85;

  /// Stiffness мягкой пружины hero-переходов и сдвига доков.
  static const double gentleStiffness = 170;

  /// Damping ratio мягкой пружины.
  static const double gentleDampingRatio = 0.90;

  /// Stiffness празднования (трофей, «+N», вспышка).
  static const double celebrateStiffness = 260;

  /// Damping ratio празднования: заметный overshoot.
  static const double celebrateDampingRatio = 0.55;

  /// Выразительная пружина: раскрытие карточки, завершение сессии, стрик.
  static SpringDescription expressiveSpring() =>
      _spring(expressiveStiffness, expressiveDampingRatio);

  /// Стандартная пружина: настройки, списки, импорт, служебные переходы.
  static SpringDescription standardSpring() =>
      _spring(standardStiffness, standardDampingRatio);

  /// Effects-пружина: цвет, прозрачность, тени (без overshoot).
  static SpringDescription effectsSpring() =>
      _spring(effectsStiffness, effectsDampingRatio);

  /// Пружина нажатия (scale 0,96 и возврат).
  static SpringDescription pressSpring() =>
      _spring(pressStiffness, pressDampingRatio);

  /// Пружина возврата: карточка ленты, переключатели, сегменты.
  static SpringDescription snapSpring() =>
      _spring(snapStiffness, snapDampingRatio);

  /// Мягкая пружина hero-переходов и сдвига доков.
  static SpringDescription gentleSpring() =>
      _spring(gentleStiffness, gentleDampingRatio);

  /// Пружина празднования (только в режиме «Выразительная»).
  static SpringDescription celebrateSpring() =>
      _spring(celebrateStiffness, celebrateDampingRatio);

  static SpringDescription _spring(double stiffness, double ratio) =>
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: stiffness,
        ratio: ratio,
      );

  // --- Длительности и кривые нефизических анимаций (REDESIGN-SPEC §6.2) ---

  /// Hover, фокус.
  static const Duration instant = Duration(milliseconds: 90);

  /// Появление тоста, смена иконки.
  static const Duration fast = Duration(milliseconds: 160);

  /// Появление контента.
  static const Duration base = Duration(milliseconds: 240);

  /// Исчезновение.
  static const Duration exit = Duration(milliseconds: 180);

  /// Переход между экранами.
  static const Duration page = Duration(milliseconds: 420);

  /// Каскад: шаг на элемент.
  static const Duration staggerStep = Duration(milliseconds: 28);

  /// Каскад: не больше 8 элементов (≤ 224 мс).
  static const int maxStaggerItems = 8;

  /// Дрейф Aurora (48–64 с; взято 56).
  static const Duration ambient = Duration(milliseconds: 56000);

  /// «Дыхание» Iris и пульс Stories.
  static const Duration breathe = Duration(milliseconds: 4000);

  /// Скелетоны.
  static const Duration shimmer = Duration(milliseconds: 1400);

  /// Hover и фокус.
  static const Curve instantCurve = Cubic(0.2, 0, 0, 1);

  /// Появление тоста.
  static const Curve fastCurve = Cubic(0.2, 0, 0, 1);

  /// Появление контента (emphasized decelerate).
  static const Curve baseCurve = Cubic(0.05, 0.7, 0.1, 1);

  /// Исчезновение.
  static const Curve exitCurve = Cubic(0.3, 0, 0.8, 0.15);

  /// Переход между экранами (emphasized decelerate).
  static const Curve pageCurve = Cubic(0.05, 0.7, 0.1, 1);

  /// Дрейф Aurora.
  static const Curve ambientCurve = Curves.easeInOutSine;

  /// «Дыхание» Iris.
  static const Curve breatheCurve = Curves.easeInOutSine;

  /// Скелетоны.
  static const Curve shimmerCurve = Curves.linear;

  /// Масштаб нажатой кнопки (§6.3-7).
  static const double pressScale = 0.96;

  /// Подъём плитки на hover (ПК), px.
  static const double hoverLift = 2;

  /// Вспышка Aurora цветом оценки, мс.
  static const int glowPulseMs = 600;

  /// Задержка каскада для элемента [index] (≤ [maxStaggerItems] шагов).
  static Duration staggerDelay(int index) {
    if (index <= 0) return Duration.zero;
    final int step = index > maxStaggerItems ? maxStaggerItems : index;
    return Duration(milliseconds: staggerStep.inMilliseconds * step);
  }
}
