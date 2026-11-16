import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/transitions/nc_page_transitions.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

/// Переходы страниц Nocturne (REDESIGN-SPEC §6.5, ADR-035).
void main() {
  group('NcPageTransitions: платформы', () {
    test('Nocturne везде, кроме iOS/macOS (жест «назад»)', () {
      const PageTransitionsTheme theme = NcPageTransitions.theme;
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(
          theme.builders[platform],
          isA<NcPageTransitionsBuilder>(),
          reason: '$platform должен использовать переход Nocturne',
        );
      }
      expect(
        theme.builders[TargetPlatform.iOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
      expect(
        theme.builders[TargetPlatform.macOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
    });

    test('тема приложения подключает переходы', () {
      expect(AppTheme.dark().pageTransitionsTheme, NcPageTransitions.theme);
    });
  });

  group('NcPageTransitionsBuilder: анимация', () {
    testWidgets('новый экран появляется fade + scale 0,98→1 + сдвиг', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: Text('Первый')),
        ),
      );
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              const Scaffold(body: Text('Второй')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Второй'), findsOneWidget);
      final Iterable<FadeTransition> fades = tester.widgetList<FadeTransition>(
        find.byType(FadeTransition),
      );
      expect(fades, isNotEmpty);
      // На середине перехода прозрачность между 0 и 1 (не мгновенное появление).
      expect(
        fades.any(
          (FadeTransition fade) =>
              fade.opacity.value > 0 && fade.opacity.value < 1,
        ),
        isTrue,
      );

      await tester.pumpAndSettle();
      expect(find.text('Первый'), findsNothing);
    });

    testWidgets('подложка предыдущего экрана затемняется при push', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: Text('Первый')),
        ),
      );
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              const Scaffold(body: Text('Второй')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      // Второй кадр перехода содержит затемняющий слой над предыдущей страницей.
      expect(
        tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .any((ColoredBox box) => box.color.a > 0 && box.color.a < 0.24),
        isTrue,
      );
      await tester.pumpAndSettle();
    });
  });
}
