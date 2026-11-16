import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';

import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/nc_harness.dart';

/// Поведение полей ввода Nocturne (REDESIGN-SPEC §8, шаг 2.3):
/// `NcTextField`, `NcSearchField`, `NcSwitch`, `NcSegmented`, `NcSlider`,
/// `NcStepper`, `NcChip`, `NcDropdown`.
void main() {
  final AppLocalizations l10n = ncL10n;

  group('NcTextField', () {
    testWidgets('ввод вызывает onChanged, метка и helper из ARB', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      final List<String> changes = <String>[];
      await pumpNc(
        tester,
        NcTextField(
          controller: controller,
          label: l10n.deckNameLabel,
          helper: l10n.cardFormReversedHint,
          onChanged: changes.add,
        ),
        config: const NcTestConfig(size: Size(420, 300)),
      );
      expect(find.text(l10n.deckNameLabel), findsOneWidget);
      expect(find.text(l10n.cardFormReversedHint), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Испанский');
      await tester.pump();
      expect(controller.text, 'Испанский');
      expect(changes, <String>['Испанский']);
    });

    testWidgets('ошибка показывается текстом ember и рамкой', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcTextField(
          label: l10n.deckNameLabel,
          errorText: l10n.deckNameEmptyError,
        ),
        config: const NcTestConfig(size: Size(420, 300)),
      );
      expect(find.text(l10n.deckNameEmptyError), findsOneWidget);
    });

    testWidgets('счётчик символов виден при maxLength, multiline на auto', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcTextField(
          label: l10n.cardFormFrontLabel,
          multiline: true,
          maxLength: 50,
          showCounter: true,
        ),
        config: const NcTestConfig(size: Size(420, 400)),
      );
      expect(find.text('0/50'), findsOneWidget);
    });

    testWidgets('disabled: поле не принимает ввод', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcTextField(
          label: l10n.deckNameLabel,
          enabled: false,
          initialValue: 'Текст',
        ),
        config: const NcTestConfig(size: Size(420, 300)),
      );
      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcTextField(
          label: l10n.cardFormSourceExcerptLabel,
          helper: l10n.cardFormSourceExcerptTooLongError,
          multiline: true,
        ),
        config: const NcTestConfig(size: Size(420, 420)),
      );
    });
  });

  group('NcSearchField', () {
    testWidgets('поиск: ввод и очистка обнуляют запрос', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      final List<String> changes = <String>[];
      await pumpNc(
        tester,
        NcSearchField(
          controller: controller,
          hint: l10n.decksSearchHint,
          clearTooltip: l10n.decksSearchClearTooltip,
          semanticLabel: l10n.decksSearchTooltip,
          onChanged: changes.add,
        ),
        config: const NcTestConfig(size: Size(420, 240)),
      );
      expect(find.text(l10n.decksSearchHint), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'био');
      await tester.pump();
      expect(controller.text, 'био');
      await tester.tap(find.byTooltip(l10n.decksSearchClearTooltip));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(changes.last, isEmpty);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcSearchField(hint: l10n.decksSearchHint),
        config: const NcTestConfig(size: Size(420, 240)),
      );
    });
  });

  group('NcSwitch', () {
    testWidgets('тап переключает значение и семантику toggled', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      bool value = false;
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => NcSwitch(
            value: value,
            semanticLabel: l10n.settingsHighContrast,
            onChanged: (bool next) => setState(() => value = next),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(
        tester
            .getSemantics(find.byType(NcSwitch))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isFalse,
      );
      await tester.tap(find.byType(NcSwitch));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(
        tester
            .getSemantics(find.byType(NcSwitch))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
      semantics.dispose();
    });

    testWidgets('клавиатура: Space переключает', (WidgetTester tester) async {
      bool value = false;
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => NcSwitch(
            value: value,
            focusNode: node,
            onChanged: (bool next) => setState(() => value = next),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });

    testWidgets('disabled: тап не переключает', (WidgetTester tester) async {
      await pumpNc(
        tester,
        const NcSwitch(value: false),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      await tester.tap(find.byType(NcSwitch), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('NcSegmented', () {
    testWidgets('тап выбирает сегмент; семантика выбранного', (
      WidgetTester tester,
    ) async {
      String value = 'classic';
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) =>
              NcSegmented<String>(
                value: value,
                semanticLabel: l10n.reviewSessionModeTitle,
                segments: <NcSegment<String>>[
                  NcSegment<String>(
                    value: 'classic',
                    label: l10n.reviewModeClassic,
                  ),
                  NcSegment<String>(value: 'feed', label: l10n.reviewModeFeed),
                ],
                onChanged: (String next) => setState(() => value = next),
              ),
        ),
        config: const NcTestConfig(size: Size(520, 240)),
      );
      await tester.tap(find.text(l10n.reviewModeFeed));
      await tester.pumpAndSettle();
      expect(value, 'feed');
    });

    testWidgets('недоступный сегмент не выбирается', (
      WidgetTester tester,
    ) async {
      String value = 'classic';
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) =>
              NcSegmented<String>(
                value: value,
                segments: <NcSegment<String>>[
                  NcSegment<String>(
                    value: 'classic',
                    label: l10n.reviewModeClassic,
                  ),
                  NcSegment<String>(
                    value: 'feed',
                    label: l10n.reviewModeFeed,
                    enabled: false,
                  ),
                ],
                onChanged: (String next) => setState(() => value = next),
              ),
        ),
        config: const NcTestConfig(size: Size(520, 240)),
      );
      await tester.tap(find.text(l10n.reviewModeFeed), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(value, 'classic');
    });

    testWidgets('клавиатура: фокус + Enter выбирает сегмент', (
      WidgetTester tester,
    ) async {
      String value = 'classic';
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) =>
              NcSegmented<String>(
                value: value,
                segments: <NcSegment<String>>[
                  NcSegment<String>(
                    value: 'classic',
                    label: l10n.reviewModeClassic,
                  ),
                  NcSegment<String>(value: 'feed', label: l10n.reviewModeFeed),
                ],
                onChanged: (String next) => setState(() => value = next),
              ),
        ),
        config: const NcTestConfig(size: Size(520, 240)),
      );
      // Фокус на втором сегменте через Tab-обход.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(value, 'feed');
    });

    testWidgets('textScale 2,0 без overflow (горизонтальная прокрутка)', (
      WidgetTester tester,
    ) async {
      await pumpNcAtTextScale2(
        tester,
        NcSegmented<int>(
          value: 0,
          segments: <NcSegment<int>>[
            NcSegment<int>(value: 0, label: l10n.reviewModeClassic),
            NcSegment<int>(value: 1, label: l10n.reviewModeFeed),
            NcSegment<int>(value: 2, label: l10n.reviewModePractice),
            NcSegment<int>(value: 3, label: l10n.generationAttachButton),
          ],
          onChanged: (_) {},
        ),
        config: const NcTestConfig(size: Size(420, 300)),
      );
    });
  });

  group('NcSlider', () {
    testWidgets('клавиатура меняет значение', (WidgetTester tester) async {
      double value = 50;
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => NcSlider(
            value: value,
            min: 0,
            max: 100,
            divisions: 10,
            focusNode: node,
            semanticLabel: l10n.settingsRetentionTitle,
            onChanged: (double next) => setState(() => value = next),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 240)),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(value, greaterThan(50));
    });

    testWidgets('перетаскивание меняет значение', (WidgetTester tester) async {
      double value = 0;
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => NcSlider(
            value: value,
            min: 0,
            max: 100,
            onChanged: (double next) => setState(() => value = next),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 240)),
      );
      await tester.drag(find.byType(NcSlider), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(value, greaterThan(0));
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcSlider(value: 30, min: 0, max: 100, onChanged: (_) {}),
        config: const NcTestConfig(size: Size(420, 240)),
      );
    });
  });

  group('NcStepper', () {
    testWidgets('плюс и минус вызывают действия; ключи сохранены', (
      WidgetTester tester,
    ) async {
      int value = 5;
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => NcStepper(
            value: value,
            minusKey: const ValueKey<String>('settings-new-limit-minus'),
            valueKey: const ValueKey<String>('settings-new-limit-value'),
            plusKey: const ValueKey<String>('settings-new-limit-plus'),
            semanticLabel: l10n.settingsDailyNewLimitTitle,
            onDecrement: () => setState(() => value--),
            onIncrement: () => setState(() => value++),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 240)),
      );
      expect(
        find.byKey(const ValueKey<String>('settings-new-limit-value')),
        findsOneWidget,
      );
      expect(find.text('5'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('settings-new-limit-plus')),
      );
      await tester.pumpAndSettle();
      expect(find.text('6'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('settings-new-limit-minus')),
      );
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('долгое нажатие — автоповтор', (WidgetTester tester) async {
      int value = 0;
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => NcStepper(
            value: value,
            minusKey: const ValueKey<String>('minus'),
            plusKey: const ValueKey<String>('plus'),
            onIncrement: () => setState(() => value++),
            onDecrement: () => setState(() => value--),
          ),
        ),
        config: const NcTestConfig(size: Size(420, 240)),
      );
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('plus'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 900));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        value,
        greaterThan(2),
        reason: 'Долгое нажатие повторяет шаг (§8)',
      );
    });

    testWidgets('disabled: кнопки неактивны', (WidgetTester tester) async {
      await pumpNc(
        tester,
        const NcStepper(
          value: 3,
          minusKey: ValueKey<String>('minus'),
          plusKey: ValueKey<String>('plus'),
        ),
        config: const NcTestConfig(size: Size(420, 240)),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('plus')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcStepper(value: 20, onIncrement: () {}, onDecrement: () {}),
        config: const NcTestConfig(size: Size(420, 240)),
      );
    });
  });

  group('NcChip', () {
    testWidgets('фильтр переключается тапом', (WidgetTester tester) async {
      bool selected = false;
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) =>
              NcChip.filter(
                label: l10n.deckFilterAll,
                selected: selected,
                onSelected: () => setState(() => selected = !selected),
              ),
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      await tester.tap(find.text(l10n.deckFilterAll));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(
        find.descendant(
          of: find.byType(NcChip),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
        reason: 'Выбранный фильтр показывает галочку (§8)',
      );
    });

    testWidgets('тег удаляется крестиком', (WidgetTester tester) async {
      var deleted = 0;
      await pumpNc(
        tester,
        NcChip.tag(
          label: l10n.cardTagsLine('биология'),
          onDeleted: () => deleted++,
          deleteTooltip: l10n.delete,
        ),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      await tester.tap(find.byTooltip(l10n.delete));
      await tester.pumpAndSettle();
      expect(deleted, 1);
    });

    testWidgets('статус показывает точку семантики', (
      WidgetTester tester,
    ) async {
      await pumpNc(
        tester,
        NcChip.status(label: l10n.reviewCompletedTitle, tone: NcBadgeTone.jade),
        config: const NcTestConfig(size: Size(420, 200)),
      );
      expect(find.text(l10n.reviewCompletedTitle), findsOneWidget);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NcChip.filter(
              label: l10n.deckFilterInProgress,
              selected: true,
              onSelected: () {},
            ),
            const SizedBox(height: 8),
            NcChip.tag(label: l10n.cardTagsLine('термины')),
            const SizedBox(height: 8),
            NcChip.status(label: l10n.reviewCompletedTitle),
          ],
        ),
        config: const NcTestConfig(size: Size(420, 400)),
      );
    });
  });

  group('NcDropdown', () {
    testWidgets('открывает меню и возвращает выбранное значение', (
      WidgetTester tester,
    ) async {
      String? value = 'a';
      await pumpNc(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) =>
              NcDropdown<String>(
                value: value,
                label: l10n.settingsModelLabel,
                fieldKey: const ValueKey<String>('provider-model'),
                items: <NcDropdownItem<String>>[
                  NcDropdownItem<String>(value: 'a', label: 'Модель A'),
                  NcDropdownItem<String>(value: 'b', label: 'Модель B'),
                ],
                onChanged: (String next) => setState(() => value = next),
              ),
        ),
        config: const NcTestConfig(size: Size(520, 320)),
      );
      expect(find.text('Модель A'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('provider-model')));
      await tester.pumpAndSettle();
      expect(find.text('Модель B'), findsOneWidget);
      await tester.tap(find.text('Модель B'));
      await tester.pumpAndSettle();
      expect(value, 'b');
      expect(find.text('Модель B'), findsOneWidget);
    });

    testWidgets('disabled: меню не открывается', (WidgetTester tester) async {
      await pumpNc(
        tester,
        NcDropdown<String>(
          value: null,
          label: l10n.settingsModelLabel,
          hint: l10n.generationModelLabel,
          enabled: false,
          fieldKey: const ValueKey<String>('provider-model'),
          items: <NcDropdownItem<String>>[
            NcDropdownItem<String>(value: 'a', label: 'Модель A'),
          ],
        ),
        config: const NcTestConfig(size: Size(520, 320)),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('provider-model')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Модель A'), findsNothing);
    });

    testWidgets('textScale 2,0 без overflow', (WidgetTester tester) async {
      await pumpNcAtTextScale2(
        tester,
        NcDropdown<String>(
          value: 'a',
          label: l10n.settingsModelLabel,
          items: <NcDropdownItem<String>>[
            NcDropdownItem<String>(value: 'a', label: 'Модель A'),
          ],
          onChanged: (_) {},
        ),
        config: const NcTestConfig(size: Size(420, 320)),
      );
    });
  });
}
