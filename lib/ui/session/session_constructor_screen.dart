import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/session/session_builder.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/domain/session/session_preset.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Экран «Конструктор сессии» (SPEC A6.7, A7.19–A7.20, ADR-018).
///
/// Колоды → фильтры (теги/тип/состояние) → режим → лимит → перемешивание /
/// интерливинг / разминка → пресет → старт. Собранная очередь уходит в
/// проверенные движки классики и ленты через `SessionPlan`.
class SessionConstructorScreen extends ConsumerStatefulWidget {
  /// Создаёт экран конструктора.
  const SessionConstructorScreen({
    this.preselectedDeckId,
    this.preselectedTag,
    super.key,
  });

  /// Колода, предвыбранная при открытии с экрана колоды (SPEC A6.3).
  final String? preselectedDeckId;

  /// Тег, предвыбранный из «Слабых тем» статистики (SPEC A6.5, ADR-019 §4).
  final String? preselectedTag;

  /// Варианты лимита по карточкам.
  static const List<int> cardLimitValues = <int>[10, 20, 50, 100];

  /// Варианты лимита по минутам.
  static const List<int> minuteLimitValues = <int>[5, 10, 15, 30];

  @override
  ConsumerState<SessionConstructorScreen> createState() =>
      _SessionConstructorScreenState();
}

