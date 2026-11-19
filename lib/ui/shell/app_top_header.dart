import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Верхняя панель приложения (ADR-038): 56 px, «хлебные крошки» текущего
/// раздела, глобальные действия. На узком экране добавляется кнопка меню,
/// открывающая выдвижную навигацию.
class AppTopHeader extends StatelessWidget {
  /// Создаёт панель.
  const AppTopHeader({
    required this.section,
    required this.onNewCard,
    required this.onOpenSettings,
    this.onOpenNav,
    super.key,
  });

  /// Название текущего раздела для крошек.
  final String section;

  /// Создать карточку (глобальное действие).
  final VoidCallback onNewCard;

  /// Открыть настройки.
  final VoidCallback onOpenSettings;

  /// Открыть навигацию на узком экране; `null` — панель постоянная.
  final VoidCallback? onOpenNav;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool compact = MediaQuery.sizeOf(context).width < 520;
    return Container(
      height: AppSizes.headerHeight,
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
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + 2,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        l10n.shellBreadcrumb(section),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (compact)
            IconButton(
              tooltip: l10n.shellNewCard,
              icon: const Icon(Icons.add, size: AppSizes.navIcon),
              onPressed: onNewCard,
            )
          else
            OutlinedButton.icon(
              key: const ValueKey<String>('shell-new-card'),
              onPressed: onNewCard,
              icon: const Icon(Icons.add, size: AppSizes.icon),
              label: Text(l10n.shellNewCard),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                textStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
                foregroundColor: scheme.onSurface,
                backgroundColor: scheme.surface,
              ),
            ),
          const SizedBox(width: AppSpacing.xxs),
          IconButton(
            key: const ValueKey<String>('shell-settings'),
            tooltip: l10n.shellOpenSettingsTooltip,
            icon: const Icon(Icons.settings_outlined, size: AppSizes.navIcon),
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}
