@Tags(<String>['golden'])
library;

import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Golden-снимки структуры Nocturne (§8, шаг 2.4).
void main() {
  setUpAll(loadNcFonts);
  final l10n = ncL10n;

  group('2.4 структура', () {
    ncGoldenGroup(
      'list_row',
      (NcGoldenVariant variant) => NcSection(
        title: l10n.settingsAppearanceTitle,
        children: <Widget>[
          NcListRow(
            leading: const Icon(Icons.contrast_rounded, size: 22),
            title: Text(l10n.settingsHighContrast),
            subtitle: Text(l10n.settingsHapticsHint),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {},
          ),
          NcListRow(
            leading: const Icon(Icons.vibration_rounded, size: 22),
            title: Text(l10n.settingsHapticsTitle),
            subtitle: Text(l10n.settingsHapticsHint),
            trailing: const NcSwitch(value: true, onChanged: null),
          ),
          NcListRow(
            title: Text(l10n.settingsAboutVersion('1.0.0')),
            trailing: const Text('1.0.0'),
            showDivider: false,
            onTap: () {},
          ),
        ],
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 620) : const Size(460, 420),
    );

    ncGoldenGroup(
      'section',
      (NcGoldenVariant variant) => NcSection(
        title: l10n.settingsAppearanceTitle,
        footer: Text(l10n.settingsHapticsHint),
        children: <Widget>[
          NcListRow(title: Text(l10n.settingsHighContrast)),
          NcListRow(title: Text(l10n.settingsHapticsTitle), showDivider: false),
        ],
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 480) : const Size(460, 320),
    );

    ncGoldenGroup(
      'card_tile',
      (NcGoldenVariant variant) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcCardTile(
            leading: const NcIcon3D(name: 'deck_gem_01', size: 52),
            title: Text(l10n.decksTitle),
            subtitle: Text(l10n.deckCardCount(12)),
            badge: NcBadge.count(count: 12),
            onTap: () {},
          ),
          const SizedBox(height: 12),
          NcCardTile(
            leading: const NcIcon3D(name: 'deck_gem_02', size: 52),
            title: Text(l10n.deckExportSuccess),
            subtitle: Text(l10n.deckCardCount(5)),
            trailing: const Icon(Icons.check_rounded),
            onTap: () {},
          ),
        ],
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 380) : const Size(460, 260),
    );

    ncGoldenGroup(
      'top_bar',
      (NcGoldenVariant variant) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcTopBar(largeTitle: l10n.decksTitle, title: l10n.decksTitle),
          const SizedBox(height: 8),
          NcTopBar(
            title: l10n.reviewTitle,
            leading: const NcIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Назад',
              variant: NcIconButtonVariant.glass,
            ),
          ),
        ],
      ),
      size: (_) => const Size(460, 220),
    );

    ncGoldenGroup(
      'empty_state',
      (NcGoldenVariant variant) => NcEmptyState(
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
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 720) : const Size(460, 520),
    );

    ncGoldenGroup(
      'error_state',
      (NcGoldenVariant variant) => NcErrorState(
        message: l10n.decksErrorTitle,
        retryLabel: l10n.retry,
        onRetry: () {},
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 620) : const Size(460, 440),
    );
  });
}
