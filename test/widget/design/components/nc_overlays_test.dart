import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/design/components/internal/nc_pressable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/glass_budget.dart';
import '../../../helpers/nc_harness.dart';

/// Поведение оверлеев Nocturne (REDESIGN-SPEC §8, шаг 2.5):
/// `NcMenu`/`showNcMenu`, `NcSheet`/`showNcSheet`, `NcDialog`/`showNcDialog`,
/// `NcToast`/`showNcToast`.
void main() {
  final AppLocalizations l10n = ncL10n;

  group('NcMenu', () {
    testWidgets('пункты меню: тап вызывает действие', (
      WidgetTester tester,
    ) async {
      var selected = 0;
      await pumpNc(
        tester,
        NcMenu<void>(
          items: <NcMenuItem<void>>[
            NcMenuItem<void>(
              label: l10n.deckRename,
              icon: Icons.edit_rounded,
              onSelected: () => selected++,
            ),
            NcMenuItem<void>(
              label: l10n.delete,
              icon: Icons.delete_rounded,
              destructive: true,
              onSelected: () => selected += 10,
            ),
          ],
          onDismiss: () {},
        ),
        config: const NcTestConfig(size: Size(520, 300)),
      );
      expect(find.text(l10n.deckRename), findsOneWidget);
      await tester.tap(find.text(l10n.delete));
      await tester.pumpAndSettle();
      expect(selected, 10);
    });

    testWidgets('showNcMenu: выбор возвращает значение и закрывает меню', (
      WidgetTester tester,
    ) async {
      final GlobalKey anchor = GlobalKey();
      String? result = 'none';
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(key: anchor, width: 120, height: 40),
              NcButton(
                label: l10n.decksCreateMenuTooltip,
                onPressed: () async {
                  result = await showNcMenu<String>(
                    context: context,
                    anchorKey: anchor,
                    items: <NcMenuItem<String>>[
                      NcMenuItem<String>(
                        label: l10n.decksCreateManual,
                        value: 'manual',
                      ),
                      NcMenuItem<String>(
                        label: l10n.decksImportZip,
                        value: 'zip',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        config: const NcTestConfig(size: Size(520, 400)),
      );
      await tester.tap(find.text(l10n.decksCreateMenuTooltip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.decksCreateManual), findsOneWidget);
      expectGlassBudget(tester, maxGroups: 1);
      await tester.tap(find.text(l10n.decksImportZip));
      await tester.pumpAndSettle();
      expect(result, 'zip');
      expect(find.text(l10n.decksCreateManual), findsNothing);
    });

    testWidgets('showNcMenu: Escape закрывает без выбора', (
      WidgetTester tester,
    ) async {
      final GlobalKey anchor = GlobalKey();
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(key: anchor, width: 120, height: 40),
              NcButton(
                label: l10n.decksMenuTooltip,
                onPressed: () => showNcMenu<void>(
                  context: context,
                  anchorKey: anchor,
                  items: <NcMenuItem<void>>[
                    NcMenuItem<void>(label: l10n.deckRename),
                  ],
                ),
              ),
            ],
          ),
        ),
        config: const NcTestConfig(size: Size(520, 400)),
      );
      await tester.tap(find.text(l10n.decksMenuTooltip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckRename), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckRename), findsNothing);
    });
  });

  group('NcSheet', () {
    testWidgets('мобильный лист: заголовок, закрытие и результат', (
      WidgetTester tester,
    ) async {
      String? result;
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) => NcButton(
            label: l10n.reviewSessionModeTitle,
            onPressed: () async {
              result = await showNcSheet<String>(
                context,
                title: l10n.reviewSessionModeTitle,
                closeTooltip: l10n.commonClose,
                builder: (BuildContext sheetContext) => NcButton(
                  label: l10n.reviewModeClassic,
                  onPressed: () => Navigator.of(sheetContext).pop('classic'),
                ),
              );
            },
          ),
        ),
        config: const NcTestConfig(size: Size(390, 844)),
      );
      await tester.tap(find.text(l10n.reviewSessionModeTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reviewModeClassic), findsOneWidget);
      expect(find.byTooltip(l10n.commonClose), findsOneWidget);
      await tester.tap(find.text(l10n.reviewModeClassic));
      await tester.pumpAndSettle();
      expect(result, 'classic');
      expect(find.text(l10n.reviewModeClassic), findsNothing);
    });

    testWidgets('на ПК (≥ 1024) лист становится диалогом', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) => NcButton(
            label: l10n.reviewSessionModeTitle,
            onPressed: () => showNcSheet<void>(
              context,
              title: l10n.reviewSessionModeTitle,
              closeTooltip: l10n.commonClose,
              builder: (BuildContext sheetContext) => Text(l10n.reviewModeFeed),
            ),
          ),
        ),
        config: const NcTestConfig(size: Size(1280, 900)),
      );
      await tester.tap(find.text(l10n.reviewSessionModeTitle));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text(l10n.reviewModeFeed), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.commonClose));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reviewModeFeed), findsNothing);
    });
  });

  group('NcDialog', () {
    testWidgets('действия возвращают результат', (WidgetTester tester) async {
      bool? confirmed;
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) => NcButton(
            label: l10n.deckDeleteDialogTitle,
            onPressed: () async {
              confirmed = await showNcDialog<bool>(
                context,
                title: l10n.deckDeleteDialogTitle,
                message: l10n.deckDeleteDialogMessage('Испанский'),
                icon3dName: 'shield_error',
                actions: <Widget>[
                  NcButton(
                    label: l10n.cancel,
                    variant: NcButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  NcButton(
                    key: const ValueKey<String>('delete-deck-confirm'),
                    label: l10n.delete,
                    variant: NcButtonVariant.destructive,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              );
            },
          ),
        ),
        config: const NcTestConfig(size: Size(1280, 900)),
      );
      await tester.tap(find.text(l10n.deckDeleteDialogTitle));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.deckDeleteDialogMessage('Испанский')),
        findsOneWidget,
      );
      expect(find.byType(NcIcon3D), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('delete-deck-confirm')),
      );
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('на телефоне кнопки столбиком', (WidgetTester tester) async {
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) => NcButton(
            label: l10n.deckDeleteDialogTitle,
            onPressed: () => showNcDialog<void>(
              context,
              title: l10n.deckDeleteDialogTitle,
              actions: <Widget>[
                NcButton(label: l10n.cancel, onPressed: () {}),
                NcButton(
                  label: l10n.delete,
                  variant: NcButtonVariant.destructive,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
        config: const NcTestConfig(size: Size(390, 844)),
      );
      await tester.tap(find.text(l10n.deckDeleteDialogTitle));
      await tester.pumpAndSettle();
      final Offset cancel = tester.getCenter(find.text(l10n.cancel));
      final Offset delete = tester.getCenter(find.text(l10n.delete));
      expect(
        (cancel.dx - delete.dx).abs(),
        lessThan(1),
        reason: 'На телефоне кнопки столбиком (§8)',
      );
      expect(cancel.dy, lessThan(delete.dy));
    });
  });

  group('NcToast', () {
    testWidgets('сообщение и «Отменить»; действие скрывает тост', (
      WidgetTester tester,
    ) async {
      var undone = 0;
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) => NcButton(
            label: l10n.deckActionArchive,
            onPressed: () => showNcToast(
              context,
              message: l10n.deckArchivedMessage,
              actionLabel: l10n.undo,
              onAction: () => undone++,
            ),
          ),
        ),
        config: const NcTestConfig(size: Size(520, 600)),
      );
      await tester.tap(find.text(l10n.deckActionArchive));
      await tester.pumpAndSettle();
      expect(find.byType(NcToast), findsOneWidget);
      expect(find.text(l10n.deckArchivedMessage), findsOneWidget);
      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(find.byType(NcToast), findsNothing);
    });

    testWidgets('тост исчезает по таймеру и не перехватывает указатель', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await pumpNc(
        tester,
        Stack(
          fit: StackFit.expand,
          children: <Widget>[
            NcTappable(
              onTap: () => taps++,
              child: const ColoredBox(color: NcColors.transparent),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Builder(
                  builder: (BuildContext context) => NcButton(
                    label: l10n.deckActionArchive,
                    onPressed: () => showNcToast(
                      context,
                      message: l10n.deckArchivedMessage,
                      duration: const Duration(seconds: 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        config: const NcTestConfig(size: Size(520, 600)),
      );
      await tester.tap(find.text(l10n.deckActionArchive));
      await tester.pumpAndSettle();
      expect(find.byType(NcToast), findsOneWidget);
      // Тост висит внизу, но указатель проходит сквозь него к экрану.
      await tester.tapAt(tester.getCenter(find.byType(NcToast)));
      await tester.pump();
      expect(taps, 1, reason: 'Тост не блокирует экран (§8)');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.byType(NcToast),
        findsNothing,
        reason: 'Тост скрывается по истечении времени (§8)',
      );
    });

    testWidgets('ошибка даёт heavyImpact (§7)', (WidgetTester tester) async {
      final NcHapticRecorder recorder = NcHapticRecorder()..install();
      addTearDown(recorder.uninstall);
      await pumpNc(
        tester,
        Builder(
          builder: (BuildContext context) => NcButton(
            label: l10n.genericError,
            onPressed: () => showNcToast(
              context,
              message: l10n.genericError,
              tone: NcToastTone.error,
            ),
          ),
        ),
        config: const NcTestConfig(size: Size(520, 600)),
        haptics: NcHaptics(enabled: true, clock: recorder.clock),
      );
      await tester.tap(find.text(l10n.genericError));
      await tester.pumpAndSettle();
      expect(
        recorder.vibrations.any(
          (String value) => value.contains('heavyImpact'),
        ),
        isTrue,
        reason: 'Тост ошибки — heavyImpact (§7): ',
      );
      expect(find.byType(NcToast), findsOneWidget);
    });
  });
}
