import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Общий каркас сессии (SPEC A6.4) для всех режимов обучения.
///
/// Здесь только служебные элементы, не зависящие от режима: верхняя панель
/// с undo, «Почему?» и выходом, диалог выхода, bottom sheet цитаты исходника и
/// состояния «пусто/завершено/ошибка загрузки». Тексты — только ARB.
///
/// Оформление — дизайн-система ADR-038: панель 56 px на `surfaceContainerLowest`
/// с нижней границей, рейтинги и карточка — на общих токенах.

/// Верхняя панель сессии: выход, название колоды, метод планировщика, undo и
/// «Почему?» (SPEC A6.4).
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
    this.progress,
    this.progressSemanticsLabel,
    this.showFsrsBadge = true,
    super.key,
  });

  /// Доступен ли откат последней оценки.
  final bool undoEnabled;

  /// Обработчик undo.
  final VoidCallback onUndo;

  /// Цитата исходника; `null` — кнопки «Почему?» нет (аудит v4: скрывать, а не
  /// показывать мёртвую иконку).
  final String? whyExcerpt;

  /// Обработчик выхода (диалог открывает вызывающий экран).
  final VoidCallback onClose;

  /// Свой обработчик «Почему?» (лента на время sheet останавливает таймер);
  /// если не задан — открывается стандартный bottom sheet с [whyExcerpt].
  final VoidCallback? onWhyPressed;

  /// Заголовок панели; `null` — «Повторение» (классика/лента).
  ///
  /// Тренировка и учебные режимы передают свой заголовок.
  final String? title;

  /// Прогресс 0..1 для строки под панелью; `null` — прогресса нет.
  final double? progress;

  /// Семантическая подпись прогресса.
  final String? progressSemanticsLabel;

  /// Показывать ли бейдж метода планирования.
  ///
  /// Аудит v4 (V12): на «Тренировке» FSRS не меняется, поэтому бейдж «FSRS»
  /// там прямо противоречил подписи режима — тренировка его не показывает.
  final bool showFsrsBadge;

  @override
  Size get preferredSize => Size.fromHeight(
    AppSizes.headerHeight + (progress == null ? 0 : AppSpacing.md),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? excerpt = whyExcerpt;
    final VoidCallback? onWhy = onWhyPressed;
    final double? value = progress;
    final Widget bar = SizedBox(
      height: AppSizes.headerHeight,
      child: Row(
        children: <Widget>[
          const SizedBox(width: AppSpacing.xxs),
          IconButton(
            key: const ValueKey<String>('review-close'),
            tooltip: l10n.reviewCloseTooltip,
            icon: const Icon(Icons.close, size: AppSizes.navIcon),
            onPressed: onClose,
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    title ?? l10n.reviewTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (showFsrsBadge) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(
                      l10n.reviewFsrsBadge,
                      style: AppTypography.caption(
                        context,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: const ValueKey<String>('review-undo'),
            tooltip: l10n.reviewUndoTooltip,
            icon: const Icon(Icons.undo, size: AppSizes.navIcon),
            onPressed: undoEnabled ? onUndo : null,
          ),
          // Аудит v4: «Почему?» скрыта, если цитаты нет, вместо disabled-иконки.
          if (onWhy != null || excerpt != null)
            IconButton(
              key: const ValueKey<String>('review-why'),
              tooltip: l10n.reviewWhyTooltip,
              icon: const Icon(Icons.info_outline, size: AppSizes.navIcon),
              onPressed:
                  onWhy ??
                  (excerpt == null
                      ? null
                      : () => showReviewSourceExcerpt(context, excerpt)),
            ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
    );

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: AppSizes.headerHeight,
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      title: bar,
      bottom: value == null
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(AppSpacing.md),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: AppProgressBar(
                  value: value,
                  semanticsLabel: progressSemanticsLabel,
                ),
              ),
            ),
    );
  }
}

/// Диалог выхода из сессии (SPEC A6.4): «Продолжить» / «Выйти».
///
/// Аудит v4 (V11): один вход (кнопка «×» или Esc) и один диалог; из диалога
/// убраны крестик и закрытие по фону — закрыть можно только осознанным
/// выбором или Esc. Опасное действие — текстовая кнопка цвета ошибки,
/// залитая primary возвращает в сессию.
Future<bool> confirmReviewExit(BuildContext context) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ThemeData theme = Theme.of(context);
  // AppDialog передаёт действиям контекст диалога — правило ADR-036
  // (закрывается маршрут диалога, а не экран-ветка).
  // Аудит v5 (V5-9): единый шаблон диалогов — крестик безопасного закрытия
  // (равен «Продолжить»), одна filled-кнопка безопасного действия.
  final bool? result = await showAppDialog<bool>(
    context: context,
    title: l10n.reviewExitDialogTitle,
    subtitle: l10n.reviewExitDialogMessage,
    closeLabel: l10n.reviewExitContinue,
    bodyBuilder: (BuildContext dialogContext) => const SizedBox.shrink(),
    actionsBuilder: (BuildContext dialogContext) => <Widget>[
      TextButton(
        key: const ValueKey<String>('review-exit-confirm'),
        onPressed: () => Navigator.of(dialogContext).pop(true),
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        child: Text(l10n.reviewExitConfirm),
      ),
      FilledButton(
        key: const ValueKey<String>('review-exit-cancel'),
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: Text(l10n.reviewExitContinue),
      ),
    ],
  );
  return result ?? false;
}

