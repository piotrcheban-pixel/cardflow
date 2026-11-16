@Tags(<String>['golden'])
library;

import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Golden-снимки оверлеев Nocturne (§8, шаг 2.5).
void main() {
  setUpAll(loadNcFonts);
  final l10n = ncL10n;

  group('2.5 оверлеи', () {
    ncGoldenGroup(
      'menu',
      (NcGoldenVariant variant) => NcMenu<void>(
        onDismiss: () {},
        items: <NcMenuItem<void>>[
          NcMenuItem<void>(label: l10n.deckRename, icon: Icons.edit_rounded),
          NcMenuItem<void>(
            label: l10n.deckExport,
            icon: Icons.ios_share_rounded,
          ),
          NcMenuItem<void>(
            label: l10n.deckActionArchive,
            icon: Icons.archive_rounded,
            dividerBefore: true,
          ),
          NcMenuItem<void>(
            label: l10n.delete,
            icon: Icons.delete_rounded,
            destructive: true,
          ),
        ],
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 380) : const Size(460, 300),
    );

    ncGoldenGroup(
      'sheet',
      (NcGoldenVariant variant) => SizedBox(
        width: 420,
        child: NcSheet(
          title: l10n.reviewSessionModeTitle,
          closeTooltip: l10n.commonClose,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              NcListRow(
                title: Text(l10n.reviewModeClassic),
                showDivider: false,
              ),
              NcListRow(title: Text(l10n.reviewModeFeed), showDivider: false),
            ],
          ),
          actions: NcButton(
            label: l10n.cancel,
            variant: NcButtonVariant.secondary,
            onPressed: () {},
          ),
        ),
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 560) : const Size(460, 420),
    );

    ncGoldenGroup(
      'dialog',
      (NcGoldenVariant variant) => SizedBox(
        width: 420,
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
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 640) : const Size(460, 480),
    );

    ncGoldenGroup(
      'toast',
      (NcGoldenVariant variant) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: NcToast(
          message: l10n.deckArchivedMessage,
          actionLabel: l10n.undo,
          duration: const Duration(seconds: 10),
        ),
      ),
      size: (_) => const Size(460, 160),
      settle: false,
      frame: const Duration(milliseconds: 300),
    );
  });
}
