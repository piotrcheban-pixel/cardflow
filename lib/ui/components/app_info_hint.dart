import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Компактная кнопка «?» рядом с заголовком раздела (TASK 04, M-07).
///
/// Владелец: второстепенные объяснения не должны постоянно занимать место —
/// только по запросу. На телефоне `Tooltip` по long-press неизвестен, поэтому
/// нажатие открывает короткий лист с заголовком и текстом; на наведении
/// (десктоп) остаётся обычная подсказка.
class AppInfoButton extends StatelessWidget {
  /// Создаёт кнопку подсказки.
  const AppInfoButton({
    required this.title,
    required this.message,
    this.tooltip,
    this.keyValue,
    super.key,
  });

  /// Заголовок листа подсказки.
  final String title;

  /// Текст объяснения.
  final String message;

  /// Подсказка при наведении; `null` — заголовок.
  final String? tooltip;

  /// Строковый ключ для тестов/автоматизации.
  final String? keyValue;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: keyValue == null ? null : ValueKey<String>('app-info-$keyValue'),
      tooltip: tooltip ?? title,
      visualDensity: VisualDensity.compact,
      iconSize: AppSizes.iconSmall,
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTouchTarget,
        minHeight: AppSizes.minTouchTarget,
      ),
      padding: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: () =>
          showAppInfoSheet(context, title: title, message: message),
      icon: const Icon(Icons.help_outline),
    );
  }
}

/// Открывает короткий лист-объяснение.
Future<void> showAppInfoSheet(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSheetHeader(title: title, icon: Icons.help_outline),
          Text(message, style: Theme.of(sheetContext).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonal(
              key: const ValueKey<String>('app-info-close'),
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(l10n.appInfoClose),
            ),
          ),
        ],
      ),
    ),
  );
}
