// v7 audit harness: renders the production review session at exact logical sizes
// (4K, exact 2K, FullHD, mobile) with real Inter/MaterialIcons fonts, prints
// geometry measurements and the widget tree of interactive elements.
//
// One screenshot per test: after `layer.toImage` the test's async guard must not
// be used for further interaction (that deadlocks flutter_test), so question and
// answer states are captured by separate tests.
//
// Run:
//   .fvm/versions/3.47.9/bin/flutter.bat test review_visual/tools/v7_shots_test.dart --no-pub
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';
const String _outDir = 'review_visual/screenshots/v7';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

Card _card() => makeCard(
  id: 'card-1',
  deckId: 'deck-1',
  front: 'Сколько векторных диаграмм строят по результатам измерений и вычислений?',
  back: 'Две: диаграмму токов и диаграмму напряжений.',
  createdAt: DateTime.utc(2026, 11, 13, 10),
);

Widget _harness({required double scale, required double textScale}) {
  final List<Override> overrides = decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Эл тех', totalCards: 12, newCards: 1),
      ],
    ),
    cardRepository: FakeCardRepository(cards: <Card>[_card()]),
    reviewRepository: FakeReviewRepository(),
    appSettingsStore: FakeAppSettingsStore(
      settings: AppSettings.defaults.copyWith(textScale: textScale),
    ),
  );
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GoRouter router = GoRouter(
    initialLocation: '/decks/deck-1/study',
    navigatorKey: navigatorKey,
    routes: <GoRoute>[
      GoRoute(
        path: '/decks/:id/study',
        builder: (BuildContext context, GoRouterState state) =>
            ReviewSessionScreen(deckId: state.pathParameters['id']!),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(scale: scale),
      routerConfig: router,
    ),
  );
}

Future<void> _shoot(WidgetTester tester, String name) async {
  // Real engine work (rasterising the layer and encoding PNG) must run outside
  // the fake-async zone, otherwise the widget test never completes.
  await tester.runAsync(() async {
    final RenderView view = tester.binding.renderViews.first;
    final OffsetLayer layer = view.debugLayer! as OffsetLayer;
    final ui.Image image = await layer.toImage(view.paintBounds);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File file = File('$_outDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT $name ${image.width}x${image.height}');
  });
}

Future<void> _pump(
  WidgetTester tester,
  double scale,
  double textScale,
  Size size,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  AppAdaptive.debugOverride = scale;
  addTearDown(() => AppAdaptive.debugOverride = null);
  await tester.pumpWidget(_harness(scale: scale, textScale: textScale));
  await tester.pumpAndSettle();
}

/// Font sizes actually painted inside the card (descending).
List<double> _cardFonts(WidgetTester tester) {
  final Finder card = find.byKey(const ValueKey<String>('review-card'));
  final MediaQueryData media = MediaQuery.of(tester.element(card));
  final List<double> sizes = <double>[];
  for (final Element element
      in find
          .descendant(of: card, matching: find.byType(RichText))
          .evaluate()) {
    final RichText rich = element.widget as RichText;
    final double base = rich.text.style?.fontSize ?? 0;
    sizes.add(
      double.parse((base * media.textScaler.scale(1)).toStringAsFixed(2)),
    );
  }
  sizes.sort((double a, double b) => b.compareTo(a));
  return sizes;
}

Future<void> _measure(WidgetTester tester, String label) async {
  final Size card = tester.getSize(
    find.byKey(const ValueKey<String>('review-card')),
  );
  final Rect cardRect = tester.getRect(
    find.byKey(const ValueKey<String>('review-card')),
  );
  final Size good = tester.getSize(
    find.byKey(const ValueKey<String>('review-rating-good')),
  );
  final double gap =
      tester
          .getRect(find.byKey(const ValueKey<String>('review-rating-hard')))
          .left -
      tester
          .getRect(find.byKey(const ValueKey<String>('review-rating-again')))
          .right;
  final Finder revealFinder = find.byKey(
    const ValueKey<String>('review-reveal'),
  );
  final String reveal = revealFinder.evaluate().isEmpty
      ? 'none'
      : '${tester.getSize(revealFinder).width.toStringAsFixed(1)}x'
            '${tester.getSize(revealFinder).height.toStringAsFixed(1)}';
  final List<double> fonts = _cardFonts(tester);
  final MediaQueryData media = MediaQuery.of(
    tester.element(find.byKey(const ValueKey<String>('review-card'))),
  );
  final double ratingFont =
      (16.0 * media.textScaler.scale(1) * AppAdaptive.debugOverride!);
  // ignore: avoid_print
  print(
    'MEASURE $label viewport=${media.size.width.toStringAsFixed(1)}x${media.size.height.toStringAsFixed(1)} '
    'card=${card.width.toStringAsFixed(1)}x${card.height.toStringAsFixed(1)} '
    'cardLeft=${cardRect.left.toStringAsFixed(1)} '
    'ratingGood=${good.width.toStringAsFixed(1)}x${good.height.toStringAsFixed(1)} '
    'gap=${gap.toStringAsFixed(1)} reveal=$reveal '
    'cardFonts=${fonts.take(4).join(",")} ratingFont=${ratingFont.toStringAsFixed(2)}',
  );
}

