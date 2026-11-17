// Скриншоты редизайна «Nocturne», этап 3 (экраны каталога).
//
//   fvm flutter test tool/screenshots/redesign3_test.dart --no-pub --update-goldens
//   fvm flutter test tool/screenshots/redesign3_test.dart --no-pub --update-goldens --plain-name "shell"
//
// Каталог `tool/` не входит в CI: прогон ручной. Шрифты Onest/Literata/
// JetBrains Mono грузятся из `assets/fonts/`, поэтому снимки показывают
// реальную типографику Nocturne. Файлы складываются в
// `tool/screenshots/screens3/` и копируются в `journal/redesign-3/screenshots/`.
@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/design/ambient/ambient_background.dart';
import 'package:cardflow/ui/design/haptics.dart';
import 'package:cardflow/ui/design/motion_scope.dart';
import 'package:cardflow/ui/session/session_constructor_screen.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/domain/settings/app_settings.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/generation_fakes.dart';
import '../../test/helpers/katex_fonts.dart';
import '../../test/helpers/pump_app.dart';
import '../../test/helpers/settings_fakes.dart';

final DateTime _now = DateTime.utc(2026, 11, 17, 12);

Future<void> _loadFonts() async {
  const Map<String, String> families = <String, String>{
    'Onest': 'assets/fonts/Onest/Onest-Variable.ttf',
    'Literata': 'assets/fonts/Literata/Literata-Variable.ttf',
    'JetBrainsMono': 'assets/fonts/JetBrainsMono/JetBrainsMono-Variable.ttf',
    'OpenDyslexic': 'assets/fonts/OpenDyslexic-Regular.otf',
  };
  for (final MapEntry<String, String> entry in families.entries) {
    final File file = File(entry.value);
    if (!file.existsSync()) continue;
    final FontLoader loader = FontLoader(entry.key);
    loader.addFont(
      Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
    );
    await loader.load();
  }
  final File icons = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\piotr\fvm\versions\3.47.9'}'
    '\\bin\\cache\\artifacts\\material_fonts\\materialicons-regular.otf',
  );
  if (icons.existsSync()) {
    final FontLoader iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(
      Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
    );
    await iconLoader.load();
  }
  await loadKatexFonts();
}

List<DeckSummary> _decks() => <DeckSummary>[
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

List<Card> _cards() {
  final DateTime today = DateTime(_now.year, _now.month, _now.day);
  return <Card>[
    makeCard(
      id: 'card-1',
      deckId: 'deck-bio',
      front: 'Какой пигмент придаёт листьям зелёный цвет?',
      back: 'Хлорофилл',
      tags: <String>['биология'],
      state: CardState.review,
      due: today,
    ),
    makeCard(
      id: 'card-2',
      deckId: 'deck-bio',
      front: 'Что такое фотосинтез?',
      back: 'Преобразование световой энергии в химическую',
      state: CardState.newCard,
    ),
    makeCard(
      id: 'card-3',
      deckId: 'deck-bio',
      front: r'Формула фотосинтеза $6CO_2 + 6H_2O → C_6H_{12}O_6$',
      back: 'Глюкоза и кислород',
      state: CardState.learning,
    ),
    makeCard(
      id: 'card-4',
      deckId: 'deck-bio',
      front: 'Деление клетки — {{c1::митоз}}',
      back: 'Митоз',
      cardType: CardType.cloze,
      state: CardState.review,
      due: today,
    ),
    makeCard(
      id: 'card-5',
      deckId: 'deck-bio',
      front: 'Где синтезируется АТФ?',
      back: 'В митохондриях',
      state: CardState.relearning,
      tags: <String>['клетка'],
    ),
    makeCard(
      id: 'card-6',
      deckId: 'deck-bio',
      front: 'Что хранит наследственную информацию?',
      back: 'ДНК',
      state: CardState.review,
      due: today.add(const Duration(days: 3)),
    ),
  ];
}

StatisticsSnapshot _statistics() {
  final DateTime today = DateTime(_now.year, _now.month, _now.day);
  final List<ReviewSample> reviews = <ReviewSample>[
    for (int index = 0; index < 24; index++)
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

List<Override> _overrides({AppSettings? settings}) => decksOverrides(
  deckRepository: FakeDeckRepository(summaries: _decks()),
  cardRepository: FakeCardRepository(cards: _cards()),
  statisticsRepository: FakeStatisticsRepository(snapshot: _statistics()),
  appSettingsStore: FakeAppSettingsStore(
    settings: settings ?? AppSettings.defaults,
  ),
  providerAccountsStore: FakeProviderAccountsStore(),
);

/// Обвязка как в корне приложения: тема Nocturne + движение/отклик + Aurora.
Widget _app(Widget home, Brightness brightness) {
  final ThemeData theme = brightness == Brightness.dark
      ? AppTheme.dark()
      : AppTheme.light();
  return ProviderScope(
    overrides: _overrides(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const <Locale>[Locale('ru')],
      localizationsDelegates: ruLocalizationDelegates,
      theme: theme,
      builder: (BuildContext context, Widget? child) {
        return NcMotionScope(
          motion: NcMotion.resolve(),
          child: NcHapticsScope(
            haptics: NcHaptics(enabled: false),
            child: NcAmbientBackground(
              child: M3ETheme(
                data: M3EThemeData.fromMaterial(Theme.of(context)),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      home: home,
    ),
  );
}

/// Полное приложение (оболочка + ветки) для снимков этапа 3.1.
Widget _shellApp(Brightness brightness) {
  final AppSettings settings = AppSettings.defaults.copyWith(
    theme: brightness == Brightness.dark
        ? AppThemePreference.dark
        : AppThemePreference.light,
  );
  return ProviderScope(
    overrides: _overrides(settings: settings),
    child: const CardFlowApp(),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screens3/$name.png'),
  );
}

void main() {
  setUpAll(_loadFonts);

  const Map<String, Widget Function()> screens = <String, Widget Function()>{
    'decks': DecksScreen.new,
    'deck': _deckScreen,
    'card-form': _cardForm,
    'constructor': SessionConstructorScreen.new,
    'statistics': StatisticsScreen.new,
    'settings': SettingsScreen.new,
    'providers': GenerationSettingsScreen.new,
  };

  const Map<String, (double, double)> sizes = <String, (double, double)>{
    'phone': (390, 844),
    'tablet': (800, 1000),
    'desktop': (1440, 900),
  };

  // Оболочка: полное приложение (router + ветки).
  for (final Brightness brightness in Brightness.values) {
    for (final MapEntry<String, (double, double)> size in sizes.entries) {
      testWidgets('shell ${brightness.name} ${size.key}', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = Size(size.value.$1, size.value.$2);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_shellApp(brightness));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await _capture(tester, 'shell-${brightness.name}-${size.key}');
      });
    }
  }

  for (final MapEntry<String, Widget Function()> screen in screens.entries) {
    for (final Brightness brightness in Brightness.values) {
      for (final MapEntry<String, (double, double)> size in sizes.entries) {
        testWidgets('${screen.key} ${brightness.name} ${size.key}', (
          WidgetTester tester,
        ) async {
          tester.view.physicalSize = Size(size.value.$1, size.value.$2);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(_app(screen.value(), brightness));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await _capture(
            tester,
            '${screen.key}-${brightness.name}-${size.key}',
          );
        });
      }
    }
  }
}

Widget _deckScreen() => const DeckScreen(deckId: 'deck-bio');

Widget _cardForm() => const CardFormScreen(deckId: 'deck-bio');
