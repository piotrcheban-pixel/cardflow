import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/source_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Документ из двух строк одного раздела: блоки 10..23 и 24..38.
Document _document() {
  const String text = 'Первая строка текста\nВторая строка текста';
  return Document(
    fileName: 'lemma.txt',
    text: text,
    blocks: <Block>[
      const Block(
        id: 'doc:lemma.txt#doc:lemma.txt#0#0',
        sectionId: 'doc:lemma.txt#0',
        start: 0,
        end: 20,
        text: 'Первая строка текста',
      ),
      const Block(
        id: 'doc:lemma.txt#doc:lemma.txt#0#1',
        sectionId: 'doc:lemma.txt#0',
        start: 21,
        end: 41,
        text: 'Вторая строка текста',
      ),
    ],
    sections: <Section>[
      Section(
        id: 'doc:lemma.txt#0',
        index: 0,
        start: 0,
        end: 41,
        title: 'Раздел 1',
        blockIds: const <String>[
          'doc:lemma.txt#doc:lemma.txt#0#0',
          'doc:lemma.txt#doc:lemma.txt#0#1',
        ],
      ),
    ],
  );
}

void main() {
  const SourceAnchorResolver resolver = SourceAnchorResolver();

  test('цитата внутри блока возвращает блок целиком, а не выдержку', () {
    final SourceAnchor? anchor = resolver.resolve(<Document>[
      _document(),
    ], quote: 'Вторая строка');
    expect(anchor, isNotNull);
    expect(anchor!.text, 'Вторая строка текста');
    expect(anchor.blockId, 'doc:lemma.txt#doc:lemma.txt#0#1');
    expect(anchor.sectionTitle, 'Раздел 1');
    expect(anchor.fileName, 'lemma.txt');
  });

  test('склеенная выдержка из двух строк даёт Block, а не склейку', () {
    final SourceAnchor? anchor = resolver.resolve(<Document>[
      _document(),
    ], excerpt: 'Первая строка текста Вторая строка');
    expect(anchor, isNotNull);
    // «Склейка» — самый длинный блок, целиком входящий в цитату.
    expect(anchor!.text, 'Первая строка текста');
    expect(anchor.text.contains('\n'), isFalse);
  });

  test('нормализация не мешает: ё/регистр/кавычки', () {
    final SourceAnchor? anchor = resolver.resolve(<Document>[
      _document(),
    ], quote: 'ВТОРАЯ СТРОКА ТЕКСТА');
    expect(anchor?.text, 'Вторая строка текста');
  });

  test('слишком короткая цитата и отсутствие текста — null', () {
    expect(resolver.resolve(<Document>[_document()], quote: 'abc'), isNull);
    expect(
      resolver.resolve(<Document>[_document()], quote: 'Такого текста нет'),
      isNull,
    );
    expect(resolver.resolve(<Document>[_document()]), isNull);
  });

  test('цитата ищется в нескольких документах', () {
    final Document second = _document();

    final SourceAnchor? anchor = resolver.resolve(<Document>[
      Document.empty(fileName: 'empty.txt'),
      second,
    ], quote: 'Первая строка текста');
    expect(anchor?.blockId, 'doc:lemma.txt#doc:lemma.txt#0#0');
  });
}