class _SessionConstructorScreenState
    extends ConsumerState<SessionConstructorScreen> {
  List<DeckSummary> _decks = const <DeckSummary>[];
  final Map<String, List<Card>> _cardsByDeck = <String, List<Card>>{};
  final Set<String> _loadingDecks = <String>{};
  Map<String, int> _failureCounts = const <String, int>{};
  List<SessionPreset> _presets = const <SessionPreset>[];

  final Set<String> _selectedDecks = <String>{};
  Set<String> _selectedTags = <String>{};
  Set<CardType> _selectedTypes = <CardType>{};
  Set<SessionStateFilter> _selectedStates = <SessionStateFilter>{};
  SessionMode _mode = SessionMode.classic;
  SessionLimitKind _limitKind = SessionLimitKind.cards;
  int _cardsLimit = SessionConfig.defaultCardsLimit;
  int _minutesLimit = 15;
  bool _shuffle = false;
  bool _interleave = false;
  bool _warmup = false;

  bool _loading = true;
  bool _loadError = false;
  bool _starting = false;

  /// Показывать все теги: по умолчанию блок ограничен (аудит v5, V5-15).
  bool _showAllTags = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final List<DeckSummary> summaries = await ref
          .read(deckRepositoryProvider)
          .watchSummaries(query: const DeckQuery())
          .first;
      final List<String> deckIds = <String>[
        for (final DeckSummary summary in summaries) summary.deck.id,
      ];
      final Map<String, int> failureCounts = deckIds.isEmpty
          ? const <String, int>{}
          : await ref
                .read(leechRepositoryProvider)
                .failureCounts(deckIds: deckIds);
      final List<SessionPreset> presets = await ref
          .read(sessionPresetRepositoryProvider)
          .presets();
      if (!mounted) return;
      final String? preselected = widget.preselectedDeckId;
      setState(() {
        _decks = summaries;
        _failureCounts = failureCounts;
        _presets = presets;
        if (preselected != null &&
            summaries.any(
              (DeckSummary summary) => summary.deck.id == preselected,
            )) {
          _selectedDecks
            ..clear()
            ..add(preselected);
        }
        _loading = false;
      });
      await _ensureCardsLoaded();
      final String? preselectedTag = widget.preselectedTag;
      if (mounted &&
          preselectedTag != null &&
          preselectedTag.trim().isNotEmpty) {
        setState(() => _selectedTags = <String>{preselectedTag});
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  /// Колоды в порядке списка (стабильный порядок плана и «Доступно»).
  List<String> get _selectedDeckIds => <String>[
    for (final DeckSummary summary in _decks)
      if (_selectedDecks.contains(summary.deck.id)) summary.deck.id,
  ];

  /// Карточки выбранных колод (только загруженные).
  List<Card> get _selectedCards => <Card>[
    for (final String deckId in _selectedDeckIds) ...?_cardsByDeck[deckId],
  ];

  /// Доступные теги выбранных колод (детерминированный порядок).
  List<String> get _availableTags {
    final Set<String> tags = <String>{
      for (final Card card in _selectedCards) ...card.tags,
    };
    final List<String> sorted = tags.toList(growable: false);
    sorted.sort(compareTags);
    return sorted;
  }

  /// Сравнение тегов по нижнему регистру (порядок чипов).
  static int compareTags(String a, String b) {
    final int byLower = a.toLowerCase().compareTo(b.toLowerCase());
    return byLower != 0 ? byLower : a.compareTo(b);
  }

  /// Текущий конфиг формы.
  SessionConfig get _config => SessionConfig(
    deckIds: _selectedDeckIds,
    tags: _selectedTags,
    cardTypes: _selectedTypes,
    states: _selectedStates,
    mode: _mode,
    limit: _limitKind == SessionLimitKind.cards
        ? SessionLimit.cards(_cardsLimit)
        : SessionLimit.minutes(_minutesLimit),
    shuffle: _shuffle,
    interleave: _interleave,
    warmup: _warmup,
  );

  /// Карточки под фильтры (без лимита) — счётчик «Доступно».
  List<Card> get _available => SessionBuilder.select(
    cards: _selectedCards,
    config: _config,
    failureCounts: _failureCounts,
    now: DateTime.now(),
  );

  Future<void> _ensureCardsLoaded() async {
    final List<String> missing = <String>[
      for (final String deckId in _selectedDeckIds)
        if (!_cardsByDeck.containsKey(deckId) &&
            !_loadingDecks.contains(deckId))
          deckId,
    ];
    if (missing.isEmpty) return;
    setState(() => _loadingDecks.addAll(missing));
    try {
      final Map<String, List<Card>> loaded = <String, List<Card>>{};
      for (final String deckId in missing) {
        loaded[deckId] = await ref
            .read(cardRepositoryProvider)
            .cardsByDeck(deckId);
      }
      if (!mounted) return;
      setState(() {
        _cardsByDeck.addAll(loaded);
        _loadingDecks.removeAll(missing);
        _selectedTags = _selectedTags.intersection(_availableTags.toSet());
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDecks.removeAll(missing));
      showAppMessage(context, AppLocalizations.of(context).genericError);
    }
  }

  void _toggleDeck(String deckId) {
    setState(() {
      if (!_selectedDecks.remove(deckId)) _selectedDecks.add(deckId);
    });
    unawaited(_ensureCardsLoaded());
  }

  void _toggleTag(String tag) {
    setState(() {
      if (!_selectedTags.remove(tag)) _selectedTags.add(tag);
    });
  }

  void _toggleType(CardType type) {
    setState(() {
      if (!_selectedTypes.remove(type)) _selectedTypes.add(type);
    });
  }

  void _toggleState(SessionStateFilter filter) {
    setState(() {
      if (!_selectedStates.remove(filter)) _selectedStates.add(filter);
    });
  }

  void _setLimitKind(SessionLimitKind kind) {
    setState(() {
      _limitKind = kind;
      if (kind == SessionLimitKind.cards) {
        _cardsLimit =
            SessionConstructorScreen.cardLimitValues.contains(_cardsLimit)
            ? _cardsLimit
            : SessionConfig.defaultCardsLimit;
      } else {
        _minutesLimit =
            SessionConstructorScreen.minuteLimitValues.contains(_minutesLimit)
            ? _minutesLimit
            : SessionConstructorScreen.minuteLimitValues.first;
      }
    });
  }

  Future<void> _start() async {
    if (_starting) return;
    final SessionPlan plan = SessionBuilder.plan(
      cards: _selectedCards,
      config: _config,
      failureCounts: _failureCounts,
      now: DateTime.now(),
    );
    if (plan.cards.isEmpty) return;
    _starting = true;
    try {
      await context.push(
        plan.mode == SessionMode.feed
            ? AppRoutes.sessionFeedPath
            : AppRoutes.sessionClassicPath,
        extra: plan,
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> _savePreset() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _PresetNameDialog(),
    );
    if (name == null || !mounted) return;
    try {
      final SessionPreset preset = await ref
          .read(sessionPresetRepositoryProvider)
          .savePreset(name: name, config: _config, createdAt: DateTime.now());
      if (!mounted) return;
      setState(() => _presets = <SessionPreset>[..._presets, preset]);
      showAppMessage(context, l10n.constructorPresetSaved);
    } catch (_) {
      if (mounted) showAppMessage(context, l10n.genericError);
    }
  }

  Future<void> _applyPreset(SessionPreset preset) async {
    final SessionConfig config = preset.config;
    setState(() {
      final Set<String> knownDecks = <String>{
        for (final DeckSummary summary in _decks) summary.deck.id,
      };
      _selectedDecks
        ..clear()
        ..addAll(config.deckIds.where(knownDecks.contains));
      _selectedTags = <String>{...config.tags};
      _selectedTypes = <CardType>{...config.cardTypes};
      _selectedStates = <SessionStateFilter>{...config.states};
      _mode = config.mode;
      _shuffle = config.shuffle;
      _interleave = config.interleave;
      _warmup = config.warmup;
      _limitKind = config.limit.kind;
      if (config.limit.kind == SessionLimitKind.cards) {
        _cardsLimit =
            SessionConstructorScreen.cardLimitValues.contains(
              config.limit.value,
            )
            ? config.limit.value
            : SessionConfig.defaultCardsLimit;
      } else {
        _minutesLimit =
            SessionConstructorScreen.minuteLimitValues.contains(
              config.limit.value,
            )
            ? config.limit.value
            : SessionConstructorScreen.minuteLimitValues.first;
      }
    });
    await _ensureCardsLoaded();
  }

  Future<void> _deletePreset(SessionPreset preset) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      await ref.read(sessionPresetRepositoryProvider).deletePreset(preset.id);
      if (!mounted) return;
      setState(() {
        _presets = <SessionPreset>[
          for (final SessionPreset item in _presets)
            if (item.id != preset.id) item,
        ];
      });
      showAppMessage(context, l10n.constructorPresetDeleted);
    } catch (_) {
      if (mounted) showAppMessage(context, l10n.genericError);
    }
  }

  String _cardTypeLabel(AppLocalizations l10n, CardType type) {
    return switch (type) {
      CardType.basic => l10n.cardTypeBasic,
      CardType.basicReversed => l10n.cardTypeBasicReversed,
      CardType.cloze => l10n.cardTypeCloze,
    };
  }

  String _stateLabel(AppLocalizations l10n, SessionStateFilter filter) {
    return switch (filter) {
      SessionStateFilter.newCards => l10n.constructorStateNew,
      SessionStateFilter.inProgress => l10n.constructorStateInProgress,
      SessionStateFilter.review => l10n.constructorStateReview,
      SessionStateFilter.leeches => l10n.constructorStateLeeches,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.constructorTitle)),
      bottomNavigationBar: _buildBottomBar(l10n),
      body: Builder(
        builder: (BuildContext context) {
          // F09/V1: конструктор — подстраница оболочки; тот же левый отступ,
          // что у контента shell, — кромка не прыгает.
          final double shellOffset =
              MediaQuery.sizeOf(context).width >= AppSizes.sidebarBreakpoint
              ? AppSizes.sidebarWidthFor(context)
              : 0;
          return Padding(
            padding: EdgeInsetsDirectional.only(start: shellOffset),
            child: _buildBody(l10n),
          );
        },
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final double scale = AppAdaptive.factorForContext(context).clamp(1.0, 1.45);
    if (_loading) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSkeleton(height: 120),
            SizedBox(height: AppSpacing.md),
            AppSkeleton(height: 96),
            SizedBox(height: AppSpacing.md),
            AppSkeleton(height: 120),
          ],
        ),
      );
    }
    if (_loadError) {
      return _ConstructorErrorState(
        message: l10n.constructorLoadError,
        onRetry: () => unawaited(_load()),
      );
    }
    if (_decks.isEmpty) {
      return _ConstructorEmptyState(message: l10n.constructorEmptyDecks);
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppSizes.detailsWidth(context)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          children: <Widget>[
            _Section(
              title: l10n.constructorDecksSection,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final DeckSummary summary in _decks)
                    FilterChip(
                      key: ValueKey<String>(
                        'constructor-deck-${summary.deck.id}',
                      ),
                      // F34/V10: длинное имя не обрезается — метка занимает
                      // до двух строк в доступной ширине панели.
                      label: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 420 * scale),
                        child: Text(
                          summary.deck.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      selected: _selectedDecks.contains(summary.deck.id),
                      onSelected: (_) => _toggleDeck(summary.deck.id),
                    ),
                ],
              ),
            ),
            _Section(
              title: l10n.constructorTagsSection,
              // Аудит v4 (V35): пустая секция «Теги» была панелью 130 px с одной
              // серой строкой — компактный вариант без большой пустоты.
              dense: _availableTags.isEmpty,
              child: _availableTags.isEmpty
                  ? Text(
                      _selectedDecks.isEmpty
                          ? l10n.constructorSelectDecksHint
                          : l10n.constructorTagsEmpty,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Builder(
                      builder: (BuildContext context) {
                        // Аудит v5 (V5-15): 40 тегов занимали 8 рядов и
                        // выталкивали настройки за фолд — показываем первые 18
                        // и «Ещё N» с разворотом.
                        const int limit = 18;
                        final bool hidden =
                            !_showAllTags && _availableTags.length > limit;
                        final List<String> visible = hidden
                            ? _availableTags.take(limit).toList()
                            : _availableTags;
                        final int rest = _availableTags.length - visible.length;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final String tag in visible)
                              FilterChip(
                                key: ValueKey<String>('constructor-tag-$tag'),
                                label: Text(tag),
                                selected: _selectedTags.contains(tag),
                                onSelected: (_) => _toggleTag(tag),
                              ),
                            if (hidden)
                              ActionChip(
                                key: const ValueKey<String>(
                                  'constructor-tags-more',
                                ),
                                label: Text(l10n.constructorTagsMore(rest)),
                                onPressed: () =>
                                    setState(() => _showAllTags = true),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            _Section(
              title: l10n.constructorTypesSection,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final CardType type in CardType.values)
                    FilterChip(
                      key: ValueKey<String>(
                        'constructor-type-${type.wireName}',
                      ),
                      label: Text(_cardTypeLabel(l10n, type)),
                      selected: _selectedTypes.contains(type),
                      onSelected: (_) => _toggleType(type),
                    ),
                ],
              ),
            ),
            _Section(
              title: l10n.constructorStatesSection,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final SessionStateFilter filter
                      in SessionStateFilter.values)
                    FilterChip(
                      key: ValueKey<String>(
                        'constructor-state-${filter.wireName}',
                      ),
                      label: Text(_stateLabel(l10n, filter)),
                      selected: _selectedStates.contains(filter),
                      onSelected: (_) => _toggleState(filter),
                    ),
                ],
              ),
            ),
            _Section(
              title: l10n.constructorModeSection,
              child: SegmentedButton<SessionMode>(
                key: const ValueKey<String>('constructor-mode'),
                segments: <ButtonSegment<SessionMode>>[
                  ButtonSegment<SessionMode>(
                    value: SessionMode.classic,
                    label: Text(l10n.reviewModeClassic),
                    icon: const Icon(Icons.style_outlined),
                  ),
                  ButtonSegment<SessionMode>(
                    value: SessionMode.feed,
                    label: Text(l10n.reviewModeFeed),
                    icon: const Icon(Icons.view_agenda_outlined),
                  ),
                ],
                selected: <SessionMode>{_mode},
                onSelectionChanged: (Set<SessionMode> selection) =>
                    setState(() => _mode = selection.first),
              ),
            ),
            _Section(
              title: l10n.constructorLimitSection,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      ChoiceChip(
                        key: const ValueKey<String>('constructor-limit-cards'),
                        label: Text(l10n.constructorLimitCards),
                        selected: _limitKind == SessionLimitKind.cards,
                        onSelected: (_) =>
                            _setLimitKind(SessionLimitKind.cards),
                      ),
                      ChoiceChip(
                        key: const ValueKey<String>(
                          'constructor-limit-minutes',
                        ),
                        label: Text(l10n.constructorLimitMinutes),
                        selected: _limitKind == SessionLimitKind.minutes,
                        onSelected: (_) =>
                            _setLimitKind(SessionLimitKind.minutes),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    key: const ValueKey<String>('constructor-limit-value'),
                    value: _limitKind == SessionLimitKind.cards
                        ? _cardsLimit
                        : _minutesLimit,
                    items: <DropdownMenuItem<int>>[
                      for (final int value
                          in _limitKind == SessionLimitKind.cards
                              ? SessionConstructorScreen.cardLimitValues
                              : SessionConstructorScreen.minuteLimitValues)
                        DropdownMenuItem<int>(
                          value: value,
                          child: Text(
                            _limitKind == SessionLimitKind.cards
                                ? l10n.constructorLimitCardsValue(value)
                                : l10n.constructorLimitMinutesValue(value),
                          ),
                        ),
                    ],
                    onChanged: (int? value) {
                      if (value == null) return;
                      setState(() {
                        if (_limitKind == SessionLimitKind.cards) {
                          _cardsLimit = value;
                        } else {
                          _minutesLimit = value;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            _Section(
              title: l10n.constructorOrderSection,
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    key: const ValueKey<String>('constructor-shuffle'),
                    contentPadding: EdgeInsets.zero,
                    value: _shuffle,
                    onChanged: (bool value) => setState(() => _shuffle = value),
                    title: Text(l10n.constructorShuffle),
                    subtitle: Text(l10n.constructorShuffleHint),
                  ),
                  SwitchListTile(
                    key: const ValueKey<String>('constructor-interleave'),
                    contentPadding: EdgeInsets.zero,
                    value: _interleave,
                    onChanged: (bool value) =>
                        setState(() => _interleave = value),
                    title: Text(l10n.constructorInterleave),
                    subtitle: Text(l10n.constructorInterleaveHint),
                  ),
                  SwitchListTile(
                    key: const ValueKey<String>('constructor-warmup'),
                    contentPadding: EdgeInsets.zero,
                    value: _warmup,
                    onChanged: (bool value) => setState(() => _warmup = value),
                    title: Text(l10n.constructorWarmup),
                    subtitle: Text(l10n.constructorWarmupHint),
                  ),
                ],
              ),
            ),
            _Section(
              title: l10n.constructorPresetsSection,
              child: _presets.isEmpty
                  ? Text(l10n.constructorPresetsEmpty)
                  : Column(
                      children: <Widget>[
                        for (final SessionPreset preset in _presets)
                          ListTile(
                            key: ValueKey<String>(
                              'constructor-preset-${preset.id}',
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: Text(preset.name),
                            onTap: () => unawaited(_applyPreset(preset)),
                            trailing: IconButton(
                              key: ValueKey<String>(
                                'constructor-preset-delete-${preset.id}',
                              ),
                              tooltip: l10n.constructorPresetDeleteTooltip,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => unawaited(_deletePreset(preset)),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    final int available = _available.length;
    final bool busy = _loading || _loadingDecks.isNotEmpty || _starting;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppSizes.detailsWidth(context),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.constructorAvailableCount(available),
                    key: const ValueKey<String>('constructor-available'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      TextButton(
                        key: const ValueKey<String>('constructor-save-preset'),
                        onPressed: busy || _selectedDecks.isEmpty
                            ? null
                            : () => unawaited(_savePreset()),
                        child: Text(l10n.constructorSavePreset),
                      ),
                      const Spacer(),
                      FilledButton(
                        key: const ValueKey<String>('constructor-start'),
                        onPressed: busy || available == 0
                            ? null
                            : () => unawaited(_start()),
                        child: Text(l10n.reviewStartSession),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Блок формы с заголовком.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.dense = false,
  });

  final String title;
  final Widget child;

  /// Компактные отступы: пустая секция не занимает пол-экрана (V35).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppSectionCard(
        title: title,
        contentPadding: dense
            ? const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.sm,
              )
            : const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
        child: child,
      ),
    );
  }
}

/// Пустое состояние конструктора (нет активных колод).
class _ConstructorEmptyState extends StatelessWidget {
  const _ConstructorEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppSizes.detailsWidth(context)),
          child: AppEmptyState(
            icon: Icons.library_books_outlined,
            title: l10n.constructorTitle,
            message: message,
            compact: true,
          ),
        ),
      ),
    );
  }
}

/// Ошибка загрузки конструктора с повтором.
class _ConstructorErrorState extends StatelessWidget {
  const _ConstructorErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppSizes.detailsWidth(context)),
          child: AppErrorState(
            message: message,
            retryLabel: l10n.retry,
            onRetry: onRetry,
          ),
        ),
      ),
    );
  }
}

/// Диалог имени пресета; `null` — отмена.
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = l10n.constructorPresetNameEmpty);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AppDialog(
      title: l10n.constructorPresetDialogTitle,
      bodyBuilder: (BuildContext dialogContext) => TextField(
        key: const ValueKey<String>('constructor-preset-name'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.constructorPresetNameLabel,
          errorText: _errorText,
        ),
      ),
      actionsBuilder: (BuildContext dialogContext) => <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('constructor-preset-submit'),
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
