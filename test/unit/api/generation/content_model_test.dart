import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контракт модели содержимого: Document → Section → Block с якорями
/// (этап Ingestion, ADR-050, TASK «Срез 1»).
///
/// Модель строится адаптером поверх готового `ParsedDocument`, поэтому фикстуры
/// здесь программные: разделы и текст задаются так же, как их отдаёт
/// `ParsedDocumentBuilder`.
void main() {
  const ContentModelBuilder builder = ContentModelBuilder();

  group('блоки и якоря', () {
    test('блок = строка; offsets точные, id стабильны, блок по id — O(1)', () {
      final ParsedDocument parsed = _parsedDocument(
        <String>[
          'Введение\nПервый абзац текста.',
          'Основы\nВторой абзац текста.',
        ],
        titles: <String?>[null, 'Основы'],
      );

      final Document model = builder.build(parsed);

      expect(model.fileName, 'конспект.docx');
      expect(model.id, 'doc:конспект.docx');
      expect(model.format, DocumentFormat.docx);
      expect(model.text, parsed.text);
      expect(model.blocks, hasLength(4));
      expect(model.blocks.map((Block block) => block.text), <String>[
        'Введение',
        'Первый абзац текста.',
        'Основы',
        'Второй абзац текста.',
      ]);
      for (final Block block in model.blocks) {
        expect(model.text.substring(block.start, block.end), block.text);
        expect(block.isNoise, isFalse);
        expect(block.noiseKind, isNull);
      }
      expect(model.blocks.map((Block block) => block.id), <String>[
        'doc:конспект.docx#0#0',
        'doc:конспект.docx#0#1',
        'doc:конспект.docx#1#0',
        'doc:конспект.docx#1#1',
      ]);
      // Восстановление по id — прямая ссылка из индексной карты, без поиска
      // подстроки в тексте.
      expect(
        identical(model.block('doc:конспект.docx#0#1'), model.blocks[1]),
        isTrue,
      );
      expect(model.block('doc:конспект.docx#9#9'), isNull);
      expect(model.blocksOfSection('doc:конспект.docx#1'), hasLength(2));
      expect(model.blocksOfSection('нет-такого'), isEmpty);
      expect(model.contentBlocks, hasLength(4));
      expect(model.noiseBlocks, isEmpty);
      // Блоки покрывают весь текст, кроме разделительных переводов строк.
      expect(
        model.contentLength,
        model.text.length - RegExp('\n').allMatches(model.text).length,
      );
    });

    test('пустые строки разделяют блоки и не попадают в модель', () {
      final Document model = builder.build(
        _parsedDocument(<String>['Первый абзац.\n\nВторой абзац.']),
      );

      expect(model.blocks.map((Block block) => block.text), <String>[
        'Первый абзац.',
        'Второй абзац.',
      ]);
      expect(model.blocks[1].start, model.text.indexOf('Второй абзац.'));
      expect(model.blocks[0].end, model.text.indexOf('Второй абзац.') - 2);
    });

    test('blockAt находит блок по смещению и молчит в промежутке', () {
      final Document model = builder.build(
        _parsedDocument(<String>['Первый абзац.\n\nВторой абзац.']),
      );
      final int secondStart = model.text.indexOf('Второй абзац.');

      expect(model.blockAt(0)?.text, 'Первый абзац.');
      expect(model.blockAt(12)?.text, 'Первый абзац.');
      expect(model.blockAt(13), isNull); // перевод строки
      expect(model.blockAt(14), isNull); // пустая строка
      expect(model.blockAt(secondStart)?.text, 'Второй абзац.');
      expect(model.blockAt(model.text.length - 1)?.text, 'Второй абзац.');
      expect(model.blockAt(model.text.length), isNull);
      expect(model.blockAt(-1), isNull);
    });

    test('нормализация не меняет ни текст, ни offsets блока', () {
      final Document model = builder.build(
        _parsedDocument(<String>['«Ёлка» — это дерево.']),
      );

      final Block block = model.blocks.single;
      expect(block.text, '«Ёлка» — это дерево.');
      expect(model.text.substring(block.start, block.end), block.text);
      expect(block.normalizedText, '"Елка" - это дерево.');
    });
  });

  group('отсев мусора', () {
    test('колонтитул, номер страницы, оглавление и подпись — флагом, а не удалением', () {
      final Document model = builder.build(
        _parsedDocument(
          <String>[
            'Колонтитул курса\nПервый абзац текста.',
            'Колонтитул курса\nВторой абзац текста.\n7\nРис. 4. Схема цепи',
            'Оглавление\nВведение .......... 1',
          ],
          titles: <String?>[null, 'Основы', 'Оглавление'],
        ),
      );

      final Map<String, NoiseKind?> kinds = <String, NoiseKind?>{
        for (final Block block in model.blocks) block.text: block.noiseKind,
      };
      expect(kinds['Колонтитул курса'], NoiseKind.runningHeaderFooter);
      expect(kinds['7'], NoiseKind.pageNumber);
      expect(kinds['Рис. 4. Схема цепи'], NoiseKind.figureCaption);
      expect(kinds['Оглавление'], NoiseKind.tableOfContents);
      expect(kinds['Введение .......... 1'], NoiseKind.tableOfContents);
      expect(kinds['Первый абзац текста.'], isNull);
      expect(kinds['Второй абзац текста.'], isNull);

      // Мусор остаётся в модели со своими offsets: текст документа не режется.
      expect(model.blocks, hasLength(8));
      expect(model.noiseBlocks, hasLength(6));
      expect(model.contentBlocks.map((Block block) => block.text), <String>[
        'Первый абзац текста.',
        'Второй абзац текста.',
      ]);
      for (final Block block in model.noiseBlocks) {
        expect(block.isNoise, isTrue);
        expect(model.text.substring(block.start, block.end), block.text);
      }
    });

    test('похожие, но содержательные строки мусором не считаются', () {
      final Document model = builder.build(
        _parsedDocument(<String>[
          'Рисунок природы красив.\n42-й закон Ньютона.',
          'Повторяющаяся фраза о схемах.\nПовторяющаяся фраза о схемах.',
        ]),
      );

      expect(model.noiseBlocks, isEmpty);
      expect(model.contentBlocks, hasLength(4));
    });
  });

  group('разделы и иерархия', () {
    test('граница раздела внутри строки не рвёт абзац', () {
      const String text =
          'Введение\n'
          'Первый абзац текста.\n'
          'Второй абзац.';
      final ParsedDocument parsed = ParsedDocument(
        format: DocumentFormat.pdf,
        fileName: 'файл.pdf',
        text: text,
        sections: const <ParsedSection>[
          // Граница — середина строки «Первый абзац текста.».
          ParsedSection(start: 0, end: 20),
          ParsedSection(start: 20, end: 43),
        ],
      );

      final Document model = builder.build(parsed);

      expect(model.blocks.map((Block block) => block.text), <String>[
        'Введение',
        'Первый абзац текста.',
        'Второй абзац.',
      ]);
      expect(model.sections, hasLength(2));
      // Раздел модели расширен до конца абзаца, следующий начинается со
      // следующей целой строки: ни один блок не пересекает границу раздела.
      expect(model.sections[0].end, 29);
      expect(model.sections[1].start, 30);
      expect(model.sections[0].blockIds, <String>[
        'doc:файл.pdf#0#0',
        'doc:файл.pdf#0#1',
      ]);
      expect(model.sections[1].blockIds, <String>['doc:файл.pdf#1#0']);
      expect(
        model.text.substring(model.sections[0].start, model.sections[0].end),
        'Введение\nПервый абзац текста.',
      );
      expect(
        model.text.substring(model.sections[1].start, model.sections[1].end),
        'Второй абзац.',
      );
      for (final Block block in model.blocks) {
        final Section section = model.section(block.sectionId)!;
        expect(
          block.start >= section.start && block.end <= section.end,
          isTrue,
          reason: 'блок ${block.id} вне раздела ${section.id}',
        );
      }
    });

    test('иерархия строится по нумерации заголовков', () {
      final Document model = builder.build(
        _parsedDocument(
          <String>[
            '1. Введение\nТекст введения.',
            '1.1. Основы\nТекст основ.',
            '1.2. Детали\nТекст деталей.',
            '2. Итоги\nТекст итогов.',
          ],
          titles: <String?>[
            '1. Введение',
            '1.1. Основы',
            '1.2. Детали',
            '2. Итоги',
          ],
        ),
      );

      expect(model.sections.map((Section section) => section.depth), <int>[
        0,
        1,
        1,
        0,
      ]);
      expect(model.sections[0].parentId, isNull);
      expect(model.sections[1].parentId, 'doc:конспект.docx#0');
      expect(model.sections[2].parentId, 'doc:конспект.docx#0');
      expect(model.sections[3].parentId, isNull);
      expect(model.sections[0].childIds, <String>[
        'doc:конспект.docx#1',
        'doc:конспект.docx#2',
      ]);
      expect(
        model
            .childrenOf('doc:конспект.docx#0')
            .map((Section section) => section.index),
        <int>[1, 2],
      );
      expect(model.childrenOf('doc:конспект.docx#3'), isEmpty);
    });

    test('пропущенный уровень нумерации не делает глубину скачком', () {
      final Document model = builder.build(
        _parsedDocument(
          <String>['1. Введение\nТекст.', '1.1.1. Глубокий пункт\nТекст.'],
          titles: <String?>['1. Введение', '1.1.1. Глубокий пункт'],
        ),
      );

      // «1.1.1» без «1.1»: родитель — ближайший раздел меньшей глубины,
      // глубина поднимается ровно на один уровень (дерево остаётся деревом).
      expect(model.sections[1].depth, 1);
      expect(model.sections[1].parentId, 'doc:конспект.docx#0');
      expect(model.sections[0].childIds, <String>['doc:конспект.docx#1']);
    });

    test('раздел без заголовка — корневой', () {
      final Document model = builder.build(
        _parsedDocument(
          <String>['Без заголовка\nТекст.'],
          titles: <String?>[null],
        ),
      );

      expect(model.sections.single.title, isNull);
      expect(model.sections.single.depth, 0);
      expect(model.sections.single.parentId, isNull);
      expect(model.sections.single.childIds, isEmpty);
    });
  });

  group('инварианты модели', () {
    test('пустая модель: нет текста, блоков и разделов, без исключения', () {
      final Document model = Document.empty(
        fileName: 'скан.pdf',
        format: DocumentFormat.pdf,
      );

      expect(model.isEmpty, isTrue);
      expect(model.text, isEmpty);
      expect(model.blocks, isEmpty);
      expect(model.sections, isEmpty);
      expect(model.contentBlocks, isEmpty);
      expect(model.blockAt(0), isNull);
      expect(model.block('doc:скан.pdf#0#0'), isNull);
      expect(model.format, DocumentFormat.pdf);
    });

    test('блок, текст которого не совпадает с документом, отклоняется', () {
      expect(
        () => Document(
          fileName: 'файл.txt',
          format: DocumentFormat.txt,
          text: 'Абзац.',
          blocks: <Block>[
            const Block(
              id: 'doc:файл.txt#0#0',
              sectionId: 'doc:файл.txt#0',
              start: 0,
              end: 6,
              text: 'Абзацх',
            ),
          ],
          sections: <Section>[
            Section(
              id: 'doc:файл.txt#0',
              index: 0,
              start: 0,
              end: 6,
              blockIds: const <String>['doc:файл.txt#0#0'],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('блок за пределами текста отклоняется', () {
      expect(
        () => Document(
          fileName: 'файл.txt',
          format: DocumentFormat.txt,
          text: 'Абзац.',
          blocks: <Block>[
            const Block(
              id: 'doc:файл.txt#0#0',
              sectionId: 'doc:файл.txt#0',
              start: 0,
              end: 6,
              text: 'Абзац.',
            ),
            const Block(
              id: 'doc:файл.txt#0#1',
              sectionId: 'doc:файл.txt#0',
              start: 6,
              end: 12,
              text: 'Шесть.',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}

/// Собирает `ParsedDocument` так же, как `ParsedDocumentBuilder`: разделы
/// разделены пустой строкой, offsets считаются по итоговому тексту.
ParsedDocument _parsedDocument(
  List<String> sectionTexts, {
  List<String?> titles = const <String?>[],
  DocumentFormat format = DocumentFormat.docx,
  String fileName = 'конспект.docx',
}) {
  final StringBuffer buffer = StringBuffer();
  final List<ParsedSection> sections = <ParsedSection>[];
  for (var index = 0; index < sectionTexts.length; index++) {
    if (buffer.isNotEmpty) {
      buffer.write('\n\n');
    }
    final int start = buffer.length;
    buffer.write(sectionTexts[index]);
    sections.add(
      ParsedSection(
        start: start,
        end: buffer.length,
        title: index < titles.length ? titles[index] : null,
      ),
    );
  }
  return ParsedDocument(
    format: format,
    fileName: fileName,
    text: buffer.toString(),
    sections: sections,
  );
}
