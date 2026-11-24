// Рендер экранов CardFlow в точных логических размерах 3840×2160 и 2560×1440.
// Только для визуального аудита: файл лежит в review_visual/ (единственная зона
// записи), проект не меняется. Запуск:
//   .fvm/versions/3.47.9/bin/flutter.bat test review_visual/tools/shots_test.dart --no-pub
// (шрифты Inter и MaterialIcons подкладываются из собранных flutter_assets).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/shell/app_sidebar.dart';
import 'package:cardflow/ui/shell/app_top_header.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart' show decksOverrides, m3eThemeBuilder;

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

DeckSummary _deck(String name, int total, int due) {
  return makeSummary(
    id: 'deck-$name',
    name: name,
    totalCards: total,
    dueCards: due,
    newCards: (total * 0.1).round(),
    inProgressCards: (total * 0.75).round(),
  );
}

Widget _shell() {
  return Row(
    children: <Widget>[
      SizedBox(
        width: 240,
        child: AppSidebar(currentBranch: 0, onSelectBranch: (int _) {}),
      ),
      Expanded(
        child: Column(
          children: <Widget>[
            AppTopHeader(onNewCard: () {}),
            const Expanded(child: DecksScreen()),
          ],
        ),
      ),
    ],
  );
}

Future<void> _shoot(WidgetTester tester, double w, double h, String out) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);

  final summaries = <DeckSummary>[
    _deck('Электротехника', 71, 60),
    _deck('Тест фигни', 134, 33),
    _deck('ЛРЗ_Трехфазная_цепь_звездой_заполненный_журнал', 40, 22),
    _deck('Вопросы для подготовки', 30, 16),
    _deck('Кинематика', 15, 0),
    _deck('Эл тех', 13, 11),
    _deck('Физика', 25, 4),
    _deck('Химия', 18, 2),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: decksOverrides(
        deckRepository: FakeDeckRepository(summaries: summaries),
      ),
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: AppTheme.light(),
        builder: m3eThemeBuilder,
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: Size(w, h),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
            ),
            child: Scaffold(body: _shell()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));

  final RenderView view = tester.binding.renderViews.first;
  final OffsetLayer layer = view.debugLayer! as OffsetLayer;
  final ui.Image image = await layer.toImage(view.paintBounds);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  final File file = File(out);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('SHOT $out ${image.width}x${image.height}');
}

void main() {
  testWidgets('4K и 2K: колоды', (WidgetTester tester) async {
    await _loadFont('Inter', '$_assets/assets/fonts/Inter-Variable.ttf');
    await _loadFont(
      'MaterialIcons',
      '$_assets/fonts/MaterialIcons-Regular.otf',
    );
    await _shoot(
      tester,
      3840,
      2160,
      'review_visual/screenshots/decks__3840x2160.png',
    );
    await _shoot(
      tester,
      2560,
      1440,
      'review_visual/screenshots/decks__2560x1440.png',
    );
    await _shoot(
      tester,
      1920,
      1080,
      'review_visual/screenshots/decks__1920x1080_widget.png',
    );
  });
}
