import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';

/// Общий каркас сессии (SPEC A6.4) для классики и ленты.
///
/// Здесь только служебные элементы, не зависящие от режима: AppBar с undo,
/// «Почему?» и выходом, диалог выхода, bottom sheet цитаты исходника и
/// состояния «пусто/завершено/ошибка загрузки». Тексты — только ARB.

/// Верхняя панель сессии: undo, «Почему?», выход (SPEC A6.4).
class ReviewSessionAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  /// Создаёт панель.
  const ReviewSessionAppBar({
    required this.undoEnabled,
    required this.onUndo,
    required this.whyExcerpt,
    required this.onClose,
    this.onWhyPressed,
    this.title,
    super.key,
  });

  /// Доступен ли откат последней оценки.
  final bool undoEnabled;

  /// Обработчик undo.
  final VoidCallback onUndo;

  /// Цитата исходника; `null` — кнопка «Почему?» неактивна.
  final String? whyExcerpt;

  /// Обработчик выхода (диалог открывает вызывающий экран).
  final VoidCallback onClose;

  /// Свой обработчик «Почему?» (лента на время sheet останавливает таймер);
  /// если не задан — открывается стандартный bottom sheet с [whyExcerpt].
  final VoidCallback? onWhyPressed;

  /// Заголовок панели; `null` — «Повторение» (классика/лента).
  ///
  /// Тренировка передаёт свой заголовок (`practiceTitle`, ADR-025).
  final String? title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? excerpt = whyExcerpt;
    final VoidCallback? onWhy = onWhyPressed;
    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(title ?? l10n.reviewTitle),
      actions: <Widget>[
        IconButton(
          key: const ValueKey<String>('review-undo'),
          tooltip: l10n.reviewUndoTooltip,
          icon: const Icon(Icons.undo),
          onPressed: undoEnabled ? onUndo : null,
        ),
        IconButton(
          key: const ValueKey<String>('review-why'),
          tooltip: l10n.reviewWhyTooltip,
          icon: const Icon(Icons.info_outline),
          onPressed:
              onWhy ??
              (excerpt == null
                  ? null
                  : () => showReviewSourceExcerpt(context, excerpt)),
        ),
        IconButton(
          key: const ValueKey<String>('review-close'),
          tooltip: l10n.reviewCloseTooltip,
          icon: const Icon(Icons.close),
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// Диалог выхода из сессии (SPEC A6.4): «Продолжить» / «Выйти».
Future<bool> confirmReviewExit(BuildContext context) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool result =
      (await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(l10n.reviewExitDialogTitle),
          content: Text(l10n.reviewExitDialogMessage),
          actions: <Widget>[
            TextButton(
              key: const ValueKey<String>('review-exit-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.reviewExitContinue),
            ),
            FilledButton(
              key: const ValueKey<String>('review-exit-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.reviewExitConfirm),
            ),
          ],
        ),
      )) ??
      false;
  return result;
}

/// Bottom sheet «Почему эта карточка?» с цитатой исходника (SPEC A6.4).
Future<void> showReviewSourceExcerpt(BuildContext context, String excerpt) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.reviewWhySheetTitle,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(child: Text(excerpt)),
          ],
        ),
      ),
    ),
  );
}

/// Пустое состояние сессии (нет карточек к повторению).
///
/// [title]/[message] переопределяют стандартный текст (дневной лимит,
/// тренировка — ADR-025). [onPractice] добавляет кнопку «Тренировать»: сессия
/// пуста из-за лимита, но карточки в колоде есть. [onContinue] добавляет
/// основную кнопку «Продолжить без лимита» (ADR-028, итерация 7.12).
class ReviewEmptyView extends StatelessWidget {
  /// Создаёт пустое состояние.
  const ReviewEmptyView({
    required this.onBack,
    this.title,
    this.message,
    this.onPractice,
    this.onContinue,
    super.key,
  });

  /// Возврат назад.
  final VoidCallback onBack;

  /// Заголовок; `null` — «Нет карточек к повторению».
  final String? title;

  /// Пояснение; `null` — стандартный текст ARB.
  final String? message;

  /// Переход в тренировку; `null` — кнопки нет.
  final VoidCallback? onPractice;

  /// Продолжение изучения без дневного лимита; `null` — кнопки нет.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final VoidCallback? practice = onPractice;
    final VoidCallback? proceed = onContinue;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.done_all,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title ?? l10n.reviewEmptyTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message ?? l10n.reviewEmptyMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (proceed != null) ...<Widget>[
              FilledButton(
                key: const ValueKey<String>('review-empty-continue'),
                onPressed: proceed,
                child: Text(l10n.reviewDailyLimitContinueAction),
              ),
              const SizedBox(height: 8),
              if (practice != null) ...<Widget>[
                OutlinedButton(
                  key: const ValueKey<String>('review-empty-practice'),
                  onPressed: practice,
                  child: Text(l10n.practiceStartAction),
                ),
                const SizedBox(height: 8),
              ],
              TextButton(onPressed: onBack, child: Text(l10n.reviewBack)),
            ] else if (practice != null) ...<Widget>[
              FilledButton(
                key: const ValueKey<String>('review-empty-practice'),
                onPressed: practice,
                child: Text(l10n.practiceStartAction),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onBack, child: Text(l10n.reviewBack)),
            ] else
              FilledButton(onPressed: onBack, child: Text(l10n.reviewBack)),
          ],
        ),
      ),
    );
  }
}

/// Итоговое состояние завершённой сессии.
class ReviewCompletedView extends StatelessWidget {
  /// Создаёт итоговый экран.
  const ReviewCompletedView({
    required this.ratedCount,
    required this.onDone,
    super.key,
  });

  /// Сколько карточек оценено.
  final int ratedCount;

  /// Закрыть сессию.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.celebration_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.reviewCompletedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.reviewCompletedMessage(ratedCount),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onDone, child: Text(l10n.reviewDone)),
          ],
        ),
      ),
    );
  }
}

/// Ошибка загрузки карточек сессии.
class ReviewLoadErrorView extends StatelessWidget {
  /// Создаёт экран ошибки.
  const ReviewLoadErrorView({required this.onRetry, super.key});

  /// Повторить загрузку.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(l10n.reviewLoadError, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}

/// Итог сессии, завершённой по лимиту минут (SPEC A6.7, ADR-018).
///
/// Карточки, которые не успели, остаются на следующий раз: `due`/`fsrs_json`
/// не тронуты.
class ReviewTimeUpView extends StatelessWidget {
  /// Создаёт итоговый экран по лимиту времени.
  const ReviewTimeUpView({
    required this.ratedCount,
    required this.onDone,
    super.key,
  });

  /// Сколько карточек оценено до истечения времени.
  final int ratedCount;

  /// Закрыть сессию.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.timer_off_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.reviewTimeUpTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.reviewTimeUpMessage(ratedCount),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onDone, child: Text(l10n.reviewDone)),
          ],
        ),
      ),
    );
  }
}

/// Состояние «план сессии не найден» (ADR-018).
///
/// Маршруты `/session/classic` и `/session/feed` получают план через
/// `GoRouter.extra`; при прямом переходе без него сессию собрать не из чего.
class ReviewPlanMissingView extends StatelessWidget {
  /// Создаёт состояние отсутствующего плана.
  const ReviewPlanMissingView({required this.onBack, super.key});

  /// Возврат назад.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.reviewPlanMissingTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.reviewPlanMissingMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onBack, child: Text(l10n.reviewBack)),
          ],
        ),
      ),
    );
  }
}
