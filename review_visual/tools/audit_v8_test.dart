// Independent visual-audit harness for gates G1–G12 (CardFlow, audit v8).
//
// It renders the PRODUCTION ReviewSessionScreen (same widget the app routes to),
// with the production theme and the production text-scale application
// (`settings.textScale` -> MediaQuery.textScaler, exactly as lib/ui/app.dart
// does in `builder:`).  The author's harness (v8_shots_test.dart) omits that
// wrapper, so its "text90" configurations were measured at 100 % text scale;
// here the user scale is applied honestly.
//
// It prints machine-readable lines:
//   META   cfg / state / viewport
//   CARD   rect in device px (DPR = 1 -> equals logical px)
//   TREE   keys that exist, with enabled/disabled state
//   DIS    every disabled button found on screen (G5)
//   TXT    every RichText inside the card: text, base px, painted px, height
//   BTN    rating / reveal geometry, gaps, rows
//   SCROLL maxScrollExtent inside the card (does content fit?)
//   ANIM   opacity of the rating panel at flip-mid and after 220 ms
//   IMG    CardImageView geometry: rendered AR vs source AR, fit
//
// Run:
//   fvm flutter test review_visual/tools/audit_v8_test.dart --no-pub
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';
const String _outDir = 'review_visual/screenshots/v8';

const String kFront =
    'Сколько векторных диаграмм строят по результатам измерений и вычислений?';
const String kBack =
    'Две: диаграмму токов и диаграмму напряжений. Их строят в одной системе '
    'координат, чтобы наглядно показать сдвиг фаз между током и напряжением.';

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
  front: kFront,
  back: kBack,
  createdAt: DateTime.utc(2026, 11, 13, 10),
);

/// Harness that mirrors lib/ui/app.dart: settings.textScale -> textScaler.
Widget _app({
  required double scale,
  required double textScale,
  bool disableAnimations = false,
}) {
  final List<Override> overrides = decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Электротехника', totalCards: 12),
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
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        final double probe = media.textScaler.scale(16);
        final double systemFactor = probe.isFinite && probe > 0 ? probe / 16 : 1;
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(systemFactor * textScale),
            disableAnimations: disableAnimations,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    ),
  );
}

