import 'package:material_ui/material_ui.dart';

import 'nc_rating_button.dart';

/// Описание оценки для дока (без зависимости от домена: `Rating` проецирует
/// экран, ADR-035).
@immutable
class NcRatingSpec {
  /// Создаёт описание оценки.
  const NcRatingSpec({
    required this.label,
    required this.interval,
    required this.color,
    required this.onPressed,
    this.key,
    this.keyHint,
    this.enabled = true,
  });

  /// Название оценки (ARB).
  final String label;

  /// Подпись интервала.
  final String interval;

  /// Цвет оценки.
  final Color color;

  /// Оценка.
  final VoidCallback? onPressed;

  /// Ключ кнопки (`review-rating-again` и т.п.).
  final Key? key;

  /// Подсказка клавиши.
  final String? keyHint;

  /// Включена ли кнопка.
  final bool enabled;
}

/// Док оценок (REDESIGN-SPEC §8, §9.6): `glass.regular`, `r.xl`, отступ 12,
/// четыре `NcRatingButton`, neighbor-squish (нажатая +6 %, соседние −3 %),
/// 2 × 2 при textScale ≥ 1,6.
class NcRatingDock extends StatefulWidget {
  /// Создаёт док.
  const NcRatingDock({
    super.key,
    required this.ratings,
    this.enabled = true,
    this.semanticLabel,
  });

  /// Оценки (обычно 4).
  final List<NcRatingSpec> ratings;

  /// Все кнопки активны (пока идёт запись — false, прозрачность 50 %).
  final bool enabled;

  /// Текст семантики дока.
  final String? semanticLabel;

  /// Порог textScale для сетки 2 × 2.
  static const double gridTextScale = 1.6;

  @override
  State<NcRatingDock> createState() => _NcRatingDockState();
}

class _NcRatingDockState extends State<NcRatingDock> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
