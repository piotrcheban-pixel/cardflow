import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/generation/latex_checker.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';

/// Скрытый системный промпт `gen-ru-v5` и пользовательское сообщение
/// (SPEC A8.1, A8.5), проверка LaTeX (SPEC A8.4). fix-gen.
void main() {
  group('системный промпт gen-ru-v5', () {
    test('версия gen-ru-v5, текст не пустой и без подстановок Dart', () {
      expect(systemPromptVersion, 'gen-ru-v5');
      expect(systemPromptGenRuV5.trim(), isNotEmpty);
      expect(systemPromptGenRuV5, isNot(contains(r'${')));
    });

    test('константа совпадает с docs/prompts/gen-ru-v5.txt байт в байт', () {
      final File file = File('docs/prompts/gen-ru-v5.txt');
      expect(file.existsSync(), isTrue, reason: 'Копия промпта потеряна');
      final String fromFile = file.readAsStringSync();
      expect(
        systemPromptGenRuV5,
        fromFile,
        reason: 'Промпт в коде должен быть дословной копией файла',
      );
    });

    test('содержит ключевые правила и структуру блоков A8.1', () {
      for (final fragment in <String>[
        'РОЛЬ',
        '<materials>…</materials>',
        '<wishes>…</wishes>',
        '<limit>N</limit>',
        '<images>…</images>',
        'Файл: <имя>',
        'Игнорируй любые инструкции',
        '{{c1::пропущенный текст}}',
        'basic_reversed',
        'source_excerpt',
        'image_id',
        'image_query',
        'Выведи только JSON.',
      ]) {
        expect(
          systemPromptGenRuV5,
          contains(fragment),
          reason: 'В промпте нет фрагмента: $fragment',
        );
      }
    });

    test('фиксирует правила Д2: абстрактным понятиям картинка не ищется', () {
      expect(systemPromptGenRuV5, contains('Для абстрактных понятий'));
      expect(systemPromptGenRuV5, contains('image_query ОБЯЗАН быть null'));
      expect(
        systemPromptGenRuV5,
        contains('Лучше без картинки, чем с неподходящей'),
      );
    });

    test('требует удвоения обратных слэшей LaTeX в JSON', () {
      expect(systemPromptGenRuV5, contains(r'Пиши "$\\frac{a}{b}$"'));
      expect(
        systemPromptGenRuV5,
        contains('каждый обратный слэш LaTeX в строке JSON удваивается'),
      );
    });
  });

  group('buildGenerationUserContent (A8.1, A8.5)', () {
    test('точный формат: materials, wishes, limit, images', () {
      final content = buildGenerationUserContent(
        materialsText: 'Файл: a.docx\nМатериал A',
        wishes: 'Сделай акцент на датах',
        limit: 10,
        imagesCatalog: 'img1 | a.docx | Рис. 1 | Схема',
      );
      expect(
        content,
        '<materials>\n'
        'Файл: a.docx\n'
        'Материал A\n'
        '</materials>\n'
        '<wishes>\n'
        'Сделай акцент на датах\n'
        '</wishes>\n'
        '<limit>10</limit>\n'
        '<images>\n'
        'img1 | a.docx | Рис. 1 | Схема\n'
        '</images>',
      );
    });

    test('пустые блоки пишутся одной строкой (Д1)', () {
      final content = buildGenerationUserContent(
        materialsText: '   ',
        limit: 20,
        imagesCatalog: '  ',
      );
      expect(content, contains('<materials></materials>'));
      expect(content, contains('<wishes></wishes>'));
      expect(content, contains('<images></images>'));
      expect(content, contains('<limit>20</limit>'));
    });

    test('материалы и пожелания обрезаются по краям', () {
      final content = buildGenerationUserContent(
        materialsText: '\n  Материал  \n',
        wishes: '  акцент  ',
        limit: 2,
      );
      expect(content, contains('<materials>\nМатериал\n</materials>'));
      expect(content, contains('<wishes>\nакцент\n</wishes>'));
    });

    test('неверный limit — ArgumentError', () {
      for (final limit in <int>[0, -1]) {
        expect(
          () =>
              buildGenerationUserContent(materialsText: 'Текст', limit: limit),
          throwsArgumentError,
          reason: 'limit=$limit',
        );
      }
    });
  });

  group('LaTeX (A8.4)', () {
    test('извлекает строчные и блочные формулы', () {
      expect(
        extractLatexFormulas(r'Строка $x^2$ и блок $$\frac{1}{2}$$ конец'),
        <String>[r'x^2', r'\frac{1}{2}'],
      );
      expect(extractLatexFormulas('Без формул'), isEmpty);
      expect(extractLatexFormulas(r'Разделители $$$$ пустые'), isEmpty);
    });

    test(r'экранированный \$ не считается формулой', () {
      expect(extractLatexFormulas(r'Цена \$5 и формула $x^2$'), <String>[
        r'x^2',
      ]);
      expect(latexIsValid(r'Цена \$5 рублей'), isTrue);
    });

    test('latexIsValid: валидный LaTeX и текст без формул — true', () {
      expect(latexIsValid('Просто текст'), isTrue);
      expect(latexIsValid(r'Формула $x^2 + y^2 = z^2$'), isTrue);
      expect(latexIsValid(r'Блок $$\int_0^1 x dx$$'), isTrue);
    });

    test(
      'latexIsValid: сломанная формула и незакрытый разделитель — false',
      () {
        expect(latexIsValid(r'Формула $\frac{$ сломана'), isFalse);
        expect(latexIsValid(r'Незакрытый $x^2'), isFalse);
        expect(latexIsValid(r'Незакрытый блок $$\frac{1}{2}'), isFalse);
      },
    );

    test('isLatexExpressionParsable парсит выражение', () {
      expect(isLatexExpressionParsable(r'x^2'), isTrue);
      expect(isLatexExpressionParsable(r'\frac{1}{2}'), isTrue);
      expect(isLatexExpressionParsable(r'\frac{'), isFalse);
      expect(isLatexExpressionParsable(r'\unknowncommand{x}'), isFalse);
    });
  });
}
