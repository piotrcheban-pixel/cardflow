import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/session/session_constructor_screen.dart';

import '../../helpers/glass_budget.dart';
import '../../helpers/nc_harness.dart';
import '../../helpers/nc_screen_harness.dart';
import '../../helpers/redesign_screen_fixtures.dart';

/// Конструктор сессии в оформлении Nocturne (REDESIGN-SPEC §9.14).
void main() {
  final AppLocalizations l10n = ncL10n;

  Future<void> pumpConstructor(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) => pumpNcScreen(
    tester,
    home: const SessionConstructorScreen(),
    overrides: ncStage3Overrides(),
    config: NcScreenConfig(size: size),
  );

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ключи §9.14: колоды, фильтры, режим, объём, порядок, низ', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(tester);
    // Теги появляются только у выбранных колод.
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-deck-deck-bio')),
    );
    await tester.pumpAndSettle();

    for (final String key in <String>[
      'constructor-deck-deck-bio',
      'constructor-deck-deck-stat',
      'constructor-tag-биология',
      'constructor-type-basic',
      'constructor-state-new',
      'constructor-mode',
      'constructor-limit-cards',
      'constructor-limit-minutes',
      'constructor-limit-value',
    ]) {
      if (find.byKey(ValueKey<String>(key)).evaluate().isEmpty) {
        await scrollTo(tester, find.byKey(ValueKey<String>(key)));
      }
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
    for (final String key in <String>[
      'constructor-shuffle',
      'constructor-interleave',
      'constructor-warmup',
    ]) {
      await scrollTo(tester, find.byKey(ValueKey<String>(key)));
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
    expect(
      find.byKey(const ValueKey<String>('constructor-available')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('constructor-save-preset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('constructor-start')),
      findsOneWidget,
    );
  });

  testWidgets('облик: пронумерованные секции, мини-плитки колод, стекло', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(tester);

    expect(find.text(l10n.constructorTitle), findsWidgets);
    expect(find.text(l10n.constructorDecksSection), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('constructor-deck-deck-bio')),
        matching: find.byType(NcIcon3D),
      ),
      findsOneWidget,
    );
    expectGlassBudget(tester, maxGroups: 2);
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('минутный лимит: NcStepper уменьшает значение и план', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(tester);

    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('constructor-limit-minutes')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-limit-minutes')),
    );
    await tester.pumpAndSettle();
    // 15 → 10 → 5 по дискретным значениям лимита.
    for (var index = 0; index < 2; index++) {
      await tester.tap(
        find.byKey(const ValueKey<String>('constructor-limit-minus')),
      );
      await tester.pumpAndSettle();
    }
    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('constructor-limit-value')),
    );
    expect(find.text(l10n.constructorLimitMinutesValue(5)), findsOneWidget);
  });

  testWidgets('пресет: NcDialog с ключами имени и подтверждения', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-deck-deck-bio')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-save-preset')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.constructorPresetDialogTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('constructor-preset-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('constructor-preset-submit')),
      findsOneWidget,
    );
  });

  testWidgets('старт активируется после выбора колоды', (
    WidgetTester tester,
  ) async {
    await pumpConstructor(tester);
    NcButton start() => tester.widget<NcButton>(
      find.byKey(const ValueKey<String>('constructor-start')),
    );
    expect(start().onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('constructor-deck-deck-bio')),
    );
    await tester.pumpAndSettle();
    expect(start().onPressed, isNotNull);
  });

  testWidgets('textScale 2,0 на телефоне 360 × 740 без overflow', (
    WidgetTester tester,
  ) async {
    await pumpNcScreenAtTextScale2(
      tester,
      home: const SessionConstructorScreen(),
      overrides: ncStage3Overrides(),
    );
    expect(
      find.byKey(const ValueKey<String>('constructor-start')),
      findsOneWidget,
    );
  });

  testWidgets('ширины 390/1440: низ бар помещает две кнопки', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1440, 900),
    ]) {
      await pumpConstructor(tester, size: size);
      final Rect save = tester.getRect(
        find.byKey(const ValueKey<String>('constructor-save-preset')),
      );
      final Rect start = tester.getRect(
        find.byKey(const ValueKey<String>('constructor-start')),
      );
      expect(save.right, lessThanOrEqualTo(size.width));
      expect(start.right, lessThanOrEqualTo(size.width));
      expect(save.overlaps(start), isFalse);
    }
  });
}
