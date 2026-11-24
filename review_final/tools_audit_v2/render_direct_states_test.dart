// Финальный аудит: production-виджеты состояний сессии напрямую (пусто,
// завершено, время истекло, план не найден, ошибка) на 2K — светлая/тёмная.
// Run: .fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_direct_states_test.dart --no-pub
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../test/helpers/pump_app.dart' show ruLocalizationDelegates;

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';
const String _outDir = 'review_final/screenshots/audit_v2/rendered';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
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

Widget _wrap(Widget child, Brightness brightness) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: ruLocalizationDelegates,
    theme: brightness == Brightness.light
        ? AppTheme.light(scale: 1.24)
        : AppTheme.dark(scale: 1.24),
    builder: (BuildContext context, Widget? inner) {
      final MediaQueryData media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(textScaler: const TextScaler.linear(0.9)),
        child: inner ?? const SizedBox.shrink(),
      );
    },
    home: Scaffold(body: child),
  );
}

Future<void> _pump(WidgetTester tester, Widget child, Brightness b) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1706.7, 940);
  addTearDown(tester.view.reset);
  AppAdaptive.debugOverride = 1.24;
  addTearDown(() => AppAdaptive.debugOverride = null);
  await tester.pumpWidget(_wrap(child, b));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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

  testWidgets('completed light', (WidgetTester tester) async {
    await _pump(
      tester,
      ReviewCompletedView(ratedCount: 24, onDone: () {}),
      Brightness.light,
    );
    await _shoot(tester, 'direct_completed_light_2k150');
  });

  testWidgets('completed dark', (WidgetTester tester) async {
    await _pump(
      tester,
      ReviewCompletedView(ratedCount: 24, onDone: () {}),
      Brightness.dark,
    );
    await _shoot(tester, 'direct_completed_dark_2k150');
  });

  testWidgets('time up light', (WidgetTester tester) async {
    await _pump(
      tester,
      ReviewTimeUpView(ratedCount: 12, onDone: () {}),
      Brightness.light,
    );
    await _shoot(tester, 'direct_timeup_light_2k150');
  });

  testWidgets('empty light', (WidgetTester tester) async {
    await _pump(tester, ReviewEmptyView(onBack: () {}), Brightness.light);
    await _shoot(tester, 'direct_empty_light_2k150');
  });

  testWidgets('empty limit light', (WidgetTester tester) async {
    await _pump(
      tester,
      ReviewEmptyView(
        onBack: () {},
        title: 'Дневной лимит исчерпан',
        message:
            'На сегодня новых карточек больше нет. Продолжите без лимита или '
            'перейдите в тренировку.',
        onContinue: () {},
        onPractice: () {},
      ),
      Brightness.light,
    );
    await _shoot(tester, 'direct_empty_limit_light_2k150');
  });

  testWidgets('error light', (WidgetTester tester) async {
    await _pump(tester, ReviewLoadErrorView(onRetry: () {}), Brightness.light);
    await _shoot(tester, 'direct_error_light_2k150');
  });
}
