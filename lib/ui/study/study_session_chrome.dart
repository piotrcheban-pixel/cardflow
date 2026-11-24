/// Общие элементы экранов новых режимов: прогресс и итоги (7.15/7.16).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Рабочая область режима проверки (аудит v7, G8/G11).
///
/// Находки аудита: «Ввод ответа» занимал 11 % высоты экрана с 1155 px пустоты
/// снизу, «Верно/Неверно» — 19,9 %. Причина — колонка без центрирования в
/// `SingleChildScrollView`. Теперь контент центрируется по доступной высоте
/// (короткое содержимое — по центру, длинное — прокручивается), а ширина
/// колонки берётся из той же формулы, что и карточка сессии (G3).
class StudyWorkspace extends StatelessWidget {
  /// Создаёт рабочую область.
  const StudyWorkspace({required this.child, super.key});

  /// Содержимое (обычно `Column`).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double windowWidth = MediaQuery.sizeOf(context).width;
    // Как карточка сессии, но не уже 720 лог. px: формы и варианты ответа.
    final double maxWidth = math.max(720, AppSizes.studyCardWidth(windowWidth));
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minHeight = math.max(
          0,
          constraints.maxHeight - AppSpacing.xl,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                minHeight: minHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[child],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Вопрос режима проверки в единой трактовке (аудит v7, G11).
///
/// В «Классике»/«Тренировке»/«Ленте» вопрос — белая карточка, а в «Тесте»,
/// «Вводе ответа» и «Верно/Неверно» он был строкой на фоне: один и тот же
/// контент выглядел как два разных продукта. Теперь вопрос всех режимов —
/// та же поверхность ([AppPanel]), тот же надзаголовок и те же отступы.
class StudyQuestionCard extends StatelessWidget {
  /// Создаёт карточку вопроса.
  const StudyQuestionCard({required this.child, super.key});

  /// Содержимое вопроса (обычно `CardContentView`).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double factor = AppAdaptive.factorForContext(context);
    final double pad = (AppSpacing.xl * factor).clamp(
      AppSpacing.xl,
      AppSpacing.xxl,
    );
    return AppPanel(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.reviewQuestionLabel.toUpperCase(),
            style: AppTypography.overline(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(child: child),
        ],
      ),
    );
  }
}

/// Прогресс сессии нового режима: подпись и полоса дизайн-системы.
class StudyProgressBar extends StatelessWidget {
  /// Создаёт прогресс.
  const StudyProgressBar({
    required this.answered,
    required this.total,
    this.currentIndex,
    super.key,
  });

  /// Сколько пройдено.
  final int answered;

  /// Сколько всего.
  final int total;

  /// Явный номер показанного вопроса (1-based).
  ///
  /// Аудит 2.0 (P2-02): после ответа на экране остаётся тот же вопрос с
  /// фидбеком, а прогресс уже уходил на следующий. Экран передаёт номер
  /// отвеченного вопроса, пока он виден.
  final int? currentIndex;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Находка D20: счётчик «Вопрос 0 из 4» → «Вопрос 1 из 4». На итогах этот
    // виджет уже не рисуется, поэтому последняя карточка показывает total.
    final int current = total == 0
        ? 0
        : (currentIndex ?? (answered + 1)).clamp(1, total);
    // F21: прогресс выровнен по контентной колонке карточки (72 % окна), а не
    // растянут на всё окно.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(
            AppSizes.studyCardWidth(MediaQuery.sizeOf(context).width),
            MediaQuery.sizeOf(context).width - AppSpacing.xxl,
          ),
        ),
        child: SessionProgressStrip(
          label: l10n.testProgressSemantics(current, total),
          value: total == 0 ? 0 : (current - 1) / total,
        ),
      ),
    );
  }
}

/// Футер действия режима проверки: одна кнопка в контентной колонке.
///
/// F21: «Проверить»/«Дальше» больше не растягиваются на всю ширину окна —
/// действие стоит по центру под колонкой вопроса и по ширине как главное
/// действие карточки сессии.
class StudyFooterAction extends StatelessWidget {
  /// Создаёт футер.
  const StudyFooterAction({required this.child, super.key});

  /// Кнопка действия.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppSizes.studyCardWidth(
                MediaQuery.sizeOf(context).width,
              ),
            ),
            child: Align(
              alignment: AlignmentDirectional.center,
              child: SizedBox(
                width: AppSizes.revealButtonMaxWidth,
                child: child,
              ),
            ),
          ),
        ),
      ),
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
          // Ширина как у карточки сессии (G3/G8): итоги не растягиваются на 2K.
          constraints: BoxConstraints(
            maxWidth: AppSizes.studyCardWidth(MediaQuery.sizeOf(context).width),
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
