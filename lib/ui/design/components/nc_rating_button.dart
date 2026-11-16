import 'package:material_ui/material_ui.dart';

/// Кнопка оценки в доке (REDESIGN-SPEC §8, §9.6): высота 64, `r.m`, фон
/// `…Soft`-цвета оценки, рамка 1 px того же цвета 30 %; интервал сверху
/// (`monoM`), название (`labelL`), подсказка клавиши на ПК.
class NcRatingButton extends StatelessWidget {
  /// Создаёт кнопку оценки.
  const NcRatingButton({
    super.key,
    required this.label,
    required this.interval,
    required this.color,
    this.onPressed,
    this.keyHint,
    this.enabled = true,
    this.minHeight = 64,
    this.flex = 100,
  });

  /// Название оценки (ARB: «Не знаю»…).
  final String label;

  /// Подпись интервала (например, «3 д»); над названием.
  final String interval;

  /// Цвет оценки (`ember`/`amber`/`jade`/`glacier`).
  final Color color;

  /// Оценка; `null` — неактивна.
  final VoidCallback? onPressed;

  /// Подсказка клавиши (1…4) на ПК.
  final String? keyHint;

  /// Включена ли кнопка.
  final bool enabled;

  /// Минимальная высота (64; растёт при textScale 2,0).
  final double minHeight;

  /// Доля ширины в доке (neighbor-squish).
  final int flex;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
