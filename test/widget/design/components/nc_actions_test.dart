import 'dart:ui' show PointerDeviceKind;

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/design/components/internal/nc_spring_builder.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/design/components/internal/nc_pressable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/nc_harness.dart';

/// Поведение кнопок Nocturne (REDESIGN-SPEC §8, шаг 2.2):
/// `NcButton`, `NcIconButton`, `NcSplitButton`, `NcFab`.
void main() {
  final AppLocalizations l10n = ncL10n;

  group('NcButton', () {
    testWidgets('тап вызывает действие; семантика — текст из ARB', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await pumpNc(
        tester,
        NcButton(label: l10n.reviewStartSession, onPressed: () => taps++),
        config: const NcTestConfig(size: Size(420, 240)),
      );
      expect(find.text(l10n.reviewStartSession), findsOneWidget);
      await tester.tap(find.byType(NcButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.bySemanticsLabel(l10n.reviewStartSession), findsWidgets);
    });

    testWidgets('все варианты и размеры рендерятся на textScale 2,0', (
      WidgetTester tester,
    ) async {
      await pumpNcAtTextScale2(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final NcButtonVariant variant in NcButtonVariant.values)
              Padding(
                padding: const EdgeInsets.all(4),
                child: NcButton(
                  label: l10n.reviewStartSession,
                  variant: variant,
                  size: NcButtonSize.values[variant.index % 3],
                  onPressed: () {},
                ),
              ),
          ],
        ),
        config: const NcTestConfig(size: Size(420, 720)),
      );
    });

    testWidgets('loading: три точки вместо текста, ширина не меняется, тап '
        'не срабатывает', (WidgetTester tester) async {
      var taps = 0;
      await pumpNc(
        tester,
        NcButton(
          label: l10n.reviewStartSession,
          size: NcButtonSize.l,
          onPressed: () => taps++,
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      final double width = tester.getSize(find.byType(NcButton)).width;
      await pumpNc(
        tester,
        NcButton(
          label: l10n.reviewStartSession,
          size: NcButtonSize.l,
          loading: true,
          onPressed: () => taps++,
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(
        tester.getSize(find.byType(NcButton)).width,
        width,
        reason: 'Ширина кнопки при загрузке не меняется (§8)',
      );
      expect(find.text(l10n.reviewStartSession), findsOneWidget);
      await tester.tap(find.byType(NcButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, 0);
    });

    testWidgets('disabled: тап и клавиатура не активируют', (
      WidgetTester tester,
    ) async {
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);
      await pumpNc(
        tester,
        NcButton(label: l10n.reviewStartSession, focusNode: node),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      final FocusableActionDetector detector = tester
          .widget<FocusableActionDetector>(
            find
                .descendant(
                  of: find.byType(NcButton),
                  matching: find.byType(FocusableActionDetector),
                )
                .first,
          );
      expect(
        detector.enabled,
        isFalse,
        reason: 'Неактивная кнопка не фокусируется',
      );
      await tester.tap(find.byType(NcButton), warnIfMissed: false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('фокус + Enter и Space активируют кнопку', (
      WidgetTester tester,
    ) async {
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);
      var taps = 0;
      await pumpNc(
        tester,
        NcButton(
          label: l10n.reviewStartSession,
          focusNode: node,
          onPressed: () => taps++,
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1, reason: 'Enter = ActivateIntent');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(taps, 2, reason: 'Space = ActivateIntent');
    });

    testWidgets('Standard motion: сжатие при нажатии без overshoot', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcButton(label: l10n.reviewStartSession, onPressed: () {}),
        config: const NcTestConfig(
          motion: NcMotionPreference.standard,
          size: Size(420, 200),
        ),
      );
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(NcButton)),
        kind: PointerDeviceKind.mouse,
      );
      final List<double> during = <double>[];
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        during.add(pressScaleOf(tester, find.byType(NcPressScale)));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      during.add(pressScaleOf(tester, find.byType(NcPressScale)));
      // Пружина нажатия (`press`, ratio 0,70) — отклик формы, не упругий
      // overshoot: допуск 10 % диапазона сжатия (≈0,2 % размера кнопки).
      expectNoOvershoot(during, min: 0.96, max: 1.0, tolerance: 0.1);
    });
  });

  group('NcSpringBuilder', () {
    Future<List<double>> sample(
      WidgetTester tester,
      SpringDescription spring,
    ) async {
      final List<double> values = <double>[];
      double target = 0;
      late StateSetter setState;
      Widget tree() => NcSpringBuilder(
        value: target,
        spring: spring,
        builder: (BuildContext context, double value) {
          values.add(value);
          return const SizedBox.shrink();
        },
      );
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setter) {
            setState = setter;
            return tree();
          },
        ),
        config: const NcTestConfig(size: Size(200, 100)),
      );
      setState(() => target = 1);
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      return values;
    }

    testWidgets('standard: без overshoot; celebrate — с overshoot (§6.4)', (
      WidgetTester tester,
    ) async {
      final List<double> standard = await sample(
        tester,
        AppMotion.standardSpring(),
      );
      expectNoOvershoot(standard, min: 0, max: 1, tolerance: 0.005);

      final List<double> celebrate = await sample(
        tester,
        AppMotion.celebrateSpring(),
      );
      expect(
        () => expectNoOvershoot(celebrate, min: 0, max: 1, tolerance: 0.005),
        throwsA(isA<TestFailure>()),
        reason: 'Выразительная пружина имеет право на overshoot (§6.1)',
      );
    });
  });

  group('NcIconButton', () {
    testWidgets('tooltip — текст семантики; тап срабатывает', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await pumpNc(
        tester,
        NcIconButton(
          icon: Icons.search_rounded,
          tooltip: l10n.decksSearchTooltip,
          onPressed: () => taps++,
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      await tester.tap(find.byType(NcIconButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.byTooltip(l10n.decksSearchTooltip), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.decksSearchTooltip), findsWidgets);
    });

    testWidgets('disabled: не фокусируется и не нажимается', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcIconButton(
          icon: Icons.search_rounded,
          tooltip: l10n.decksSearchTooltip,
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      final FocusableActionDetector detector = tester
          .widget<FocusableActionDetector>(
            find
                .descendant(
                  of: find.byType(NcIconButton),
                  matching: find.byType(FocusableActionDetector),
                )
                .first,
          );
      expect(
        detector.enabled,
        isFalse,
        reason: 'Неактивная иконочная кнопка не фокусируется и не hover (§8)',
      );
    });

    testWidgets('фокус + Enter активирует', (WidgetTester tester) async {
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);
      var taps = 0;
      await pumpNc(
        tester,
        NcIconButton(
          icon: Icons.search_rounded,
          tooltip: l10n.decksSearchTooltip,
          focusNode: node,
          onPressed: () => taps++,
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final NcIconButtonVariant variant
                in NcIconButtonVariant.values)
              Padding(
                padding: const EdgeInsets.all(4),
                child: NcIconButton(
                  icon: Icons.settings_rounded,
                  tooltip: l10n.settingsOpenTooltip,
                  variant: variant,
                  onPressed: () {},
                ),
              ),
          ],
        ),
        config: const NcTestConfig(size: Size(420, 300)),
      );
    });
  });

  group('NcSplitButton', () {
    testWidgets('основной сегмент и пункт меню вызывают свои действия', (
      WidgetTester tester,
    ) async {
      var mainTaps = 0;
      var menuTaps = 0;
      await pumpNc(
        tester,
        NcSplitButton(
          label: l10n.decksCreateButton,
          onPressed: () => mainTaps++,
          menuSemanticLabel: l10n.decksCreateMenuTooltip,
          items: <NcMenuItem<void>>[
            NcMenuItem<void>(
              label: l10n.decksCreateManual,
              onSelected: () => menuTaps++,
            ),
            NcMenuItem<void>(
              label: l10n.decksImportZip,
              onSelected: () => menuTaps++,
            ),
          ],
        ),
        config: const NcTestConfig(size: Size(520, 400)),
      );

      await tester.tap(find.text(l10n.decksCreateButton));
      await tester.pumpAndSettle();
      expect(mainTaps, 1);

      await tester.tap(find.byTooltip(l10n.decksCreateMenuTooltip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.decksCreateManual), findsOneWidget);
      await tester.tap(find.text(l10n.decksImportZip));
      await tester.pumpAndSettle();
      expect(menuTaps, 1);
      expect(find.text(l10n.decksImportZip), findsNothing);
    });

    testWidgets('меню работает при неактивном основном действии', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcSplitButton(
          label: l10n.decksCreateButton,
          menuSemanticLabel: l10n.decksCreateMenuTooltip,
          items: <NcMenuItem<void>>[
            NcMenuItem<void>(label: l10n.decksCreateManual),
          ],
        ),
        config: const NcTestConfig(size: Size(520, 400)),
      );
      await tester.tap(find.byTooltip(l10n.decksCreateMenuTooltip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.decksCreateManual), findsOneWidget);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcSplitButton(
          label: l10n.decksCreateButton,
          onPressed: () {},
          menuSemanticLabel: l10n.decksCreateMenuTooltip,
          items: <NcMenuItem<void>>[
            NcMenuItem<void>(label: l10n.decksCreateManual),
          ],
        ),
        config: const NcTestConfig(size: Size(520, 300)),
      );
    });
  });

  group('NcFab', () {
    testWidgets('extended: подпись видна, тап срабатывает, семантика из ARB', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await pumpNc(
        tester,
        NcFab(label: l10n.decksCreateDeckFab, onPressed: () => taps++),
        config: const NcTestConfig(size: Size(420, 300)),
      );
      expect(find.text(l10n.decksCreateDeckFab), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.decksCreateDeckFab), findsWidgets);
      await tester.tap(find.byType(NcFab));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('схлопывается при прокрутке вниз и разворачивается вверх', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        SizedBox(
          width: 420,
          height: 400,
          child: NcScrollCollapseScope(
            child: Stack(
              children: <Widget>[
                ListView(
                  children: <Widget>[
                    for (var index = 0; index < 40; index++)
                      SizedBox(
                        height: 48,
                        child: Text(l10n.deckDueCount(index)),
                      ),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: NcFab(
                    label: l10n.decksCreateDeckFab,
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 400)),
      );

      final double expandedWidth = tester.getSize(find.byType(NcFab)).width;
      expect(expandedWidth, greaterThan(120));

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      final double collapsedWidth = tester.getSize(find.byType(NcFab)).width;
      expect(collapsedWidth, 56, reason: 'Вниз — круг 56 (§8)');
      expect(find.text(l10n.decksCreateDeckFab), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(NcFab)).width,
        greaterThan(120),
        reason: 'Вверх — снова pill (§8)',
      );
    });

    testWidgets('disabled: тап не срабатывает и FAB не фокусируется', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        const NcFab(label: 'Создать колоду', onPressed: null),
        config: const NcTestConfig(size: Size(420, 300)),
      );
      final FocusableActionDetector detector = tester
          .widget<FocusableActionDetector>(
            find
                .descendant(
                  of: find.byType(NcFab),
                  matching: find.byType(FocusableActionDetector),
                )
                .first,
          );
      expect(detector.enabled, isFalse);
      await tester.tap(find.byType(NcFab), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
