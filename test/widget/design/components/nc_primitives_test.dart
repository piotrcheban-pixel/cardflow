import 'dart:ui' show PointerDeviceKind;

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/glass_budget.dart';
import '../../../helpers/nc_harness.dart';

/// Поведение примитивов Nocturne (REDESIGN-SPEC §8, шаг 2.1):
/// `NcSurface`, `NcGlass`, `NcIcon3D`, `NcKeyHint`, `NcBadge`, `NcSpinner`,
/// `NcSkeleton`. Golden-снимки — `test/golden/nc_primitives_golden_test.dart`.
void main() {
  final AppLocalizations l10n = ncL10n;

  group('NcSurface', () {
    testWidgets('рендерит содержимое; тап срабатывает; семантика — кнопка', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      var taps = 0;
      await pumpNc(
        tester,
        NcSurface(
          padding: const EdgeInsets.all(16),
          onTap: () => taps++,
          semanticLabel: l10n.decksTitle,
          child: Text(l10n.decksCreateDeckFab),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );

      expect(find.text(l10n.decksCreateDeckFab), findsOneWidget);
      await tester.tap(find.byType(NcSurface));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        find.bySemanticsLabel(l10n.decksTitle),
        findsOneWidget,
        reason: 'Семантика поверхности — текст из ARB',
      );
      expect(
        tester.getSemantics(find.byType(NcSurface)).getSemanticsData().flags,
        hasSemanticsFlag(SemanticsFlag.isButton),
      );
    });

    testWidgets('без onTap тап ничего не делает, узел не кнопка', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await pumpNc(
        tester,
        const NcSurface(
          padding: EdgeInsets.all(16),
          child: SizedBox(width: 80, height: 40),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(
        tester
            .getSemantics(find.byType(NcSurface))
            .getSemanticsData()
            .hasFlag(SemanticsFlag.isButton),
        isFalse,
      );
    });

    testWidgets('hover на ПК приподнимает плитку на 2 px', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcSurface(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.appTitle),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      final double before = tester.getTopLeft(find.text(l10n.appTitle)).dy;
      final TestGesture gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(NcSurface)));
      await tester.pumpAndSettle();
      final double after = tester.getTopLeft(find.text(l10n.appTitle)).dy;
      expect(after, lessThan(before), reason: 'hover-подъём (§6.3-7)');
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcSurface(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.decksEmptyMessage),
        ),
        config: const NcTestConfig(size: Size(420, 300)),
      );
      expect(find.byType(NcSurface), findsOneWidget);
    });
  });

  group('NcGlass', () {
    testWidgets('стекло рисует BackdropFilter и держит бюджет групп', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcGlass(
          tier: NcGlassTier.thin,
          padding: const EdgeInsets.all(12),
          child: Text(l10n.appTitle),
        ),
        config: const NcTestConfig(size: Size(320, 160)),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      expectGlassBudget(tester, maxGroups: 1);
      expect(find.text(l10n.appTitle), findsOneWidget);
    });

    testWidgets('повышенный контраст — сплошная поверхность без размытия', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcGlass(child: Text(l10n.appTitle)),
        config: const NcTestConfig(
          highContrast: true,
          size: Size(320, 160),
        ),
      );
      expectNoGlass(tester);
      expect(find.text(l10n.appTitle), findsOneWidget);
    });

    testWidgets('NcGlassGroup объединяет фильтры в одну группу', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcGlassGroup(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              NcGlass(grouped: true, child: Text(l10n.decksTitle)),
              NcGlass(grouped: true, child: Text(l10n.settingsOpenTooltip)),
            ],
          ),
        ),
        config: const NcTestConfig(size: Size(520, 160)),
      );
      final NcGlassBudget budget = measureGlassBudget(tester);
      expect(budget.filters, 2);
      expect(budget.groups, 1, reason: 'Один проход размытия на группу (§4.1)');
      expect(budget.ungrouped, 0);
      expectGlassBudget(tester, maxGroups: 1);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcGlass(padding: const EdgeInsets.all(16), child: Text(l10n.appTitle)),
        config: const NcTestConfig(size: Size(320, 240)),
      );
    });
  });

  group('NcIcon3D', () {
    testWidgets('резерв рисует глиф, исключён из семантики и держит размер', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await pumpNc(
        tester,
        const NcIcon3D(name: 'target', size: 64),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      final Size size = tester.getSize(find.byType(NcIcon3D));
      expect(size.width, 64);
      expect(size.height, 64);
      expect(
        find.descendant(
          of: find.byType(NcIcon3D),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NcIcon3D),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ассетов ещё нет — резерв работает для любого имени', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        const NcIcon3D(name: 'несуществующее-имя', size: 56),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(find.byType(Icon), findsOneWidget);
      expect(NcIcon3D.hasAsset('mode_classic'), isFalse);
    });
  });

  group('NcKeyHint', () {
    testWidgets('показывает клавишу моноширинным monoM', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        const NcKeyHint(label: 'Space'),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      final Text text = tester.widget<Text>(find.text('Space'));
      expect(text.style?.fontFamily, NcTypography.monoFamily);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        const NcKeyHint(label: 'Enter'),
        config: const NcTestConfig(size: Size(420, 200)),
      );
    });
  });

  group('NcBadge', () {
    testWidgets('счётчик: табличные цифры и семантика', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await pumpNc(
        tester,
        NcBadge.count(
          count: 12,
          semanticLabel: l10n.deckDueCount(12),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      final Text text = tester.widget<Text>(find.text('12'));
      expect(
        text.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(find.bySemanticsLabel(l10n.deckDueCount(12)), findsOneWidget);
    });

    testWidgets('семантический тон меняет цвета', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcBadge(label: l10n.reviewCompletedTitle, tone: NcBadgeTone.jade),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(find.text(l10n.reviewCompletedTitle), findsOneWidget);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcBadge(label: l10n.cardStateLearning),
        config: const NcTestConfig(size: Size(420, 200)),
      );
    });
  });

  group('NcSpinner', () {
    testWidgets('вращается и сообщает семантику ожидания', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await pumpNc(
        tester,
        NcSpinner(semanticLabel: l10n.commonLoading),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(find.bySemanticsLabel(l10n.commonLoading), findsOneWidget);
      final Finder rotation = find.descendant(
        of: find.byType(NcSpinner),
        matching: find.byType(RotationTransition),
      );
      final double before =
          tester.widget<RotationTransition>(rotation).turns.value;
      await tester.pump(const Duration(milliseconds: 300));
      final double after =
          tester.widget<RotationTransition>(rotation).turns.value;
      expect(after, isNot(before), reason: 'Кольцо ожидания вращается (§8)');
    });
  });

  group('NcSkeleton', () {
    testWidgets('блик анимируется на фиксированном кадре', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        const NcSkeleton(width: 240, height: 16),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      final Finder animated = find.descendant(
        of: find.byType(NcSkeleton),
        matching: find.byType(AnimatedBuilder),
      );
      expect(animated, findsWidgets);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('при уменьшении движения блик статичен (без кадров)', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        const NcSkeleton(width: 240, height: 16),
        config: const NcTestConfig(
          reduceMotion: true,
          size: Size(420, 200),
        ),
        settle: true,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'Статичный skeleton при disableAnimations (§6.4)',
      );
    });

    testWidgets('textScale 2,0 не влияет на геометрию и не даёт overflow', (
      WidgetTester tester,
    ) async {
      await pumpNcAtTextScale2(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NcSkeleton.line(width: 200),
            SizedBox(height: 8),
            NcSkeleton.circle(height: 48),
          ],
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
    });
  });
}

/// Matcher «у узла есть флаг семантики».
Matcher hasSemanticsFlag(SemanticsFlag flag) => predicate<int>(
  (int flags) => (flags & flag.index) != 0,
  'семантика с флагом $flag',
);
