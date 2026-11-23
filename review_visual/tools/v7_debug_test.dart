// Debug: locate the hang in the reveal/flip + toImage sequence.
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
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart' show decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

Card _card() => makeCard(
  id: 'card-1',
  deckId: 'deck-1',
  front: 'Сколько векторных диаграмм строят по результатам измерений и вычислений?',
  back: 'Две: диаграмму токов и диаграмму напряжений.',
  createdAt: DateTime.utc(2026, 11, 13, 10),
);

Widget _harness() {
  final List<Override> overrides = decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Эл тех', totalCards: 12, newCards: 1),
      ],
    ),
    cardRepository: FakeCardRepository(cards: <Card>[_card()]),
    reviewRepository: FakeReviewRepository(),
    appSettingsStore: FakeAppSettingsStore(
      settings: AppSettings.defaults.copyWith(textScale: 0.9),
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
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(scale: 1.24),
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('debug reveal', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1707, 940);
    addTearDown(tester.view.reset);
    AppAdaptive.debugOverride = 1.24;
    addTearDown(() => AppAdaptive.debugOverride = null);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('DBG pumped');

    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    // ignore: avoid_print
    print('DBG tapped');
    await tester.pump();
    // ignore: avoid_print
    print('DBG pump1');
    await tester.pump(const Duration(milliseconds: 400));
    // ignore: avoid_print
    print('DBG pump2');

    final Finder rating = find.byKey(const ValueKey<String>('review-rating-good'));
    final FilledButton button = tester.widget<FilledButton>(rating);
    // ignore: avoid_print
    print('DBG rating enabled=${button.onPressed != null}');
    // ignore: avoid_print
    print('DBG reveal present=${find.byKey(const ValueKey<String>('review-reveal')).evaluate().length}');
    // ignore: avoid_print
    print('DBG hint present=${find.byKey(const ValueKey<String>('review-rating-hint')).evaluate().length}');

    final RenderView view = tester.binding.renderViews.first;
    final OffsetLayer layer = view.debugLayer! as OffsetLayer;
    // ignore: avoid_print
    print('DBG layer ok');
    final ui.Image image = await layer.toImage(view.paintBounds);
    // ignore: avoid_print
    print('DBG toImage ${image.width}x${image.height}');
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    // ignore: avoid_print
    print('DBG png bytes=${data?.lengthInBytes}');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
