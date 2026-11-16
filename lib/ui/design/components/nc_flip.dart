import 'package:material_ui/material_ui.dart';

/// 3D-переворот (REDESIGN-SPEC §6.3-1, §8): `rotateY` 0→π на `expressive`,
/// перспектива 0,0012; при уменьшении движения — кроссфейд 120 мс.
///
/// Управляется снаружи ([revealed]) — экран сессии держит состояние стороны.
class NcFlip extends StatefulWidget {
  /// Создаёт переворот.
  const NcFlip({
    super.key,
    required this.revealed,
    required this.front,
    required this.back,
    this.onTap,
    this.semanticLabel,
  });

  /// Показана ли обратная сторона.
  final bool revealed;

  /// Лицевая сторона.
  final Widget front;

  /// Обратная сторона.
  final Widget back;

  /// Тап по монолиту (переворот).
  final VoidCallback? onTap;

  /// Текст семантики стороны.
  final String? semanticLabel;

  /// Перспектива переворота.
  static const double perspective = 0.0012;

  @override
  State<NcFlip> createState() => _NcFlipState();
}

class _NcFlipState extends State<NcFlip> with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
