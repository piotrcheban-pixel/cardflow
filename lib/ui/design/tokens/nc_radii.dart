import 'package:material_ui/material_ui.dart';

import 'nc_spacing.dart';

/// Радиусы Nocturne — непрерывные скругления (superellipse), REDESIGN-SPEC §3.2.
///
/// Все радиусы строятся `RoundedSuperellipseBorder`/`ClipRSuperellipse`
/// (встроены в Flutter ≥ 3.32, спайк 1.0). Вложенный элемент концентричен:
/// радиус = радиус внешнего − внутренний отступ, минимум [xs].
abstract final class NcRadii {
  /// 8 px — маленький бейдж, подсказка клавиши.
  static const double xs = 8;

  /// 12 px — поле ввода, чип.
  static const double s = 12;

  /// 16 px — строка-плитка, кнопка оценки, вариант «Теста».
  static const double m = 16;

  /// 22 px — плитка колоды, секция настроек.
  static const double l = 22;

  /// 30 px — монолит, лист, диалог.
  static const double xl = 30;

  /// 38 px — hero «Начать сессию», зона прикрепления.
  static const double xxl = 38;

  /// 999 px — кнопки-действия, док навигации, сегменты.
  static const double pill = 999;

  /// `BorderRadius` из радиуса токена.
  static BorderRadius borderRadius(double radius) =>
      BorderRadius.all(Radius.circular(radius));

  /// Радиус вложенного элемента: внешний − отступ, но не меньше [xs].
  static double concentric({required double outer, required double inset}) {
    final double value = outer - inset;
    return value < xs ? xs : value;
  }

  /// `BorderRadius` вложенного элемента.
  static BorderRadius concentricBorder({
    required double outer,
    required double inset,
  }) => borderRadius(concentric(outer: outer, inset: inset));

  /// Непрерывное скругление (форма Nocturne) с опциональной рамкой.
  static RoundedSuperellipseBorder superellipse(
    double radius, {
    BorderSide side = BorderSide.none,
  }) =>
      RoundedSuperellipseBorder(borderRadius: borderRadius(radius), side: side);

  /// Внешние поля hero-секций/листов: внутренний отступ концентричного
  /// элемента по умолчанию.
  static const double sheetInset = NcSpace.s12;
}
