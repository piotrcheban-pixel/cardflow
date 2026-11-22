import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Баннер «основной провайдер не настроен» (находка F7 аудита).
///
/// Показывается на экране «Колоды» и в настройках, когда выбранный основным
/// аккаунт невалиден (пустые адрес/модель): генерация в такой конфигурации
/// недоступна, и пользователь должен увидеть причину там, где он работает, а
/// не только на экране генерации. Кнопка ведёт прямо к исправлению.
class PrimaryProviderBanner extends StatelessWidget {
  /// Создаёт баннер.
  const PrimaryProviderBanner({this.showAction = true, super.key});

  /// Показывать ли кнопку «Исправить».
  final bool showAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      key: const ValueKey<String>('primary-provider-banner'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm + 4,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.key_off_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              l10n.settingsProvidersPrimaryBroken,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          if (showAction)
            TextButton(
              key: const ValueKey<String>('primary-provider-fix'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.onErrorContainer,
                ),
              ),
              onPressed: () => context.push(AppRoutes.generationSettingsPath),
              child: Text(l10n.settingsProvidersFixAction),
            ),
        ],
      ),
    );
  }
}
