import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/match_game.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/state/app_providers.dart';

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

  String _formatMs(int milliseconds) {
    final String seconds = (milliseconds / 1000).toStringAsFixed(1);
    return seconds.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.matchTitle),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('match-close'),
            tooltip: l10n.reviewCloseTooltip,
            icon: const Icon(Icons.close),
            onPressed: () {
              if (context.canPop()) context.pop();
            },
          ),
        ],
      ),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: <Widget>[
              Text(
                l10n.matchTimer(_formatMs(_elapsedMs)),
                key: const ValueKey<String>('match-timer'),
                style: theme.textTheme.titleMedium,
              ),
              Text(
                l10n.matchMoves(game.moves),
                key: const ValueKey<String>('match-moves'),
                style: theme.textTheme.bodyMedium,
              ),
              if (_bestMs != null)
                Text(
                  l10n.matchBest(_formatMs(_bestMs!)),
                  key: const ValueKey<String>('match-best'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
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
                    Text(l10n.matchTimer(_formatMs(_elapsedMs))),
                    if (_bestMs != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        l10n.matchBest(_formatMs(_bestMs!)),
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
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int columns = constraints.maxWidth >= 640 ? 4 : 3;
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: game.tiles.length,
                  itemBuilder: (BuildContext context, int index) {
                    final MatchTile tile = game.tiles[index];
                    final bool matched = game.matched.contains(index);
                    final bool selected = game.selected == index;
                    final bool mismatch = game.mismatch.contains(index);
                    return _ShakeTile(
                      key: ValueKey<String>('match-tile-$index'),
                      shake: mismatch,
                      child: AnimatedOpacity(
                        opacity: matched ? 0 : 1,
                        duration: const Duration(milliseconds: 250),
                        child: IgnorePointer(
                          ignoring: matched,
                          child: FilledButton.tonal(
                            onPressed: matched ? null : () => _select(index),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.all(8),
                              backgroundColor: selected
                                  ? theme.colorScheme.primaryContainer
                                  : mismatch
                                  ? theme.colorScheme.errorContainer
                                  : null,
                            ),
                            child: Text(
                              tile.text,
                              maxLines: 4,
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
      ],
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
    duration: const Duration(milliseconds: 450),
  );

  @override
  void didUpdateWidget(_ShakeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shake && !oldWidget.shake) {
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
