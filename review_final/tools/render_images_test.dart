// Финальный аудит: изображения карточки — вписывание (contain), доля площади,
// сетка нескольких изображений, разные пропорции.
//
// Run:
//   .fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_images_test.dart --no-pub
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';
const String _outDir = 'review_final/screenshots/rendered';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

final DateTime _now = DateTime.utc(2026, 11, 23, 12);

/// PNG с рамкой и диагоналями: по краям видно обрезку, внутри — пропорции.
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

Widget _app({
  required double factor,
  required double textScale,
  required Card card,
  required Map<String, Uint8List> bytes,
}) {
  final List<Override> overrides = decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Биология', totalCards: 4),
      ],
    ),
    cardRepository: FakeCardRepository(cards: <Card>[card]),
    reviewRepository: FakeReviewRepository(),
    cardMediaRepository: FakeCardMediaRepository(
      bytesById: bytes,
      metadataById: <String, MediaMetadata>{
        for (final String id in bytes.keys)
          id: const MediaMetadata(
            provider: 'wikimedia',
            license: 'CC BY-SA 4.0',
            kind: GeneratedCardImageKind.photo,
          ),
      },
    ),
    appSettingsStore: FakeAppSettingsStore(
      settings: AppSettings.defaults.copyWith(textScale: textScale),
    ),
  );
  final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(scale: factor),
      routerConfig: createAppRouter(
        initialLocation: '/decks/deck-1/study',
        navigatorKey: key,
      ),
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

Future<void> _shoot(WidgetTester tester, String name) async {
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

  final Map<String, (double, Size)> sizes = <String, (double, Size)>{
    '2k150': (1.24, const Size(1706.7, 940)),
    '4k100': (1.45, const Size(3840, 2160)),
    'fhd150': (1.0, const Size(1280, 720)),
    'm390': (1.0, const Size(390, 844)),
  };

  final List<(String, int, int)> shapes = <(String, int, int)>[
    ('tall_960x1371', 960, 1371),
    ('wide_1500x511', 1500, 511),
    ('photo_1200x900', 1200, 900),
  ];

  for (final MapEntry<String, (double, Size)> cfg in sizes.entries) {
    for (final (String name, int w, int h) in shapes) {
      testWidgets('image $name ${cfg.key}', (WidgetTester tester) async {
        final Uint8List png = _patternPng(w, h);
        final Card card = makeCard(
          id: 'card-img',
          deckId: 'deck-1',
          front: 'Что изображено на рисунке #$name?',
          back: 'Схема, показанная на рисунке.',
          answerMediaIds: const <String>['media-1'],
          createdAt: _now,
          updatedAt: _now,
        );
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = cfg.value.$2;
        addTearDown(tester.view.reset);
        AppAdaptive.debugOverride = cfg.value.$1;
        addTearDown(() => AppAdaptive.debugOverride = null);
        await tester.pumpWidget(
          _app(
            factor: cfg.value.$1,
            textScale: cfg.key == '2k150' || cfg.key == 'fhd150' ? 0.9 : 1.0,
            card: card,
            bytes: <String, Uint8List>{'media-1': png},
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        await tester.tap(find.byKey(const ValueKey<String>('review-card')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 340));
        await tester.pump(const Duration(milliseconds: 280));
        await tester.runAsync(() async {
          await precacheImage(
            MemoryImage(png),
            tester.element(find.byType(Scaffold).first),
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pump(const Duration(milliseconds: 220));
        final Finder image = find.byKey(
          const ValueKey<String>('card-image-media-1'),
        );
        final Finder cardFinder = find.byKey(
          const ValueKey<String>('review-card'),
        );
        if (image.evaluate().isNotEmpty && cardFinder.evaluate().isNotEmpty) {
          final Rect ir = tester.getRect(image);
          final Rect cr = tester.getRect(cardFinder);
          // ignore: avoid_print
          print(
            'IMG ${cfg.key}|$name|image=${ir.width.toStringAsFixed(0)}x'
            '${ir.height.toStringAsFixed(0)} ar=${(ir.width / ir.height).toStringAsFixed(3)} '
            'source_ar=${(w / h).toStringAsFixed(3)} '
            'card=${cr.width.toStringAsFixed(0)}x${cr.height.toStringAsFixed(0)} '
            'shareCard=${(100 * ir.width * ir.height / (cr.width * cr.height)).toStringAsFixed(1)}% '
            'shareCardW=${(100 * ir.width / cr.width).toStringAsFixed(1)}%',
          );
        } else {
          // ignore: avoid_print
          print(
            'IMG ${cfg.key}|$name|missing image=${image.evaluate().length} '
            'card=${cardFinder.evaluate().length}',
          );
        }
        await _shoot(tester, 'img_${cfg.key}_$name');
      }, timeout: const Timeout(Duration(seconds: 180)));
    }
  }

  // Несколько изображений: сетка по два.
  testWidgets('two images 2k150', (WidgetTester tester) async {
    final Card card = makeCard(
      id: 'card-2img',
      deckId: 'deck-1',
      front: 'Сравните две схемы.',
      back: 'Первая — звезда, вторая — треугольник.',
      answerMediaIds: const <String>['media-1', 'media-2'],
      createdAt: _now,
      updatedAt: _now,
    );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1706.7, 940);
    addTearDown(tester.view.reset);
    AppAdaptive.debugOverride = 1.24;
    addTearDown(() => AppAdaptive.debugOverride = null);
    final Map<String, Uint8List> twoBytes = <String, Uint8List>{
      'media-1': _patternPng(1200, 900),
      'media-2': _patternPng(960, 1371),
    };
    await tester.pumpWidget(
      _app(factor: 1.24, textScale: 0.9, card: card, bytes: twoBytes),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 280));
    await tester.runAsync(() async {
      for (final Uint8List bytes in twoBytes.values) {
        await precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(Scaffold).first),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 220));
    for (final String id in <String>['media-1', 'media-2']) {
      final Finder f = find.byKey(ValueKey<String>('card-image-$id'));
      if (f.evaluate().isEmpty) {
        // ignore: avoid_print
        print('IMG2 $id=absent');
        continue;
      }
      final Rect r = tester.getRect(f);
      // ignore: avoid_print
      print(
        'IMG2 $id=${r.width.toStringAsFixed(0)}x'
        '${r.height.toStringAsFixed(0)}@${r.left.toStringAsFixed(0)},'
        '${r.top.toStringAsFixed(0)}',
      );
    }
    await _shoot(tester, 'img_2k150_two_images');
  }, timeout: const Timeout(Duration(seconds: 180)));
}
