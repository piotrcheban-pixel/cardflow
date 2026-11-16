import 'package:material_ui/material_ui.dart';

import '../motion_scope.dart';
import '../nc_theme.dart';

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

  /// Ключ пульсирующего сегмента.
  static const Key pulseKey = ValueKey<String>('nc-segmented-progress-pulse');

  @override
  State<NcSegmentedProgress> createState() => _NcSegmentedProgressState();
}

class _NcSegmentedProgressState extends State<NcSegmentedProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: NcSegmentedProgress.pulsePeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool expressive = NcMotion.of(context).isExpressive;
    if (expressive && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!expressive && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final int total = widget.total <= 0 ? 1 : widget.total;
    final Widget row = Row(
      children: <Widget>[
        for (var index = 0; index < total; index++) ...<Widget>[
          if (index > 0) SizedBox(width: widget.gap),
          Expanded(child: _segment(theme, index)),
        ],
      ],
    );
    if (widget.semanticLabel == null) return row;
    return Semantics(label: widget.semanticLabel, child: row);
  }

  Widget _segment(NcTheme theme, int index) {
    final bool passed = index < widget.current;
    final bool isCurrent = index == widget.current;
    final bool rated = index < widget.rated;
    final Color? ratingColor = widget.ratingColors[index];
    final double radius = widget.height / 2;

    Widget fill(double opacity) => ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            color: theme.colors.textPrimary.withValues(alpha: 0.8 * opacity),
          ),
          if (rated && ratingColor != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 1.5,
                child: ColoredBox(color: ratingColor),
              ),
            ),
        ],
      ),
    );

    Widget segment;
    if (isCurrent) {
      segment = AnimatedBuilder(
        animation: _pulse,
        builder: (BuildContext context, Widget? child) {
          final double opacity = 0.45 + 0.4 * _pulse.value;
          return fill(opacity);
        },
      );
      segment = KeyedSubtree(key: NcSegmentedProgress.pulseKey, child: segment);
    } else if (passed) {
      segment = fill(1);
    } else {
      segment = ColoredBox(color: theme.colors.ink5);
    }

    return SizedBox(
      height: widget.height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.ink5,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: segment,
      ),
    );
  }
}
