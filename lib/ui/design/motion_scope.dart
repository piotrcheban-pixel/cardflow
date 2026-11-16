import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';

/// Режим движения (проекция `MotionPreference` домена, чтобы дизайн-система
/// не импортировала `domain/`, ADR-035).
enum NcMotionPreference {
  /// Всё по таблицам REDESIGN-SPEC §6.
  expressive,

  /// Без overshoot, без дрейфа Aurora, каскадов и искр.
  standard,
}

/// Набор пружин, длительностей и флагов движения для текущего режима
/// (REDESIGN-SPEC §6.4, ADR-035).
///
/// Значение передаётся сверху (`app.dart` → [NcMotionScope]) — дизайн-система
/// не читает настройки сама. Без scope возвращается выразительный режим.
@immutable
class NcMotion {
  const NcMotion._({required this.preference, required this.reduceMotion});

  /// Разрешает ли режим выразительные эффекты (overshoot, дрейф, каскады).
  factory NcMotion.resolve({
    NcMotionPreference preference = NcMotionPreference.expressive,
    bool disableAnimations = false,
  }) => NcMotion._(preference: preference, reduceMotion: disableAnimations);

  /// Выбранный пользователем режим.
  final NcMotionPreference preference;

  /// Системное «уменьшить движение» (`MediaQuery.disableAnimations`).
  final bool reduceMotion;

  /// Полный выразительный режим: пружины по таблице, Aurora дрейфует.
  bool get isExpressive =>
      preference == NcMotionPreference.expressive && !reduceMotion;

  /// Дрейф Aurora разрешён.
  bool get ambientDrift => isExpressive;

  /// Каскадное появление разрешено (иначе общий fade 160 мс).
  bool get staggerEnabled => isExpressive;

  /// Искры/трофей/празднование разрешены.
  bool get celebrateEnabled => isExpressive;

  /// Переворот карточки заменяется кроссфейдом 120 мс (§6.4).
  bool get flipAsCrossfade => reduceMotion;

  /// Переворот есть во всех режимах: это смысл, а не украшение (§6.4).
  bool get flipEnabled => true;

  /// Длительность перехода между экранами (при уменьшении движения — instant).
  Duration get pageDuration =>
      reduceMotion ? AppMotion.instant : AppMotion.page;

  /// Выразительная пружина; в стандартном режиме — стандартная.
  SpringDescription expressiveSpring() =>
      isExpressive ? AppMotion.expressiveSpring() : AppMotion.standardSpring();

  /// Стандартная пружина.
  SpringDescription standardSpring() => AppMotion.standardSpring();

  /// Пружина нажатия (в обоих режимах).
  SpringDescription pressSpring() => AppMotion.pressSpring();

  /// Пружина возврата (в обоих режимах).
  SpringDescription snapSpring() => AppMotion.snapSpring();

  /// Мягкая пружина hero; в стандартном режиме — стандартная.
  SpringDescription gentleSpring() =>
      isExpressive ? AppMotion.gentleSpring() : AppMotion.standardSpring();

  /// Пружина празднования; в стандартном режиме — стандартная.
  SpringDescription celebrateSpring() =>
      isExpressive ? AppMotion.celebrateSpring() : AppMotion.standardSpring();

  /// Effects-пружина (цвет, прозрачность, тени).
  SpringDescription effectsSpring() => AppMotion.effectsSpring();

  /// Значение движения из ближайшего [NcMotionScope]; без scope —
  /// выразительный режим.
  static NcMotion of(BuildContext context) => NcMotionScope.of(context);

  /// Значение движения или `null`, если scope нет.
  static NcMotion? maybeOf(BuildContext context) =>
      NcMotionScope.maybeOf(context);

  @override
  bool operator ==(Object other) =>
      other is NcMotion &&
      other.preference == preference &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(preference, reduceMotion);

  @override
  String toString() =>
      'NcMotion(${preference.name}, reduceMotion: $reduceMotion)';
}

/// Передаёт [NcMotion] вниз по дереву (ставится в `builder` приложения).
class NcMotionScope extends InheritedWidget {
  const NcMotionScope({super.key, required this.motion, required super.child});

  /// Значение движения текущего режима.
  final NcMotion motion;

  /// Значение из ближайшего scope; без scope — выразительный режим.
  static NcMotion of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NcMotionScope>()?.motion ??
      NcMotion.resolve();

  /// Ближайшее значение или `null` (без подписки на изменения).
  static NcMotion? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NcMotionScope>()?.motion;

  @override
  bool updateShouldNotify(NcMotionScope oldWidget) =>
      motion != oldWidget.motion;
}
