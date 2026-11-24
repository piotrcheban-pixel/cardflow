import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
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
    this.showClose = true,
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

  /// Показывать ли крестик выхода.
  ///
  /// F13: в терминальных состояниях сессии («завершено», «пусто», «время
  /// истекло», «план не найден») выход уже есть основным действием панели —
  /// второй вход (крестик) убран, чтобы не было дубля.
  final bool showClose;

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
          if (showClose)
            IconButton(
              key: const ValueKey<String>('review-close'),
              tooltip: l10n.reviewCloseTooltip,
              icon: const Icon(Icons.close, size: AppSizes.navIcon),
              onPressed: onClose,
            )
          else
            const SizedBox(width: AppSpacing.sm),
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
                  // Аудит 2.0 (P3-06): «FSRS» — аббревиатура; расшифровка в
                  // подсказке, чтобы новичок понимал, что это расписание.
                  Tooltip(
                    message: l10n.reviewFsrsTooltip,
                    child: Container(
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
                  ),
                ],
              ],
            ),
          ),
          // Аудит v7 (G5): недоступное действие скрывается, а не показывается
          // серым. Без истории отката кнопки undo в дереве нет вовсе.
          if (undoEnabled)
            IconButton(
              key: const ValueKey<String>('review-undo'),
              tooltip: l10n.reviewUndoTooltip,
              icon: const Icon(Icons.undo, size: AppSizes.navIcon),
              onPressed: onUndo,
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

/// Режим, из которого выходит пользователь: от него зависит текст диалога.
enum SessionExitKind {
  /// Классическое повторение: оценки уже записаны, текущая карточка — нет.
  classic,

  /// Свободный просмотр «Лента»: ничего не записывается.
  feed,

  /// Тренировка: оценки пишутся в `review_logs`, расписание не меняется.
  practice,

  /// Проверочные режимы («Тест», «Ввод», «Пары», «Верно/Неверно»).
  study,
}

/// Диалог выхода из сессии (SPEC A6.4): «Продолжить» / «Выйти».
///
/// Аудит v4 (V11): один вход (кнопка «×» или Esc) и один диалог; из диалога
/// убраны крестик и закрытие по фону — закрыть можно только осознанным
/// выбором или Esc. Опасное действие — текстовая кнопка цвета ошибки,
/// залитая primary возвращает в сессию.
///
/// Аудит v7 (G5/V7-14): убрано дублирование «остаться» — раньше крестик в
/// шапке и filled-кнопка «Продолжить» делали одно и то же. Теперь «остаться» —
/// ровно один вход (кнопка), а Esc/крестик закрытия в диалоге нет.
///
/// Аудит 2.0 (P2-03): текст диалога соответствует режиму — в «Ленте» оценок
/// нет, в «Тренировке» они уже сохранены.
Future<bool> confirmReviewExit(
  BuildContext context, {
  SessionExitKind kind = SessionExitKind.classic,
  String? title,
  String? message,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ThemeData theme = Theme.of(context);
  final String resolvedMessage =
      message ??
      switch (kind) {
        SessionExitKind.classic => l10n.reviewExitDialogMessage,
        SessionExitKind.feed => l10n.sessionExitFeedMessage,
        SessionExitKind.practice => l10n.sessionExitPracticeMessage,
        SessionExitKind.study => l10n.sessionExitStudyMessage,
      };
  // AppDialog передаёт действиям контекст диалога — правило ADR-036
  // (закрывается маршрут диалога, а не экран-ветка).
  final bool? result = await showAppDialog<bool>(
    context: context,
    title: title ?? l10n.reviewExitDialogTitle,
    subtitle: resolvedMessage,
    bodyBuilder: (BuildContext dialogContext) => const SizedBox.shrink(),
    // F12: та же семантика destructive, что у удаления колоды — опасное
    // действие залито error, безопасное — нейтральный текст.
    actionsBuilder: (BuildContext dialogContext) => <Widget>[
      TextButton(
        key: const ValueKey<String>('review-exit-cancel'),
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
        ),
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: Text(l10n.reviewExitContinue),
      ),
      FilledButton(
        key: const ValueKey<String>('review-exit-confirm'),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: theme.colorScheme.onError,
        ),
        onPressed: () => Navigator.of(dialogContext).pop(true),
        child: Text(l10n.reviewExitConfirm),
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
        hero: true,
        icon: Icons.done_all,
        title: title ?? l10n.reviewEmptyTitle,
        message: message ?? l10n.reviewEmptyMessage,
        // F13: крестик в шапке скрыт в этом состоянии — выход один (кнопка
        // ниже); «Продолжить» и «Тренировка» — разные действия, не дубли.
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
          ] else if (practice != null) ...<Widget>[
            FilledButton(
              key: const ValueKey<String>('review-empty-practice'),
              onPressed: practice,
              child: Text(l10n.practiceStartAction),
            ),
          ],
          if (proceed != null || practice != null)
            TextButton(onPressed: onBack, child: Text(l10n.reviewBack))
          else
            FilledButton(onPressed: onBack, child: Text(l10n.reviewBack)),
        ],
      ),
    );
  }
}

