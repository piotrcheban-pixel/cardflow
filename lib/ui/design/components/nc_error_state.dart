import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_spacing.dart';
import 'nc_button.dart';
import 'nc_icon3d.dart';

/// Ошибка загрузки (REDESIGN-SPEC §8): `shield_error` + текст ARB +
/// «Повторить» (`secondary`).
class NcErrorState extends StatelessWidget {
  /// Создаёт состояние ошибки.
  const NcErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title,
    this.retryLabel,
    this.iconName = 'shield_error',
    this.compact = false,
  });

  /// Текст ошибки (ARB).
  final String message;

  /// Повторить.
  final VoidCallback onRetry;

  /// Заголовок (ARB), необязателен.
  final String? title;

  /// Подпись кнопки (ARB «Повторить»).
  final String? retryLabel;

  /// Имя 3D-иконки.
  final String iconName;

  /// Компактный вариант.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        NcIcon3D(name: iconName, size: compact ? 72 : 120),
        SizedBox(height: compact ? NcSpace.s12 : NcSpace.s20),
        if (title != null) ...<Widget>[
          Text(
            title!,
            textAlign: TextAlign.center,
            style: theme.typography.titleL.copyWith(
              color: theme.colors.textPrimary,
            ),
          ),
          const SizedBox(height: NcSpace.s8),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.typography.bodyM.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
        const SizedBox(height: NcSpace.s20),
        if (retryLabel != null)
          NcButton(
            label: retryLabel!,
            variant: NcButtonVariant.secondary,
            onPressed: onRetry,
          ),
      ],
    );
  }
}
