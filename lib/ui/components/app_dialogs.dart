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
            final Widget body = bodyBuilder(dialogContext);
            // Аудит v4 (V42): у диалога без тела (подтверждение выхода,
            // удаление) больше нет 44 px пустоты между заголовком и кнопками.
            final bool hasBody = body is! SizedBox;
            // V8: заголовок и действия закреплены, прокручивается только тело.
            // Высокая форма (провайдер, смена характеристик) не уводит
            // «Сохранить»/«Удалить» за нижнюю кромку экрана.
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      hasBody ? 0 : AppSpacing.sm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(title, style: theme.textTheme.titleLarge),
                              if (subtitle != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.xxs),
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
                  ),
                  if (hasBody)
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.md,
                          AppSpacing.xl,
                          0,
                        ),
                        child: body,
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      hasBody ? AppSpacing.xl : AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: actions.isEmpty
                        ? const SizedBox.shrink()
                        : Wrap(
                            alignment: WrapAlignment.end,
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: actions,
                          ),
                  ),
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
///
/// TASK 04 (M-03): лист учитывает клавиатуру (`viewInsets`) и системные
/// области; содержимое прокручивается внутри листа, а не растягивает его за
/// пределы экрана.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) {
      final double keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return AnimatedPadding(
        padding: EdgeInsets.only(bottom: keyboard),
        duration: AppDurations.quick,
        curve: Curves.easeOut,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(child: builder(sheetContext)),
          ),
        ),
      );
    },
  );
}

/// Высокий нижний лист с управляемой высотой и закрытием свайпом вниз.
///
/// Для длинных списков (выбор режима, меню действий, пресеты): стартовая высота
/// [initialChildSize] (72 %), максимум [maxChildSize] (92 %), минимум
/// [minChildSize]. Внутренний `ListView` получает [ScrollController] от
/// `DraggableScrollableSheet`, поэтому жест «потянуть вниз» в любом месте
/// содержимого сначала уменьшает лист, а достигнув минимума — закрывает его
/// (`shouldCloseOnMinExtent`). Так лист больше не открывается «на весь экран»
/// и не требует искать крошечный drag handle.
Future<T?> showAppDetentSheet<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext sheetContext,
    ScrollController controller,
  )
  builder,
  double initialChildSize = 0.72,
  double minChildSize = 0.4,
  double maxChildSize = 0.92,
  double maxWidth = 760,
}) {
  final double initial = initialChildSize.clamp(0.2, 0.95);
  final double min = minChildSize.clamp(0.15, initial);
  final double max = maxChildSize.clamp(initial, 0.98);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // Лист рисует свою поверхность: прозрачный модальный контейнер не
    // перекрывает фон за пределами листа.
    backgroundColor: Colors.transparent,
    elevation: 0,
    useSafeArea: true,
    builder: (BuildContext sheetContext) {
      final ThemeData theme = Theme.of(sheetContext);
      final ColorScheme scheme = theme.colorScheme;
      final double keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return AnimatedPadding(
        padding: EdgeInsets.only(bottom: keyboard),
        duration: AppDurations.quick,
        curve: Curves.easeOut,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: initial,
              minChildSize: min,
              maxChildSize: max,
              snap: true,
              snapSizes: <double>[initial, max],
              builder: (BuildContext dragContext, ScrollController controller) {
                return Material(
                  key: const ValueKey<String>('app-detent-sheet'),
                  color: scheme.surfaceContainerLowest,
                  clipBehavior: Clip.antiAlias,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadii.panel),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        key: const ValueKey<String>('app-detent-sheet-handle'),
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Expanded(child: builder(dragContext, controller)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
