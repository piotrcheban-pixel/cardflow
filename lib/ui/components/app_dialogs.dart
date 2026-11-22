import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';

/// Диалог дизайн-системы CardFlow (ADR-038): ширина до 512 px, скругление 20,
/// шапка с заголовком/пояснением и кнопкой закрытия, прокручиваемое тело и
/// нижний ряд действий.
///
/// Правило ADR-036 соблюдается конструкцией: действия получают
/// `BuildContext` диалога и закрывают маршрут диалога через
/// `Navigator.of(dialogContext).pop(...)`, а не навигатор экрана-ветки.
class AppDialog extends StatelessWidget {
  /// Создаёт диалог.
  const AppDialog({
    required this.title,
    required this.bodyBuilder,
    required this.actionsBuilder,
    this.subtitle,
    this.closeLabel,
    this.onClose,
    this.maxWidth = AppSizes.dialogMaxWidth,
    super.key,
  });

  /// Заголовок.
  final String title;

  /// Пояснение под заголовком.
  final String? subtitle;

  /// Тело диалога (строится в контексте диалога).
  final WidgetBuilder bodyBuilder;

  /// Действия; получают контекст диалога для корректного `pop`.
  final List<Widget> Function(BuildContext dialogContext) actionsBuilder;

  /// Подпись кнопки закрытия (для tooltip/семантики); `null` — без крестика.
  final String? closeLabel;

  /// Обработчик закрытия; `null` — крестик закрывает диалог сам.
  final VoidCallback? onClose;

  /// Максимальная ширина.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.panel)),
      ),
      child: SizedBox(
        key: const ValueKey<String>('app-dialog-surface'),
        // Находка D23: диалог фиксированной ширины (по умолчанию 512), а не
        // на всю ширину окна: раньше `ConstrainedBox` не ограничивал, потому
        // что растянутый Column занимал максимум доступной ширины.
        width: maxWidth,
        child: Builder(
          builder: (BuildContext dialogContext) {
            final List<Widget> actions = actionsBuilder(dialogContext);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(title, style: theme.textTheme.titleLarge),
                            if (subtitle != null) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (closeLabel != null)
                        IconButton(
                          tooltip: closeLabel,
                          icon: const Icon(Icons.close, size: AppSizes.icon),
                          onPressed:
                              onClose ??
                              () => Navigator.of(dialogContext).pop(),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  bodyBuilder(dialogContext),
                  if (actions.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: actions,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Открывает [AppDialog] и возвращает результат закрытия.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder bodyBuilder,
  required List<Widget> Function(BuildContext dialogContext) actionsBuilder,
  String? subtitle,
  String? closeLabel,
  double maxWidth = AppSizes.dialogMaxWidth,
}) {
  return showDialog<T>(
    context: context,
    builder: (BuildContext dialogContext) => AppDialog(
      title: title,
      subtitle: subtitle,
      closeLabel: closeLabel,
      maxWidth: maxWidth,
      bodyBuilder: bodyBuilder,
      actionsBuilder: actionsBuilder,
    ),
  );
}

/// Заголовок нижнего листа: заголовок, пояснение и (опционально) иконка.
class AppSheetHeader extends StatelessWidget {
  /// Создаёт заголовок листа.
  const AppSheetHeader({
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    super.key,
  });

  /// Заголовок.
  final String title;

  /// Пояснение.
  final String? subtitle;

  /// Иконка слева.
  final IconData? icon;

  /// Элемент справа.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: AppSizes.navIcon,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleLarge),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Открывает нижний лист в стиле системы: максимальная ширина 560 px на
/// широком экране, прокрутка при нехватке высоты, drag handle.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(child: builder(sheetContext)),
        ),
      );
    },
  );
}
