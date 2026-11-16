/// Общие элементы экранов новых режимов: прогресс и итоги (7.15/7.16).
library;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Прогресс сессии нового режима.
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
    return LinearProgressIndicator(
      value: total == 0 ? 0 : answered / total,
      semanticsLabel: l10n.testProgressSemantics(answered, total),
      minHeight: 6,
      borderRadius: BorderRadius.circular(3),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.emoji_events_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              title.isEmpty ? l10n.testResultsTitle : title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(l10n.testAccuracy(accuracy), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              l10n.studyResultsScore(correct, total),
              textAlign: TextAlign.center,
            ),
            if (errorsCount > 0) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                l10n.testErrorsCount(mistakes.length),
                textAlign: TextAlign.center,
              ),
            ],
            if (showMistakes && mistakes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(l10n.studyWrongListTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final Card card in mistakes)
                      ListTile(
                        dense: true,
                        title: Text(
                          card.front,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          card.back,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (onRepeatMistakes != null) ...<Widget>[
              FilledButton(
                key: const ValueKey<String>('study-repeat-mistakes'),
                onPressed: onRepeatMistakes,
                child: Text(l10n.testRepeatMistakes),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              key: const ValueKey<String>('study-results-done'),
              onPressed: onDone,
              child: Text(l10n.reviewDone),
            ),
          ],
        ),
      ),
    );
  }

  /// Число ошибок = всего − верно.
  int get errorsCount => total - correct;
}
