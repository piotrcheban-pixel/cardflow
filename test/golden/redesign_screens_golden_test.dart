@Tags(<String>['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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

  for (final Brightness brightness in Brightness.values) {
    final String themeName = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('decks $themeName', (WidgetTester tester) async {
      await pumpNcScreen(
        tester,
        home: const DecksScreen(),
        overrides: ncStage3Overrides(),
        config: NcScreenConfig(
          brightness: brightness,
          size: const Size(390, 844),
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/screens/decks_$themeName.png'),
      );
    });
  }
}
