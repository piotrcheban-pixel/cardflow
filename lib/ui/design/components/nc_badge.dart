import 'package:material_ui/material_ui.dart';

/// Семантический тон бейджа (REDESIGN-SPEC §8: soft-цвета).
enum NcBadgeTone {
  /// Aurum: «к повторению», счётчик.
  accent,

  /// Jade: успех, «Работает».
  jade,

  /// Ember: ошибка, слабая тема.
  ember,

  /// Amber: предупреждение, пометка качества.
  amber,

  /// Iris: нейросеть, Vision.
  iris,

  /// Glacier: новые карточки.
  glacier,

  /// `ink4`: нейтральная подпись.
  neutral,
}

/// Pill-бейдж 20–24 px: счётчик или семантический статус (§8).
///
/// Цифры — табличные (`tabularFigures`), чтобы счётчик не дёргался.
class NcBadge extends StatelessWidget {
  /// Создаёт бейдж с готовым текстом.
  const NcBadge({
    super.key,
    required this.label,
    this.tone = NcBadgeTone.accent,
    this.icon,
    this.semanticLabel,
  });

  /// Бейдж-счётчик: [label] = число, цифры табличные.
  factory NcBadge.count({
    Key? key,
    required int count,
    NcBadgeTone tone = NcBadgeTone.accent,
    String? semanticLabel,
  }) => NcBadge(
    key: key,
    label: '$count',
    tone: tone,
    semanticLabel: semanticLabel,
  );

  /// Текст бейджа.
  final String label;

  /// Тон фона и текста.
  final NcBadgeTone tone;

  /// Иконка перед текстом (галочка, точка статуса).
  final IconData? icon;

  /// Текст семантики (если [label] — только число).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
