/// Общие элементы экранов новых режимов: прогресс и итоги (7.15/7.16).
library;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Прогресс сессии нового режима: подпись и полоса дизайн-системы.
class StudyProgressBar extends StatelessWidget {
  /// Создаёт прогресс.
  const StudyProgressBar({
    required this.answered,
    required this.total,
    super.key,
  });

  /// Сколько пройдено.
  final int answered;

  /// Сколько всего.
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Находка D20: счётчик «Вопрос 0 из 4» → «Вопрос 1 из 4». На итогах этот
    // виджет уже не рисуется, поэтому последняя карточка показывает total.
    final int current = total == 0 ? 0 : (answered + 1).clamp(1, total);
    return SessionProgressStrip(
      label: l10n.testProgressSemantics(current, total),
      value: total == 0 ? 0 : answered / total,
    );
  }
}

/// Итог сессии: точность, ошибки и повтор ошибок.
class StudyResultsView extends StatelessWidget {
  /// Создаёт итоговый экран.
  const StudyResultsView({
    required this.accuracy,
    required this.correct,
    required this.total,
    required this.mistakes,
    required this.onRepeatMistakes,
    required this.onDone,
    this.title = '',
    this.showMistakes = true,
    super.key,
  });

  /// Точность, %.
  final int accuracy;

  /// Верных ответов.
  final int correct;

  /// Всего ответов.
  final int total;

  /// Ошибочные карточки (для списка и повтора).
  final List<Card> mistakes;

  /// Повторить только ошибки.
  final VoidCallback? onRepeatMistakes;

  /// Закрыть.
  final VoidCallback onDone;

  /// Заголовок; пустой — стандартный из ARB.
  final String title;

  /// Показывать список ошибок.
  final bool showMistakes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.studyCardMaxWidth,
          ),
          child: AppPanel(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: AppIconBadge(
                    icon: Icons.emoji_events_outlined,
                    color: scheme.primary,
                    size: 56,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  title.isEmpty ? l10n.testResultsTitle : title,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.testAccuracy(accuracy),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.studyResultsScore(correct, total),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (errorsCount > 0) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.testErrorsCount(mistakes.length),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.tertiary,
                    ),
                  ),
                ],
                if (showMistakes && mistakes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Divider(color: scheme.outlineVariant),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.studyWrongListTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs + 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final Card card in mistakes)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: CardText(
                              key: ValueKey<String>('study-mistake-${card.id}'),
                              source: card.front,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: CardText(
                              source: card.back,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (onRepeatMistakes != null) ...<Widget>[
                  FilledButton(
                    key: const ValueKey<String>('study-repeat-mistakes'),
                    onPressed: onRepeatMistakes,
                    child: Text(l10n.testRepeatMistakes),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                OutlinedButton(
                  key: const ValueKey<String>('study-results-done'),
                  onPressed: onDone,
                  child: Text(l10n.reviewDone),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Число ошибок = всего − верно.
  int get errorsCount => total - correct;
}
