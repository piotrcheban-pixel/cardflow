import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'nc_surface.dart';

/// Группа строк в стиле inset grouped (REDESIGN-SPEC §8): заголовок
/// `overline`, поверхность `ink2` `r.l`, `depth1`, разделители между строками
/// с отступом от `leading`.
class NcSection extends StatelessWidget {
  /// Создаёт секцию.
  const NcSection({
    super.key,
    this.title,
    required this.children,
    this.footer,
    this.padding = EdgeInsets.zero,
    this.dividerIndent = 16,
    this.semanticLabel,
  });

  /// Заголовок секции (`overline`, текст заглавными в ARB).
  final String? title;

  /// Строки секции.
  final List<Widget> children;

  /// Пояснение под секцией.
  final Widget? footer;

  /// Внутренние отступы строк.
  final EdgeInsetsGeometry padding;

  /// Отступ разделителя слева (запасной, если строка не `NcListRow`).
  final double dividerIndent;

  /// Текст семантики секции.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Widget body = NcSurface(
      radius: NcRadii.l,
      level: 1,
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < children.length; index++) children[index],
        ],
      ),
    );
    final Widget section = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: NcSpace.s4,
              bottom: NcSpace.s8,
            ),
            child: Text(
              title!,
              style: theme.typography.overline.copyWith(
                color: theme.colors.textTertiary,
              ),
            ),
          ),
        body,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(left: NcSpace.s4, top: NcSpace.s8),
            child: DefaultTextStyle.merge(
              style: theme.typography.bodyS.copyWith(
                color: theme.colors.textTertiary,
              ),
              child: footer!,
            ),
          ),
      ],
    );
    if (semanticLabel == null) return section;
    return Semantics(label: semanticLabel, container: true, child: section);
  }
}
