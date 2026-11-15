import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/api/generation/latex_escape_repair.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/ui/cards/content/latex_text.dart';
import 'package:cardflow/ui/review/review_card_view.dart';

import '../../helpers/pump_app.dart';

/// Рендер LaTeX после нормализации (fix-gen, Д4): формулы — виджетами Math,
/// сырой `$…$` в дереве не остаётся, ошибка разметки — предупреждение, не краш.
void main() {
  final DateTime now = DateTime.utc(2026, 11, 15, 12);

  Card card({
    String front = 'Вопрос',
    String back = 'Ответ',
    CardType type = CardType.basic,
  }) {
    return Card(
      id: 'card-1',
      deckId: 'deck-1',
      front: front,
      back: back,
      cardType: type,
      state: CardState.newCard,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> pumpLatex(
    WidgetTester tester,
    String source, {
    bool revealed = true,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: const [],
        home: Scaffold(
          body: LatexText(source: source, revealed: revealed),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpClassic(
    WidgetTester tester,
    Card value, {
    bool revealed = true,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: const [],
        home: Scaffold(
          body: ReviewCardView(
            front: value.front,
            back: value.back,
            card: value,
            revealed: revealed,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(r'«Найди $E=mc^2$» → виджет Math, сырой строки нет', (
    tester,
  ) async {
    await pumpLatex(tester, r'Найди $E=mc^2$');

    expect(find.byType(Math), findsOneWidget);
    expect(find.text(r'Найди $E=mc^2$'), findsNothing);
    final Math math = tester.widget<Math>(find.byType(Math));
    expect(math.mathStyle, MathStyle.text);
    expect(math.parseError, isNull);
    expect(math.ast, isNotNull);
  });

  testWidgets(r'«$$\frac{a}{b}$$» → блочная формула', (tester) async {
    await pumpLatex(tester, r'$$\frac{a}{b}$$');

    expect(find.byType(Math), findsOneWidget);
    final Math math = tester.widget<Math>(find.byType(Math));
    expect(math.mathStyle, MathStyle.display);
    expect(math.parseError, isNull);
    expect(find.text(r'$$\frac{a}{b}$$'), findsNothing);
  });

  testWidgets(r'испорченный «$\f rac{a}{b}$» после восстановления рендерится', (
    tester,
  ) async {
    // Символ 0x0C — то, что JSON-декодер оставил от \frac; шаг восстановления
    // возвращает команду, рендер получает корректный LaTeX.
    final String repaired = repairLatexControlCharacters('\$\u000Crac{a}{b}\$');
    expect(repaired, r'$\frac{a}{b}$');
    await pumpLatex(tester, repaired);

    expect(find.byType(Math), findsOneWidget);
    final Math math = tester.widget<Math>(find.byType(Math));
    expect(math.parseError, isNull);
    expect(math.ast, isNotNull);
  });

  testWidgets(r'\(…\) и \[…\] рендерятся как формулы', (tester) async {
    await pumpLatex(tester, r'Формула \(x^2\) и блок \[a+b\]');
    expect(find.byType(Math), findsNWidgets(2));
  });

  testWidgets(r'экранированный \$ — не формула', (tester) async {
    await pumpLatex(tester, r'Цена \$5 рублей');
    expect(find.byType(Math), findsNothing);
    expect(find.text(r'Цена $5 рублей'), findsOneWidget);
  });

  testWidgets('невалидная формула — предупреждение, карточка не исчезает', (
    tester,
  ) async {
    await pumpLatex(tester, r'Формула $\frac{$ сломана');
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationIssueLatexBroken), findsOneWidget);
    expect(find.textContaining('сломана'), findsOneWidget);
  });

  testWidgets('cloze: формула внутри пропуска раскрывается Math-виджетом', (
    tester,
  ) async {
    await pumpClassic(
      tester,
      card(
        front: r'Число стержней равно {{c1::$2n - 3$}}',
        type: CardType.cloze,
      ),
      revealed: false,
    );

    // До раскрытия — скрытая подсказка, после тапа — Math.
    await tester.tap(find.byKey(const ValueKey<String>('cloze-gap-1')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('cloze-answer-1')),
      findsOneWidget,
    );
    expect(find.byType(Math), findsOneWidget);
    expect(find.text(r'$2n - 3$'), findsNothing);
  });

  testWidgets('cloze: формула вне пропуска рендерится Math-виджетом', (
    tester,
  ) async {
    await pumpClassic(
      tester,
      card(
        front: r'При $n=3$ число стержней {{c1::$2n - 3$}}',
        type: CardType.cloze,
      ),
      revealed: false,
    );
    expect(find.byType(Math), findsOneWidget);
    expect(find.text(r'$n=3$'), findsNothing);
  });
}
