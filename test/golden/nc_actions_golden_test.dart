@Tags(<String>['golden'])
library;

import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Golden-снимки действий Nocturne (§8, шаг 2.2).
void main() {
  setUpAll(loadNcFonts);
  final l10n = ncL10n;
  Size sizeFor(NcGoldenVariant variant) =>
      variant.textScale > 1 ? const Size(460, 520) : const Size(460, 340);

  group('2.2 действия', () {
    ncGoldenGroup(
      'button',
      (NcGoldenVariant variant) => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          NcButton(label: l10n.reviewStartSession, onPressed: () {}),
          NcButton(
            label: l10n.save,
            variant: NcButtonVariant.secondary,
            onPressed: () {},
          ),
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
          NcButton(
            label: l10n.decksCreateGenerate,
            variant: NcButtonVariant.ai,
            onPressed: () {},
          ),
          NcButton(
            label: l10n.reviewDone,
            size: NcButtonSize.s,
            onPressed: () {},
          ),
          NcButton(
            label: l10n.generationAttachButton,
            size: NcButtonSize.l,
            prominent: true,
            onPressed: () {},
          ),
          NcButton(label: l10n.importConfirm, loading: true, onPressed: () {}),
          NcButton(label: l10n.reviewBack),
          NcButton(
            label: l10n.deckAddCardTooltip,
            icon: Icons.add_rounded,
            trailingIcon: Icons.expand_more_rounded,
            onPressed: () {},
          ),
        ],
      ),
      size: sizeFor,
    );

    ncGoldenGroup(
      'icon_button',
      (NcGoldenVariant variant) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcIconButton(
            icon: Icons.search_rounded,
            tooltip: l10n.decksSearchTooltip,
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          NcIconButton(
            icon: Icons.filter_alt_rounded,
            tooltip: l10n.decksFilterTooltip,
            variant: NcIconButtonVariant.tonal,
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          NcIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: l10n.reviewBack,
            variant: NcIconButtonVariant.glass,
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          NcIconButton(
            icon: Icons.close_rounded,
            tooltip: l10n.cancel,
            selected: true,
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          NcIconButton(
            icon: Icons.settings_rounded,
            tooltip: l10n.settingsOpenTooltip,
          ),
        ],
      ),
      size: (_) => const Size(460, 160),
    );

    ncGoldenGroup(
      'split_button',
      (NcGoldenVariant variant) => NcSplitButton(
        label: l10n.decksCreateButton,
        onPressed: () {},
        menuSemanticLabel: l10n.decksCreateMenuTooltip,
        items: <NcMenuItem<void>>[
          NcMenuItem<void>(label: l10n.decksCreateManual),
          NcMenuItem<void>(label: l10n.decksImportZip),
        ],
      ),
      size: (_) => const Size(460, 160),
    );

    ncGoldenGroup(
      'fab',
      (NcGoldenVariant variant) =>
          NcFab(label: l10n.decksCreateDeckFab, onPressed: () {}),
      size: (_) => const Size(460, 160),
    );
  });
}
