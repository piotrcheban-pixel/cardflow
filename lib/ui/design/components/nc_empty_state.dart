import 'package:material_ui/material_ui.dart';

import 'internal/nc_stagger.dart';
import '../nc_theme.dart';
import '../tokens/nc_spacing.dart';
import 'nc_icon3d.dart';

/// Пустое состояние (REDESIGN-SPEC §8): 3D-иконка 120 → заголовок `titleL` →
/// текст `bodyM` `textSecondary` → 1–2 кнопки. Появление — каскад.
class NcEmptyState extends StatelessWidget {
  /// Создаёт пустое состояние.
  const NcEmptyState({
    super.key,
    required this.iconName,
    required this.title,
    required this.message,
    this.primaryAction,
    this.secondaryAction,
    this.compact = false,
    this.showIcon = true,
    this.semanticLabel,
  });

  /// Имя 3D-иконки из инвентаря §5.3.
  final String iconName;

  /// Показывать ли 3D-иконку (тихие состояния — без неё, §9.2).
  final bool showIcon;

  /// Заголовок (ARB).
  final String title;

  /// Пояснение (ARB).
  final String message;

  /// Главное действие (обычно `NcButton`).
  final Widget? primaryAction;

  /// Второе действие.
  final Widget? secondaryAction;

  /// Компактный вариант (внутри секции).
  final bool compact;

  /// Текст семантики.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (showIcon) ...<Widget>[
          NcStagger(
            index: 0,
            child: NcIcon3D(
              name: iconName,
              size: compact ? 80 : 120,
              showShadow: false,
            ),
          ),
          SizedBox(height: compact ? NcSpace.s16 : NcSpace.s24),
        ],
        NcStagger(
          index: 1,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.typography.titleL.copyWith(
              color: theme.colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: NcSpace.s8),
        NcStagger(
          index: 2,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.typography.bodyM.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
        ),
        if (primaryAction != null || secondaryAction != null) ...<Widget>[
          const SizedBox(height: NcSpace.s24),
          NcStagger(
            index: 3,
            child: Wrap(
              spacing: NcSpace.s12,
              runSpacing: NcSpace.s8,
              alignment: WrapAlignment.center,
              children: <Widget>[?primaryAction, ?secondaryAction],
            ),
          ),
        ],
      ],
    );
    if (semanticLabel == null) return content;
    return Semantics(label: semanticLabel, container: true, child: content);
  }
}