/// Bottom sheet «Почему эта карточка?» с цитатой исходника (SPEC A6.4).
Future<void> showReviewSourceExcerpt(BuildContext context, String excerpt) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSheetHeader(
            title: l10n.reviewWhySheetTitle,
            icon: Icons.info_outline,
          ),
          SingleChildScrollView(child: Text(excerpt)),
        ],
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
    return _SessionStateLayout(
      child: AppEmptyState(
        icon: Icons.done_all,
        title: title ?? l10n.reviewEmptyTitle,
        message: message ?? l10n.reviewEmptyMessage,
        actions: <Widget>[
          if (proceed != null) ...<Widget>[
            FilledButton(
              key: const ValueKey<String>('review-empty-continue'),
              onPressed: proceed,
              child: Text(l10n.reviewDailyLimitContinueAction),
            ),
            if (practice != null)
              OutlinedButton(
                key: const ValueKey<String>('review-empty-practice'),
                onPressed: practice,
                child: Text(l10n.practiceStartAction),
              ),
            TextButton(onPressed: onBack, child: Text(l10n.reviewBack)),
          ] else if (practice != null) ...<Widget>[
            FilledButton(
              key: const ValueKey<String>('review-empty-practice'),
              onPressed: practice,
              child: Text(l10n.practiceStartAction),
            ),
            OutlinedButton(onPressed: onBack, child: Text(l10n.reviewBack)),
          ] else
            FilledButton(onPressed: onBack, child: Text(l10n.reviewBack)),
        ],
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
    return _SessionStateLayout(
      child: AppEmptyState(
        icon: Icons.celebration_outlined,
        title: l10n.reviewCompletedTitle,
        message: l10n.reviewCompletedMessage(ratedCount),
        actions: <Widget>[
          FilledButton(onPressed: onDone, child: Text(l10n.reviewDone)),
        ],
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
    return _SessionStateLayout(
      child: AppErrorState(
        message: l10n.reviewLoadError,
        retryLabel: l10n.retry,
        onRetry: onRetry,
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
    return _SessionStateLayout(
      child: AppEmptyState(
        icon: Icons.timer_off_outlined,
        title: l10n.reviewTimeUpTitle,
        message: l10n.reviewTimeUpMessage(ratedCount),
        actions: <Widget>[
          FilledButton(onPressed: onDone, child: Text(l10n.reviewDone)),
        ],
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
    return _SessionStateLayout(
      child: AppEmptyState(
        icon: Icons.search_off,
        title: l10n.reviewPlanMissingTitle,
        message: l10n.reviewPlanMissingMessage,
        actions: <Widget>[
          FilledButton(onPressed: onBack, child: Text(l10n.reviewBack)),
        ],
      ),
    );
  }
}

/// Центрированный контент состояний сессии с шириной карточки.
class _SessionStateLayout extends StatelessWidget {
  const _SessionStateLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.studyCardMaxWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Строка прогресса над карточкой: подпись, полоса и хвостовая метрика.
class SessionProgressStrip extends StatelessWidget {
  /// Создаёт строку прогресса.
  const SessionProgressStrip({
    required this.label,
    required this.value,
    this.trailing,
    super.key,
  });

  /// Подпись («Карточка 1 из 4», «Оценено 5»).
  final String label;

  /// Доля 0..1.
  final double value;

  /// Дополнительный текст справа.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: AppTypography.numeric(context, color: scheme.onSurface),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpacing.xxs + 2),
        AppProgressBar(value: value, semanticsLabel: label),
      ],
    );
  }
}

