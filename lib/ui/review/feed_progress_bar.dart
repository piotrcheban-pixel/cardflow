import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Stories-прогресс ленты (SPEC A7.3): сегмент на карточку, текущий пульсирует.
///
/// Аудит v4 (V25): на длинной колоде (69 карточек) сегменты превращались в
/// шум из микро-полосок — теперь сегменты рисуются до 24 карточек, дальше
/// показывается одна полоса и «N из M». Пульс учитывает reduced motion и
/// длится 1,4 с вместо 0,9 с.
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

  /// Сколько сегментов рисовать, прежде чем перейти на общую полосу.
  static const int segmentLimit = 24;

  @override
  State<FeedProgressBar> createState() => _FeedProgressBarState();
}

class _FeedProgressBarState extends State<FeedProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _pulsing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(FeedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animatePulse != widget.animatePulse) _syncPulse();
  }

  /// Пульс включается только при выразительной анимации и без reduced motion.
  void _syncPulse() {
    final bool shouldPulse =
        widget.animatePulse &&
        widget.rated.length <= FeedProgressBar.segmentLimit &&
        !AppMotion.reduce(context);
    if (shouldPulse == _pulsing) return;
    _pulsing = shouldPulse;
    if (shouldPulse) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
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
    final int total = widget.rated.length;
    final String semantics = l10n.feedProgressSemantics(ratedCount, total);
    if (total > FeedProgressBar.segmentLimit) {
      final ThemeData theme = Theme.of(context);
      return Semantics(
        container: true,
        label: semantics,
        child: Row(
          children: <Widget>[
            Expanded(
              child: AppProgressBar(
                value: total == 0 ? 0 : ratedCount / total,
                semanticsLabel: semantics,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              l10n.reviewCardCounter(
                (widget.currentIndex + 1).clamp(1, total),
                total,
              ),
              style: AppTypography.numeric(
                context,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      container: true,
      label: semantics,
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
                          _pulsing &&
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