/// Итоговое состояние завершённой сессии.
///
/// Аудит 2.0 (P2-25): момент завершения даёт обратную связь — разбивка оценок,
/// время и два действия, а не только число и маленькая кнопка «Готово».
class ReviewCompletedView extends StatelessWidget {
  /// Создаёт итоговый экран.
  const ReviewCompletedView({
    required this.ratedCount,
    required this.onDone,
    this.ratingCounts = const <Rating, int>{},
    this.elapsed,
    this.onAgain,
    super.key,
  });

  /// Сколько карточек оценено.
  final int ratedCount;

  /// Закрыть сессию.
  final VoidCallback onDone;

  /// Разбивка оценок (Again/Hard/Good/Easy).
  final Map<Rating, int> ratingCounts;

  /// Длительность сессии.
  final Duration? elapsed;

  /// Повторить сессию; `null` — действия нет.
  final VoidCallback? onAgain;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _SessionStateLayout(
      child: AppEmptyState(
        hero: true,
        icon: Icons.celebration_outlined,
        // F07: завершение — hero-момент: крупная метрика, заголовок 30–38,
        // одно основное действие.
        metric: Text(ratedCount.toString()),
        title: l10n.reviewCompletedTitle,
        message: l10n.reviewCompletedMessage(ratedCount),
        body: SessionSummary(ratingCounts: ratingCounts, elapsed: elapsed),
        actions: <Widget>[
          FilledButton(
            key: const ValueKey<String>('review-completed-done'),
            onPressed: onDone,
            child: Text(l10n.reviewToDeckAction),
          ),
          if (onAgain != null)
            OutlinedButton(
              key: const ValueKey<String>('review-completed-again'),
              onPressed: onAgain,
              child: Text(l10n.reviewAgainAction),
            ),
        ],
      ),
    );
  }
}

/// Сводка сессии: разбивка оценок, доля «без ошибок» и время.
class SessionSummary extends StatelessWidget {
  /// Создаёт сводку.
  const SessionSummary({required this.ratingCounts, this.elapsed, super.key});

  /// Разбивка оценок.
  final Map<Rating, int> ratingCounts;

