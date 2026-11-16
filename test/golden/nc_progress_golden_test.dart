@Tags(<String>['golden'])
library;

import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Golden-снимки прогресса Nocturne (§8, шаг 2.6).
void main() {
  setUpAll(loadNcFonts);
  final l10n = ncL10n;

  group('2.6 прогресс', () {
    ncGoldenGroup(
      'progress_line',
      (NcGoldenVariant variant) => SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NcProgressLine(
              value: 0.35,
              semanticLabel: l10n.reviewProgressLabel,
            ),
            const SizedBox(height: 16),
            NcProgressLine(value: 0.72, height: 5),
            const SizedBox(height: 16),
            NcProgressLine(value: 1),
          ],
        ),
      ),
      size: (_) => const Size(460, 160),
    );

    ncGoldenGroup(
      'segmented_progress',
      (NcGoldenVariant variant) => SizedBox(
        width: 360,
        child: NcSegmentedProgress(
          total: 6,
          current: 2,
          rated: 2,
          ratingColors: <int, Color>{
            0: const Color(0xFF66D3A3),
            1: const Color(0xFFF0806B),
          },
          height: 4,
          semanticLabel: l10n.feedProgressSemantics(2, 6),
        ),
      ),
      size: (_) => const Size(460, 120),
      settle: false,
      frame: const Duration(milliseconds: 600),
    );

    ncGoldenGroup(
      'ring',
      (NcGoldenVariant variant) => NcRing(
        value: 0.72,
        size: 200,
        semanticLabel: l10n.statisticsRetentionTitle,
        child: NcAnimatedNumber(
          value: 72,
          duration: Duration.zero,
          format: (num value) => l10n.statisticsRetentionValue(value.round()),
        ),
      ),
      size: (_) => const Size(460, 300),
    );

    ncGoldenGroup(
      'animated_number',
      (NcGoldenVariant variant) => NcAnimatedNumber(
        value: 1234,
        duration: Duration.zero,
        style: const TextStyle(fontFamily: 'Literata', fontSize: 56),
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(460, 200) : const Size(460, 140),
    );
  });
}
