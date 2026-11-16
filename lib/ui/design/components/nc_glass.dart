import 'package:material_ui/material_ui.dart';

/// Толщина стекла Nocturne (REDESIGN-SPEC §4.1).
enum NcGlassTier {
  /// `glass.thin` — верхняя панель, капсула действий, тосты.
  thin,

  /// `glass.regular` — док навигации, док оценок, тулбар.
  regular,

  /// `glass.thick` — листы, диалоги, меню.
  thick,
}

/// Примитив стекла (REDESIGN-SPEC §4.1): размытие с насыщением, тинт, зерно,
/// rim light и рамка. При повышенном контрасте и выключенном стекле —
/// сплошная `ink3` с рамкой (§4.4).
class NcGlass extends StatelessWidget {
  /// Создаёт стеклянную поверхность.
  const NcGlass({
    super.key,
    required this.child,
    this.tier = NcGlassTier.regular,
    this.radius = 30,
    this.padding,
    this.grouped = false,
    this.showNoise = true,
    this.showRimLight = true,
    this.width,
    this.height,
    this.semanticLabel,
  });

  /// Содержимое.
  final Widget child;

  /// Толщина материала.
  final NcGlassTier tier;

  /// Радиус скругления (из `NcRadii`).
  final double radius;

  /// Внутренние отступы.
  final EdgeInsetsGeometry? padding;

  /// Использовать `BackdropFilter.grouped` (нужен [NcGlassGroup] выше).
  final bool grouped;

  /// Рисовать ли зерно 2–3 %.
  final bool showNoise;

  /// Рисовать ли верхний блик.
  final bool showRimLight;

  /// Ширина.
  final double? width;

  /// Высота.
  final double? height;

  /// Текст семантики (если стекло — отдельный смысловой слой).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Общая группа `BackdropGroup` для нескольких `NcGlass(grouped: true)`
/// (§4.1): один проход размытия вместо N.
class NcGlassGroup extends StatelessWidget {
  /// Оборачивает несколько стеклянных элементов одной группой.
  const NcGlassGroup({super.key, required this.child});

  /// Стеклянные элементы.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
