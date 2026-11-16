import 'package:material_ui/material_ui.dart';

import '../tokens/nc_spacing.dart';

/// Монолит карточки сессии (REDESIGN-SPEC §8): `ink3`, `r.xl`, `depth3`,
/// rim light, внутренние поля 28/32, максимум 640. Слоты: лицо, метаданные,
/// бейджи.
class NcMonolith extends StatelessWidget {
  /// Создаёт монолит.
  const NcMonolith({
    super.key,
    required this.child,
    this.metadata,
    this.badges,
    this.maxWidth = NcSpace.maxSessionWidth,
    this.minHeight = 320,
    this.padding,
    this.onTap,
    this.semanticLabel,
  });

  /// Лицо карточки (вопрос/ответ).
  final Widget child;

  /// Тихая строка метаданных над лицом.
  final Widget? metadata;

  /// Бейджи под лицом.
  final Widget? badges;

  /// Максимальная ширина.
  final double maxWidth;

  /// Минимальная высота.
  final double minHeight;

  /// Внутренние поля (по умолчанию 32 × 28).
  final EdgeInsetsGeometry? padding;

  /// Тап (переворот).
  final VoidCallback? onTap;

  /// Текст семантики (лицо стороны).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
