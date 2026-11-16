@Tags(<String>['golden'])
library;

import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Golden-снимки примитивов (REDESIGN-SPEC §8, шаг 2.1):
/// dark/light × обычный/high-contrast × textScale 1,0/2,0.
void main() {
  setUpAll(loadNcFonts);
  final l10n = ncL10n;
  Size sizeFor(NcGoldenVariant variant) =>
      variant.textScale > 1 ? const Size(420, 200) : const Size(420, 150);

  group('2.1 примитивы', () {
    ncGoldenGroup(
      'surface',
      (NcGoldenVariant variant) => NcSurface(
        padding: const EdgeInsets.all(16),
        onTap: () {},
        semanticLabel: l10n.decksTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.decksTitle, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 4),
            Text(
              l10n.deckDueCount(12),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      size: sizeFor,
    );

    ncGoldenGroup(
      'glass',
      (NcGoldenVariant variant) => NcGlass(
        tier: NcGlassTier.thin,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(l10n.appTitle),
      ),
      size: (_) => const Size(360, 140),
    );

    ncGoldenGroup(
      'icon3d',
      (NcGoldenVariant variant) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const NcIcon3D(name: 'target', size: 64),
          const SizedBox(width: 16),
          const NcIcon3D(name: 'mode_classic', size: 56),
          const SizedBox(width: 16),
          const NcIcon3D(name: 'shield_error', size: 48),
        ],
      ),
      size: (_) => const Size(360, 160),
    );

    ncGoldenGroup(
      'key_hint',
      (NcGoldenVariant variant) => Wrap(
        spacing: 8,
        children: <Widget>[
          NcKeyHint(label: l10n.reviewTitle),
          const NcKeyHint(label: 'Space'),
          const NcKeyHint(label: '1'),
          const NcKeyHint(label: 'Enter'),
          const NcKeyHint(label: '2', compact: true),
        ],
      ),
      size: (_) => const Size(360, 140),
    );

    ncGoldenGroup(
      'badge',
      (NcGoldenVariant variant) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          NcBadge.count(count: 12),
          NcBadge(label: l10n.cardStateLearning, tone: NcBadgeTone.glacier),
          NcBadge(label: l10n.reviewCompletedTitle, tone: NcBadgeTone.jade),
          NcBadge(label: l10n.deckFilterDue, tone: NcBadgeTone.ember),
          NcBadge(label: l10n.generationFileParsed, tone: NcBadgeTone.neutral),
        ],
      ),
      size: (_) => const Size(360, 160),
    );

    ncGoldenGroup(
      'spinner',
      (NcGoldenVariant variant) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcSpinner(semanticLabel: l10n.commonLoading),
          const SizedBox(width: 16),
          NcSpinner(size: 32, strokeWidth: 3, semanticLabel: l10n.commonLoading),
        ],
      ),
      size: (_) => const Size(300, 120),
      settle: false,
    );

    ncGoldenGroup(
      'skeleton',
      (NcGoldenVariant variant) => const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NcSkeleton(width: 280, height: 20),
          SizedBox(height: 8),
          NcSkeleton.line(width: 220),
          SizedBox(height: 8),
          NcSkeleton.line(width: 160),
          SizedBox(height: 8),
          NcSkeleton.circle(height: 48),
        ],
      ),
      size: (_) => const Size(360, 220),
      settle: false,
    );
  });
}
