import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/glass_budget.dart';
import '../../../helpers/nc_harness.dart';

/// Поведение структуры Nocturne (REDESIGN-SPEC §8, шаг 2.4):
/// `NcListRow`, `NcSection`, `NcCardTile`, `NcTopBar`, `NcEmptyState`,
/// `NcErrorState`.
void main() {
  final AppLocalizations l10n = ncL10n;

  group('NcListRow', () {
    testWidgets('тап и долгое нажатие срабатывают; семантика из ARB', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      var longs = 0;
      await pumpNc(
        tester,
        NcSection(
          children: <Widget>[
            NcListRow(
              title: Text(l10n.settingsHighContrast),
              subtitle: Text(l10n.settingsHapticsHint),
              semanticLabel: l10n.settingsHighContrast,
              leading: const Icon(Icons.contrast_rounded, size: 22),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => taps++,
              onLongPress: () => longs++,
            ),
          ],
        ),
        config: const NcTestConfig(size: Size(520, 300)),
      );
      expect(find.text(l10n.settingsHighContrast), findsOneWidget);
      await tester.tap(find.text(l10n.settingsHighContrast));
      await tester.pumpAndSettle();
      expect(taps, 1);
      await tester.longPress(find.text(l10n.settingsHighContrast));
      await tester.pumpAndSettle();
      expect(longs, 1);
      expect(find.bySemanticsLabel(l10n.settingsHighContrast), findsWidgets);
    });

    testWidgets('разделитель рисуется по флагу', (WidgetTester tester) async {
      await pumpNc(
        tester,
        NcSection(
          children: <Widget>[
            NcListRow(title: Text(l10n.settingsHighContrast)),
            NcListRow(
              title: Text(l10n.settingsHapticsTitle),
              showDivider: false,
            ),
          ],
        ),
        config: const NcTestConfig(size: Size(520, 300)),
      );
      expect(
        find.byType(Divider),
        findsOneWidget,
        reason: 'Один разделитель между двумя строками, последняя — без него',
      );
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcSection(
          children: <Widget>[
            NcListRow(
              title: Text(l10n.cardFormSourceExcerptLabel),
              subtitle: Text(l10n.cardFormSourceExcerptTooLongError),
              leading: const Icon(Icons.info_rounded, size: 22),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {},
            ),
          ],
        ),
        config: const NcTestConfig(size: Size(420, 400)),
      );
    });
  });

  group('NcSection', () {
    testWidgets('overline-заголовок и footer', (WidgetTester tester) async {
      await pumpNc(
        tester,
        NcSection(
          title: l10n.settingsAppearanceTitle,
          footer: Text(l10n.settingsHapticsHint),
          children: <Widget>[NcListRow(title: Text(l10n.settingsHighContrast))],
        ),
        config: const NcTestConfig(size: Size(520, 320)),
      );
      expect(find.text(l10n.settingsAppearanceTitle), findsOneWidget);
      final Text title = tester.widget<Text>(
        find.text(l10n.settingsAppearanceTitle),
      );
      expect(title.style?.fontFamily, NcTypography.sansFamily);
      expect(find.text(l10n.settingsHapticsHint), findsOneWidget);
    });
  });

  group('NcCardTile', () {
    testWidgets('тап, бейдж и семантика', (WidgetTester tester) async {
      var taps = 0;
      await pumpNc(
        tester,
        NcCardTile(
          title: Text(l10n.decksTitle),
          subtitle: Text(l10n.deckDueCount(12)),
          leading: const NcIcon3D(name: 'deck_gem_01', size: 52),
          badge: NcBadge.count(count: 12),
          semanticLabel: l10n.decksTitle,
          onTap: () => taps++,
        ),
        config: const NcTestConfig(size: Size(520, 240)),
      );
      expect(find.text(l10n.decksTitle), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      await tester.tap(find.byType(NcCardTile));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.bySemanticsLabel(l10n.decksTitle), findsWidgets);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcCardTile(
          title: Text(l10n.decksEmptyMessage),
          subtitle: Text(l10n.deckCardCount(12)),
          badge: NcBadge.count(count: 12),
          onTap: () {},
        ),
        config: const NcTestConfig(size: Size(420, 320)),
      );
    });
  });

  group('NcTopBar', () {
    testWidgets('стекло появляется при прокрутке, large title схлопывается', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpNc(
        tester,
        SizedBox(
          width: 420,
          height: 420,
          child: Column(
            children: <Widget>[
              NcTopBar(
                largeTitle: l10n.decksTitle,
                title: l10n.decksTitle,
                scrollController: controller,
                actions: <Widget>[
                  NcIconButton(
                    icon: Icons.search_rounded,
                    tooltip: l10n.decksSearchTooltip,
                    onPressed: () {},
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: <Widget>[
                    for (var index = 0; index < 30; index++)
                      SizedBox(
                        height: 48,
                        child: Text(l10n.deckDueCount(index)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        config: const NcTestConfig(size: Size(420, 420)),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      final double expandedHeight = tester
          .getSize(find.byType(NcTopBar))
          .height;
      expect(expandedHeight, NcTopBar.largeHeight);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expectGlassBudget(tester, maxGroups: 1);
      expect(
        tester.getSize(find.byType(NcTopBar)).height,
        closeTo(NcTopBar.compactHeight, 0.01),
        reason: 'Large title схлопывается в titleM (§8)',
      );
    });

    testWidgets('без large title — компактная панель', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcTopBar(title: l10n.reviewTitle),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(
        tester.getSize(find.byType(NcTopBar)).height,
        NcTopBar.compactHeight,
      );
      expect(find.text(l10n.reviewTitle), findsOneWidget);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcTopBar(
          largeTitle: l10n.decksTitle,
          title: l10n.decksTitle,
          actions: <Widget>[
            NcIconButton(
              icon: Icons.settings_rounded,
              tooltip: l10n.settingsOpenTooltip,
              onPressed: () {},
            ),
          ],
        ),
        config: const NcTestConfig(size: Size(420, 320)),
      );
    });
  });

  group('NcEmptyState', () {
    testWidgets('3D-иконка, тексты и главное действие', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await pumpNc(
        tester,
        NcEmptyState(
          iconName: 'empty_decks',
          title: l10n.decksEmptyTitle,
          message: l10n.decksEmptyMessage,
          primaryAction: NcButton(
            label: l10n.decksCreateDeckFab,
            onPressed: () => taps++,
          ),
        ),
        config: const NcTestConfig(size: Size(520, 520)),
      );
      expect(find.byType(NcIcon3D), findsOneWidget);
      expect(find.text(l10n.decksEmptyTitle), findsOneWidget);
      expect(find.text(l10n.decksEmptyMessage), findsOneWidget);
      await tester.tap(find.text(l10n.decksCreateDeckFab));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcEmptyState(
          iconName: 'empty_decks',
          title: l10n.decksEmptyTitle,
          message: l10n.decksEmptyMessage,
          primaryAction: NcButton(
            label: l10n.decksCreateDeckFab,
            onPressed: () {},
          ),
          secondaryAction: NcButton(
            label: l10n.decksCreateGenerate,
            variant: NcButtonVariant.secondary,
            onPressed: () {},
          ),
        ),
        config: const NcTestConfig(size: Size(420, 900)),
      );
    });
  });

  group('NcErrorState', () {
    testWidgets('сообщение и «Повторить»', (WidgetTester tester) async {
      var retries = 0;
      await pumpNc(
        tester,
        NcErrorState(
          message: l10n.decksErrorTitle,
          retryLabel: l10n.retry,
          onRetry: () => retries++,
        ),
        config: const NcTestConfig(size: Size(520, 420)),
      );
      expect(find.text(l10n.decksErrorTitle), findsOneWidget);
      expect(find.text(l10n.retry), findsOneWidget);
      await tester.tap(find.text(l10n.retry));
      await tester.pumpAndSettle();
      expect(retries, 1);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcErrorState(
          message: l10n.decksErrorTitle,
          retryLabel: l10n.retry,
          onRetry: () {},
        ),
        config: const NcTestConfig(size: Size(420, 640)),
      );
    });
  });
}
