import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/components/app_filter_chip.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import '../../helpers/pump_app.dart';

/// Чип фильтра дизайн-системы v3 (ADR-045): единая высота и центрирование.
///
/// Находка владельца: в ряду «Все (13) / Новые (10) / В процессе (7) /
/// Срок наступил (7)» подписи стояли не по центру — «Container(height: 38)»
/// без выравнивания прижимал текст к верхней кромке.
void main() {
  Widget row({
    int selectedIndex = 0,
    List<(String, int)> items = const <(String, int)>[
      ('Все', 13),
      ('Новые', 10),
      ('В процессе', 7),
      ('Срок наступил', 7),
    ],
  }) {
    return appWithHome(
      overrides: const <Override>[],
      home: Scaffold(
        body: Center(
          child: Wrap(
            spacing: 4,
            runSpacing: 8,
            children: <Widget>[
              for (int index = 0; index < items.length; index++)
                AppFilterChip(
                  key: ValueKey<String>('chip-$index'),
                  label: items[index].$1,
                  count: items[index].$2,
                  selected: index == selectedIndex,
                  danger: index == 3,
                  onPressed: () {},
                ),
            ],
          ),
        ),
      ),
    );
  }

  AnimatedContainer visual(WidgetTester tester, int index) =>
      tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(ValueKey<String>('chip-$index')),
          matching: find.byType(AnimatedContainer),
        ),
      );

  testWidgets('все чипы одной высоты, текст и счётчик по центру', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(row());
    await tester.pumpAndSettle();

    for (int index = 0; index < 4; index++) {
      final Finder chip = find.byKey(ValueKey<String>('chip-$index'));
      final Rect chipRect = tester.getRect(
        find.descendant(of: chip, matching: find.byType(AnimatedContainer)),
      );
      expect(chipRect.height, AppFilterChip.height, reason: 'чип $index');

      // Подпись центрирована относительно визуального прямоугольника чипа.
      final Rect labelRect = tester.getRect(
        find.descendant(
          of: chip,
          matching: find.text(
            <String>['Все', 'Новые', 'В процессе', 'Срок наступил'][index],
          ),
        ),
      );
      expect(
        labelRect.center.dy,
        closeTo(chipRect.center.dy, 0.75),
        reason:
            'подпись $index не по центру: ${labelRect.center.dy} vs '
            '${chipRect.center.dy}',
      );
    }
  });

  testWidgets('счётчик — отдельный бейдж и не сдвигает подпись', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(row());
    await tester.pumpAndSettle();

    expect(find.text('13'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('7'), findsNWidgets(2));
    // Подпись остаётся самостоятельным Text-узлом: «Все» без «(13)».
    expect(find.text('Все'), findsOneWidget);
    expect(find.text('Все (13)'), findsNothing);
  });

  testWidgets('selected рисуется акцентом, unselected — нейтральной', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(row(selectedIndex: 0));
    await tester.pumpAndSettle();
    final BuildContext context = tester.element(
      find.byKey(const ValueKey<String>('chip-0')),
    );
    final ColorScheme scheme = Theme.of(context).colorScheme;

    expect(
      (visual(tester, 0).decoration! as BoxDecoration).color,
      scheme.primary,
    );
    expect(
      (visual(tester, 1).decoration! as BoxDecoration).color,
      scheme.surfaceContainerLow,
    );
  });

  testWidgets('длинная подпись ограничивается шириной и не ломает высоту', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      row(
        items: <(String, int)>[
          ('Срок наступил и очень длинная подпись фильтра', 7),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final Rect chipRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('chip-0')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(chipRect.height, AppFilterChip.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('тема: чип использует токены темы, без литеральных цветов', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(row());
    await tester.pumpAndSettle();
    final ThemeData theme = Theme.of(
      tester.element(find.byKey(const ValueKey<String>('chip-0'))),
    );
    expect(theme.colorScheme.brightness, Brightness.light);
    expect(AppTheme.light().colorScheme.primary, isNotNull);
  });
}