void _dumpInteractive(WidgetTester tester, String label) {
  final List<String> found = <String>[];
  for (final String key in <String>[
    'review-close',
    'review-undo',
    'review-why',
    'review-reveal',
    'review-rating-again',
    'review-rating-hard',
    'review-rating-good',
    'review-rating-easy',
    'review-rating-hint',
    'review-keyboard-hints-front',
    'review-keyboard-hints',
  ]) {
    final Finder f = find.byKey(ValueKey<String>(key));
    if (f.evaluate().isEmpty) continue;
    final String state;
    switch (key) {
      case 'review-rating-again':
      case 'review-rating-hard':
      case 'review-rating-good':
      case 'review-rating-easy':
        state = tester.widget<FilledButton>(f).onPressed == null
            ? 'DISABLED'
            : 'enabled';
      case 'review-undo':
        state = tester.widget<IconButton>(f).onPressed == null
            ? 'DISABLED'
            : 'enabled';
      default:
        state = 'visible';
    }
    found.add('$key($state)');
  }
  // ignore: avoid_print
  print('TREE $label visibleInteractive=${found.length} ${found.join(' ')}');
}

void main() {
  setUpAll(() async {
    await _loadFont('Inter', '$_assets/assets/fonts/Inter-Variable.ttf');
    await _loadFont(
      'MaterialIcons',
      '$_assets/fonts/MaterialIcons-Regular.otf',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async => null,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // ---- configurations -----------------------------------------------------
  final Map<String, (double, double, Size)> configs =
      <String, (double, double, Size)>{
        '2k150': (1.24, 0.9, const Size(1707, 940)),
        '2k100': (1.24, 1.0, const Size(2560, 1440)),
        '4k100': (1.45, 1.0, const Size(3840, 2160)),
        '4k150': (1.45, 1.0, const Size(2560, 1440)),
        'fhd': (1.0, 0.9, const Size(1920, 1080)),
        '390x844': (1.0, 1.0, const Size(390, 844)),
        '844x390': (1.0, 1.0, const Size(844, 390)),
      };
  const Map<String, String> titles = <String, String>{
    '2k150': '2K live 1707x940 text90',
    '2k100': '2K exact 2560x1440',
    '4k100': '4K 3840x2160 at 100%',
    '4k150': '4K at 150% = 2560x1440 logical',
    'fhd': 'FullHD 1920x1080 text90',
    '390x844': 'mobile portrait 390x844',
    '844x390': 'mobile landscape 844x390',
  };

  for (final MapEntry<String, (double, double, Size)> entry
      in configs.entries) {
    final (double, double, Size) cfg = entry.value;

    testWidgets('Q ${titles[entry.key]}', (WidgetTester tester) async {
      await _pump(tester, cfg.$1, cfg.$2, cfg.$3);
      _dumpInteractive(tester, '${entry.key}-question');
      await _measure(tester, '${entry.key}-question');
      await _shoot(tester, 'wt_${entry.key}_classic_question');
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('A ${titles[entry.key]}', (WidgetTester tester) async {
      await _pump(tester, cfg.$1, cfg.$2, cfg.$3);
      await tester.tap(find.byKey(const ValueKey<String>('review-card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      _dumpInteractive(tester, '${entry.key}-answer');
      await _measure(tester, '${entry.key}-answer');
      await _shoot(tester, 'wt_${entry.key}_classic_answer');
    }, timeout: const Timeout(Duration(seconds: 120)));
  }
}
