@Tags(<String>['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_screen_harness.dart';
import '../helpers/redesign_screen_fixtures.dart';

/// Golden-эталоны экранов этапа 3 (REDESIGN-SPEC §9, тег `golden`).
///
/// По два снимка на экран — тёмная Nocturne и светлая Porcelain, телефон
/// 390 × 844. Шрифты Onest/Literata/JetBrainsMono подкладываются явно.
/// Эталоны сняты на Windows (единственная доступная платформа, L98).
void main() {
  setUpAll(loadNcFonts);

  final Map<String, Widget Function()> screens = <String, Widget Function()>{
    'decks': DecksScreen.new,
    'deck': () => const DeckScreen(deckId: 'deck-bio'),
    'card-form': () => const CardFormScreen(deckId: 'deck-bio'),
  };

  for (final MapEntry<String, Widget Function()> screen in screens.entries) {
    for (final Brightness brightness in Brightness.values) {
      final String themeName = brightness == Brightness.dark ? 'dark' : 'light';
      testWidgets('${screen.key} $themeName', (WidgetTester tester) async {
        await pumpNcScreen(
          tester,
          home: screen.value(),
          overrides: ncStage3Overrides(),
          config: NcScreenConfig(
            brightness: brightness,
            size: const Size(390, 844),
          ),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/screens/${screen.key}_$themeName.png'),
        );
      });
    }
  }
}
