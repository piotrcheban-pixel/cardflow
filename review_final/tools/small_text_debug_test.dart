// Отладка: какие тексты на экране имеют кегль ниже 13 лог. px (и где).
// Run: .fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/small_text_debug_test.dart --no-pub
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
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

List<Override> _overrides() => decksOverrides(
  deckRepository: FakeDeckRepository(
    summaries: <DeckSummary>[
      makeSummary(
        id: 'deck-1',
        name: 'Электротехника',
        totalCards: 71,
        newCards: 9,
        inProgressCards: 59,
        dueCards: 60,
      ),
    ],
  ),
  cardRepository: FakeCardRepository(
    cards: <Card>[
      makeCard(
        id: 'card-1',
        deckId: 'deck-1',
        front: 'Вопрос',
        back: 'Ответ',
        tags: const <String>['#тег'],
      ),
    ],
  ),
  reviewRepository: FakeReviewRepository(),
  practiceRepository: FakePracticeRepository(),
  sessionPresetRepository: FakeSessionPresetRepository(),
  leechRepository: FakeLeechRepository(),
  appSettingsStore: FakeAppSettingsStore(
    settings: AppSettings.defaults.copyWith(textScale: 0.9),
  ),
);

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

  for (final String location in <String>[
    '/',
    '/decks/deck-1',
    '/statistics',
    '/settings',
  ]) {
    testWidgets('small text $location', (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1706.7, 940);
      addTearDown(tester.view.reset);
      AppAdaptive.debugOverride = 1.24;
      addTearDown(() => AppAdaptive.debugOverride = null);
      final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ru'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: ruLocalizationDelegates,
            theme: AppTheme.light(scale: 1.24),
            routerConfig: createAppRouter(
              initialLocation: location,
              navigatorKey: key,
            ),
            builder: (BuildContext context, Widget? child) {
              final MediaQueryData media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(textScaler: const TextScaler.linear(0.9)),
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final MediaQueryData media = MediaQuery.of(
        tester.element(find.byType(Scaffold).first),
      );
      final double ts = media.textScaler.scale(1);
      for (final Element e in find.byType(RichText).evaluate()) {
        final RichText rt = e.widget as RichText;
        final double fs = (rt.text.style?.fontSize ?? 0) * ts;
        if (fs >= 13.5) continue;
        final RenderBox box = e.renderObject! as RenderBox;
        final Offset o = box.localToGlobal(Offset.zero);
        // ignore: avoid_print
        print(
          'SMALL $location font=${fs.toStringAsFixed(2)} '
          'at=${o.dx.toStringAsFixed(0)},${o.dy.toStringAsFixed(0)} '
          'text="${rt.text.toPlainText().replaceAll('\n', ' ')}"',
        );
      }
      // ignore: avoid_print
      print('DONE $location');
    }, timeout: const Timeout(Duration(seconds: 120)));
  }
}
