import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/tokens/nc_radii.dart';
import 'package:cardflow/ui/design/tokens/nc_spacing.dart';

/// Пространство, сетка и радиусы Nocturne (REDESIGN-SPEC §3.1–3.2).
void main() {
  group('NcSpace: 4-pt сетка §3.1', () {
    test('шкала', () {
      expect(NcSpace.scale, <double>[
        0,
        2,
        4,
        8,
        12,
        16,
        20,
        24,
        32,
        40,
        56,
        72,
        96,
      ]);
      expect(NcSpace.s0, 0);
      expect(NcSpace.s2, 2);
      expect(NcSpace.s4, 4);
      expect(NcSpace.s8, 8);
      expect(NcSpace.s12, 12);
      expect(NcSpace.s16, 16);
      expect(NcSpace.s20, 20);
      expect(NcSpace.s24, 24);
      expect(NcSpace.s32, 32);
      expect(NcSpace.s40, 40);
      expect(NcSpace.s56, 56);
      expect(NcSpace.s72, 72);
      expect(NcSpace.s96, 96);
    });

    test('поля страницы: телефон 20 · планшет 32 · ПК 40', () {
      expect(NcSpace.pagePadding(390), 20);
      expect(NcSpace.pagePadding(599), 20);
      expect(NcSpace.pagePadding(600), 32);
      expect(NcSpace.pagePadding(1023), 32);
      expect(NcSpace.pagePadding(1024), 40);
      expect(NcSpace.pagePadding(1440), 40);
    });

    test('между секциями 32 / ПК 40', () {
      expect(NcSpace.sectionGap(390), 32);
      expect(NcSpace.sectionGap(1440), 40);
    });

    test('максимальная ширина контента', () {
      expect(NcSpace.maxListWidth, 760);
      expect(NcSpace.maxSessionWidth, 640);
      expect(NcSpace.maxFormWidth, 680);
      expect(NcSpace.maxStatsWidth, 1120);
    });

    test('плитка и касаемые зоны', () {
      expect(NcSpace.tilePaddingH, 16);
      expect(NcSpace.tilePaddingV, 14);
      expect(NcSpace.minTouchTarget, 48);
      expect(NcSpace.ratingButtonHeight, 64);
      expect(NcSpace.dockClearance, 120);
    });
  });

  group('NcRadii: непрерывные скругления §3.2', () {
    test('значения радиусов', () {
      expect(NcRadii.xs, 8);
      expect(NcRadii.s, 12);
      expect(NcRadii.m, 16);
      expect(NcRadii.l, 22);
      expect(NcRadii.xl, 30);
      expect(NcRadii.xxl, 38);
      expect(NcRadii.pill, 999);
    });

    test('BorderRadius из токена', () {
      expect(
        NcRadii.borderRadius(NcRadii.l),
        const BorderRadius.all(Radius.circular(22)),
      );
    });

    test('концентричность: внешний − отступ, минимум r.xs', () {
      expect(NcRadii.concentric(outer: 30, inset: 12), 18);
      expect(NcRadii.concentric(outer: 22, inset: 0), 22);
      expect(NcRadii.concentric(outer: 30, inset: 200), NcRadii.xs);
      expect(
        NcRadii.concentricBorder(outer: NcRadii.xl, inset: 12),
        const BorderRadius.all(Radius.circular(18)),
      );
    });

    test('форма — superellipse, а не RRect (ADR-035 §4)', () {
      final ShapeBorder shape = NcRadii.superellipse(NcRadii.xl);
      expect(shape, isA<RoundedSuperellipseBorder>());
      expect(
        (shape as RoundedSuperellipseBorder).borderRadius,
        const BorderRadius.all(Radius.circular(30)),
      );
      expect(
        NcRadii.superellipse(NcRadii.m, side: const BorderSide(width: 1)).side,
        const BorderSide(width: 1),
      );
    });
  });
}
