import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/components/app_info_hint.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Заголовок секции формы: название, необязательная подсказка и действие.
///
/// Заменяет самодельные `Row(Expanded(Text), OutlinedButton)` в редакторе
/// карточки (TASK 04, M-02/M-07): подпись никогда не сжимается в колонку —
/// действие вынесено в компактную иконку, а объяснение — в кнопку «?».
class AppSectionHeader extends StatelessWidget {
  /// Создаёт заголовок секции.
  const AppSectionHeader({
    required this.title,
    this.subtitle,
    this.infoTitle,
    this.infoMessage,
    this.infoKey,
    this.action,
    this.titleKey,
    super.key,
  });

  /// Название секции.
  final String title;

  /// Дополнительная строка под названием (короткая).
  final String? subtitle;

  /// Заголовок подсказки; `null` — подсказки нет.
  final String? infoTitle;

  /// Текст подсказки.
  final String? infoMessage;

  /// Стабильный ключ кнопки «?» (для тестов); `null` — по названию секции.
  final String? infoKey;

  /// Действие справа: обычно компактная `IconButton` (44×44).
  final Widget? action;

  /// Ключ самого текста названия (для измерений в тестах).
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? info = infoMessage;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, key: titleKey, style: theme.textTheme.titleMedium),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (info != null) ...<Widget>[
          const SizedBox(width: AppSpacing.xxs),
          AppInfoButton(
            title: infoTitle ?? title,
            message: info,
            keyValue: infoKey ?? title,
          ),
        ],
        if (action != null) ...<Widget>[
          const SizedBox(width: AppSpacing.xxs),
          action!,
        ],
      ],
    );
  }
}
