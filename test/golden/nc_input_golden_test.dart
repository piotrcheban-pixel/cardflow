@Tags(<String>['golden'])
library;

import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Golden-снимки полей ввода Nocturne (§8, шаг 2.3).
void main() {
  setUpAll(loadNcFonts);
  final l10n = ncL10n;
  Size tall(NcGoldenVariant variant) =>
      variant.textScale > 1 ? const Size(460, 640) : const Size(460, 460);

  group('2.3 ввод', () {
    ncGoldenGroup(
      'text_field',
      (NcGoldenVariant variant) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcTextField(
            label: l10n.cardFormFrontLabel,
            initialValue: 'Что такое фотосинтез?',
            helper: l10n.cardFormReversedHint,
          ),
          const SizedBox(height: 16),
          NcTextField(
            label: l10n.deckNameLabel,
            initialValue: '',
            hint: l10n.deckNameEmptyError,
            errorText: l10n.deckNameEmptyError,
          ),
          const SizedBox(height: 16),
          NcTextField(
            label: l10n.cardFormBackLabel,
            multiline: true,
            maxLength: 200,
            showCounter: true,
            initialValue: 'Преобразование световой энергии',
          ),
        ],
      ),
      size: tall,
    );

    ncGoldenGroup(
      'search_field',
      (NcGoldenVariant variant) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcSearchField(hint: l10n.decksSearchHint),
          const SizedBox(height: 16),
          NcSearchField(
            controller: TextEditingController(text: 'биология'),
            hint: l10n.decksSearchHint,
            clearTooltip: l10n.decksSearchClearTooltip,
          ),
        ],
      ),
      size: (_) => const Size(460, 200),
    );

    ncGoldenGroup(
      'switch',
      (NcGoldenVariant variant) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcSwitch(value: false, onChanged: (_) {}),
          const SizedBox(width: 24),
          NcSwitch(value: true, onChanged: (_) {}),
          const SizedBox(width: 24),
          const NcSwitch(value: true),
        ],
      ),
      size: (_) => const Size(460, 160),
    );

    ncGoldenGroup(
      'segmented',
      (NcGoldenVariant variant) => NcSegmented<String>(
        value: 'feed',
        segments: <NcSegment<String>>[
          NcSegment<String>(value: 'classic', label: l10n.reviewModeClassic),
          NcSegment<String>(value: 'feed', label: l10n.reviewModeFeed),
          NcSegment<String>(value: 'practice', label: l10n.reviewModePractice),
        ],
        onChanged: (_) {},
      ),
      size: (_) => const Size(460, 160),
    );

    ncGoldenGroup(
      'slider',
      (NcGoldenVariant variant) => NcSlider(
        value: 60,
        min: 0,
        max: 100,
        divisions: 10,
        semanticLabel: l10n.settingsRetentionTitle,
        valueLabel: (double value) =>
            l10n.settingsRetentionValue(value.round()),
        onChanged: (_) {},
      ),
      size: (_) => const Size(460, 160),
    );

    ncGoldenGroup(
      'stepper',
      (NcGoldenVariant variant) => NcStepper(
        value: 20,
        semanticLabel: l10n.settingsDailyNewLimitTitle,
        onDecrement: () {},
        onIncrement: () {},
      ),
      size: (_) => const Size(460, 140),
    );

    ncGoldenGroup(
      'chip',
      (NcGoldenVariant variant) => Wrap(
        spacing: 8,
        runSpacing: 8,
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
          NcChip.status(label: l10n.generationFileParsing),
        ],
      ),
      size: (_) => const Size(460, 220),
    );

    ncGoldenGroup(
      'dropdown',
      (NcGoldenVariant variant) => NcDropdown<String>(
        value: 'deepseek',
        label: l10n.settingsModelLabel,
        items: <NcDropdownItem<String>>[
          NcDropdownItem<String>(value: 'deepseek', label: 'deepseek-chat'),
          NcDropdownItem<String>(value: 'flash', label: 'deepseek-flash'),
        ],
        onChanged: (_) {},
      ),
      size: (_) => const Size(460, 180),
    );
  });
}
