@Tags(<String>['golden'])
library;

import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Каталог всей библиотеки компонентов Nocturne на одном полотне
/// (REDESIGN-PLAN, шаг 2.8): dark и light. Полотно — для ревью владельцем;
/// в приложении витрины нет (это была бы мёртвая функция).
void main() {
  setUpAll(loadNcFonts);
  final l10n = ncL10n;

  Widget demo(String title, Widget child, {double width = 300}) => SizedBox(
    width: width,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 11,
            color: Color(0xFF8A8780),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  Widget catalog(NcColors colors) => ColoredBox(
    color: colors.ink0,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        spacing: 24,
        runSpacing: 28,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: <Widget>[
          demo(
            'NcSurface / NcGlass',
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                NcSurface(
                  padding: const EdgeInsets.all(12),
                  child: Text(l10n.decksTitle),
                ),
                const SizedBox(height: 8),
                NcGlass(
                  tier: NcGlassTier.thin,
                  padding: const EdgeInsets.all(12),
                  width: 240,
                  child: Text(l10n.appTitle),
                ),
              ],
            ),
          ),
          demo(
            'NcIcon3D / NcBadge / NcKeyHint',
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const <Widget>[
                    NcIcon3D(name: 'target', size: 56),
                    SizedBox(width: 8),
                    NcIcon3D(name: 'mode_classic', size: 56),
                    SizedBox(width: 8),
                    NcIcon3D(name: 'shield_error', size: 56),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    NcBadge.count(count: 12),
                    NcBadge(
                      label: l10n.cardStateNew,
                      tone: NcBadgeTone.glacier,
                    ),
                    NcBadge(
                      label: l10n.generationFileParsed,
                      tone: NcBadgeTone.jade,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const NcKeyHint(label: 'Space'),
                    const SizedBox(width: 6),
                    const NcKeyHint(label: '1'),
                    const SizedBox(width: 6),
                    NcSkeleton.line(
                      width: 80,
                      semanticLabel: l10n.commonLoading,
                    ),
                  ],
                ),
              ],
            ),
          ),
          demo(
            'NcSpinner / NcSkeleton',
            Builder(
              builder: (BuildContext context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    NcSpinner(semanticLabel: l10n.commonLoading),
                    const SizedBox(height: 8),
                    const NcSkeleton(width: 200, height: 16),
                    const SizedBox(height: 6),
                    const NcSkeleton.line(width: 150),
                  ],
                ),
              ),
            ),
          ),
          demo(
            'NcButton',
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                NcButton(label: l10n.reviewStartSession, onPressed: () {}),
                const SizedBox(height: 6),
                NcButton(
                  label: l10n.save,
                  variant: NcButtonVariant.secondary,
                  onPressed: () {},
                ),
                const SizedBox(height: 6),
                NcButton(
                  label: l10n.cancel,
                  variant: NcButtonVariant.ghost,
                  onPressed: () {},
                ),
                const SizedBox(height: 6),
                NcButton(
                  label: l10n.delete,
                  variant: NcButtonVariant.destructive,
                  onPressed: () {},
                ),
                const SizedBox(height: 6),
                NcButton(
                  label: l10n.decksCreateGenerate,
                  variant: NcButtonVariant.ai,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          demo(
            'NcButton: размеры / loading',
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                NcButton(
                  label: l10n.reviewDone,
                  size: NcButtonSize.s,
                  onPressed: () {},
                ),
                const SizedBox(height: 6),
                NcButton(
                  label: l10n.generationAttachButton,
                  size: NcButtonSize.l,
                  prominent: true,
                  onPressed: () {},
                ),
                const SizedBox(height: 6),
                NcButton(
                  label: l10n.importConfirm,
                  loading: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          demo(
            'NcIconButton / NcSplitButton / NcFab',
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    NcIconButton(
                      icon: Icons.search_rounded,
                      tooltip: l10n.decksSearchTooltip,
                      onPressed: () {},
                    ),
                    const SizedBox(width: 8),
                    NcIconButton(
                      icon: Icons.filter_alt_rounded,
                      tooltip: l10n.decksFilterTooltip,
                      variant: NcIconButtonVariant.tonal,
                      onPressed: () {},
                    ),
                    const SizedBox(width: 8),
                    NcIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: l10n.reviewBack,
                      variant: NcIconButtonVariant.glass,
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                NcSplitButton(
                  label: l10n.decksCreateButton,
                  onPressed: () {},
                  menuSemanticLabel: l10n.decksCreateMenuTooltip,
                  items: <NcMenuItem<void>>[
                    NcMenuItem<void>(label: l10n.decksCreateManual),
                    NcMenuItem<void>(label: l10n.decksImportZip),
                  ],
                ),
                const SizedBox(height: 12),
                NcFab(label: l10n.decksCreateDeckFab, onPressed: () {}),
              ],
            ),
          ),
          demo(
            'NcTextField / NcSearchField',
            SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  NcTextField(
                    label: l10n.cardFormFrontLabel,
                    initialValue: 'Что такое фотосинтез?',
                    helper: l10n.cardFormReversedHint,
                  ),
                  const SizedBox(height: 12),
                  NcTextField(
                    label: l10n.deckNameLabel,
                    errorText: l10n.deckNameEmptyError,
                  ),
                  const SizedBox(height: 12),
                  NcSearchField(hint: l10n.decksSearchHint),
                ],
              ),
            ),
          ),
          demo(
            'NcSwitch / NcSegmented',
            SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      NcSwitch(value: true, onChanged: (_) {}),
                      const SizedBox(width: 12),
                      const NcSwitch(value: false),
                    ],
                  ),
                  const SizedBox(height: 12),
                  NcSegmented<String>(
                    value: 'classic',
                    segments: <NcSegment<String>>[
                      NcSegment<String>(
                        value: 'classic',
                        label: l10n.reviewModeClassic,
                      ),
                      NcSegment<String>(
                        value: 'feed',
                        label: l10n.reviewModeFeed,
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
          demo(
            'NcSlider / NcStepper',
            SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  NcSlider(
                    value: 60,
                    min: 0,
                    max: 100,
                    divisions: 10,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 8),
                  NcStepper(value: 20, onDecrement: () {}, onIncrement: () {}),
                ],
              ),
            ),
          ),
          demo(
            'NcChip / NcDropdown',
            SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      NcChip.filter(
                        label: l10n.deckFilterAll,
                        selected: false,
                        onSelected: () {},
                      ),
                      NcChip.filter(
                        label: l10n.deckFilterDue,
                        selected: true,
                        onSelected: () {},
                      ),
                      NcChip.tag(label: l10n.cardTagsLine('биология')),
                      NcChip.status(
                        label: l10n.reviewCompletedTitle,
                        tone: NcBadgeTone.jade,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  NcDropdown<String>(
                    value: 'a',
                    label: l10n.settingsModelLabel,
                    items: <NcDropdownItem<String>>[
                      NcDropdownItem<String>(
                        value: 'a',
                        label: 'deepseek-chat',
                      ),
                      NcDropdownItem<String>(
                        value: 'b',
                        label: 'deepseek-flash',
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
          demo(
            'NcSection / NcListRow',
            SizedBox(
              width: 360,
              child: NcSection(
                title: l10n.settingsAppearanceTitle,
                footer: Text(l10n.settingsHapticsHint),
                children: <Widget>[
                  NcListRow(
                    leading: const Icon(Icons.contrast_rounded, size: 22),
                    title: Text(l10n.settingsHighContrast),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {},
                  ),
                  NcListRow(
                    leading: const Icon(Icons.vibration_rounded, size: 22),
                    title: Text(l10n.settingsHapticsTitle),
                    trailing: const NcSwitch(value: true, onChanged: null),
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
          demo(
            'NcCardTile / NcTopBar',
            SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  NcCardTile(
                    leading: const NcIcon3D(name: 'deck_gem_01', size: 52),
                    title: Text(l10n.decksTitle),
                    subtitle: Text(l10n.deckCardCount(12)),
                    badge: NcBadge.count(count: 12),
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  NcTopBar(
                    title: l10n.reviewTitle,
                    leading: NcIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: l10n.reviewBack,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
          demo(
            'NcEmptyState / NcErrorState',
            SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  NcEmptyState(
                    iconName: 'empty_decks',
                    title: l10n.decksEmptyTitle,
                    message: l10n.decksEmptyMessage,
                    primaryAction: NcButton(
                      label: l10n.decksCreateDeckFab,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(height: 16),
                  NcErrorState(
                    message: l10n.decksErrorTitle,
                    retryLabel: l10n.retry,
                    onRetry: () {},
                    compact: true,
                  ),
                ],
              ),
            ),
          ),
          demo(
            'NcMenu',
            NcMenu<void>(
              onDismiss: () {},
              items: <NcMenuItem<void>>[
                NcMenuItem<void>(
                  label: l10n.deckRename,
                  icon: Icons.edit_rounded,
                ),
                NcMenuItem<void>(
                  label: l10n.deckExport,
                  icon: Icons.ios_share_rounded,
                ),
                NcMenuItem<void>(
                  label: l10n.delete,
                  icon: Icons.delete_rounded,
                  destructive: true,
                  dividerBefore: true,
                ),
              ],
            ),
            width: 240,
          ),
          demo(
            'NcSheet',
            SizedBox(
              width: 380,
              child: NcSheet(
                title: l10n.reviewSessionModeTitle,
                closeTooltip: l10n.commonClose,
                child: NcListRow(
                  title: Text(l10n.reviewModeClassic),
                  showDivider: false,
                ),
              ),
            ),
            width: 380,
          ),
          demo(
            'NcDialog',
            SizedBox(
              width: 380,
              child: NcDialog(
                icon3dName: 'shield_error',
                title: l10n.deckDeleteDialogTitle,
                message: l10n.deckDeleteDialogMessage('Испанский'),
                actions: <Widget>[
                  NcButton(
                    label: l10n.cancel,
                    variant: NcButtonVariant.ghost,
                    onPressed: () {},
                  ),
                  NcButton(
                    label: l10n.delete,
                    variant: NcButtonVariant.destructive,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            width: 380,
          ),
          demo(
            'NcToast',
            NcToast(
              message: l10n.deckArchivedMessage,
              actionLabel: l10n.undo,
              duration: const Duration(seconds: 30),
            ),
            width: 340,
          ),
          demo(
            'NcProgressLine / NcSegmentedProgress',
            Builder(
              builder: (BuildContext context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: SizedBox(
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      NcProgressLine(value: 0.35),
                      const SizedBox(height: 12),
                      NcProgressLine(value: 0.72, height: 5),
                      const SizedBox(height: 12),
                      NcSegmentedProgress(
                        total: 6,
                        current: 2,
                        rated: 2,
                        ratingColors: <int, Color>{0: colors.jade},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          demo(
            'NcRing / NcAnimatedNumber',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                NcRing(
                  value: 0.72,
                  size: 140,
                  child: NcAnimatedNumber(
                    value: 72,
                    duration: Duration.zero,
                    format: (num value) =>
                        l10n.statisticsRetentionValue(value.round()),
                  ),
                ),
                const SizedBox(width: 24),
                NcAnimatedNumber(
                  value: 1234,
                  duration: Duration.zero,
                  style: const TextStyle(fontFamily: 'Literata', fontSize: 40),
                ),
              ],
            ),
            width: 340,
          ),
          demo(
            'NcMonolith / NcFlip',
            SizedBox(
              width: 380,
              child: NcMonolith(
                metadata: Text(l10n.cardTypeBasic),
                badges: NcBadge(label: l10n.cardStateNew),
                child: Text(
                  l10n.cardFormFrontLabel,
                  style: const TextStyle(fontFamily: 'Literata', fontSize: 24),
                ),
              ),
            ),
            width: 380,
          ),
          demo(
            'NcRatingDock',
            SizedBox(
              width: 600,
              child: Builder(
                builder: (BuildContext context) => NcRatingDock(
                  ratings: <NcRatingSpec>[
                    NcRatingSpec(
                      label: l10n.ratingAgain,
                      interval: l10n.reviewIntervalLessThanMinute,
                      color: NcTheme.of(context).colors.ember,
                      keyHint: '1',
                      onPressed: () {},
                    ),
                    NcRatingSpec(
                      label: l10n.ratingHard,
                      interval: l10n.reviewIntervalMinutes(10),
                      color: NcTheme.of(context).colors.amber,
                      keyHint: '2',
                      onPressed: () {},
                    ),
                    NcRatingSpec(
                      label: l10n.ratingGood,
                      interval: l10n.reviewIntervalDays(3),
                      color: NcTheme.of(context).colors.jade,
                      keyHint: '3',
                      onPressed: () {},
                    ),
                    NcRatingSpec(
                      label: l10n.ratingEasy,
                      interval: l10n.reviewIntervalDays(7),
                      color: NcTheme.of(context).colors.glacier,
                      keyHint: '4',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            width: 600,
          ),
        ],
      ),
    ),
  );

  for (final (String id, Brightness brightness) in <(String, Brightness)>[
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('каталог компонентов: $id', (WidgetTester tester) async {
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) =>
              catalog(NcTheme.of(context).colors),
        ),
        config: NcTestConfig(
          brightness: brightness,
          size: const Size(1360, 2900),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/components_catalog_$id.png'),
      );
    });
  }
}
