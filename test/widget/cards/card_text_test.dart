import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/latex_markup.dart';
import 'package:cardflow/domain/study/answer_matcher.dart';
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/cards/content/inline_latex_text.dart';
import 'package:cardflow/ui/study/typing_screen.dart';

import '../../helpers/pump_app.dart';

/// Единый inline-рендер текста карточки (7.17): [CardText] и LaTeX-diff.
void main() {
  Future<void> pumpChild(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: const [],
        home: Scaffold(
          body: Center(
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 16),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('CardText', () {
    testWidgets(r'формула — Math, сырого $…$ нет', (tester) async {
      await pumpChild(tester, const CardText(source: r'Формула $E=mc^2$'));

      expect(find.byType(Math), findsOneWidget);
      expect(find.text(r'Формула $E=mc^2$'), findsNothing);
      expect(find.text(r'$E=mc^2$'), findsNothing);
    });

    testWidgets('обычный текст остаётся Text с data (find.text работает)', (
      tester,
    ) async {
      await pumpChild(tester, const CardText(source: 'Митохондрия'));

      expect(find.text('Митохондрия'), findsOneWidget);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('cloze-разметка раскрывается, а не показывается сырой', (
      tester,
    ) async {
      await pumpChild(
        tester,
        const CardText(source: 'Столица {{c1::Франции}} — {{c2::Париж}}'),
      );

      expect(find.textContaining('{{', findRichText: true), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('cloze-answer-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('cloze-answer-2')),
        findsOneWidget,
      );
    });

    testWidgets('cloze с revealed: false прячет пропуски', (tester) async {
      await pumpChild(
        tester,
        const CardText(source: 'Столица {{c1::Франции}}', revealed: false),
      );

      expect(find.byKey(const ValueKey<String>('cloze-gap-1')), findsOneWidget);
      expect(find.textContaining('{{', findRichText: true), findsNothing);
    });

    testWidgets(r'формула внутри cloze-пропуска — Math', (tester) async {
      await pumpChild(
        tester,
        const CardText(source: r'Число стержней {{c1::$2n - 3$}}'),
      );

      expect(find.byType(Math), findsOneWidget);
      expect(find.text(r'$2n - 3$'), findsNothing);
    });
  });

  group('InlineLatexText', () {
    testWidgets('несколько формул и текста — все Math, без «Следующий шаг»', (
      tester,
    ) async {
      await pumpChild(
        tester,
        const InlineLatexText(source: r'При $n=3$ и $m=4$ итог'),
      );

      expect(find.byType(Math), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey<String>('latex-next-step')),
        findsNothing,
      );
    });

    testWidgets('maxLines/ellipsis/textAlign прокидываются в Text.rich', (
      tester,
    ) async {
      await pumpChild(
        tester,
        const InlineLatexText(
          source: r'Длинный текст с формулой $a+b$',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      );

      final Text text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.textAlign, TextAlign.center);
    });
  });

  group('plainTextOfLatex', () {
    test('убирает разделители, оставляет выражения', () {
      expect(plainTextOfLatex(r'Формула $E=mc^2$'), 'Формула E=mc^2');
      expect(plainTextOfLatex(r'$$a+b$$'), 'a+b');
      expect(plainTextOfLatex(r'\(x^2\)'), 'x^2');
      expect(plainTextOfLatex('Обычный текст'), 'Обычный текст');
    });

    test('незакрытый разделитель возвращает строку как есть', () {
      expect(plainTextOfLatex(r'Сломанная $\frac{'), r'Сломанная $\frac{');
    });
  });

  group('AnswerDiffView', () {
    testWidgets('формула во фрагменте diff рендерится Math', (tester) async {
      await pumpChild(
        tester,
        const AnswerDiffView(
          diff: <AnswerDiffOp>[
            AnswerDiffOp(AnswerDiffKind.equal, 'E='),
            AnswerDiffOp(AnswerDiffKind.missing, r'$mc^2$'),
          ],
        ),
      );

      expect(find.byType(Math), findsOneWidget);
      expect(find.text(r'$mc^2$'), findsNothing);
      expect(find.byKey(const ValueKey<String>('typing-diff')), findsOneWidget);
    });

    testWidgets('обрывок формулы не падает и остаётся текстом', (tester) async {
      await pumpChild(
        tester,
        const AnswerDiffView(
          diff: <AnswerDiffOp>[
            AnswerDiffOp(AnswerDiffKind.missing, r'$\frac{'),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('typing-diff')), findsOneWidget);
    });

    testWidgets('обычный diff: подсветка лишнего и недостающего', (
      tester,
    ) async {
      await pumpChild(
        tester,
        const AnswerDiffView(
          diff: <AnswerDiffOp>[
            AnswerDiffOp(AnswerDiffKind.equal, 'Митох'),
            AnswerDiffOp(AnswerDiffKind.extra, 'и'),
            AnswerDiffOp(AnswerDiffKind.missing, 'ондрия'),
          ],
        ),
      );

      expect(find.textContaining('Митох', findRichText: true), findsOneWidget);
      final Text text = tester.widget<Text>(
        find.byKey(const ValueKey<String>('typing-diff')),
      );
      final String plain = text.textSpan!.toPlainText();
      expect(plain, 'Митохиондрия');
      expect(find.byType(Math), findsNothing);
    });
  });
}
