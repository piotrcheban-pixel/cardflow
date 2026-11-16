import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_radii.dart';

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
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final (Color background, Color foreground) = switch (tone) {
      NcBadgeTone.accent => (theme.colors.aurumSoft, theme.colors.aurum),
      NcBadgeTone.jade => (theme.colors.jadeSoft, theme.colors.jade),
      NcBadgeTone.ember => (theme.colors.emberSoft, theme.colors.ember),
      NcBadgeTone.amber => (theme.colors.amberSoft, theme.colors.amber),
      NcBadgeTone.iris => (theme.colors.irisSoft, theme.colors.iris),
      NcBadgeTone.glacier => (theme.colors.glacierSoft, theme.colors.glacier),
      NcBadgeTone.neutral => (theme.colors.ink4, theme.colors.textSecondary),
    };
    final Widget text = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: theme.typography.labelM.copyWith(
        color: foreground,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: ShapeDecoration(
        color: background,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(NcRadii.xs),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          text,
        ],
      ),
    );
    if (semanticLabel == null) return content;
    return Semantics(
      label: semanticLabel,
      container: true,
      excludeSemantics: true,
      child: content,
    );
  }
}
