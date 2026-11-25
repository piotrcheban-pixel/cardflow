import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/decks/deck_modes_sheet.dart';

import '../../helpers/pump_app.dart';

/// TASK 04 / ADR-046, M-03: нижние листы.
///
/// Контракт:
/// * высокий лист открывается на 72 % высоты (а не на 98 %);
/// * свайп вниз по содержимому закрывает его, а не только drag handle;
/// * фон листа не перекрывает экран прозрачным слоем;
/// * «Начать сессию» (лист режимов) использует тот же фрейм.
void main() {
  Widget host({
    required Size size,
    required void Function(BuildContext) onOpen,
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: FilledButton(
                key: const ValueKey<String>('open-sheet'),
                onPressed: () => onOpen(context),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('высокий лист: 72 %, закрывается свайпом по содержимому', (
    WidgetTester tester,
  ) async {
    const Size size = Size(390, 844);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        size: size,
        onOpen: (BuildContext context) {
          showAppDetentSheet<void>(
            context: context,
            builder: (BuildContext sheetContext, ScrollController controller) {
              return ListView(
                key: const ValueKey<String>('sheet-content'),
                controller: controller,
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  for (int index = 0; index < 24; index++)
                    SizedBox(height: 56, child: Text('Строка $index')),
                ],
              );
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('open-sheet')));
    await tester.pumpAndSettle();

    final Finder sheet = find.byKey(const ValueKey<String>('app-detent-sheet'));
    expect(sheet, findsOneWidget);
    final Rect rect = tester.getRect(sheet);
    expect(rect.top, greaterThan(size.height * 0.15));
    expect(
      rect.height,
      lessThanOrEqualTo(size.height * 0.8),
      reason: 'лист открылся почти на весь экран: ${rect.height}',
    );
    expect(rect.height, greaterThan(size.height * 0.5));

    // Свайп вниз по содержимому (не по handle): лист уменьшается и
    // закрывается, когда доходит до минимума.
    await tester.drag(
      find.byKey(const ValueKey<String>('sheet-content')),
      const Offset(0, 520),
    );
    await tester.pumpAndSettle();
    expect(sheet, findsNothing, reason: 'лист не закрылся свайпом вниз');
    expect(find.text('Строка 0'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('лист режимов — тот же фрейм и закрывается свайпом', (
    WidgetTester tester,
  ) async {
    const Size size = Size(390, 844);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        size: size,
        onOpen: (BuildContext context) {
          showDeckModesSheet(
            context,
            availability: const DeckModeAvailability(
              testCount: 1,
              typingCount: 1,
              matchableCount: 6,
              trueFalseCount: 1,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('open-sheet')));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = l10nOf(tester);
    expect(find.text(l10n.reviewSessionModeTitle), findsOneWidget);
    final Rect sheet = tester.getRect(
      find.byKey(const ValueKey<String>('app-detent-sheet')),
    );
    expect(sheet.height, lessThanOrEqualTo(size.height * 0.8));

    await tester.drag(
      find.byKey(const ValueKey<String>('deck-modes-list')),
      const Offset(0, 520),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.reviewSessionModeTitle),
      findsNothing,
      reason: 'лист режимов не закрылся свайпом',
    );
  }, timeout: const Timeout(Duration(seconds: 180)));
}
