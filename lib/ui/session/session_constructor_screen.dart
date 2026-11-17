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
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/decks/deck_gem.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Экран «Конструктор сессии» (SPEC A6.7, A7.19–A7.20, ADR-018;
/// REDESIGN-SPEC §9.14).
///
/// Колоды → фильтры (теги/тип/состояние) → режим → лимит → перемешивание /
/// интерливинг / разминка → пресет → старт. Собранная очередь уходит в
/// проверенные движки классики и ленты через `SessionPlan`. Оформление —
/// пронумерованные `NcSection`, `NcChip.filter`, `NcSegmented`, `NcStepper`,
/// стеклянная нижняя панель; обработчики и провайдеры прежние.
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

  /// Следующее/предыдущее дискретное значение лимита (степпер §9.14).
  void _stepLimit(int direction) {
    final List<int> values = _limitKind == SessionLimitKind.cards
        ? SessionConstructorScreen.cardLimitValues
        : SessionConstructorScreen.minuteLimitValues;
    final int current = _limitKind == SessionLimitKind.cards
        ? _cardsLimit
        : _minutesLimit;
    final int index = values.indexOf(current);
    final int nextIndex = index < 0
        ? 0
        : (index + direction).clamp(0, values.length - 1);
    final int next = values[nextIndex];
    setState(() {
      if (_limitKind == SessionLimitKind.cards) {
        _cardsLimit = next;
      } else {
        _minutesLimit = next;
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
    final String? name = await _showPresetNameDialog(context);
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
    return NcGlassGroup(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NcTopBar(
                title: l10n.constructorTitle,
                leading: NcIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: l10n.reviewBack,
                  variant: NcIconButtonVariant.glass,
                  onPressed: () {
                    if (context.canPop()) context.pop();
                  },
                ),
              ),
              Expanded(child: _buildBody(l10n)),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomBar(l10n),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final NcTheme theme = NcTheme.of(context);
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          NcSkeleton(height: 64, radius: NcRadii.l),
          SizedBox(height: 12),
          NcSkeleton(height: 120, radius: NcRadii.l),
          SizedBox(height: 12),
          NcSkeleton(height: 120, radius: NcRadii.l),
        ],
      );
    }
    if (_loadError) {
      return NcErrorState(
        message: l10n.constructorLoadError,
        retryLabel: l10n.retry,
        onRetry: () => unawaited(_load()),
      );
    }
    if (_decks.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NcEmptyState(
            iconName: 'empty_decks',
            title: l10n.constructorEmptyDecks,
            message: l10n.constructorSelectDecksHint,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        _StepSection(
          number: 1,
          title: l10n.constructorDecksSection,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final DeckSummary summary in _decks)
                _DeckPick(
                  key: ValueKey<String>('constructor-deck-${summary.deck.id}'),
                  summary: summary,
                  selected: _selectedDecks.contains(summary.deck.id),
                  onTap: () => _toggleDeck(summary.deck.id),
                ),
            ],
          ),
        ),
        _StepSection(
          number: 2,
          title: l10n.constructorTagsSection,
          child: _availableTags.isEmpty
              ? Text(
                  _selectedDecks.isEmpty
                      ? l10n.constructorSelectDecksHint
                      : l10n.constructorTagsEmpty,
                  style: theme.typography.bodyS.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String tag in _availableTags)
                      NcChip.filter(
                        key: ValueKey<String>('constructor-tag-$tag'),
                        label: tag,
                        selected: _selectedTags.contains(tag),
                        onSelected: () => _toggleTag(tag),
                      ),
                  ],
                ),
        ),
        _StepSection(
          number: 3,
          title: l10n.constructorTypesSection,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final CardType type in CardType.values)
                NcChip.filter(
                  key: ValueKey<String>('constructor-type-${type.wireName}'),
                  label: _cardTypeLabel(l10n, type),
                  selected: _selectedTypes.contains(type),
                  onSelected: () => _toggleType(type),
                ),
            ],
          ),
        ),
        _StepSection(
          number: 4,
          title: l10n.constructorStatesSection,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final SessionStateFilter filter in SessionStateFilter.values)
                NcChip.filter(
                  key: ValueKey<String>('constructor-state-${filter.wireName}'),
                  label: _stateLabel(l10n, filter),
                  selected: _selectedStates.contains(filter),
                  onSelected: () => _toggleState(filter),
                ),
            ],
          ),
        ),
        _StepSection(
          number: 5,
          title: l10n.constructorModeSection,
          child: NcSegmented<SessionMode>(
            key: const ValueKey<String>('constructor-mode'),
            value: _mode,
            onChanged: (SessionMode mode) => setState(() => _mode = mode),
            segments: <NcSegment<SessionMode>>[
              NcSegment<SessionMode>(
                value: SessionMode.classic,
                label: l10n.reviewModeClassic,
                leading: const Icon(Icons.style_outlined, size: 18),
              ),
              NcSegment<SessionMode>(
                value: SessionMode.feed,
                label: l10n.reviewModeFeed,
                leading: const Icon(Icons.view_agenda_outlined, size: 18),
              ),
            ],
          ),
        ),
        _StepSection(
          number: 6,
          title: l10n.constructorLimitSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NcSegmented<SessionLimitKind>(
                value: _limitKind,
                onChanged: _setLimitKind,
                segments: <NcSegment<SessionLimitKind>>[
                  NcSegment<SessionLimitKind>(
                    key: const ValueKey<String>('constructor-limit-cards'),
                    value: SessionLimitKind.cards,
                    label: l10n.constructorLimitCards,
                  ),
                  NcSegment<SessionLimitKind>(
                    key: const ValueKey<String>('constructor-limit-minutes'),
                    value: SessionLimitKind.minutes,
                    label: l10n.constructorLimitMinutes,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  NcStepper(
                    value: _limitKind == SessionLimitKind.cards
                        ? _cardsLimit
                        : _minutesLimit,
                    minusKey: const ValueKey<String>('constructor-limit-minus'),
                    valueKey: const ValueKey<String>('constructor-limit-value'),
                    plusKey: const ValueKey<String>('constructor-limit-plus'),
                    minValue: 0,
                    maxValue: 1000,
                    onDecrement: () => _stepLimit(-1),
                    onIncrement: () => _stepLimit(1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _limitKind == SessionLimitKind.cards
                          ? l10n.constructorLimitCardsValue(_cardsLimit)
                          : l10n.constructorLimitMinutesValue(_minutesLimit),
                      style: theme.typography.bodyS.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _StepSection(
          number: 7,
          title: l10n.constructorOrderSection,
          child: NcSection(
            children: <Widget>[
              NcListRow(
                key: const ValueKey<String>('constructor-shuffle'),
                title: Text(l10n.constructorShuffle),
                subtitle: Text(l10n.constructorShuffleHint),
                trailing: NcSwitch(
                  value: _shuffle,
                  onChanged: (bool value) => setState(() => _shuffle = value),
                  semanticLabel: l10n.constructorShuffle,
                ),
                onTap: () => setState(() => _shuffle = !_shuffle),
              ),
              NcListRow(
                key: const ValueKey<String>('constructor-interleave'),
                title: Text(l10n.constructorInterleave),
                subtitle: Text(l10n.constructorInterleaveHint),
                trailing: NcSwitch(
                  value: _interleave,
                  onChanged: (bool value) =>
                      setState(() => _interleave = value),
                  semanticLabel: l10n.constructorInterleave,
                ),
                onTap: () => setState(() => _interleave = !_interleave),
              ),
              NcListRow(
                key: const ValueKey<String>('constructor-warmup'),
                title: Text(l10n.constructorWarmup),
                subtitle: Text(l10n.constructorWarmupHint),
                showDivider: false,
                trailing: NcSwitch(
                  value: _warmup,
                  onChanged: (bool value) => setState(() => _warmup = value),
                  semanticLabel: l10n.constructorWarmup,
                ),
                onTap: () => setState(() => _warmup = !_warmup),
              ),
            ],
          ),
        ),
        _StepSection(
          number: 8,
          title: l10n.constructorPresetsSection,
          child: _presets.isEmpty
              ? Text(
                  l10n.constructorPresetsEmpty,
                  style: theme.typography.bodyS.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                )
              : NcSection(
                  children: <Widget>[
                    for (var index = 0; index < _presets.length; index++)
                      NcListRow(
                        key: ValueKey<String>(
                          'constructor-preset-${_presets[index].id}',
                        ),
                        title: Text(_presets[index].name),
                        showDivider: index < _presets.length - 1,
                        onTap: () => unawaited(_applyPreset(_presets[index])),
                        trailing: NcIconButton(
                          key: ValueKey<String>(
                            'constructor-preset-delete-${_presets[index].id}',
                          ),
                          icon: Icons.delete_outline,
                          tooltip: l10n.constructorPresetDeleteTooltip,
                          size: 36,
                          onPressed: () =>
                              unawaited(_deletePreset(_presets[index])),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    final NcTheme theme = NcTheme.of(context);
    final int available = _available.length;
    final bool busy = _loading || _loadingDecks.isNotEmpty || _starting;
    return NcGlass(
      tier: NcGlassTier.regular,
      radius: 0,
      grouped: true,
      showNoise: false,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.constructorAvailableCount(available),
            key: const ValueKey<String>('constructor-available'),
            style: theme.typography.monoM.copyWith(
              color: available == 0
                  ? theme.colors.amber
                  : theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              NcButton(
                key: const ValueKey<String>('constructor-save-preset'),
                label: l10n.constructorSavePreset,
                variant: NcButtonVariant.secondary,
                onPressed: busy || _selectedDecks.isEmpty
                    ? null
                    : () => unawaited(_savePreset()),
              ),
              NcButton(
                key: const ValueKey<String>('constructor-start'),
                label: l10n.reviewStartSession,
                loading: _starting,
                onPressed: busy || available == 0
                    ? null
                    : () => unawaited(_start()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Секция формы с номером шага в золотом кружке.
class _StepSection extends StatelessWidget {
  const _StepSection({
    required this.number,
    required this.title,
    required this.child,
  });

  final int number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final String numberLabel = '$number';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colors.aurumSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  numberLabel,
                  style: theme.typography.labelM.copyWith(
                    color: theme.colors.aurum,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.typography.overline.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Мини-плитка колоды: аватар 32, название и галочка выбранной.
class _DeckPick extends StatelessWidget {
  const _DeckPick({
    super.key,
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  final DeckSummary summary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Semantics(
      selected: selected,
      label: summary.deck.name,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: NcSurface(
          radius: NcRadii.l,
          color: selected ? theme.colors.aurumSoft : null,
          border: true,
          hoverLift: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              NcIcon3D(
                name: deckGemName(summary.deck.id),
                size: 40,
                showShadow: false,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  summary.deck.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.titleS.copyWith(
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: 8),
                Icon(Icons.check_rounded, size: 18, color: theme.colors.aurum),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Диалог имени пресета; `null` — отмена.
Future<String?> _showPresetNameDialog(BuildContext context) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final GlobalKey<_PresetNameFieldState> fieldKey =
      GlobalKey<_PresetNameFieldState>();

  void submit() {
    final String? name = fieldKey.currentState?.trySubmit();
    if (name == null) return;
    Navigator.of(context).pop(name);
  }

  return showNcDialog<String>(
    context,
    title: l10n.constructorPresetDialogTitle,
    content: _PresetNameField(key: fieldKey),
    actions: <Widget>[
      NcButton(
        label: l10n.cancel,
        variant: NcButtonVariant.ghost,
        onPressed: () => Navigator.of(context).pop(),
      ),
      NcButton(
        key: const ValueKey<String>('constructor-preset-submit'),
        label: l10n.save,
        onPressed: submit,
      ),
    ],
  );
}

/// Поле имени пресета с валидацией (Enter = отправка).
class _PresetNameField extends StatefulWidget {
  const _PresetNameField({super.key});

  @override
  State<_PresetNameField> createState() => _PresetNameFieldState();
}

class _PresetNameFieldState extends State<_PresetNameField> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Возвращает имя или `null`, если оно пустое.
  String? trySubmit() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = l10n.constructorPresetNameEmpty);
      return null;
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NcTextField(
      key: const ValueKey<String>('constructor-preset-name'),
      controller: _controller,
      autofocus: true,
      label: l10n.constructorPresetNameLabel,
      errorText: _errorText,
      textInputAction: TextInputAction.done,
      onSubmitted: (String value) {
        final String? name = trySubmit();
        if (name != null) Navigator.of(context).pop(name);
      },
    );
  }
}
