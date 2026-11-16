import 'package:material_ui/material_ui.dart';

/// Плотная поверхность Nocturne (REDESIGN-SPEC §8): основа плиток, секций,
/// строк. Глубину даёт `NcDepth` (elevation Material = 0), hover на ПК
/// приподнимает элемент на 2 px.
enum NcSurfaceTone {
  /// `ink2` — плитки колод, строки, поверхности контента.
  tile,

  /// `ink3` — монолит карточки сессии, диалог.
  monolith,

  /// Без заливки: только рамка/тень (зона прикрепления, hero).
  bare,
}

/// Плотная поверхность: `ink2`/`ink3`, `depth0–3`, радиус из токенов,
/// hover-подъём на ПК. Основа плиток (REDESIGN-SPEC §8).
class NcSurface extends StatefulWidget {
  /// Создаёт поверхность.
  const NcSurface({
    super.key,
    required this.child,
    this.tone = NcSurfaceTone.tile,
    this.level = 1,
    this.radius = 16,
    this.color,
    this.padding,
    this.border = true,
    this.hoverLift = true,
    this.width,
    this.height,
    this.onTap,
    this.semanticLabel,
  });

  /// Содержимое.
  final Widget child;

  /// Заливка поверхности.
  final NcSurfaceTone tone;

  /// Уровень глубины 0…3 (`NcDepth`).
  final int level;

  /// Радиус скругления (из `NcRadii`).
  final double radius;

  /// Переопределение заливки (например, `amberSoft` у баннера).
  final Color? color;

  /// Внутренние отступы.
  final EdgeInsetsGeometry? padding;

  /// Рисовать ли рамку `hairline` (уровень 0 без рамки пуст).
  final bool border;

  /// Приподнимать ли на hover (ПК) на 2 px.
  final bool hoverLift;

  /// Ширина (иначе по содержимому).
  final double? width;

  /// Высота (иначе по содержимому).
  final double? height;

  /// Тап по поверхности (делает её кнопкой).
  final VoidCallback? onTap;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  @override
  State<NcSurface> createState() => _NcSurfaceState();
}

class _NcSurfaceState extends State<NcSurface> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
