// Читаемые скриншоты экранов для отчёта (ручной прогон, golden).
//
//   fvm flutter test tool/screenshots/screens_test.dart --no-pub --update-goldens
//
// Каталог `tool/` не входит в CI; шрифт Segoe UI загружается только локально.
// ignore_for_file: avoid_print
@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/study/match_screen.dart';
import 'package:cardflow/ui/study/multiple_choice_screen.dart';
import 'package:cardflow/ui/study/true_false_screen.dart';
import 'package:cardflow/ui/study/typing_screen.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart';
import '../../test/helpers/review_fakes.dart';

final DateTime _now = DateTime.utc(2026, 11, 16, 12);

Future<void> _loadFonts() async {
  final FontLoader loader = FontLoader('ScreenshotFont');
  for (final String file in <String>['segoeui.ttf', 'segoeuib.ttf']) {
    final File font = File('C:\\Windows\\Fonts\\$file');
    if (!font.existsSync()) continue;
    final Uint8List bytes = await font.readAsBytes();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  final File icons = File(
    'C:\\Users\\piotr\\fvm\\versions\\3.47.9\\bin\\cache\\artifacts'
    '\\material_fonts\\materialicons-regular.otf',
  );
  if (icons.existsSync()) {
    final FontLoader iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(
      Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
    );
    await iconLoader.load();
  }
}

List<Card> _cards() => <Card>[
  makeCard(
    id: 'bio-1',
    deckId: 'deck-1',
    front: 'Какой пигмент придаёт листьям зелёный цвет?',
    back: 'Хлорофилл',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'bio-2',
    deckId: 'deck-1',
    front: 'Какая органелла изображена на схеме?',
    back: 'Хлоропласт',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'bio-3',
    deckId: 'deck-1',
    front: 'Что такое фотосинтез?',
    back: 'Преобразование световой энергии в химическую',
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

ThemeData _theme(Brightness brightness) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppTheme.seedColor,
      brightness: brightness,
    ),
    fontFamily: 'ScreenshotFont',
    useMaterial3: true,
  );
}

Widget _app(Widget home, Brightness brightness) {
  return ProviderScope(
    overrides: decksOverrides(
      deckRepository: FakeDeckRepository(),
      cardRepository: FakeCardRepository(cards: _cards()),
      reviewRepository: FakeReviewRepository()..previousCard = _cards().first,
      matchBestStore: FakeMatchBestStore(
        bestByDeck: <String, int>{'deck-1': 42000},
      ),
    ),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const <Locale>[Locale('ru')],
      localizationsDelegates: ruLocalizationDelegates,
      theme: _theme(brightness),
      home: home,
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('readable/$name.png'),
  );
}

void main() {
  setUpAll(_loadFonts);

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('test light', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(const MultipleChoiceScreen(deckId: 'deck-1'), Brightness.light),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'test-light');
  });

  testWidgets('test dark', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(const MultipleChoiceScreen(deckId: 'deck-1'), Brightness.dark),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'test-dark');
  });

  testWidgets('typing light', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(const TypingScreen(deckId: 'deck-1'), Brightness.light),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'typing-light');
  });

  testWidgets('match light', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(const MatchScreen(deckId: 'deck-1'), Brightness.light),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'match-light');
  });

  testWidgets('true false dark', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(const TrueFalseScreen(deckId: 'deck-1'), Brightness.dark),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'true-false-dark');
  });

  testWidgets('card photo light', (WidgetTester tester) async {
    await phone(tester);
    final Uint8List? photo = await tester.runAsync(
      () => File('journal/iteration-7.14/images/biology/06.jpg').readAsBytes(),
    );
    final Card card = makeCard(
      id: 'photo',
      deckId: 'deck-1',
      front: 'Какой пигмент придаёт листьям зелёный цвет?',
      back: 'Хлорофилл',
      mediaIds: const <String>['media-1'],
      createdAt: _now,
      updatedAt: _now,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          appBar: AppBar(title: const Text('Биология')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CardContentView(
              card: card,
              side: card.front,
              revealed: true,
              faceKey: const ValueKey<String>('face'),
              mediaBytes: photo == null
                  ? const <String, Uint8List>{}
                  : <String, Uint8List>{'media-1': photo},
              mediaMetadata: const <String, MediaMetadata>{
                'media-1': MediaMetadata(
                  provider: 'wikipedia',
                  license: 'CC BY-SA 4.0',
                  kind: GeneratedCardImageKind.photo,
                ),
              },
            ),
          ),
        ),
        Brightness.light,
      ),
    );
    await tester.pump();
    if (photo != null) {
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(photo),
          tester.element(find.byType(CardContentView)),
        ),
      );
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _capture(tester, 'card-photo-light');
  });

  testWidgets('card diagram dark', (WidgetTester tester) async {
    await phone(tester);
    final Uint8List? diagram = await tester.runAsync(
      () => File('journal/iteration-7.14/images/biology/03.png').readAsBytes(),
    );
    final Card card = makeCard(
      id: 'diagram',
      deckId: 'deck-1',
      front: 'Какая органелла изображена на схеме?',
      back: 'Хлоропласт',
      mediaIds: const <String>['media-1'],
      createdAt: _now,
      updatedAt: _now,
    );
    await tester.pumpWidget(
      _app(
        RepaintBoundary(
          child: Scaffold(
            appBar: AppBar(title: const Text('Биология')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CardContentView(
                card: card,
                side: card.front,
                revealed: true,
                faceKey: const ValueKey<String>('face'),
                mediaBytes: diagram == null
                    ? const <String, Uint8List>{}
                    : <String, Uint8List>{'media-1': diagram},
                mediaMetadata: const <String, MediaMetadata>{
                  'media-1': MediaMetadata(
                    provider: 'wikipedia',
                    license: 'CC BY-SA 4.0',
                    kind: GeneratedCardImageKind.diagram,
                  ),
                },
              ),
            ),
          ),
        ),
        Brightness.dark,
      ),
    );
    await tester.pump();
    if (diagram != null) {
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(diagram),
          tester.element(find.byType(CardContentView)),
        ),
      );
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _capture(tester, 'card-diagram-dark');
  });

  testWidgets('card placeholder light', (WidgetTester tester) async {
    await phone(tester);
    final GeneratedCardImage placeholder = const PlaceholderImageGenerator()
        .generate(seed: 'screenshot', kind: GeneratedCardImageKind.photo);
    final Card card = makeCard(
      id: 'placeholder',
      deckId: 'deck-1',
      front: 'Что такое фотосинтез?',
      back: 'Преобразование световой энергии в химическую',
      mediaIds: const <String>['media-1'],
      createdAt: _now,
      updatedAt: _now,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          appBar: AppBar(title: const Text('Биология')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CardContentView(
              card: card,
              side: card.front,
              revealed: true,
              faceKey: const ValueKey<String>('face'),
              mediaBytes: <String, Uint8List>{'media-1': placeholder.bytes},
              mediaMetadata: const <String, MediaMetadata>{
                'media-1': MediaMetadata(
                  provider: 'placeholder',
                  isPlaceholder: true,
                  kind: GeneratedCardImageKind.photo,
                ),
              },
            ),
          ),
        ),
        Brightness.light,
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(placeholder.bytes),
        tester.element(find.byType(CardContentView)),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _capture(tester, 'card-placeholder-light');
  });
}
