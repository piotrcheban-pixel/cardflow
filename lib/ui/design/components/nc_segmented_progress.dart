import 'package:material_ui/material_ui.dart';

/// Сегментный прогресс Stories (REDESIGN-SPEC §8): зазор 3 px, высота 3,
/// текущий сегмент пульсирует (`breathe`, только Expressive). Ключ
/// `feed-progress-pulse` сохраняется у экрана.
class NcSegmentedProgress extends StatefulWidget {
  /// Создаёт сегментный прогресс.
  const NcSegmentedProgress({
    super.key,
    required this.total,
    required this.current,
    this.rated = 0,
    this.ratingColors = const <int, Color>{},
    this.height = 3,
    this.gap = 3,
    this.semanticLabel,
  });

  /// Всего сегментов.
  final int total;

  /// Текущий сегмент (0-based); всё левее — пройдено.
  final int current;

  /// Сколько карточек оценено (цветные полоски).
  final int rated;

  /// Цвет оценки по индексу карточки.
  final Map<int, Color> ratingColors;

  /// Высота сегмента.
  final double height;

  /// Зазор между сегментами.
  final double gap;

  /// Текст семантики (ARB «Оценено N из M»).
  final String? semanticLabel;

  /// Длительность пульса.
  static const Duration pulsePeriod = Duration(milliseconds: 4000);

  @override
  State<NcSegmentedProgress> createState() => _NcSegmentedProgressState();
}

class _NcSegmentedProgressState extends State<NcSegmentedProgress>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
