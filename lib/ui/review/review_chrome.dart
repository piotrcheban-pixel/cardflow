import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';

/// Общий каркас сессии (SPEC A6.4) для классики и ленты.
///
/// Здесь только служебные элементы, не зависящие от режима: AppBar с undo,
/// «Почему?» и выходом, диалог выхода, bottom sheet цитаты исходника и
/// состояния «пусто/завершено/ошибка загрузки». Тексты — только ARB.

/// Верхняя панель сессии: undo, «Почему?», выход (SPEC A6.4).
class ReviewSessionAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Создаёт панель.
  const ReviewSessionAppBar({
    required this.undoEnabled,
    required this.onUndo,
    required this.whyExcerpt,
    required this.onClose,
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

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? excerpt = whyExcerpt;
    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(l10n.reviewTitle),
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
          onPressed: excerpt == null
              ? null
              : () => showReviewSourceExcerpt(context, excerpt),
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
class ReviewEmptyView extends StatelessWidget {
  /// Создаёт пустое состояние.
  const ReviewEmptyView({required this.onBack, super.key});

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
              Icons.done_all,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.reviewEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.reviewEmptyMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
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
