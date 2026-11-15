import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/cards_json_extractor.dart';
import 'package:cardflow/api/generation/latex_escape_repair.dart';
import 'package:cardflow/api/generation/latex_checker.dart';
import 'package:cardflow/domain/cards/latex_markup.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';

/// Фикстуры реальных «плохих» ответов модели (fix-gen, шаг 1 → шаг 5).
///
/// Модель пишет LaTeX в JSON-строке одним обратным слэшем: JSON-декодер
/// превращает `\f`/`\t`/`\b`/`\r`/`\n` в управляющие символы (тихая порча) и
/// отвергает `\alpha`/`\sum`/`\Delta`/`\cdot` (фрагмент падает).
void main() {
  const CardsJsonExtractor extractor = CardsJsonExtractor();

  Map<String, Object?> decode(String raw) =>
      extractor.decode(raw, tolerant: true)! as Map<String, Object?>;

  Map<String, Object?> firstCard(String raw) {
    final cards = decode(raw)['cards']! as List<Object?>;
    return (cards.first as Map).cast<String, Object?>();
  }

  String cardJson(String front, {String? imageQuery, String? imageId}) {
    return '{'
        '"front": $front, '
        '"back": "Ответ", '
        '"card_type": "basic", '
        '"tags": ["тег"], '
        '"hint": null, '
        '"source_excerpt": null, '
        '"source_file": null, '
        '"image_id": ${imageId ?? 'null'}, '
        '"image_query": ${imageQuery ?? 'null'}'
        '}';
  }

  group('гипотеза JSON-экранирования подтверждена и исправлена', () {
    test(
      r'\alpha / \sum / \Delta / \cdot не ломают разбор (был json_parse)',
      () {
        for (final command in <String>[
          r'\alpha',
          r'\sum',
          r'\Delta',
          r'\cdot',
        ]) {
          final raw = '{"cards":[${cardJson('"$command = \$1\$"')}]}';
          final Map<String, Object?> card = firstCard(raw);
          expect(
            card['front'],
            contains(command),
            reason: 'Команда $command должна дойти до карточки',
          );
        }
      },
    );

    test(r'\f rac восстанавливается в \frac (был form feed)', () {
      final raw = '{"cards":[${cardJson(r'"$\frac{a}{b}$"')}]}';
      final Map<String, Object?> card = firstCard(raw);
      expect(card['front'], r'$\frac{a}{b}$');
      expect((card['front']! as String).codeUnits.contains(0x0C), isFalse);
    });

    test('тихая порча \t imes, \b eta, \r ho, \n abla восстанавливается', () {
      for (final pair in <List<String>>[
        <String>[r'\times', r'$\times$'],
        <String>[r'\theta', r'$\theta$'],
        <String>[r'\beta', r'$\beta$'],
        <String>[r'\rho', r'$\rho$'],
        <String>[r'\nabla', r'$\nabla$'],
        <String>[r'\neq', r'$\neq$'],
      ]) {
        final raw = '{"cards":[${cardJson('"${pair[1]}"')}]}';
        final Map<String, Object?> card = firstCard(raw);
        expect(card['front'], pair[1], reason: 'команда ${pair[0]}');
      }
    });

    test('обычный перевод строки \\n не превращается в команду', () {
      final raw = '{"cards":[${cardJson(r'"Первая строка\nВторая"')}]}';
      final Map<String, Object?> card = firstCard(raw);
      expect(card['front'], contains('\n'));
      expect(card['front'], contains('Вторая'));
    });

    test('уже удвоенные слэши не портятся повторно', () {
      final raw = '{"cards":[${cardJson(r'"$\\frac{a}{b}$"')}]}';
      final Map<String, Object?> card = firstCard(raw);
      expect(card['front'], r'$\frac{a}{b}$');
    });

    test('текст без LaTeX не меняется', () {
      final raw = '{"cards":[${cardJson('"Что такое ферма?"')}]}';
      expect(firstCard(raw)['front'], 'Что такое ферма?');
    });

    test('невалидный JSON без LaTeX остаётся json_parse', () {
      expect(
        () => extractor.decode('{"cards": [', tolerant: false),
        throwsA(
          isA<GenerationException>()
              .having(
                (GenerationException error) => error.code,
                'code',
                GenerationErrorCode.invalidResponse,
              )
              .having(
                (GenerationException error) => error.reason,
                'reason',
                GenerationFailureReason.jsonParse,
              ),
        ),
      );
    });

    test('после разбора управляющий символ внутри формулы не остаётся', () {
      final Map<String, Object?> card = firstCard(
        '{"cards":[${cardJson(r'"$\frac{1}{2}$"')}]}',
      );
      final String front = card['front']! as String;
      expect(front.codeUnits.any((int code) => code < 0x20), isFalse);
      expect(front, r'$\frac{1}{2}$');
    });
  });

  group('repairLatexControlCharacters (после разбора)', () {
    test(r'\f rac → \frac внутри формулы', () {
      // Символ 0x0C — то, что осталось бы, если бы JSON разобрали до починки.
      // Восстановление работает только внутри формул: вне $…$ это обычный текст.
      expect(
        repairLatexControlCharacters('\u000Crac{1}{2}'),
        '\u000Crac{1}{2}',
      );
      expect(
        repairLatexControlCharacters('\$\u000Crac{1}{2}\$'),
        r'$\frac{1}{2}$',
      );
    });

    test('вне формулы управляющий символ не превращается в команду', () {
      expect(
        repairLatexControlCharacters('Строка\u000Crac'),
        'Строка\u000Crac',
      );
    });

    test('обычный перенос строки сохраняется', () {
      expect(repairLatexControlCharacters(r'$x\nabla$'), r'$x\nabla$');
      expect(repairLatexControlCharacters('строка\nabla'), 'строка\nabla');
    });
  });

  group('нормализация разделителей', () {
    test(r'\(…\) → $…$, \[…\] → $$…$$', () {
      expect(
        normalizeLatexDelimiters(r'Формула \(x^2\) конец'),
        r'Формула $x^2$ конец',
      );
      expect(
        normalizeLatexDelimiters(r'Блок \[a + b\] конец'),
        r'Блок $$a + b$$ конец',
      );
    });

    test(r'LatexMarkup понимает \(…\)/\[…\] и экранированный \$', () {
      final markup = LatexMarkup.parse(r'Найди \(x^2\) и цену \$5');
      expect(markup.hasFormulas, isTrue);
      final formulas = markup.segments
          .where((LatexSegment segment) => segment.isFormula)
          .toList();
      expect(formulas, hasLength(1));
      expect(formulas.single.value, 'x^2');
      final text = markup.segments
          .where((LatexSegment segment) => !segment.isFormula)
          .map((LatexSegment segment) => segment.value)
          .join();
      expect(text, contains(r'$5'));
    });

    test('незакрытый разделитель — hasUnclosedDelimiter', () {
      final markup = LatexMarkup.parse(r'Формула $x^2');
      expect(markup.hasUnclosedDelimiter, isTrue);
    });
  });

  group('latexIsValid после починки', () {
    test('испорченная формула, восстановленная из JSON, валидна', () {
      final raw = '{"cards":[${cardJson(r'"$\frac{a}{b}$"')}]}';
      final front = firstCard(raw)['front']! as String;
      expect(latexIsValid(front), isTrue);
    });

    test('экранированный доллар не делает формулу незакрытой', () {
      expect(latexIsValid(r'Цена \$5 рублей'), isTrue);
    });
  });

  test('фикстура с несколькими карточками: одна испорчена — JSON цел', () {
    final raw =
        '{"cards":['
        '${cardJson(r'"$\frac{a}{b}$"')},'
        '${cardJson(r'"$\nabla f$"', imageQuery: '"physics diagram"')}'
        ']}';
    final cards = decode(raw)['cards']! as List<Object?>;
    expect(cards, hasLength(2));
    expect(jsonEncode(cards), contains(r'\frac'));
    expect(jsonEncode(cards), contains(r'\nabla'));
  });
}
