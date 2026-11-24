import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/match_game.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Игровой режим «Подбор пар» (7.16).
///
/// Сетка из 6 пар: вопрос и ответ вперемешку. Совпавшая пара исчезает,
/// несовпавшая встряхивается. Таймер идёт с первого тапа, лучший результат
/// колоды хранится локально (`app_settings`, JSON v1). В FSRS ничего не
/// пишется: режим игровой (ADR-032, `StudyMode.match`).
class MatchScreen extends ConsumerStatefulWidget {
  /// Создаёт экран для колоды [deckId].
  const MatchScreen({required this.deckId, super.key});

  /// Колода.
  final String deckId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  MatchGame? _game;
  int? _bestMs;
  bool _loading = true;
  bool _loadFailed = false;
  bool _started = false;
  bool _completed = false;
  int _seed = 0;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _completed = false;
      _started = false;
      _elapsedMs = 0;
      _stopwatch.reset();
    });
    try {
      final List<Card> cards = await ref
          .read(cardRepositoryProvider)
          .cardsByDeck(widget.deckId);
      final int? best = await ref
          .read(matchBestStoreProvider)
          .bestMs(widget.deckId);
      if (!mounted) return;
      setState(() {
        _game = MatchGame.build(cards: cards, seed: _seed);
        _bestMs = best;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _startTimer() {
    if (_started) return;
    _started = true;
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsedMs = _stopwatch.elapsedMilliseconds);
    });
  }

  void _select(int index) {
    final MatchGame? game = _game;
    if (game == null || game.mismatch.isNotEmpty) return;
    _startTimer();
    final MatchSelectionResult result = game.select(index);
    if (result == MatchSelectionResult.matched && _hapticsEnabled) {
      unawaited(HapticFeedback.selectionClick());
    }
    if (result == MatchSelectionResult.mismatch) {
      if (_hapticsEnabled) unawaited(HapticFeedback.heavyImpact());
      Timer(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        game.clearMismatch();
        setState(() {});
      });
    }
    if (game.isCompleted && !_completed) {
      _completed = true;
      _ticker?.cancel();
      _stopwatch.stop();
      _elapsedMs = _stopwatch.elapsedMilliseconds;
      final int elapsed = _elapsedMs;
      unawaited(_saveBest(elapsed));
      if (_hapticsEnabled) unawaited(HapticFeedback.mediumImpact());
    }
    setState(() {});
  }

  bool get _hapticsEnabled => ref.read(effectiveAppSettingsProvider).haptics;

  Future<void> _saveBest(int elapsed) async {
    try {
      await ref
          .read(matchBestStoreProvider)
          .saveIfBetter(widget.deckId, elapsed);
      final int? best = await ref
          .read(matchBestStoreProvider)
          .bestMs(widget.deckId);
      if (mounted) setState(() => _bestMs = best);
    } catch (_) {
      // Игровой результат не критичен для приложения.
    }
  }

  void _restart() {
    _ticker?.cancel();
    _stopwatch
      ..reset()
      ..stop();
    setState(() {
      _seed++;
      _completed = false;
      _started = false;
      _elapsedMs = 0;
    });
    unawaited(_reloadGame());
  }

  Future<void> _reloadGame() async {
    final List<Card> cards = await ref
        .read(cardRepositoryProvider)
        .cardsByDeck(widget.deckId);
    if (!mounted) return;
    setState(() {
      _game = MatchGame.build(cards: cards, seed: _seed);
    });
  }

  /// Выход из игры с подтверждением: результат не сохранится.
  Future<void> _confirmExit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool playing =
        _started && !_completed && (_game?.isPlayable ?? false);
    if (!playing) {
      if (context.canPop()) context.pop();
      return;
    }
    final bool confirmed = await confirmReviewExit(
      context,
      kind: SessionExitKind.study,
      title: l10n.matchExitTitle,
      message: l10n.matchExitMessage,
    );
    if (confirmed && mounted && context.canPop()) context.pop();
  }

  /// Время игры строкой с единицами (аудит 2.0, P2-23): «2,6 с» / «1 мин 05 с».
  String _formatDuration(int milliseconds) {
    if (milliseconds >= Duration.millisecondsPerMinute) {
      final int minutes = milliseconds ~/ Duration.millisecondsPerMinute;
      final String seconds =
          ((milliseconds % Duration.millisecondsPerMinute) / 1000)
              .toStringAsFixed(1)
              .replaceAll('.', ',');
      return AppLocalizations.of(context).matchTimeMinutes(minutes, seconds);
    }
    final String seconds = (milliseconds / 1000)
        .toStringAsFixed(1)
        .replaceAll('.', ',');
    return AppLocalizations.of(context).matchTimeSeconds(seconds);
  }

  /// Только значение времени с единицами — для строки «Лучшее время».
  String _formatValue(int milliseconds) {
    if (milliseconds >= Duration.millisecondsPerMinute) {
      final int minutes = milliseconds ~/ Duration.millisecondsPerMinute;
      final String seconds =
          ((milliseconds % Duration.millisecondsPerMinute) / 1000)
              .toStringAsFixed(1)
              .replaceAll('.', ',');
      return '$minutes мин $seconds с';
    }
    return '${(milliseconds / 1000).toStringAsFixed(1).replaceAll('.', ',')} с';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // F20: «Подбор пар» — тот же каркас сессии, что у остальных режимов:
    // выход слева, один заголовок, никаких отдельных AppBar-действий.
    final bool playable = _game?.isPlayable ?? false;
    return Scaffold(
      appBar: ReviewSessionAppBar(
        title: l10n.matchTitle,
        undoEnabled: false,
        onUndo: () {},
        whyExcerpt: null,
        showFsrsBadge: false,
        showClose: _loading || _loadFailed || playable,
        // Аудит 2.0 (P2-23): выход из игры не теряет прогресс молча.
        onClose: () => unawaited(_confirmExit()),
      ),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) return const ReviewLoadingView();
    if (_loadFailed) {
      return ReviewLoadErrorView(onRetry: () => unawaited(_load()));
    }
    final MatchGame game = _game!;
    if (!game.isPlayable) {
      return ReviewEmptyView(
        title: l10n.matchEmptyTitle,
        message: l10n.matchEmptyMessage,
        onBack: () {
          if (context.canPop()) context.pop();
        },
      );
    }
    final ThemeData theme = Theme.of(context);
    final double contentWidth = AppSizes.pageWidth(context);
    final Widget stats = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          // F20: служебные числа режима — аккуратные плашки, а не голый текст.
          _MatchStat(
            key: const ValueKey<String>('match-timer'),
            icon: Icons.timer_outlined,
            label: _formatDuration(_elapsedMs),
          ),
          _MatchStat(
            key: const ValueKey<String>('match-progress'),
            icon: Icons.extension_outlined,
            label: l10n.matchProgress(
              game.matched.length ~/ 2,
              game.tiles.length ~/ 2,
            ),
          ),
          _MatchStat(
            key: const ValueKey<String>('match-moves'),
            icon: Icons.touch_app_outlined,
            label: l10n.matchMoves(game.moves),
          ),
          if (_bestMs != null)
            _MatchStat(
              key: const ValueKey<String>('match-best'),
              icon: Icons.emoji_events_outlined,
              label: l10n.matchBest(_formatValue(_bestMs!)),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentWidth),
            child: stats,
          ),
        ),
        if (_completed)
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.extension_outlined,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.matchCompletedTitle,
                      key: const ValueKey<String>('match-completed'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(_formatDuration(_elapsedMs)),
                    if (_bestMs != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        l10n.matchBest(_formatValue(_bestMs!)),
                        key: const ValueKey<String>('match-best-result'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const ValueKey<String>('match-restart'),
                      onPressed: _restart,
                      child: Text(l10n.matchRestart),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const ValueKey<String>('match-done'),
                      onPressed: () {
                        if (context.canPop()) context.pop();
                      },
                      child: Text(l10n.matchDone),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    // V11: 1024×768 (683×512 лог.) — четыре колонки при
                    // кегле 13: все 12 плиток видны, длинные вопросы
                    // переносятся в 4 строки без многоточия.
                    final bool compactTiles = constraints.maxWidth < 900;
                    final int columns = constraints.maxWidth >= 1600
                        ? 6
                        : constraints.maxWidth >= 560
                        ? 4
                        : constraints.maxWidth >= 380
                        ? 2
                        : 1;
                    // Аудит 2.0 (P2-23): совпавшие плитки убираются из сетки,
                    // а не оставляют дыры — сетка перестраивается.
                    final List<int> visible = <int>[
                      for (var i = 0; i < game.tiles.length; i++)
                        if (!game.matched.contains(i)) i,
                    ];
                    return GridView.builder(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: AppSpacing.xs,
                        crossAxisSpacing: AppSpacing.xs,
                        childAspectRatio: 1.35,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int position) {
                        final int index = visible[position];
                        final MatchTile tile = game.tiles[index];
                        final bool selected = game.selected == index;
                        final bool mismatch = game.mismatch.contains(index);
                        return _ShakeTile(
                          key: ValueKey<String>('match-tile-$index'),
                          shake: mismatch,
                          child: AnimatedOpacity(
                            opacity: 1,
                            duration: AppMotion.duration(
                              context,
                              AppDurations.medium,
                            ),
                            child: IgnorePointer(
                              ignoring: false,
                              child: FilledButton(
                                onPressed: () => _select(index),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  backgroundColor: selected
                                      ? theme.colorScheme.primaryContainer
                                      : mismatch
                                      ? theme.colorScheme.errorContainer
                                      : theme.colorScheme.surfaceContainerLow,
                                  foregroundColor: selected
                                      ? theme.colorScheme.onPrimaryContainer
                                      : mismatch
                                      ? theme.colorScheme.onErrorContainer
                                      : theme.colorScheme.onSurface,
                                  disabledBackgroundColor:
                                      theme.colorScheme.surfaceContainerLow,
                                  disabledForegroundColor:
                                      theme.colorScheme.onSurfaceVariant,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppRadii.inputRadius,
                                    side: BorderSide(
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : AppColors.controlBorder(
                                              theme.colorScheme,
                                            ),
                                    ),
                                  ),
                                  elevation: 0,
                                  textStyle: theme.textTheme.titleSmall
                                      ?.copyWith(
                                        fontSize: compactTiles ? 13 : null,
                                      ),
                                ),
                                child: CardText(
                                  source: tile.text,
                                  maxLines: compactTiles ? 6 : 4,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Плашка служебного значения режима («Время», «Ходов», «Лучшее»).
class _MatchStat extends StatelessWidget {
  const _MatchStat({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: AppSizes.iconSmall, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xxs + 2),
          Text(
            label,
            style: AppTypography.numeric(context, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Плитка с анимацией встряхивания при несовпадении пары.
class _ShakeTile extends StatefulWidget {
  const _ShakeTile({required this.shake, required this.child, super.key});

  final bool shake;
  final Widget child;

  @override
  State<_ShakeTile> createState() => _ShakeTileState();
}

class _ShakeTileState extends State<_ShakeTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.base,
  );

  @override
  void didUpdateWidget(_ShakeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reduced motion: без встряхивания — только цветовая вспышка.
    if (widget.shake && !oldWidget.shake && !AppMotion.reduce(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double offset =
            math.sin(_controller.value * math.pi * 6) *
            6 *
            (1 - _controller.value);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: widget.child,
    );
  }
}
