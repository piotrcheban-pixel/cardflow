import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/ambient/ambient_background.dart';
import 'package:cardflow/ui/design/motion_scope.dart';
import 'package:cardflow/ui/design/nc_theme.dart';
import 'package:cardflow/ui/design/tokens/nc_colors.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

/// Фон Aurora (REDESIGN-SPEC §4.5): дрейф по режиму движения, статичность в
/// тестах, отключение при повышенном контрасте, зерно.
Widget _host({required Widget child, NcMotion? motion, ThemeData? theme}) {
  final Widget scoped = motion == null
      ? child
      : NcMotionScope(motion: motion, child: child);
  return MaterialApp(theme: theme ?? AppTheme.dark(), home: scoped);
}

Finder _ambient() => find.byType(NcAmbientBackground);

NcAmbientBackgroundState _state(WidgetTester tester) =>
    tester.state<NcAmbientBackgroundState>(_ambient());

void main() {
  tearDown(() => NcAmbientBackground.debugAnimateInTests = false);

  testWidgets('рисует контент поверх фона и пропускает касания', (
    tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      _host(
        motion: NcMotion.resolve(),
        child: NcAmbientBackground(
          child: Center(
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('Кнопка'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Кнопка'), findsOneWidget);
    expect(
      find.descendant(of: _ambient(), matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    await tester.tap(find.text('Кнопка'));
    expect(taps, 1);
    expect(_state(tester).auroraEnabled, isTrue);
  });

  testWidgets('в тестах статичен — pumpAndSettle завершается', (tester) async {
    await tester.pumpWidget(
      _host(
        motion: NcMotion.resolve(),
        child: NcAmbientBackground(child: const SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(_state(tester).isAnimating, isFalse);
  });

  testWidgets('debugAnimateInTests включает дрейф, pumpAndSettle не нужен', (
    tester,
  ) async {
    NcAmbientBackground.debugAnimateInTests = true;
    await tester.pumpWidget(
      _host(
        motion: NcMotion.resolve(),
        child: NcAmbientBackground(child: const SizedBox.expand()),
      ),
    );
    await tester.pump();
    expect(_state(tester).isAnimating, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(_state(tester).isAnimating, isTrue);
  });

  testWidgets('стандартный режим движения — без дрейфа', (tester) async {
    NcAmbientBackground.debugAnimateInTests = true;
    await tester.pumpWidget(
      _host(
        motion: NcMotion.resolve(preference: NcMotionPreference.standard),
        child: NcAmbientBackground(child: const SizedBox.expand()),
      ),
    );
    await tester.pump();
    expect(_state(tester).isAnimating, isFalse);
  });

  testWidgets('disableAnimations — без дрейфа', (tester) async {
    NcAmbientBackground.debugAnimateInTests = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: NcMotionScope(
            motion: NcMotion.resolve(),
            child: NcAmbientBackground(child: const SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_state(tester).isAnimating, isFalse);
  });

  testWidgets('повышенный контраст выключает Aurora', (tester) async {
    NcAmbientBackground.debugAnimateInTests = true;
    await tester.pumpWidget(
      _host(
        theme: AppTheme.dark(highContrast: true),
        motion: NcMotion.resolve(),
        child: NcAmbientBackground(child: const SizedBox.expand()),
      ),
    );
    await tester.pump();
    expect(_state(tester).auroraEnabled, isFalse);
    expect(_state(tester).isAnimating, isFalse);
  });

  testWidgets('зерно грузится из ассета и рисуется поверх фона', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        motion: NcMotion.resolve(),
        child: NcAmbientBackground(child: const SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
    // Загрузка и декодирование PNG идут вне fake-async теста.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(_state(tester).hasGrain, isTrue);
  });

  test('painter: shouldRepaint реагирует на фазу и зерно', () {
    final NcTheme theme = NcTheme(
      colors: NcColors.dark(),
      typography: NcTheme.fallback.typography,
      depth: NcTheme.fallback.depth,
      glass: NcTheme.fallback.glass,
      highContrast: false,
      glassEnabled: true,
    );
    NcAmbientPainter painter({
      double progress = 0.3,
      NcAmbientTone tone = NcAmbientTone.aurum,
    }) => NcAmbientPainter(
      colors: theme.colors,
      progress: progress,
      auroraEnabled: true,
      intensity: 1,
      tone: tone,
      grain: null,
      grainOpacity: 0.9,
    );
    expect(painter().shouldRepaint(painter()), isFalse);
    expect(painter(progress: 0.4).shouldRepaint(painter()), isTrue);
    expect(painter(tone: NcAmbientTone.iris).shouldRepaint(painter()), isTrue);
  });
}
