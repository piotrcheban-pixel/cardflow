import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/feed_progress_bar.dart';

import '../../helpers/pump_app.dart';

/// Прогресс ленты: позиция без оценок и без постоянной анимации (ADR-044).
void main() {
  Widget bar({
    required int total,
    required int current,
    ValueChanged<int>? onSeek,
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: Scaffold(
        body: FeedProgressBar(
          total: total,
          currentIndex: current,
          onSeek: onSeek,
        ),
      ),
    );
  }

  testWidgets('сегмент на карточку, текущий выше остальных', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(bar(total: 3, current: 1));
    await tester.pumpAndSettle();

    // Аудит 2.0 (P2-26): полоса стала заметнее (10/7 px), а её зона нажатия —
    // 44 px по высоте, иначе сегмент нельзя было ни нажать, ни задеть пальцем.
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('feed-progress-segment-1')),
          )
          .height,
      10,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('feed-progress-segment-0')),
          )
          .height,
      7,
    );
    expect(find.byType(FeedProgressBar), findsOneWidget);
  });

  testWidgets('счётчик позиции и семантика', (WidgetTester tester) async {
    await tester.pumpWidget(bar(total: 4, current: 2));
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.reviewCardCounter(3, 4)), findsOneWidget);
  });

  testWidgets('клик по сегменту переходит к карточке (onSeek)', (
    WidgetTester tester,
  ) async {
    int? seeked;
    await tester.pumpWidget(
      bar(total: 3, current: 0, onSeek: (int index) => seeked = index),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('feed-progress-segment-2')),
    );
    await tester.pumpAndSettle();
    expect(seeked, 2);
  });

  testWidgets('нет постоянной анимации: кадры после settle не тикают', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(bar(total: 2, current: 0));
    await tester.pumpAndSettle();
    // Падающий тест при повторяющейся анимации: pumpAndSettle зависает —
    // здесь он завершился, значит пульса нет.
    expect(tester.hasRunningAnimations, isFalse);
  });
}
