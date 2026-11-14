import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/review/feed_progress_bar.dart';

import '../../helpers/pump_app.dart';

/// A6.6: «Стандартная» анимация отключает пульс Stories (ADR-019 §2).
void main() {
  Widget bar({required bool animate}) {
    return appWithHome(
      overrides: const <Override>[],
      home: Scaffold(
        body: FeedProgressBar(
          rated: const <bool>[false, false, false],
          currentIndex: 0,
          animatePulse: animate,
        ),
      ),
    );
  }

  testWidgets('выразительная анимация: текущий сегмент пульсирует', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(bar(animate: true));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey<String>('feed-progress-pulse')),
      findsOneWidget,
    );
  });

  testWidgets('стандартная анимация: пульса нет', (WidgetTester tester) async {
    await tester.pumpWidget(bar(animate: false));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey<String>('feed-progress-pulse')),
      findsNothing,
    );
    expect(find.byType(FeedProgressBar), findsOneWidget);
  });
}
