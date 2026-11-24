import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Верхняя панель приложения (ADR-038): 56 px, «хлебные крошки» текущего
/// раздела, глобальные действия. На узком экране добавляется кнопка меню,
/// открывающая выдвижную навигацию.
class AppTopHeader extends StatelessWidget {
  /// Создаёт панель.
  const AppTopHeader({
    required this.onNewCard,
    this.showNewCard = true,
    this.onOpenNav,
    super.key,
  });

  /// Создать карточку (глобальное действие).
  final VoidCallback onNewCard;

  /// Показывать ли действие «Новая карточка».
  ///
  /// Аудит v4 (V17): глобальное действие имеет смысл только в разделах с
  /// колодами; на «Статистике» и в «Настройках» оно не по контексту и убрано.
  final bool showNewCard;

  /// Открыть навигацию на узком экране; `null` — панель постоянная.
  final VoidCallback? onOpenNav;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool compact = MediaQuery.sizeOf(context).width < 520;
    return Container(
      height: AppSizes.headerHeightFor(context),
      padding: EdgeInsets.symmetric(
        horizontal: onOpenNav == null ? AppSpacing.lg : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant,
            width: AppSizes.borderWidth,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          if (onOpenNav != null) ...<Widget>[
            IconButton(
              tooltip: l10n.shellOpenNavTooltip,
              icon: const Icon(Icons.menu, size: AppSizes.navIcon),
              onPressed: onOpenNav,
            ),
            const SizedBox(width: 2),
          ],
          // Аудит 2.0 (P3-03): «Рабочее пространство / ...» нигде не
          // выбиралось, а название раздела дублировало H1 страницы. В шапке
          // остаются только глобальные действия; контекст раздела даёт
          // подсветка навигации и заголовок самой страницы.
          const Spacer(),
          if (showNewCard) ...<Widget>[
            if (compact)
              IconButton(
                key: const ValueKey<String>('shell-new-card'),
                tooltip: l10n.shellNewCard,
                icon: const Icon(Icons.add, size: AppSizes.navIcon),
                onPressed: onNewCard,
              )
            else
              OutlinedButton.icon(
                key: const ValueKey<String>('shell-new-card'),
                onPressed: onNewCard,
                icon: const Icon(Icons.add, size: AppSizes.iconSmall),
                label: Text(l10n.shellNewCard),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.buttonHeight),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                  ),
                  foregroundColor: scheme.onSurface,
                  backgroundColor: scheme.surface,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
