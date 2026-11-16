import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/nc_harness.dart';

/// Поведение прогресса Nocturne (REDESIGN-SPEC §8, шаг 2.6):
/// `NcProgressLine`, `NcSegmentedProgress`, `NcRing`, `NcAnimatedNumber`.
void main() {
  final AppLocalizations l10n = ncL10n;

  group('NcProgressLine', () {
    testWidgets('семантика прогресса и пружина без overshoot', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      double value = 0.2;
      late StateSetter setState;
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setter) {
            setState = setter;
            return SizedBox(
              width: 300,
              child: NcProgressLine(
                value: value,
                semanticLabel: l10n.reviewProgressLabel,
              ),
            );
          },
        ),
        config: const NcTestConfig(
          motion: NcMotionPreference.standard,
          size: Size(420, 200),
        ),
      );
      expect(find.bySemanticsLabel(l10n.reviewProgressLabel), findsWidgets);
      final double startWidth = tester
          .getSize(find.byKey(NcProgressLine.fillKey))
          .width;
      expect(startWidth, closeTo(60, 1));
      setState(() => value = 0.8);
      final List<double> widths = <double>[];
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        widths.add(tester.getSize(find.byKey(NcProgressLine.fillKey)).width);
      }
      expectNoOvershoot(widths, min: 60, max: 240, tolerance: 0.02);
      expect(widths.last, closeTo(240, 1));
      semantics.dispose();
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcProgressLine(value: 0.5),
        config: const NcTestConfig(size: Size(420, 200)),
      );
    });
  });

  group('NcSegmentedProgress', () {
    testWidgets('сегменты: пройденные залиты, текущий пульсирует', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpNc(
        tester,
        SizedBox(
          width: 300,
          child: NcSegmentedProgress(
            total: 6,
            current: 2,
            rated: 2,
            ratingColors: <int, Color>{0: const Color(0xFFF0806B)},
            semanticLabel: l10n.feedProgressSemantics(2, 6),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(
        find.bySemanticsLabel(l10n.feedProgressSemantics(2, 6)),
        findsWidgets,
      );
      final Finder pulse = find.byKey(
        const ValueKey<String>('nc-segmented-progress-pulse'),
      );
      expect(pulse, findsOneWidget);
      final double before = tester.getSize(pulse).width;
      await tester.pump(const Duration(milliseconds: 1000));
      final double after = tester.getSize(pulse).width;
      expect(tester.takeException(), isNull);
      expect(after, lessThanOrEqualTo(before));
      semantics.dispose();
    });

    testWidgets('при уменьшении движения пульса нет (без кадров)', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        SizedBox(
          width: 300,
          child: NcSegmentedProgress(
            total: 4,
            current: 1,
            semanticLabel: l10n.feedProgressSemantics(1, 4),
          ),
        ),
        config: const NcTestConfig(reduceMotion: true, size: Size(420, 200)),
        settle: true,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        SizedBox(width: 300, child: NcSegmentedProgress(total: 10, current: 3)),
        config: const NcTestConfig(size: Size(420, 200)),
      );
    });
  });

  group('NcRing', () {
    testWidgets('кольцо держит размер, центр и семантику', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpNc(
        tester,
        NcRing(
          value: 0.75,
          size: 180,
          semanticLabel: l10n.statisticsRetentionTitle,
          child: NcAnimatedNumber(
            value: 75,
            style: const TextStyle(fontSize: 40),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 400)),
        settle: true,
      );
      expect(tester.getSize(find.byType(NcRing)).width, 180);
      expect(
        find.bySemanticsLabel(l10n.statisticsRetentionTitle),
        findsWidgets,
      );
      expect(find.byType(NcAnimatedNumber), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcRing(
          value: 0.4,
          size: 120,
          child: Text(l10n.statisticsRetentionValue(40)),
        ),
        config: const NcTestConfig(size: Size(420, 320)),
      );
    });
  });

  group('NcAnimatedNumber', () {
    testWidgets('считает от 0 к значению и завершает на нём', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpNc(
        tester,
        NcAnimatedNumber(
          value: 100,
          semanticLabel: l10n.statisticsRetentionValue(100),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      String text() => tester
          .widget<Text>(
            find.descendant(
              of: find.byType(NcAnimatedNumber),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(int.parse(text()), 0);
      await tester.pump(const Duration(milliseconds: 400));
      final int middle = int.parse(text());
      expect(middle, greaterThan(0));
      expect(middle, lessThan(100));
      await tester.pump(const Duration(milliseconds: 700));
      expect(text(), '100');
      expect(
        find.bySemanticsLabel(l10n.statisticsRetentionValue(100)),
        findsWidgets,
      );
      semantics.dispose();
    });

    testWidgets('форматирование значения уважается', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcAnimatedNumber(
          value: 42,
          duration: Duration.zero,
          format: (num value) => '${value.round()} 000',
        ),
        config: const NcTestConfig(size: Size(420, 200)),
        settle: true,
      );
      expect(find.text('42 000'), findsOneWidget);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcAnimatedNumber(value: 1234, duration: Duration.zero),
        config: const NcTestConfig(size: Size(420, 200)),
      );
    });
  });
}
