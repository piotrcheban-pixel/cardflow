import 'package:flutter/physics.dart';

/// Токены движения M3 Expressive (SPEC A4.4).
///
/// Физика задаётся парой stiffness + damping ratio, а не абсолютным
/// коэффициентом затухания: конструктор `SpringDescription(damping: …)`
/// принимает абсолютный коэффициент и для stiffness 380 даёт ratio ≈ 0.02.
/// Здесь всегда используется [SpringDescription.withDampingRatio].
///
/// Значения сверены с токенами M3E (`M3EMotion.expressiveSpatialDefault` и др.),
/// см. `lib/ui/m3e/` и `docs/decisions/ADR-001-m3e-library.md`.
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

  /// Выразительная пружина: раскрытие карточки, завершение сессии, стрик.
  static SpringDescription expressiveSpring() =>
      _spring(expressiveStiffness, expressiveDampingRatio);

  /// Стандартная пружина: настройки, списки, импорт, служебные переходы.
  static SpringDescription standardSpring() =>
      _spring(standardStiffness, standardDampingRatio);

  /// Effects-пружина: цвет, прозрачность, тени (без overshoot).
  static SpringDescription effectsSpring() =>
      _spring(effectsStiffness, effectsDampingRatio);

  static SpringDescription _spring(double stiffness, double ratio) =>
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: stiffness,
        ratio: ratio,
      );
}
