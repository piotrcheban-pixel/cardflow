// Скриншоты редизайна «Nocturne», этап 1 (фундамент).
//
//   fvm flutter test tool/screenshots/redesign1_test.dart --no-pub --update-goldens
//
// Каталог `tool/` не входит в CI: прогон ручной. Шрифты Onest/Literata/
// JetBrains Mono грузятся из `assets/fonts/` (не Segoe UI, как в старом
// харнессе), поэтому скриншоты показывают реальную типографику Nocturne.
// Файлы складываются в `tool/screenshots/screens/` и копируются в
// `journal/redesign-1/screenshots/`.
@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/design/ambient/ambient_background.dart';
import 'package:cardflow/ui/design/haptics.dart';
import 'package:cardflow/ui/design/motion_scope.dart';
import 'package:cardflow/ui/generation/generation_screen.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/review/feed_session_screen.dart';
import 'package:cardflow/ui/review/practice_session_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/session/session_constructor_screen.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';
import 'package:cardflow/ui/study/match_screen.dart';
import 'package:cardflow/ui/study/multiple_choice_screen.dart';
import 'package:cardflow/ui/study/true_false_screen.dart';
import 'package:cardflow/ui/study/typing_screen.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/settings_fakes.dart';
import '../../test/helpers/pump_app.dart';

final DateTime _now = DateTime.utc(2026, 11, 17, 12);

/// Реальные шрифты Nocturne из ассетов + MaterialIcons.
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
}

List<Card> _cards() => <Card>[
  for (final (String front, String back) in <(String, String)>[
    ('Какой пигмент придаёт листьям зелёный цвет?', 'Хлорофилл'),
    ('Что такое фотосинтез?', 'Преобразование световой энергии в химическую'),
    ('Где синтезируется АТФ?', 'В митохондриях'),
    ('Как называется деление клетки?', 'Митоз'),
    ('Что хранит наследственную информацию?', 'ДНК'),
  ])
    makeCard(
      id: 'card-${front.hashCode.abs()}',
      deckId: 'deck-1',
      front: front,
      back: back,
      createdAt: _now,
      updatedAt: _now,
    ),
];

StatisticsSnapshot _statistics() {
  final DateTime today = DateTime(_now.year, _now.month, _now.day);
  final List<ReviewSample> reviews = <ReviewSample>[
    for (int index = 0; index < 8; index++)
      ReviewSample(
        cardId: index.isEven ? 'card-a' : 'card-b',
        rating: index.isEven ? 3 : 1,
        reviewedAt: today.subtract(Duration(days: index)),
      ),
  ];
  return StatisticsCalculator.build(
    reviews: reviews,
    tagsByCard: const <String, List<String>>{
      'card-a': <String>['биология'],
      'card-b': <String>['термины'],
    },
    dueDates: <DateTime>[
      today,
      today.add(const Duration(days: 2, hours: 9)),
      today.add(const Duration(days: 3, hours: 18)),
    ],
    now: today.add(const Duration(hours: 12)),
  );
}

/// Обвязка как в корне приложения: тема Nocturne + движение/отклик + Aurora.
Widget _app(Widget home, Brightness brightness) {
  final ThemeData theme = brightness == Brightness.dark
      ? AppTheme.dark()
      : AppTheme.light();
  return ProviderScope(
    overrides: decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Биология',
            totalCards: 5,
            dueCards: 3,
          ),
        ],
      ),
      cardRepository: FakeCardRepository(cards: _cards()),
      reviewRepository: FakeReviewRepository()..previousCard = _cards().first,
      statisticsRepository: FakeStatisticsRepository(snapshot: _statistics()),
    ),
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

Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screens/$name.png'),
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
    'generation': GenerationScreen.new,
    'review': _reviewScreen,
    'feed': _feedScreen,
    'practice': _practiceScreen,
    'test': _testScreen,
    'typing': _typingScreen,
    'match': _matchScreen,
    'true-false': _trueFalseScreen,
  };

  const Map<String, (double, double)> sizes = <String, (double, double)>{
    'phone': (390, 844),
    'desktop': (1440, 900),
  };

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
          await tester.pump(const Duration(milliseconds: 400));
          await _capture(
            tester,
            '${screen.key}-${brightness.name}-${size.key}',
          );
        });
      }
    }
  }
}

Widget _deckScreen() => const DeckScreen(deckId: 'deck-1');

Widget _cardForm() => const CardFormScreen(deckId: 'deck-1');

Widget _reviewScreen() => const ReviewSessionScreen(deckId: 'deck-1');

Widget _feedScreen() => const FeedSessionScreen(deckId: 'deck-1');

Widget _practiceScreen() => const PracticeSessionScreen(deckId: 'deck-1');

Widget _testScreen() => const MultipleChoiceScreen(deckId: 'deck-1');

Widget _typingScreen() => const TypingScreen(deckId: 'deck-1');

Widget _matchScreen() => const MatchScreen(deckId: 'deck-1');

Widget _trueFalseScreen() => const TrueFalseScreen(deckId: 'deck-1');
