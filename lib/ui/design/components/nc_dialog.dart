import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'nc_glass.dart';
import 'nc_icon3d.dart';

/// Диалог Nocturne (REDESIGN-SPEC §8): `glass.thick`, ширина 400–480,
/// `r.xl`, опционально 3D-иконка 64 сверху, заголовок `titleL`, текст `bodyM`
/// `textSecondary`, кнопки справа (ПК) / столбиком (ширина < 400).
class NcDialog extends StatelessWidget {
  /// Создаёт диалог.
  const NcDialog({
    super.key,
    this.title,
    this.message,
    this.icon3dName,
    this.content,
    this.actions = const <Widget>[],
    this.semanticLabel,
  });

  /// Заголовок (ARB).
  final String? title;

  /// Текст (ARB).
  final String? message;

  /// Имя 3D-иконки (например, `shield_error`, `hourglass_time`).
  final String? icon3dName;

  /// Произвольное содержимое между текстом и кнопками.
  final Widget? content;

  /// Кнопки диалога (ключи и действия задаёт экран).
  final List<Widget> actions;

  /// Текст семантики диалога.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool narrow = MediaQuery.sizeOf(context).width < 400;
    final Widget buttons = narrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < actions.length; index++) ...<Widget>[
                if (index > 0) const SizedBox(height: NcSpace.s8),
                actions[index],
              ],
            ],
          )
        : Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: NcSpace.s8,
              runSpacing: NcSpace.s8,
              children: actions,
            ),
          );
    final Widget dialog = NcGlass(
      tier: NcGlassTier.thick,
      radius: NcRadii.xl,
      showNoise: false,
      child: Padding(
        padding: const EdgeInsets.all(NcSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (icon3dName != null) ...<Widget>[
              Center(child: NcIcon3D(name: icon3dName!, size: 64)),
              const SizedBox(height: NcSpace.s16),
            ],
            if (title != null)
              Text(
                title!,
                textAlign: icon3dName != null
                    ? TextAlign.center
                    : TextAlign.start,
                style: theme.typography.titleL.copyWith(
                  color: theme.colors.textPrimary,
                ),
              ),
            if (message != null) ...<Widget>[
              const SizedBox(height: NcSpace.s8),
              Text(
                message!,
                textAlign: icon3dName != null
                    ? TextAlign.center
                    : TextAlign.start,
                style: theme.typography.bodyM.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            ],
            if (content != null) ...<Widget>[
              const SizedBox(height: NcSpace.s16),
              content!,
            ],
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: NcSpace.s24),
              buttons,
            ],
          ],
        ),
      ),
    );
    if (semanticLabel == null) return dialog;
    return Semantics(label: semanticLabel, container: true, child: dialog);
  }
}

/// Показывает диалог Nocturne и возвращает результат типа [T].
Future<T?> showNcDialog<T>(
  BuildContext context, {
  String? title,
  String? message,
  String? icon3dName,
  Widget? content,
  List<Widget> actions = const <Widget>[],
  String? semanticLabel,
  bool barrierDismissible = true,
  double maxWidth = 480,
}) {
  final NcTheme theme = NcTheme.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: theme.colors.scrim,
    builder: (BuildContext dialogContext) => Dialog(
      backgroundColor: NcColors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(NcSpace.s24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 320, maxWidth: maxWidth),
        child: SingleChildScrollView(
          child: NcDialog(
            title: title,
            message: message,
            icon3dName: icon3dName,
            content: content,
            actions: actions,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    ),
  );
}
