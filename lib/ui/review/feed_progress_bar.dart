import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';

/// Stories-прогресс ленты (SPEC A7.3): сегмент на карточку, текущий пульсирует.
///
/// Оценённые сегменты заполнены `primary`; текущий пульсирует прозрачностью
/// (повторяющаяся анимация, поэтому экран ленты в тестах прогоняется
/// `pump(Duration)`, а не `pumpAndSettle`).
class FeedProgressBar extends StatefulWidget {
  /// Создаёт прогресс ленты.
  const FeedProgressBar({
    required this.rated,
    required this.currentIndex,
    this.animatePulse = true,
    super.key,
  });

  /// Оценена ли карточка с каждым индексом.
  final List<bool> rated;

  /// Индекс текущей карточки.
  final int currentIndex;

  /// Пульс текущего сегмента (A6.6: «Стандартная» анимация — без пульса).
  final bool animatePulse;

  @override
  State<FeedProgressBar> createState() => _FeedProgressBarState();
}

class _FeedProgressBarState extends State<FeedProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = _createPulse();

  AnimationController _createPulse() {
    final AnimationController controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.animatePulse) {
      controller.repeat(reverse: true);
    } else {
      controller.value = 1;
    }
    return controller;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int ratedCount = widget.rated.where((bool value) => value).length;
    return Semantics(
      container: true,
      label: l10n.feedProgressSemantics(ratedCount, widget.rated.length),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (BuildContext context, Widget? child) {
          final double pulse = 0.45 + 0.55 * _pulse.value;
          return Row(
            children: <Widget>[
              for (int index = 0; index < widget.rated.length; index++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: _Segment(
                      segmentKey: ValueKey<String>(
                        'feed-progress-segment-$index',
                      ),
                      color: widget.rated[index]
                          ? scheme.primary
                          : index == widget.currentIndex
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      opacity: widget.rated[index]
                          ? 1
                          : index == widget.currentIndex
                          ? pulse
                          : 1,
                      pulse:
                          widget.animatePulse &&
                          !widget.rated[index] &&
                          index == widget.currentIndex,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segmentKey,
    required this.color,
    required this.opacity,
    required this.pulse,
  });

  final Key segmentKey;
  final Color color;
  final double opacity;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final Widget bar = Container(
      key: segmentKey,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    if (!pulse) return bar;
    return Opacity(
      key: const ValueKey<String>('feed-progress-pulse'),
      opacity: opacity,
      child: bar,
    );
  }
}
