import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/domain/session/session_preset.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/session/session_constructor_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/session_fakes.dart';

/// Красная фаза итерации 6: экран «Конструктор сессии» (SPEC A6.7, ADR-018) —
/// мультивыбор колод, фильтры, режим, лимит, порядок, пресеты, старт.
void main() {
  final DateTime cardsTime = DateTime.utc(2026, 11, 14, 10);

  late FakeSessionPresetRepository presets;
  late FakeLeechRepository leeches;
  late FakeCardRepository cards;
  late FakeDeckRepository decks;

  List<Card> deckOneCards() => <Card>[
    makeCard(
      id: 'c1',
      deckId: 'deck-1',
      front: 'Первая',
      tags: <String>['даты'],
      createdAt: cardsTime,
    ),
    makeCard(
      id: 'c2',
      deckId: 'deck-1',
      front: 'Вторая',
      tags: <String>['язык'],
      state: CardState.learning,
      due: DateTime.utc(2026, 11, 14, 9),
    ),
  ];

  List<Card> deckTwoCards() => <Card>[
    makeCard(
      id: 'b1',
      deckId: 'deck-2',
      front: 'Третья',
      cardType: CardType.cloze,
      tags: <String>['даты'],
      createdAt: cardsTime.add(const Duration(minutes: 1)),
    ),
  ];

  List<Override> overrides({List<SessionPreset> savedPresets = const <SessionPreset>[]}) {
    cards = FakeCardRepository(cards: <Card>[...deckOneCards(), ...deckTwoCards()]);
    decks = FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 2, newCards: 1),
        makeSummary(id: 'deck-2', name: 'Биология', totalCards: 1, newCards: 1),
      ],
    );
    presets = FakeSessionPresetRepository(presets: savedPresets);
    leeches = FakeLeechRepository();
    return decksOverrides(
      deckRepository: decks,
      cardRepository: cards,
      sessionPresetRepository: presets,
      leechRepository: leeches,
    );
  }

  String planLabel(Object? extra) {
    if (extra is! SessionPlan) return 'NO_PLAN';
    final String ids = extra.cards
        .map((Card card) => card.id)
        .join(',');
    final String budget = extra.timeBudget == null
        ? ''
        : '|${extra.timeBudget!.inMinutes}m';
    return 'PLAN:$ids$budget';
  }

  List<GoRoute> routes() => <GoRoute>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const SizedBox.shrink(),
    ),
    GoRoute(
      path: '/constructor',
      builder: (BuildContext context, GoRouterState state) =>
          SessionConstructorScreen(
            preselectedDeckId: state.uri.queryParameters['deck'],
          ),
    ),
    GoRoute(
      path: '/session/classic',
      builder: (BuildContext context, GoRouterState state) =>
          Text(planLabel(state.extra)),
    ),
    GoRoute(
      path: '/session/feed',
      builder: (BuildContext context, GoRouterState state) => Text(
        planLabel(state.extra),
      ),
    ),
  ];

  Future<void> pumpConstructor(
    WidgetTester tester, {
    required List<Override> overrideList,
    String location = '/constructor',
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: overrideList,
        routes: routes(),
        initialLocation: location,
      ),
    );
    await tester.pumpAndSettle();
  }

  bool chipSelected(WidgetTester tester, String key) =>
      tester.widget<FilterChip>(find.byKey(ValueKey<String>(key))).selected;

  bool startEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('constructor-start')),
          )
          .onPressed !=
      null;

  testWidgets('загрузка: колоды, предвыбор с экрана колоды, счётчик доступных', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(
      tester,
      overrideList: overrides(),
      location: '/constructor?deck=deck-1',
    );
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.constructorTitle), findsOneWidget);
    expect(find.text(l10n.constructorDecksSection), findsOneWidget);
    expect(find.text('Испанский'), findsOneWidget);
    expect(find.text('Биология'), findsOneWidget);
    expect(
      chipSelected(tester, 'constructor-deck-deck-1'),
      isTrue,
      reason: 'колода с экрана колоды предвыбрана',
    );
    expect(chipSelected(tester, 'constructor-deck-deck-2'), isFalse);
    expect(find.text(l10n.constructorAvailableCount(2)), findsOneWidget);
    expect(startEnabled(tester), isTrue);
    expect(
      leeches.requestedDecks.single.toSet(),
      <String>{'deck-1', 'deck-2'},
      reason: 'счётчики провалов запрошены для активных колод',
    );
    expect(
      find.text(l10n.constructorPresetsEmpty),
      findsOneWidget,
      reason: 'пресетов пока нет',
    );
  });

  testWidgets('старт: базовый порядок плана и переход в классику', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(
      tester,
      overrideList: overrides(),
      location: '/constructor?deck=deck-1',
    );

    await tester.tap(find.byKey(const ValueKey<String>('constructor-start')));
    await tester.pumpAndSettle();

    expect(
      find.text('PLAN:c2,c1'),
      findsOneWidget,
      reason: 'сначала карточка с due, затем новая (ADR-008)',
    );
  });

  testWidgets('фильтр по тегу ограничивает выборку', (WidgetTester tester) async {
    await pumpConstructor(tester, overrideList: overrides());
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('constructor-deck-deck-1')));
    await tester.tap(find.byKey(const ValueKey<String>('constructor-deck-deck-2')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.constructorAvailableCount(3)), findsOneWidget);
    expect(find.text(l10n.constructorTagsEmpty), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('constructor-tag-даты')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.constructorAvailableCount(2)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('constructor-start')));
    await tester.pumpAndSettle();
    expect(find.text('PLAN:c1,b1'), findsOneWidget);
  });

  testWidgets('фильтр по типу карточки', (WidgetTester tester) async {
    await pumpConstructor(tester, overrideList: overrides());
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('constructor-deck-deck-1')));
    await tester.tap(find.byKey(const ValueKey<String>('constructor-deck-deck-2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-type-cloze')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.constructorAvailableCount(1)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('constructor-start')));
    await tester.pumpAndSettle();
    expect(find.text('PLAN:b1'), findsOneWidget);
  });

  testWidgets('фильтр по состоянию', (WidgetTester tester) async {
    await pumpConstructor(tester, overrideList: overrides());
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('constructor-deck-deck-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-state-in_progress')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.constructorAvailableCount(1)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('constructor-start')));
    await tester.pumpAndSettle();
    expect(find.text('PLAN:c2'), findsOneWidget);
  });

  testWidgets('фильтр «Пиявки» берёт счётчики провалов', (
    WidgetTester tester,
  ) async {
    leeches = FakeLeechRepository(counts: <String, int>{'c1': 9});
    cards = FakeCardRepository(
      cards: <Card>[...deckOneCards(), ...deckTwoCards()],
    );
    decks = FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 2),
      ],
    );
    presets = FakeSessionPresetRepository();
    await pumpConstructor(
      tester,
      overrideList: decksOverrides(
        deckRepository: decks,
        cardRepository: cards,
        sessionPresetRepository: presets,
        leechRepository: leeches,
      ),
      location: '/constructor?deck=deck-1',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-state-leeches')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('constructor-start')));
    await tester.pumpAndSettle();

    expect(find.text('PLAN:c1'), findsOneWidget);
  });

  testWidgets('интерливинг чередует колоды', (WidgetTester tester) async {
    await pumpConstructor(tester, overrideList: overrides());

    await tester.tap(find.byKey(const ValueKey<String>('constructor-deck-deck-1')));
    await tester.tap(find.byKey(const ValueKey<String>('constructor-deck-deck-2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-interleave')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('constructor-start')));
    await tester.pumpAndSettle();

    expect(find.text('PLAN:c2,b1,c1'), findsOneWidget);
  });

  testWidgets('лимит минут: бюджет попадает в план', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(
      tester,
      overrideList: overrides(),
      location: '/constructor?deck=deck-1',
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-limit-minutes')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('constructor-limit-value')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.constructorLimitMinutesValue(5)).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('constructor-start')));
    await tester.pumpAndSettle();

    expect(find.text('PLAN:c2,c1|5m'), findsOneWidget);
  });

  testWidgets('сохранение пресета: диалог, конфиг в репозиторий, снекбар', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(
      tester,
      overrideList: overrides(),
      location: '/constructor?deck=deck-1',
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-save-preset')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.constructorPresetDialogTitle), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('constructor-preset-name')),
      'Утренняя',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-preset-submit')),
    );
    await tester.pumpAndSettle();

    expect(presets.savedNames, <String>['Утренняя']);
    final SessionConfig saved = presets.savedConfigs.single;
    expect(saved.deckIds, <String>['deck-1']);
    expect(saved.mode, SessionMode.classic);
    expect(saved.limit, const SessionLimit.cards(20));
    expect(find.text(l10n.constructorPresetSaved), findsOneWidget);
    expect(find.text('Утренняя'), findsOneWidget, reason: 'пресет в списке');
  });

  testWidgets('сохранение пресета: пустое имя — ошибка без записи', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(
      tester,
      overrideList: overrides(),
      location: '/constructor?deck=deck-1',
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-save-preset')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-preset-submit')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.constructorPresetNameEmpty), findsOneWidget);
    expect(presets.savedNames, isEmpty);
  });

  testWidgets('пресет применяется к форме и запускает свой режим', (
    WidgetTester tester,
  ) async {
    final SessionPreset preset = SessionPreset(
      id: 'preset-7',
      name: 'Биология на 10 минут',
      config: const SessionConfig(
        deckIds: <String>['deck-2'],
        mode: SessionMode.feed,
        limit: SessionLimit.minutes(10),
      ),
      createdAt: cardsTime,
    );
    await pumpConstructor(
      tester,
      overrideList: overrides(savedPresets: <SessionPreset>[preset]),
    );

    await tester.tap(find.byKey(const ValueKey<String>('constructor-preset-preset-7')));
    await tester.pumpAndSettle();

    expect(chipSelected(tester, 'constructor-deck-deck-2'), isTrue);
    expect(chipSelected(tester, 'constructor-deck-deck-1'), isFalse);
    await tester.tap(find.byKey(const ValueKey<String>('constructor-start')));
    await tester.pumpAndSettle();

    expect(find.text('PLAN:b1|10m'), findsOneWidget);
  });

  testWidgets('пресет удаляется', (WidgetTester tester) async {
    final SessionPreset preset = SessionPreset(
      id: 'preset-8',
      name: 'Старый',
      config: const SessionConfig(deckIds: <String>['deck-1']),
      createdAt: cardsTime,
    );
    await pumpConstructor(
      tester,
      overrideList: overrides(savedPresets: <SessionPreset>[preset]),
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-preset-delete-preset-8')),
    );
    await tester.pumpAndSettle();

    expect(presets.deletedIds, <String>['preset-8']);
    expect(find.text(l10n.constructorPresetDeleted), findsOneWidget);
    expect(find.text('Старый'), findsNothing);
    expect(find.text(l10n.constructorPresetsEmpty), findsOneWidget);
  });

  testWidgets('нет колод — пустое состояние, старт недоступен', (
    WidgetTester tester,
  ) async {
    cards = FakeCardRepository();
    decks = FakeDeckRepository();
    presets = FakeSessionPresetRepository();
    leeches = FakeLeechRepository();
    await pumpConstructor(
      tester,
      overrideList: decksOverrides(
        deckRepository: decks,
        cardRepository: cards,
        sessionPresetRepository: presets,
        leechRepository: leeches,
      ),
    );
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.constructorEmptyDecks), findsOneWidget);
    expect(startEnabled(tester), isFalse);
  });

  testWidgets('ошибка загрузки: сообщение и повтор', (
    WidgetTester tester,
  ) async {
    final List<Override> overrideList = overrides();
    decks.failSummaries = true;
    await pumpConstructor(tester, overrideList: overrideList);
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.constructorLoadError), findsOneWidget);

    decks.failSummaries = false;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();

    expect(find.text('Испанский'), findsOneWidget);
  });
}