Future<void> _pumpSession(
  WidgetTester tester,
  double factor,
  double textScale,
  Size size, {
  bool disableAnimations = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  AppAdaptive.debugOverride = factor;
  addTearDown(() => AppAdaptive.debugOverride = null);
  await tester.pumpWidget(
    _app(
      scale: factor,
      textScale: textScale,
      disableAnimations: disableAnimations,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final RenderView view = tester.binding.renderViews.first;
    final OffsetLayer layer = view.debugLayer! as OffsetLayer;
    final ui.Image image = await layer.toImage(view.paintBounds);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    final File file = File('$_outDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT $name ${image.width}x${image.height}');
  });
}

// ---------------------------------------------------------------------------
// measurement helpers
// ---------------------------------------------------------------------------

Finder get _cardFinder => find.byKey(const ValueKey<String>('review-card'));

double _painted(WidgetTester tester, double base) {
  final MediaQueryData media = MediaQuery.of(tester.element(_cardFinder));
  final double painted = media.textScaler.scale(base);
  return double.parse(painted.toStringAsFixed(2));
}

/// All RichText inside the card with base & painted size and screen rect.
void _dumpTexts(WidgetTester tester, String label, Rect cardRect) {
  final List<Element> elements = find
      .descendant(of: _cardFinder, matching: find.byType(RichText))
      .evaluate()
      .toList();
  for (final Element e in elements) {
    final RichText rt = e.widget as RichText;
    final RenderBox box = e.renderObject! as RenderBox;
    final Offset o = box.localToGlobal(Offset.zero);
    final Size s = box.size;
    final String plain = rt.text.toPlainText().replaceAll('\n', r'\n');
    final double base = rt.text.style?.fontSize ?? 0;
    final String where = (o.dy + s.height <= cardRect.bottom + 0.5 &&
            o.dy >= cardRect.top - 0.5)
        ? 'inside'
        : 'OUTSIDE';
    // ignore: avoid_print
    print(
      'TXT $label "$plain" base=$base painted=${_painted(tester, base)} '
      'height=${rt.text.style?.height} rect=${o.dx.toStringAsFixed(1)},'
      '${o.dy.toStringAsFixed(1)},${s.width.toStringAsFixed(1)},'
      '${s.height.toStringAsFixed(1)} $where',
    );
  }
}

void _dumpTree(WidgetTester tester, String label) {
  const List<String> keys = <String>[
    'review-close',
    'review-undo',
    'review-why',
    'review-reveal',
    'review-toolbar',
    'review-rating-panel',
    'review-rating-again',
    'review-rating-hard',
    'review-rating-good',
    'review-rating-easy',
    'review-rating-hint',
    'review-keyboard-hints',
    'review-keyboard-hints-front',
    'review-interval-again',
    'review-interval-good',
  ];
  final List<String> found = <String>[];
  for (final String key in keys) {
    final Finder f = find.byKey(ValueKey<String>(key));
    if (f.evaluate().isEmpty) continue;
    String state = 'visible';
    final Widget w = tester.widget(f);
    if (w is FilledButton) {
      state = w.onPressed == null ? 'DISABLED' : 'enabled';
    } else if (w is IconButton) {
      state = w.onPressed == null ? 'DISABLED' : 'enabled';
    }
    found.add('$key($state)');
  }
  // ignore: avoid_print
  print('TREE $label n=${found.length} ${found.join(' ')}');
}

/// Every disabled/onPressed-null button reachable on screen (G5).
void _dumpDisabled(WidgetTester tester, String label) {
  final List<String> disabled = <String>[];
  for (final Element e in find.byType(IconButton).evaluate()) {
    final IconButton b = e.widget as IconButton;
    if (b.onPressed == null) {
      final Key? k = b.key;
      disabled.add('IconButton(${k is ValueKey<String> ? k.value : '?'})');
    }
  }
  for (final Element e in find.byType(FilledButton).evaluate()) {
    final FilledButton b = e.widget as FilledButton;
    if (b.onPressed == null) {
      final Key? k = b.key;
      disabled.add('FilledButton(${k is ValueKey<String> ? k.value : '?'})');
    }
  }
  for (final Element e in find.byType(TextButton).evaluate()) {
    final TextButton b = e.widget as TextButton;
    if (b.onPressed == null) {
      disabled.add('TextButton');
    }
  }
  // ignore: avoid_print
  print('DIS $label count=${disabled.length} ${disabled.join(' ')}');
}

double _cardScrollExtent(WidgetTester tester) {
  double maxExtent = 0;
  for (final Element e in find
      .descendant(of: _cardFinder, matching: find.byType(Scrollable))
      .evaluate()) {
    final ScrollableState state = (e as StatefulElement).state as ScrollableState;
    maxExtent = math.max(maxExtent, state.position.maxScrollExtent);
  }
  return maxExtent;
}

void _dumpGeometry(WidgetTester tester, String label) {
  final Size viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
  final Rect cardRect = tester.getRect(_cardFinder);
  final Size card = cardRect.size;
  // ignore: avoid_print
  print(
    'META $label viewport=${viewport.width.toStringAsFixed(1)}x'
    '${viewport.height.toStringAsFixed(1)} factor=${AppAdaptive.factorForContext(tester.element(_cardFinder)).toStringAsFixed(2)} '
    'textScale=${MediaQuery.of(tester.element(_cardFinder)).textScaler.scale(1).toStringAsFixed(2)} '
    'card=${card.width.toStringAsFixed(1)}x${card.height.toStringAsFixed(1)} '
    'cardShareW=${(100 * card.width / viewport.width).toStringAsFixed(1)} '
    'cardShareH=${(100 * card.height / viewport.height).toStringAsFixed(1)}',
  );
  // ignore: avoid_print
  print(
    'CARD $label ${cardRect.left.toStringAsFixed(1)} '
    '${cardRect.top.toStringAsFixed(1)} ${card.width.toStringAsFixed(1)} '
    '${card.height.toStringAsFixed(1)}',
  );
  _dumpTree(tester, label);
  _dumpDisabled(tester, label);

  // Ratings.
  final Finder again = find.byKey(const ValueKey<String>('review-rating-again'));
  if (again.evaluate().isNotEmpty) {
    final Rect rAgain = tester.getRect(again);
    final Rect rHard = tester.getRect(
      find.byKey(const ValueKey<String>('review-rating-hard')),
    );
    final Rect rGood = tester.getRect(
      find.byKey(const ValueKey<String>('review-rating-good')),
    );
    final Rect rEasy = tester.getRect(
      find.byKey(const ValueKey<String>('review-rating-easy')),
    );
    final Set<double> tops = <double>{
      rAgain.top.roundToDouble(),
      rHard.top.roundToDouble(),
      rGood.top.roundToDouble(),
      rEasy.top.roundToDouble(),
    };
    final List<String> gaps = <String>[
      'again-hard=${(rHard.left - rAgain.right).toStringAsFixed(1)}',
      'hard-good=${(rGood.left - rHard.right).toStringAsFixed(1)}',
      'good-easy=${(rEasy.left - rGood.right).toStringAsFixed(1)}',
      'again-good-v=${(rGood.top - rAgain.bottom).toStringAsFixed(1)}',
    ];
    // ignore: avoid_print
    print(
      'BTN $label rating=${rGood.width.toStringAsFixed(1)}x'
      '${rGood.height.toStringAsFixed(1)} rows=${tops.length} '
      'gap=${gaps.join(',')} '
      'panelInCard=${rEasy.bottom <= cardRect.bottom + 0.5}',
    );
    // Painted label size of "Хорошо".
    final AppLocalizations l10n = AppLocalizations.of(tester.element(_cardFinder));
    final Finder goodLabel = find.descendant(
      of: find.byKey(const ValueKey<String>('review-rating-good')),
      matching: find.text(l10n.ratingGood),
    );
    if (goodLabel.evaluate().isNotEmpty) {
      final Element e = find
          .descendant(of: goodLabel, matching: find.byType(RichText))
          .evaluate()
          .first;
      final RichText rt = e.widget as RichText;
      final double base = rt.text.style?.fontSize ?? 0;
      // ignore: avoid_print
      print(
        'BTN_LABEL $label base=$base painted=${_painted(tester, base)} '
        'height=${rt.text.style?.height}',
      );
    }
  } else {
    // ignore: avoid_print
    print('BTN $label rating=none rows=0 gap=none panelInCard=none');
  }
  final Finder reveal = find.byKey(const ValueKey<String>('review-reveal'));
  if (reveal.evaluate().isNotEmpty) {
    final Size s = tester.getSize(reveal);
    // ignore: avoid_print
    print('REVEAL $label ${s.width.toStringAsFixed(1)}x${s.height.toStringAsFixed(1)}');
  } else {
    // ignore: avoid_print
    print('REVEAL $label none');
  }
  // ignore: avoid_print
  print(
    'SCROLL $label maxExtent=${_cardScrollExtent(tester).toStringAsFixed(1)}',
  );
  final Object? ex = tester.takeException();
  // ignore: avoid_print
  print('EXC $label ${ex == null ? 'none' : ex.toString().split('\n').first}');
  _dumpTexts(tester, label, cardRect);
}

Future<void> _reveal(WidgetTester tester) async {
  await tester.tap(_cardFinder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump(const Duration(milliseconds: 120));
}

// ---------------------------------------------------------------------------

Uint8List _patternPng(int width, int height) {
  final img.Image image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(236, 240, 250));
  img.drawRect(
    image,
    x1: 2,
    y1: 2,
    x2: width - 3,
    y2: height - 3,
    color: img.ColorRgb8(53, 37, 205),
    thickness: 6,
  );
  img.drawLine(
    image,
    x1: 0,
    y1: 0,
    x2: width - 1,
    y2: height - 1,
    color: img.ColorRgb8(186, 26, 26),
    thickness: 4,
  );
  img.drawLine(
    image,
    x1: width - 1,
    y1: 0,
    x2: 0,
    y2: height - 1,
    color: img.ColorRgb8(186, 26, 26),
    thickness: 4,
  );
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  setUpAll(() async {
    await _loadFont('Inter', '$_assets/assets/fonts/Inter-Variable.ttf');
    await _loadFont('MaterialIcons', '$_assets/fonts/MaterialIcons-Regular.otf');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final Map<String, (Size, double, double)> configs =
      <String, (Size, double, double)>{
        '2k150': (const Size(1707, 940), 1.24, 0.9),
        '2k100': (const Size(2560, 1440), 1.24, 1.0),
        '4k100': (const Size(3840, 2160), 1.45, 1.0),
        'fhd90': (const Size(1920, 1080), 1.0, 0.9),
        'fhd100': (const Size(1920, 1080), 1.0, 1.0),
        '390x844': (const Size(390, 844), 1.0, 1.0),
        '844x390': (const Size(844, 390), 1.0, 1.0),
        '533x400': (const Size(533, 400), 1.0, 0.9),
      };

  for (final MapEntry<String, (Size, double, double)> entry
      in configs.entries) {
    final (Size size, double factor, double textScale) = entry.value;

    testWidgets('Q ${entry.key}', (WidgetTester tester) async {
      await _pumpSession(tester, factor, textScale, size);
      _dumpGeometry(tester, '${entry.key}-Q');
      await _shoot(tester, 'v8_${entry.key}_Q');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('A ${entry.key}', (WidgetTester tester) async {
      await _pumpSession(tester, factor, textScale, size);
      await _reveal(tester);
      _dumpGeometry(tester, '${entry.key}-A');
      await _shoot(tester, 'v8_${entry.key}_A');
    }, timeout: const Timeout(Duration(seconds: 180)));
  }

  // G9: rating panel appears as a fade (Opacity < 1 at start, 1.0 after 220 ms)
  // and the flip crosses halves at ~150 ms of its 300 ms.
  testWidgets('ANIM panel fade', (WidgetTester tester) async {
    await _pumpSession(tester, 1.24, 0.9, const Size(1707, 940));
    await tester.tap(_cardFinder);
    await tester.pump();
    // 130 ms: still the question face (flip is 300 ms, face flips at 50 %).
    await tester.pump(const Duration(milliseconds: 130));
    final bool backAt130 = find
        .byKey(const ValueKey<String>('review-rating-panel'))
        .evaluate()
        .isNotEmpty;
    // 175 ms: back face exists, its fade has just started.
    await tester.pump(const Duration(milliseconds: 45));
    final Finder panel = find.byKey(
      const ValueKey<String>('review-rating-panel'),
    );
    final bool backAt175 = panel.evaluate().isNotEmpty;
    double opAt175 = -1;
    if (backAt175) {
      final Finder opacity = find.descendant(
        of: panel,
        matching: find.byType(Opacity),
      );
      if (opacity.evaluate().isNotEmpty) {
        opAt175 = tester
            .widget<Opacity>(opacity.first)
            .opacity;
      }
    }
    await tester.pump(const Duration(milliseconds: 230));
    double opAfter = -1;
    final Finder opacity2 = find.descendant(
      of: panel,
      matching: find.byType(Opacity),
    );
    if (opacity2.evaluate().isNotEmpty) {
      opAfter = tester.widget<Opacity>(opacity2.first).opacity;
    }
    // The flip duration is the widget constant (<= 350, >= 280).
    // ignore: avoid_print
    print(
      'ANIM panel backAt130=$backAt130 backAt175=$backAt175 '
      'opacityAt175=$opAt175 opacityAfter220=$opAfter',
    );
  }, timeout: const Timeout(Duration(seconds: 180)));

  // G9: reduced motion -> no fade widget, answer appears immediately.
  testWidgets('ANIM reduced motion', (WidgetTester tester) async {
    await _pumpSession(
      tester,
      1.24,
      0.9,
      const Size(1707, 940),
      disableAnimations: true,
    );
    await tester.tap(_cardFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final bool panel = find
        .byKey(const ValueKey<String>('review-rating-panel'))
        .evaluate()
        .isNotEmpty;
    final bool hasOpacity = find
        .descendant(
          of: find.byKey(const ValueKey<String>('review-rating-panel')),
          matching: find.byType(Opacity),
        )
        .evaluate()
        .isNotEmpty;
    // ignore: avoid_print
    print('ANIM_REDUCED panelAfterOneFrame=$panel opacityWidget=$hasOpacity');
  }, timeout: const Timeout(Duration(seconds: 180)));

  // G4: every image is contain and keeps the file's aspect ratio.
  final List<(String, int, int)> images = <(String, int, int)>[
    ('photo_960x720', 960, 720),
    ('tall_960x1371', 960, 1371),
    ('wide_1500x511', 1500, 511),
    ('very_tall_800x2000', 800, 2000),
  ];
  for (final (String name, int w, int h) in images) {
    testWidgets('IMG $name', (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1707, 940);
      addTearDown(tester.view.reset);
      AppAdaptive.debugOverride = 1.24;
      addTearDown(() => AppAdaptive.debugOverride = null);
      final Uint8List bytes = _patternPng(w, h);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: ruLocalizationDelegates,
          home: Scaffold(
            body: Center(
              child: CardImageView(bytes: bytes, maxWidth: 1116, maxHeight: 480),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
      final Size box = tester.getSize(find.byType(CardImageView));
      final Finder imageFinder = find.byType(Image);
      final String fit = imageFinder.evaluate().isEmpty
          ? 'no-image'
          : '${tester.widget<Image>(imageFinder.first).fit}';
      final bool hasAspectRatio = find
          .descendant(
            of: find.byType(CardImageView),
            matching: find.byType(AspectRatio),
          )
          .evaluate()
          .isNotEmpty;
      // The picture itself is painted with contain, so no pixel is cropped.
      // ignore: avoid_print
      print(
        'IMG $name source=${w}x$h sourceAR=${(w / h).toStringAsFixed(3)} '
        'box=${box.width.toStringAsFixed(1)}x${box.height.toStringAsFixed(1)} '
        'boxAR=${(box.width / box.height).toStringAsFixed(3)} fit=$fit '
        'aspectRatioWidget=$hasAspectRatio',
      );
      await _shoot(tester, 'v8_img_$name');
    }, timeout: const Timeout(Duration(seconds: 180)));
  }
}