  /// Длительность сессии.
  final Duration? elapsed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int total = ratingCounts.values.fold<int>(0, (int a, int b) => a + b);
    final int clean =
        (ratingCounts[Rating.good] ?? 0) + (ratingCounts[Rating.easy] ?? 0);
    final int percent = total == 0 ? 0 : (clean * 100 / total).round();
    final Duration? duration = elapsed;
    return Column(
      key: const ValueKey<String>('review-summary'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (total > 0)
          Row(
            children: <Widget>[
              for (final Rating rating in Rating.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                    ),
                    child: _SummaryRatingCell(
                      rating: rating,
                      count: ratingCounts[rating] ?? 0,
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          children: <Widget>[
            Text(
              l10n.reviewSummaryAccuracy(percent),
              key: const ValueKey<String>('review-summary-accuracy'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (duration != null)
              Text(
                l10n.reviewSummaryDuration(_formatDuration(duration)),
                key: const ValueKey<String>('review-summary-duration'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Компактная длительность: «42 с», «3 мин 05 с», «1 ч 04 мин».
  static String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours ч ${minutes.toString().padLeft(2, '0')} мин';
    }
    if (minutes > 0) {
      return '$minutes мин ${seconds.toString().padLeft(2, '0')} с';
    }
    return '$seconds с';
  }
}

/// Одна ячейка разбивки оценок в сводке.
class _SummaryRatingCell extends StatelessWidget {
  const _SummaryRatingCell({required this.rating, required this.count});

  final Rating rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final RatingRole role = RatingButton.roleOf(rating);
    final ColorScheme scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ratingSurface(scheme, role),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.controlBorder(scheme)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              count.toString(),
              style: AppTypography.numeric(
                context,
                color: AppColors.ratingForeground(scheme, role),
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              RatingButton.labelOf(l10n, rating),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.ratingForeground(scheme, role),
              ),
            ),
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
    return _SessionStateLayout(
      child: AppErrorState(
        hero: true,
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
    this.ratingCounts = const <Rating, int>{},
    this.elapsed,
    super.key,
  });

  /// Сколько карточек оценено до истечения времени.
  final int ratedCount;

  /// Закрыть сессию.
  final VoidCallback onDone;

  /// Разбивка оценок.
  final Map<Rating, int> ratingCounts;

  /// Длительность сессии.
  final Duration? elapsed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _SessionStateLayout(
      child: AppEmptyState(
        hero: true,
        icon: Icons.timer_off_outlined,
        metric: Text(ratedCount.toString()),
        title: l10n.reviewTimeUpTitle,
        message: l10n.reviewTimeUpMessage(ratedCount),
        body: SessionSummary(ratingCounts: ratingCounts, elapsed: elapsed),
        actions: <Widget>[
          FilledButton(
            key: const ValueKey<String>('review-timeup-done'),
            onPressed: onDone,
            child: Text(l10n.reviewDone),
          ),
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
        hero: true,
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
    final double width = AppSizes.studyCardWidth(
      MediaQuery.sizeOf(context).width,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxWidth.isFinite
            ? math.max(0, constraints.maxWidth - AppSpacing.lg * 2)
            : width;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            // F07: состояния занимают ширину и высоту карточки сессии —
            // полноценный экран-итог (≥40 % площади), а не миниатюра 253×252.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  math.min(
                    constraints.maxHeight.isFinite
                        ? constraints.maxHeight - AppSpacing.xxl
                        : AppSizes.studyCardMinHeightFor(context),
                    AppSizes.studyCardMinHeightFor(context),
                  ),
                ),
              ),
              child: SizedBox(width: math.min(width, available), child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Скелетон загрузки сессии: геометрия карточки и строки прогресса вместо
/// голого спиннера (F22). Layout не прыгает, когда приходит контент.
class ReviewLoadingView extends StatelessWidget {
  /// Создаёт скелетон сессии.
  const ReviewLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = AppSizes.studyCardWidth(
          MediaQuery.sizeOf(context).width,
        );
        final double availableW = constraints.maxWidth.isFinite
            ? math.max(0, constraints.maxWidth - AppSpacing.lg * 2)
            : width;
        final double availableH = constraints.maxHeight.isFinite
            ? math.max(0, constraints.maxHeight - AppSpacing.lg * 2)
            : 480;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SizedBox(
              width: math.min(width, availableW),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const AppSkeleton(width: 220, height: 20),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSkeleton(height: AppSizes.progressHeight),
                  const SizedBox(height: AppSpacing.md),
                  AppCardSkeleton(
                    width: math.min(width, availableW),
                    height: math.max(
                      96,
                      math.min(
                        AppSizes.studyCardMinHeightFor(context),
                        availableH - 80,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
