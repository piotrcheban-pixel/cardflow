import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'nc_glass.dart';
import 'nc_icon_button.dart';

/// Нижний лист Nocturne (REDESIGN-SPEC §8): `glass.thick`, `r.xl` сверху,
/// ручка 36 × 4, заголовок `titleL`, максимум 88 % высоты. На ПК (≥ 1024)
/// превращается в центрированный диалог 560 px.
class NcSheet extends StatelessWidget {
  /// Создаёт содержимое листа.
  const NcSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.closeTooltip,
    this.onClose,
    this.showHandle = true,
    this.borderRadius,
    this.semanticLabel,
  });

  /// Заголовок листа (ARB).
  final String title;

  /// Содержимое.
  final Widget child;

  /// Нижняя панель действий (например, кнопки).
  final Widget? actions;

  /// Подпись кнопки закрытия (ARB).
  final String? closeTooltip;

  /// Закрыть лист; по умолчанию `Navigator.maybePop`.
  final VoidCallback? onClose;

  /// Рисовать ручку-грабер.
  final bool showHandle;

  /// Геометрия скругления (на телефоне — только верхние углы).
  final BorderRadiusGeometry? borderRadius;

  /// Текст семантики листа.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final BorderRadiusGeometry radius =
        borderRadius ?? BorderRadius.circular(NcRadii.xl);
    final Widget content = NcGlass(
      tier: NcGlassTier.thick,
      borderRadiusGeometry: radius,
      showNoise: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showHandle)
            Padding(
              padding: const EdgeInsets.only(top: NcSpace.s8),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: ShapeDecoration(
                    color: theme.colors.hairlineStrong,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(NcRadii.pill),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NcSpace.s20,
              NcSpace.s8,
              NcSpace.s8,
              NcSpace.s4,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.titleL.copyWith(
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
                if (closeTooltip != null)
                  NcIconButton(
                    icon: Icons.close_rounded,
                    tooltip: closeTooltip!,
                    onPressed: onClose ?? () => Navigator.maybePop(context),
                  ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                NcSpace.s20,
                NcSpace.s8,
                NcSpace.s20,
                NcSpace.s20,
              ),
              child: child,
            ),
          ),
          if (actions != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NcSpace.s20,
                0,
                NcSpace.s20,
                NcSpace.s20,
              ),
              child: actions,
            ),
        ],
      ),
    );
    if (semanticLabel == null) return content;
    return Semantics(label: semanticLabel, container: true, child: content);
  }
}

/// Показывает нижний лист (`NcSheet`); на ПК — центрированный диалог 560 px.
///
/// Обёртка над `showModalBottomSheet<T>`/`showDialog<T>`: тип результата
/// сохраняется, вызовы в экранах остаются прежними.
Future<T?> showNcSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  List<Widget>? actions,
  String? closeTooltip,
  bool barrierDismissible = true,
  double maxHeightFactor = 0.88,
  bool isDesktopDialog = true,
}) {
  final NcTheme theme = NcTheme.of(context);
  final Size size = MediaQuery.sizeOf(context);
  final bool desktop = isDesktopDialog && size.width >= 1024;
  final Widget sheet = NcSheet(
    title: title,
    closeTooltip: closeTooltip,
    showHandle: !desktop,
    borderRadius: desktop
        ? BorderRadius.circular(NcRadii.xl)
        : BorderRadius.vertical(top: Radius.circular(NcRadii.xl)),
    actions: actions == null
        ? null
        : Wrap(
            alignment: WrapAlignment.end,
            spacing: NcSpace.s8,
            runSpacing: NcSpace.s8,
            children: actions,
          ),
    child: Builder(builder: builder),
  );
  if (desktop) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: theme.colors.scrim,
      builder: (BuildContext dialogContext) => Dialog(
        backgroundColor: NcColors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(NcSpace.s24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: size.height * maxHeightFactor,
            minHeight: 200,
          ),
          child: sheet,
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NcColors.transparent,
    barrierColor: theme.colors.scrim,
    isDismissible: barrierDismissible,
    builder: (BuildContext sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: size.height * maxHeightFactor),
      child: sheet,
    ),
  );
}
