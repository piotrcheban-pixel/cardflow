@Tags(<String>['golden'])
library;

import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Golden-снимки сессионных компонентов (§8, шаг 2.7).
void main() {
  setUpAll(loadNcFonts);
  final l10n = ncL10n;

  List<NcRatingSpec> ratings(NcColors colors) => <NcRatingSpec>[
    NcRatingSpec(
      label: l10n.ratingAgain,
      interval: l10n.reviewIntervalLessThanMinute,
      color: colors.ember,
      keyHint: '1',
      onPressed: () {},
    ),
    NcRatingSpec(
      label: l10n.ratingHard,
      interval: l10n.reviewIntervalMinutes(10),
      color: colors.amber,
      keyHint: '2',
      onPressed: () {},
    ),
    NcRatingSpec(
      label: l10n.ratingGood,
      interval: l10n.reviewIntervalDays(3),
      color: colors.jade,
      keyHint: '3',
      onPressed: () {},
    ),
    NcRatingSpec(
      label: l10n.ratingEasy,
      interval: l10n.reviewIntervalDays(7),
      color: colors.glacier,
      keyHint: '4',
      onPressed: () {},
    ),
  ];

  group('2.7 сессия', () {
    ncGoldenGroup(
      'monolith',
      (NcGoldenVariant variant) => SizedBox(
        width: 640,
        child: NcMonolith(
          metadata: Text(l10n.cardTypeBasic),
          badges: Row(
            children: <Widget>[
              NcBadge(label: l10n.cardStateNew),
              const SizedBox(width: 8),
              NcBadge(label: l10n.cardTagsLine('биология')),
            ],
          ),
          child: Text(
            l10n.decksEmptyMessage,
            style: const TextStyle(fontFamily: 'Literata', fontSize: 24),
          ),
        ),
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(700, 640) : const Size(700, 440),
    );

    ncGoldenGroup(
      'flip',
      (NcGoldenVariant variant) => SizedBox(
        width: 640,
        child: NcFlip(
          revealed: false,
          front: NcMonolith(
            child: Text(
              l10n.decksEmptyTitle,
              style: const TextStyle(fontFamily: 'Literata', fontSize: 28),
            ),
          ),
          back: NcMonolith(
            child: Text(
              l10n.decksEmptyMessage,
              style: const TextStyle(fontFamily: 'Literata', fontSize: 19),
            ),
          ),
        ),
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(700, 720) : const Size(700, 480),
    );

    ncGoldenGroup(
      'rating_button',
      (NcGoldenVariant variant) => Builder(
        builder: (BuildContext context) {
          final NcColors colors = NcTheme.of(context).colors;
          return SizedBox(
            width: 600,
            child: Row(
              children: <Widget>[
                for (final NcRatingSpec spec in ratings(colors))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: NcRatingButton(
                        label: spec.label,
                        interval: spec.interval,
                        color: spec.color,
                        keyHint: spec.keyHint,
                        onPressed: () {},
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(700, 260) : const Size(700, 180),
    );

    ncGoldenGroup(
      'rating_dock',
      (NcGoldenVariant variant) => Builder(
        builder: (BuildContext context) => SizedBox(
          width: 600,
          child: NcRatingDock(
            ratings: ratings(NcTheme.of(context).colors),
            semanticLabel: l10n.reviewSessionModeTitle,
          ),
        ),
      ),
      size: (NcGoldenVariant variant) =>
          variant.textScale > 1 ? const Size(700, 420) : const Size(700, 240),
    );
  });
}
