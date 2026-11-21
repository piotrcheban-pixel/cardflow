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
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
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
  await _loadKatexFonts();
}

/// Шрифты KaTeX из `flutter_math_fork`.
///
/// `flutter_test` не загружает шрифты пакетов сам: без этого формулы в
/// скриншотах рисуются квадратами Ahem. Семейства объявлены в pubspec
/// пакета (`KaTeX_Main`, `KaTeX_Math`, `KaTeX_Size1..4`, …).
Future<void> _loadKatexFonts() async {
  final String? localAppData = Platform.environment['LOCALAPPDATA'];
  final String? pubCache = Platform.environment['PUB_CACHE'];
  final Directory hosted = Directory(
    '${pubCache ?? '$localAppData\\Pub\\Cache'}\\hosted\\pub.dev',
  );
  if (!hosted.existsSync()) return;
  final Directory? package = hosted
      .listSync()
      .whereType<Directory>()
      .where(
        (Directory entry) => entry.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('flutter_math_fork-'),
      )
      .firstOrNull;
  if (package == null) return;
  final Directory fonts = Directory('${package.path}\\lib\\katex_fonts\\fonts');
  if (!fonts.existsSync()) return;

  final Map<String, File> preferred = <String, File>{};
  for (final FileSystemEntity entry in fonts.listSync()) {
    if (entry is! File || !entry.path.endsWith('.ttf')) continue;
    final String name = entry.path.split(Platform.pathSeparator).last;
    final String family = name.substring(0, name.indexOf('-'));
    final bool isItalic = name.contains('Italic');
    final bool isRegular = name.contains('Regular');
    final int rank = isRegular ? 0 : (isItalic ? 1 : 2);
    final File? current = preferred[family];
    if (current == null) {
      preferred[family] = entry;
      continue;
    }
    final String currentName = current.path.split(Platform.pathSeparator).last;
    final int currentRank = currentName.contains('Regular')
        ? 0
        : (currentName.contains('Italic') ? 1 : 2);
    if (rank < currentRank) preferred[family] = entry;
  }

  for (final MapEntry<String, File> entry in preferred.entries) {
    // Семейство в рендере — с префиксом пакета (см. make_symbol.dart).
    final FontLoader loader = FontLoader(
      'packages/flutter_math_fork/${entry.key}',
    );
    loader.addFont(
      Future<ByteData>.value(
        ByteData.sublistView(await entry.value.readAsBytes()),
      ),
    );
    await loader.load();
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

/// Колода с формулами для скриншотов 7.17 (LaTeX в новых режимах).
List<Card> _latexCards() => <Card>[
  makeCard(
    id: 'latex-1',
    deckId: 'deck-1',
    front: r'Формула энергии покоя $E=mc^2$?',
    back: r'$E = mc^2$',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'latex-2',
    deckId: 'deck-1',
    front: r'Формула силы $F$?',
    back: r'$F = ma$',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'latex-3',
    deckId: 'deck-1',
    front: r'Формула мощности $P$?',
    back: r'$P = UI$',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'latex-4',
    deckId: 'deck-1',
    front: r'Закон Ома $I$?',
    back: r'$I = U/R$',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'latex-5',
    deckId: 'deck-1',
    front: r'Теплота $Q$ при нагреве?',
    back: r'$Q = cm\Delta t$',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'latex-6',
    deckId: 'deck-1',
    front: r'Период колебаний $T$?',
    back: r'$T = 2\pi\sqrt{l/g}$',
    createdAt: _now,
    updatedAt: _now,
  ),
];

/// Колода для «Ввода ответа»: формула в вопросе, печатаемый ответ.
List<Card> _latexTypingCards() => <Card>[
  makeCard(
    id: 'latex-typing-1',
    deckId: 'deck-1',
    front: r'Что означает формула $E=mc^2$?',
    back: 'Энергия покоя',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'latex-typing-2',
    deckId: 'deck-1',
    front: r'Что связывает $F=ma$?',
    back: 'Сила и ускорение',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'latex-typing-3',
    deckId: 'deck-1',
    front: r'Что такое $P=UI$?',
    back: 'Мощность тока',
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

Widget _app(Widget home, Brightness brightness, {List<Card>? cards}) {
  final List<Card> deck = cards ?? _cards();
  return ProviderScope(
    overrides: decksOverrides(
      deckRepository: FakeDeckRepository(),
      cardRepository: FakeCardRepository(cards: deck),
      reviewRepository: FakeReviewRepository()..previousCard = deck.first,
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

  testWidgets('latex test light', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const MultipleChoiceScreen(deckId: 'deck-1'),
        Brightness.light,
        cards: _latexCards(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'latex-test-light');
  });

  testWidgets('latex match light', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const MatchScreen(deckId: 'deck-1'),
        Brightness.light,
        cards: _latexCards(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'latex-match-light');
  });

  testWidgets('latex typing dark', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const TypingScreen(deckId: 'deck-1'),
        Brightness.dark,
        cards: _latexTypingCards(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'latex-typing-dark');
  });

  testWidgets('latex true false dark', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const TrueFalseScreen(deckId: 'deck-1'),
        Brightness.dark,
        cards: _latexCards(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, 'latex-true-false-dark');
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
      questionMediaIds: const <String>['media-1'],
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
      questionMediaIds: const <String>['media-1'],
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

  testWidgets('card image light', (WidgetTester tester) async {
    await phone(tester);
    final Uint8List placeholder = Uint8List.fromList(
      img.encodePng(img.Image(width: 800, height: 450)),
    );
    final Card card = makeCard(
      id: 'placeholder',
      deckId: 'deck-1',
      front: 'Что такое фотосинтез?',
      back: 'Преобразование световой энергии в химическую',
      questionMediaIds: const <String>['media-1'],
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
              mediaBytes: <String, Uint8List>{'media-1': placeholder},
              mediaMetadata: const <String, MediaMetadata>{
                'media-1': MediaMetadata(
                  provider: 'file',
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
        MemoryImage(placeholder),
        tester.element(find.byType(CardContentView)),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _capture(tester, 'card-image-light');
  });
}
