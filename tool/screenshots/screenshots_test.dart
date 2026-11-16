// Скриншоты для отчёта итераций 7.14/7.15/7.16.
//
// Запуск вручную (golden, не часть CI):
//   fvm flutter test tool/screenshots/screenshots_test.dart --no-pub --update-goldens
// Требуется Windows-шрифт Segoe UI (кириллица) и живые картинки из
// `journal/iteration-7.14/images/` (gitignored, сняты в 7.14).
// ignore_for_file: avoid_print
@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart';
import '../../test/helpers/review_fakes.dart';

const String _fontDir = r'C:\Windows\Fonts';
final DateTime _now = DateTime.utc(2026, 11, 16, 12);

Future<void> _loadFonts() async {
  for (final String family in <String>['Roboto', 'Ahem']) {
    final FontLoader loader = FontLoader(family);
    for (final String file in <String>['segoeui.ttf', 'segoeuib.ttf']) {
      final File font = File('$_fontDir\\$file');
      if (!font.existsSync()) continue;
      final Uint8List bytes = await font.readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

List<Card> _cards() => <Card>[
  makeCard(
    id: 'bio-1',
    deckId: 'deck-1',
    front: 'Какой пигмент придаёт листьям зелёный цвет?',
    back: 'Хлорофилл',
    mediaIds: const <String>['shot-photo'],
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'bio-2',
    deckId: 'deck-1',
    front: 'Какая органелла изображена на схеме?',
    back: 'Хлоропласт',
    mediaIds: const <String>['shot-diagram'],
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'bio-3',
    deckId: 'deck-1',
    front: 'Что такое фотосинтез?',
    back: 'Преобразование световой энергии в химическую',
    mediaIds: const <String>['shot-placeholder'],
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'bio-4',
    deckId: 'deck-1',
    front: 'Где синтезируется АТФ?',
    back: 'В митохондриях',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'bio-5',
    deckId: 'deck-1',
    front: 'Как называется процесс деления клетки?',
    back: 'Митоз',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'bio-6',
    deckId: 'deck-1',
    front: 'Что хранит наследственную информацию?',
    back: 'ДНК',
    createdAt: _now,
    updatedAt: _now,
  ),
];

Future<Uint8List?> _read(String path) async {
  final File file = File(path);
  if (!file.existsSync()) return null;
  return file.readAsBytes();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Widget _cardHarness({
  required Card card,
  required Uint8List? image,
  required MediaMetadata? metadata,
  required Brightness brightness,
}) {
  final ThemeData theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F6B4F),
      brightness: brightness,
    ),
    fontFamily: 'Roboto',
    useMaterial3: true,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: const <Locale>[Locale('ru')],
    localizationsDelegates: ruLocalizationDelegates,
    theme: theme,
    home: RepaintBoundary(
      key: const ValueKey<String>('screenshot-boundary'),
      child: Scaffold(
        appBar: AppBar(title: const Text('Биология')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CardContentView(
            card: card,
            side: card.front,
            revealed: true,
            faceKey: const ValueKey<String>('screenshot-face'),
            mediaBytes: image == null
                ? const <String, Uint8List>{}
                : <String, Uint8List>{card.mediaIds.first: image},
            mediaMetadata: metadata == null
                ? const <String, MediaMetadata>{}
                : <String, MediaMetadata>{card.mediaIds.first: metadata},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('card photo light', (WidgetTester tester) async {
    await setPhone(tester);
    final Uint8List? photo = await _read(
      'journal/iteration-7.14/images/biology/06.jpg',
    );
    await tester.pumpWidget(
      _cardHarness(
        card: _cards()[0],
        image: photo,
        metadata: const MediaMetadata(
          provider: 'wikipedia',
          license: 'CC BY-SA 4.0',
          query: 'chlorophyll green leaf pigment',
          kind: GeneratedCardImageKind.photo,
        ),
        brightness: Brightness.light,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, 'card-photo-light');
  });

  testWidgets('card diagram dark', (WidgetTester tester) async {
    await setPhone(tester);
    final Uint8List? diagram = await _read(
      'journal/iteration-7.14/images/biology/03.png',
    );
    await tester.pumpWidget(
      _cardHarness(
        card: _cards()[1],
        image: diagram,
        metadata: const MediaMetadata(
          provider: 'wikipedia',
          license: 'CC BY-SA 4.0',
          query: 'chloroplast structure diagram',
          kind: GeneratedCardImageKind.diagram,
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, 'card-diagram-dark');
  });

  testWidgets('card placeholder light', (WidgetTester tester) async {
    await setPhone(tester);
    final GeneratedCardImage placeholder = const PlaceholderImageGenerator()
        .generate(seed: 'photo-light', kind: GeneratedCardImageKind.photo);
    await tester.pumpWidget(
      _cardHarness(
        card: _cards()[2],
        image: placeholder.bytes,
        metadata: MediaMetadata(
          provider: 'placeholder',
          isPlaceholder: true,
          query: 'photosynthesis process',
          kind: GeneratedCardImageKind.photo,
        ),
        brightness: Brightness.light,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, 'card-placeholder-light');
  });

  Future<void> pumpMode(
    WidgetTester tester, {
    required String location,
    required Brightness brightness,
  }) async {
    await setPhone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final FakeReviewRepository reviews = FakeReviewRepository()
      ..previousCard = _cards().first;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey<String>('screenshot-boundary'),
        child: appWithRouter(
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(),
            cardRepository: FakeCardRepository(cards: _cards()),
            reviewRepository: reviews,
          ),
          routes: decksRoutes(),
          initialLocation: location,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets('test light', (WidgetTester tester) async {
    await pumpMode(
      tester,
      location: '/decks/deck-1/test',
      brightness: Brightness.light,
    );
    await _capture(tester, 'test-light');
  });

  testWidgets('test dark', (WidgetTester tester) async {
    await pumpMode(
      tester,
      location: '/decks/deck-1/test',
      brightness: Brightness.dark,
    );
    await _capture(tester, 'test-dark');
  });

  testWidgets('typing light', (WidgetTester tester) async {
    await pumpMode(
      tester,
      location: '/decks/deck-1/typing',
      brightness: Brightness.light,
    );
    await _capture(tester, 'typing-light');
  });

  testWidgets('match light', (WidgetTester tester) async {
    await pumpMode(
      tester,
      location: '/decks/deck-1/match',
      brightness: Brightness.light,
    );
    await _capture(tester, 'match-light');
  });

  testWidgets('true false dark', (WidgetTester tester) async {
    await pumpMode(
      tester,
      location: '/decks/deck-1/true-false',
      brightness: Brightness.dark,
    );
    await _capture(tester, 'true-false-dark');
  });
}
