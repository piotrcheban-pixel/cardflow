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
///
/// Аудит 2.0 (P2-01): это **настройка**, а не сбой приложения. Тон — спокойный
/// предупреждающий (tertiary), а не `errorContainer`: красная полоса на первом
/// запуске читалась как «приложение сломано».
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
    final Color background = scheme.tertiaryContainer;
    final Color foreground = scheme.onTertiaryContainer;
    // Итерация «Фикс мобильного Empty State»: та же ловушка, что и в блоке ИИ
    // пустого состояния, — `Row` отдаёт `TextButton` неделимую ширину, а
    // `Expanded` получает остаток. На 390 px тексту оставалось 146 px, при
    // кегле 150 % — 78,6 px. На мобильной ширине действие уходит под текст.
    final bool stacked =
        MediaQuery.sizeOf(context).width < AppSizes.mobileBreakpoint;

    final Widget message = Row(
      children: <Widget>[
        Icon(Icons.info_outline, color: foreground),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            l10n.settingsProvidersPrimaryBroken,
            style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
          ),
        ),
      ],
    );
    final Widget action = TextButton(
      key: const ValueKey<String>('primary-provider-fix'),
      style: TextButton.styleFrom(foregroundColor: foreground),
      onPressed: () => context.push(AppRoutes.generationSettingsPath),
      child: Text(l10n.settingsProvidersFixAction),
    );

    return Container(
      key: const ValueKey<String>('primary-provider-banner'),
      padding: stacked
          ? const EdgeInsets.all(AppSpacing.sm)
          : const EdgeInsets.fromLTRB(
              AppSpacing.sm + 4,
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[message, if (showAction) action],
            )
          : Row(
              children: <Widget>[
                Expanded(child: message),
                if (showAction) action,
              ],
            ),
    );
  }
}
