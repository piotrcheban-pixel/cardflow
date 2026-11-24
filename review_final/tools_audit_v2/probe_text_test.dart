// Аудит v2: диагностика мелких кеглей и геометрии чипов. Пишет только в stdout.
// Run: fvm flutter test review_final/tools_audit_v2/probe_text_test.dart --no-pub -r expanded
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/session_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

List<DeckSummary> _summaries() => <DeckSummary>[
  makeSummary(
    id: 'deck-1',
    name: 'Электротехника',
    totalCards: 71,
    newCards: 9,
    inProgressCards: 59,
    dueCards: 60,
  ),
];

List<Override> _overrides(double textScale) => decksOverrides(
  deckRepository: FakeDeckRepository(summaries: _summaries()),
  cardRepository: FakeCardRepository(),
  reviewRepository: FakeReviewRepository(),
  practiceRepository: FakePracticeRepository(),
  sessionPresetRepository: FakeSessionPresetRepository(),
  leechRepository: FakeLeechRepository(),
  appSettingsStore: FakeAppSettingsStore(
    settings: AppSettings.defaults.copyWith(textScale: textScale),
  ),
);

Widget _app(double factor, double textScale, String location) {
  final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: _overrides(textScale),
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(scale: factor),
      routerConfig: createAppRouter(initialLocation: location, navigatorKey: key),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    ),
  );
}

void main() {
  setUpAll(() async {
    await _loadFont('Inter', '$_assets/assets/fonts/Inter-Variable.ttf');
    await _loadFont('MaterialIcons', '$_assets/fonts/MaterialIcons-Regular.otf');
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

  Future<void> run(
    WidgetTester tester, {
    required Size size,
    required double factor,
    required double textScale,
    required String location,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    AppAdaptive.debugOverride = factor;
    addTearDown(() => AppAdaptive.debugOverride = null);
    await tester.pumpWidget(_app(factor, textScale, location));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  void dumpSmall(WidgetTester tester, String tag) {
    final double ts = MediaQuery.of(
      tester.element(find.byType(Scaffold).first),
    ).textScaler.scale(1);
    for (final Element e in find.byType(RichText).evaluate()) {
      final RichText rt = e.widget as RichText;
      final double fs = (rt.text.style?.fontSize ?? 0) * ts;
      if (fs >= 13.5) continue;
      final String t = rt.text.toPlainText().replaceAll('\n', ' ');
      final RenderBox? box = e.renderObject as RenderBox?;
      final Offset? pos = box?.localToGlobal(Offset.zero);
      // ignore: avoid_print
      print(
        'SMALL $tag ${fs.toStringAsFixed(1)}px "${t.length > 40 ? '${t.substring(0, 40)}…' : t}" '
        '@${pos?.dx.toStringAsFixed(0)},${pos?.dy.toStringAsFixed(0)} '
        'size=${box?.size.width.toStringAsFixed(0)}x${box?.size.height.toStringAsFixed(0)}',
      );
    }
  }

  void dumpChips(WidgetTester tester, String tag) {
    for (final Element e in find
        .byWidgetPredicate(
          (Widget w) =>
              w.runtimeType.toString() == 'ChoiceChip' ||
              w.runtimeType.toString() == 'FilterChip' ||
              w.runtimeType.toString() == 'SegmentedButton' ||
              w.runtimeType.toString() == 'InputChip',
        )
        .evaluate()) {
      final RenderBox? box = e.renderObject as RenderBox?;
      if (box == null) continue;
      final Offset o = box.localToGlobal(Offset.zero);
      // ignore: avoid_print
      print(
        'CHIP $tag ${e.widget.runtimeType} '
        '${box.size.width.toStringAsFixed(0)}x${box.size.height.toStringAsFixed(0)}'
        '@${o.dx.toStringAsFixed(0)},${o.dy.toStringAsFixed(0)}',
      );
    }
  }

  for (final (String name, Size size, double factor, double text) in <
    (String, Size, double, double)
  >[
    ('2k150', const Size(1706.7, 940), 1.24, 0.9),
    ('4k100', const Size(3840, 2160), 1.45, 1.0),
    ('fhd150', const Size(1280, 720), 1.0, 0.9),
  ]) {
    testWidgets('decks $name', (WidgetTester tester) async {
      await run(
        tester,
        size: size,
        factor: factor,
        textScale: text,
        location: '/',
      );
      dumpSmall(tester, 'decks|$name');
      dumpChips(tester, 'decks|$name');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('settings $name', (WidgetTester tester) async {
      await run(
        tester,
        size: size,
        factor: factor,
        textScale: text,
        location: '/settings',
      );
      dumpSmall(tester, 'settings|$name');
      dumpChips(tester, 'settings|$name');
    }, timeout: const Timeout(Duration(seconds: 180)));
  }
}
