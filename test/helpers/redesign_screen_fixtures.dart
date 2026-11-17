import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/session/session_constructor_screen.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';

import 'decks_fakes.dart';
import 'generation_fakes.dart';
import 'pump_app.dart';
import 'settings_fakes.dart';

/// Экраны этапа 3 (REDESIGN-SPEC §9.1–9.4, 9.14–9.17).
enum NcStage3Screen {
  /// «Мои колоды» (§9.2).
  decks,

  /// Экран колоды (§9.3).
  deck,

  /// Новая карточка (§9.4).
  cardForm,

  /// Конструктор сессии (§9.14).
  constructor,

  /// Статистика (§9.15).
  statistics,

  /// Настройки (§9.16).
  settings,

  /// Провайдеры (§9.17).
  providers,
}

/// Данные фейкового каталога: три колоды с разными счётчиками.
List<DeckSummary> ncStage3DeckSummaries() => <DeckSummary>[
  makeSummary(
    id: 'deck-bio',
    name: 'Биология',
    totalCards: 18,
    newCards: 4,
    inProgressCards: 5,
    dueCards: 6,
  ),
  makeSummary(
    id: 'deck-stat',
    name: 'Статистика',
    totalCards: 12,
    newCards: 0,
    inProgressCards: 2,
    dueCards: 3,
  ),
  makeSummary(
    id: 'deck-hist',
    name: 'История искусства',
    totalCards: 7,
    newCards: 0,
    inProgressCards: 0,
    dueCards: 0,
  ),
];

/// Данные фейковой колоды «Биология»: типы, состояния, теги, LaTeX, cloze.
List<Card> ncStage3Cards() {
  final DateTime now = DateTime(2026, 11, 17, 12);
  final DateTime today = DateTime(now.year, now.month, now.day);
  return <Card>[
    makeCard(
      id: 'card-1',
      deckId: 'deck-bio',
      front: 'Какой пигмент придаёт листьям зелёный цвет?',
      back: 'Хлорофилл',
      tags: <String>['биология'],
      state: CardState.review,
      due: today,
      createdAt: now,
      updatedAt: now,
    ),
    makeCard(
      id: 'card-2',
      deckId: 'deck-bio',
      front: 'Что такое фотосинтез?',
      back: 'Преобразование световой энергии в химическую',
      state: CardState.newCard,
      createdAt: now,
      updatedAt: now,
    ),
    makeCard(
      id: 'card-3',
      deckId: 'deck-bio',
      front: r'Формула фотосинтеза $6CO_2 + 6H_2O → C_6H_{12}O_6$',
      back: 'Глюкоза и кислород',
      state: CardState.learning,
      createdAt: now,
      updatedAt: now,
    ),
    makeCard(
      id: 'card-4',
      deckId: 'deck-bio',
      front: 'Деление клетки — {{c1::митоз}}',
      back: 'Митоз',
      cardType: CardType.cloze,
      state: CardState.review,
      due: today,
      createdAt: now,
      updatedAt: now,
    ),
    makeCard(
      id: 'card-5',
      deckId: 'deck-bio',
      front: 'Где синтезируется АТФ?',
      back: 'В митохондриях',
      state: CardState.relearning,
      tags: <String>['клетка'],
      createdAt: now,
      updatedAt: now,
    ),
    makeCard(
      id: 'card-6',
      deckId: 'deck-bio',
      front: 'Что хранит наследственную информацию?',
      back: 'ДНК',
      state: CardState.review,
      due: today.add(const Duration(days: 3)),
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

/// Снимок статистики с данными (удержание, карта, прогноз, слабые темы).
StatisticsSnapshot ncStage3Statistics() {
  final DateTime now = DateTime(2026, 11, 17, 12);
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<ReviewSample> reviews = <ReviewSample>[
    for (var index = 0; index < 24; index++)
      ReviewSample(
        cardId: index.isEven ? 'card-1' : 'card-2',
        rating: index % 5 == 0 ? 1 : 3,
        reviewedAt: today.subtract(Duration(days: index)),
      ),
  ];
  return StatisticsCalculator.build(
    reviews: reviews,
    tagsByCard: const <String, List<String>>{
      'card-1': <String>['биология'],
      'card-2': <String>['термины'],
      'card-3': <String>['формулы'],
    },
    dueDates: <DateTime>[
      today,
      today.add(const Duration(days: 2, hours: 9)),
      today.add(const Duration(days: 3, hours: 18)),
      today.add(const Duration(days: 5, hours: 12)),
    ],
    now: today.add(const Duration(hours: 12)),
  );
}

/// Фейковый data-слой этапа 3 для стенда экрана.
List<Override> ncStage3Overrides({
  List<DeckSummary>? summaries,
  List<Card>? cards,
  StatisticsSnapshot? statistics,
  AppSettings? settings,
}) => decksOverrides(
  deckRepository: FakeDeckRepository(
    summaries: summaries ?? ncStage3DeckSummaries(),
  ),
  cardRepository: FakeCardRepository(cards: cards ?? ncStage3Cards()),
  statisticsRepository: FakeStatisticsRepository(
    snapshot: statistics ?? ncStage3Statistics(),
    tokens: 12400,
  ),
  appSettingsStore: FakeAppSettingsStore(
    settings: settings ?? AppSettings.defaults,
  ),
  providerAccountsStore: FakeProviderAccountsStore(),
);

/// Экран этапа на стандартных фейках.
Widget ncStage3Home(NcStage3Screen screen) => switch (screen) {
  NcStage3Screen.decks => const DecksScreen(),
  NcStage3Screen.deck => const DeckScreen(deckId: 'deck-bio'),
  NcStage3Screen.cardForm => const CardFormScreen(deckId: 'deck-bio'),
  NcStage3Screen.constructor => const SessionConstructorScreen(),
  NcStage3Screen.statistics => const StatisticsScreen(),
  NcStage3Screen.settings => const SettingsScreen(),
  NcStage3Screen.providers => const GenerationSettingsScreen(),
};
