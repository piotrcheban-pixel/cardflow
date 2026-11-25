import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';

/// Нижняя закреплённая панель действия (TASK 04, M-09).
///
/// Единая геометрия для редактора карточки и других длинных форм:
///
/// * учитывает системную область навигации (`SafeArea`);
/// * на телефоне действие занимает всю ширину, на широком экране — не шире
///   [maxContentWidth] по центру;
/// * высота не больше 72 px, чтобы не отнимать контент у клавиатуры;
/// * отделена тонкой линией от содержимого, а не «висит» над ним.
class AppActionBar extends StatelessWidget {
  /// Создаёт панель.
  const AppActionBar({
    required this.child,
    this.maxContentWidth = 480,
    this.topPadding = AppSpacing.xs,
    super.key,
  });

  /// Основное действие.
  final Widget child;

  /// Максимальная ширина действия на широком экране.
  final double maxContentWidth;

  /// Верхний отступ внутри полосы.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: AppSizes.borderWidth,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            topPadding,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
