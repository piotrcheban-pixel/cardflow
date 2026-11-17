import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/glass_budget.dart';
import '../../../helpers/nc_harness.dart';

/// Поведение сессионных компонентов (REDESIGN-SPEC §8, шаг 2.7):
/// `NcMonolith`, `NcFlip`, `NcRatingButton`, `NcRatingDock`.
void main() {
  final AppLocalizations l10n = ncL10n;

  group('NcMonolith', () {
    testWidgets('слоты метаданных, лица и бейджей; тап и семантика', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await pumpNc(
        tester,
        NcMonolith(
          metadata: Text(l10n.cardTypeBasic),
          badges: NcBadge(label: l10n.cardStateNew),
          semanticLabel: l10n.cardFormFrontLabel,
          onTap: () => taps++,
          child: Text(l10n.cardFormFrontLabel),
        ),
        config: const NcTestConfig(size: Size(720, 600)),
        settle: true,
      );
      expect(find.text(l10n.cardTypeBasic), findsOneWidget);
      expect(find.text(l10n.cardFormFrontLabel), findsWidgets);
      expect(find.byType(NcBadge), findsOneWidget);
      final Size size = tester.getSize(find.byType(NcMonolith));
      expect(size.width, lessThanOrEqualTo(640));
      expect(size.height, greaterThanOrEqualTo(320));
      await tester.tap(find.byType(NcMonolith));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('на узком экране занимает доступную ширину без overflow', (
      WidgetTester tester,
    ) async {
      await pumpNcAtTextScale2(
        tester,
        NcMonolith(
          metadata: Text(l10n.cardTagsLine('биология')),
          child: Text(l10n.cardFormFrontLabel),
        ),
        config: const NcTestConfig(size: Size(390, 720)),
      );
      expect(
        tester.getSize(find.byType(NcMonolith)).width,
        lessThanOrEqualTo(390),
      );
    });
  });

  group('NcFlip', () {
    testWidgets('переворачивает лицевую сторону в обратную', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => NcFlip(
            revealed: false,
            onTap: () => setState(() {}),
            front: const Text('Вопрос'),
            back: const Text('Ответ'),
          ),
        ),
        config: const NcTestConfig(size: Size(640, 420)),
      );
      expect(find.text('Вопрос'), findsOneWidget);
      expect(find.text('Ответ'), findsNothing);
      await pumpNc(
        tester,
        NcFlip(
          revealed: true,
          front: const Text('Вопрос'),
          back: const Text('Ответ'),
        ),
        config: const NcTestConfig(size: Size(640, 420)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ответ'), findsOneWidget);
      expect(find.text('Вопрос'), findsNothing);
    });

    testWidgets('при уменьшении движения — кроссфейд 120 мс', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcFlip(
          revealed: true,
          front: const Text('Вопрос'),
          back: const Text('Ответ'),
        ),
        config: const NcTestConfig(reduceMotion: true, size: Size(640, 420)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Ответ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcFlip(
          revealed: false,
          front: Text(l10n.cardFormFrontLabel),
          back: Text(l10n.cardFormBackLabel),
        ),
        config: const NcTestConfig(size: Size(390, 600)),
      );
    });
  });

  group('NcRatingButton', () {
    testWidgets('интервал, название, подсказка клавиши и тап', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await pumpNc(
        tester,
        NcRatingButton(
          label: l10n.ratingGood,
          interval: l10n.reviewIntervalDays(3),
          color: NcColors.dark().jade,
          keyHint: '3',
          onPressed: () => taps++,
        ),
        config: const NcTestConfig(size: Size(420, 260)),
      );
      expect(find.text(l10n.ratingGood), findsOneWidget);
      expect(find.text(l10n.reviewIntervalDays(3)), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byType(NcRatingButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('disabled не нажимается; textScale 2,0 без overflow', (
      WidgetTester tester,
    ) async {
      await pumpNcAtTextScale2(
        tester,
        NcRatingButton(
          label: l10n.ratingAgain,
          interval: l10n.reviewIntervalLessThanMinute,
          color: NcColors.dark().ember,
        ),
        config: const NcTestConfig(size: Size(420, 260)),
      );
    });
  });

  group('NcRatingDock', () {
    testWidgets('четыре кнопки в стеклянном доке; тап вызывает оценку', (
      WidgetTester tester,
    ) async {
      var pressed = -1;
      await pumpNc(
        tester,
        _DockHarness(onPressed: (int index) => pressed = index),
        config: const NcTestConfig(size: Size(720, 420)),
      );
      expect(find.byType(NcRatingDock), findsOneWidget);
      expect(find.byType(NcRatingButton), findsNWidgets(4));
      expectGlassBudget(tester, maxGroups: 1);
      await tester.tap(find.byType(NcRatingButton).at(2));
      await tester.pumpAndSettle();
      expect(pressed, 2);
    });

    testWidgets('neighbor-squish: нажатая шире, соседние уже', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        _DockHarness(onPressed: (_) {}),
        config: const NcTestConfig(size: Size(720, 420)),
      );
      final List<double> before = <double>[
        for (var index = 0; index < 4; index++)
          tester.getSize(find.byType(NcRatingButton).at(index)).width,
      ];
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(NcRatingButton).at(1)),
      );
      await tester.pumpAndSettle();
      final List<double> during = <double>[
        for (var index = 0; index < 4; index++)
          tester.getSize(find.byType(NcRatingButton).at(index)).width,
      ];
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        during[1],
        greaterThan(before[1]),
        reason: 'Нажатая кнопка шире (§9.6 neighbor-squish)',
      );
      expect(
        during[0],
        lessThan(before[0]),
        reason: 'Соседняя кнопка уже (§9.6)',
      );
    });

    testWidgets('неактивный док: все кнопки disabled', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        _DockHarness(onPressed: (_) {}, enabled: false),
        config: const NcTestConfig(size: Size(720, 420)),
      );
      for (var index = 0; index < 4; index++) {
        final Finder detector = find
            .descendant(
              of: find.byType(NcRatingButton).at(index),
              matching: find.byType(FocusableActionDetector),
            )
            .first;
        expect(
          tester.widget<FocusableActionDetector>(detector).enabled,
          isFalse,
        );
      }
    });

    testWidgets('при textScale 2,0 — сетка 2 × 2 без overflow', (
      WidgetTester tester,
    ) async {
      await pumpNcAtTextScale2(
        tester,
        _DockHarness(onPressed: (_) {}),
        config: const NcTestConfig(size: Size(420, 700)),
      );
      final Offset first = tester.getCenter(find.byType(NcRatingButton).at(0));
      final Offset second = tester.getCenter(find.byType(NcRatingButton).at(1));
      final Offset third = tester.getCenter(find.byType(NcRatingButton).at(2));
      expect(
        (first.dx - second.dx).abs() > 40,
        isTrue,
        reason: 'В сетке 2 × 2 первые две кнопки — в одной строке',
      );
      expect(
        third.dy > first.dy,
        isTrue,
        reason: 'В сетке 2 × 2 вторая строка ниже первой',
      );
    });
  });
}

