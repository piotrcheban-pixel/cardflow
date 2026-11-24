import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Компактный прогресс ленты (ADR-044).
///
/// Одна полоса-сегмент на карточку (до 24; на длинной колоде карточки
/// группируются), текущий сегмент залит акцентом. Режим свободного просмотра
/// не «оценивает» карточки, поэтому прогресс показывает только позицию —
/// никакого процента изученного и никакой пульсации: движение здесь ничего
/// не сообщает пользователю, а постоянная анимация нагружала бы растр.
///
/// Сегменты кликабельны ([onSeek]): на десктопе это быстрый способ прыгнуть
/// к карточке, не листая ленту колесом.
class FeedProgressBar extends StatelessWidget {
  /// Создаёт прогресс ленты.
  const FeedProgressBar({
    required this.total,
    required this.currentIndex,
    this.onSeek,
    super.key,
  });

  /// Всего карточек.
  final int total;

  /// Индекс текущей карточки.
  final int currentIndex;

  /// Переход к карточке по клику на сегмент; `null` — сегменты статичны.
  final ValueChanged<int>? onSeek;

  /// Сколько сегментов рисовать, прежде чем группировать карточки.
  static const int segmentLimit = 24;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int position = total == 0 ? 0 : (currentIndex + 1).clamp(1, total);
    final String semantics = l10n.feedProgressSemantics(position, total);
    final int segments = total == 0
        ? 0
        : math.min(total, FeedProgressBar.segmentLimit);
    final int groupSize = segments == 0 ? 1 : (total / segments).ceil();
    final int currentSegment = groupSize == 0
        ? 0
        : (currentIndex ~/ groupSize).clamp(0, math.max(0, segments - 1));
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                for (int index = 0; index < segments; index++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: _Segment(
                        segmentKey: ValueKey<String>(
                          'feed-progress-segment-$index',
                        ),
                        color: index <= currentSegment
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        highlighted: index == currentSegment,
                        onTap: onSeek == null || total == 0
                            ? null
                            : () => onSeek!(
                                math.min(
                                  total - 1,
                                  index * groupSize + groupSize ~/ 2,
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.reviewCardCounter(position, total),
            key: const ValueKey<String>('feed-progress-counter'),
            style: AppTypography.numeric(
              context,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segmentKey,
    required this.color,
    required this.highlighted,
    this.onTap,
  });

  final Key segmentKey;
  final Color color;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Аудит 2.0 (P2-26): сегмент высотой 4 px нельзя ни нажать мышью, ни
    // попасть пальцем. Визуальная полоса остаётся тонкой, но каждая ячейка
    // имеет полноценную цель 44 px (WCAG 2.5.5) на всю высоту строки.
    final Widget bar = AnimatedContainer(
      key: segmentKey,
      duration: AppMotion.duration(context, AppDurations.quick),
      curve: AppMotion.feedback,
      // Текущий сегмент выше остальных: позиция читается без анимации.
      height: highlighted ? 10 : 7,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    if (onTap == null) {
      return SizedBox(
        height: AppSizes.minTouchTarget,
        child: Center(child: bar),
      );
    }
    return SizedBox(
      height: AppSizes.minTouchTarget,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(child: bar),
      ),
    );
  }
}
