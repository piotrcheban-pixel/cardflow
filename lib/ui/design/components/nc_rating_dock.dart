import 'package:material_ui/material_ui.dart';

import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'nc_glass.dart';
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
  int? _pressed;

  int _flexFor(int index) {
    final int? pressed = _pressed;
    if (pressed == null) return 100;
    if (index == pressed) return 106;
    if ((index - pressed).abs() == 1) return 97;
    return 100;
  }

  Widget _button(int index) {
    final NcRatingSpec spec = widget.ratings[index];
    return Expanded(
      flex: _flexFor(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Listener(
          onPointerDown: (_) => setState(() => _pressed = index),
          onPointerUp: (_) => setState(() => _pressed = null),
          onPointerCancel: (_) => setState(() => _pressed = null),
          child: NcRatingButton(
            key: spec.key,
            label: spec.label,
            interval: spec.interval,
            color: spec.color,
            keyHint: spec.keyHint,
            enabled: widget.enabled && spec.enabled,
            onPressed: spec.onPressed,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final bool grid = textScale >= NcRatingDock.gridTextScale;
    final int half = (widget.ratings.length / 2).ceil();
    final Widget row = grid
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  for (var index = 0; index < half; index++)
                    if (index < widget.ratings.length) _button(index),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  for (var index = half; index < widget.ratings.length; index++)
                    _button(index),
                ],
              ),
            ],
          )
        : Row(
            children: <Widget>[
              for (var index = 0; index < widget.ratings.length; index++)
                _button(index),
            ],
          );

    final Widget dock = NcGlass(
      tier: NcGlassTier.regular,
      radius: NcRadii.xl,
      showNoise: false,
      padding: const EdgeInsets.all(NcSpace.s12),
      child: Opacity(opacity: widget.enabled ? 1 : 0.5, child: row),
    );
    if (widget.semanticLabel == null) return dock;
    return Semantics(label: widget.semanticLabel, container: true, child: dock);
  }
}