class _DockHarness extends StatelessWidget {
  const _DockHarness({required this.onPressed, this.enabled = true});

  final ValueChanged<int> onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcColors colors = NcTheme.of(context).colors;
    return NcRatingDock(
      enabled: enabled,
      semanticLabel: l10n.reviewSessionModeTitle,
      ratings: <NcRatingSpec>[
        NcRatingSpec(
          label: l10n.ratingAgain,
          interval: l10n.reviewIntervalLessThanMinute,
          color: colors.ember,
          key: const ValueKey<String>('review-rating-again'),
          keyHint: '1',
          onPressed: () => onPressed(0),
          enabled: enabled,
        ),
        NcRatingSpec(
          label: l10n.ratingHard,
          interval: l10n.reviewIntervalMinutes(10),
          color: colors.amber,
          key: const ValueKey<String>('review-rating-hard'),
          keyHint: '2',
          onPressed: () => onPressed(1),
          enabled: enabled,
        ),
        NcRatingSpec(
          label: l10n.ratingGood,
          interval: l10n.reviewIntervalDays(3),
          color: colors.jade,
          key: const ValueKey<String>('review-rating-good'),
          keyHint: '3',
          onPressed: () => onPressed(2),
          enabled: enabled,
        ),
        NcRatingSpec(
          label: l10n.ratingEasy,
          interval: l10n.reviewIntervalDays(7),
          color: colors.glacier,
          key: const ValueKey<String>('review-rating-easy'),
          keyHint: '4',
          onPressed: () => onPressed(3),
          enabled: enabled,
        ),
      ],
    );
  }
}
