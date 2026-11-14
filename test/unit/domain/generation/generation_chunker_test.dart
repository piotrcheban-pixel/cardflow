import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Документ из разделов: текст — разделы через пустую строку (инвариант A8.3).
ParsedDocument docOf(
  String fileName,
  List<String> sections, {
  List<String?> titles = const <String?>[],
}) {
  final buffer = StringBuffer();
  final parsed = <ParsedSection>[];
  for (var i = 0; i < sections.length; i++) {
    if (i > 0) buffer.write('\n\n');
    final start = buffer.length;
    buffer.write(sections[i]);
    parsed.add(
      ParsedSection(
        start: start,
        end: buffer.length,
        title: i < titles.length ? titles[i] : null,
      ),
    );
  }
  return ParsedDocument(
    format: DocumentFormat.txt,
    fileName: fileName,
    text: buffer.toString(),
    sections: parsed,
  );
}

void main() {
  const chunker = GenerationChunker();

  test('пустой список документов — пустой результат', () {
    expect(
      chunker.chunkDocuments(const <ParsedDocument>[], maxInputTokens: 1000),
      isEmpty,
    );
  });

  test('маленький документ — один фрагмент, текст и файл сохранены', () {
    final document = docOf('лекция.txt', <String>['Раздел 1', 'Текст раздела']);
    final chunks = chunker.chunkDocuments(<ParsedDocument>[
      document,
    ], maxInputTokens: 1000);
    expect(chunks, hasLength(1));
    expect(chunks.single.materialsText, contains('Раздел 1'));
    expect(chunks.single.materialsText, contains('Текст раздела'));
    expect(chunks.single.sourceFiles, <String>['лекция.txt']);
    expect(chunks.single.index, 1);
    expect(chunks.single.limit, kMaxCardsPerChunk);
    expect(chunks.single.splitAttempted, isFalse);
  });

  test('разделы упаковываются по бюджету без потери текста', () {
    final document = docOf('a.md', <String>[
      'abcdefghij',
      'klmnopqrst',
      'uvwxyzабвг',
      'дежзийклмн',
    ]);
    final chunks = chunker.chunkDocuments(<ParsedDocument>[
      document,
    ], maxInputTokens: 10);
    expect(chunks.length, greaterThan(1));
    final joined = chunks.map((chunk) => chunk.materialsText).join('\n\n');
    for (final text in <String>[
      'abcdefghij',
      'klmnopqrst',
      'uvwxyzабвг',
      'дежзийклмн',
    ]) {
      expect(joined, contains(text));
    }
  });

  test('порядок фрагментов и нумерация с 1', () {
    final chunks = chunker.chunkDocuments(<ParsedDocument>[
      docOf('a.txt', <String>['Первый раздел длиной побольше']),
      docOf('b.txt', <String>['Второй раздел длиной побольше']),
    ], maxInputTokens: 6);
    expect(chunks.length, greaterThanOrEqualTo(2));
    for (var i = 0; i < chunks.length; i++) {
      expect(chunks[i].index, i + 1);
    }
    final int firstIndex = chunks.indexWhere(
      (chunk) => chunk.materialsText.contains('Первый'),
    );
    final int secondIndex = chunks.indexWhere(
      (chunk) => chunk.materialsText.contains('Второй'),
    );
    expect(firstIndex, greaterThanOrEqualTo(0));
    expect(secondIndex, greaterThan(firstIndex));
  });

  test('большой раздел делится по абзацам, бюджет соблюдается', () {
    final paragraph = 'а' * 40; // 16 токенов
    final document = docOf('big.txt', <String>[
      '$paragraph\n\n$paragraph\n\n$paragraph',
    ]);
    final chunks = chunker.chunkDocuments(<ParsedDocument>[
      document,
    ], maxInputTokens: 10);
    expect(chunks.length, greaterThan(1));
    for (final chunk in chunks) {
      expect(
        const TokenEstimator().estimate(chunk.materialsText),
        lessThanOrEqualTo(10),
      );
    }
    final joined = chunks.map((chunk) => chunk.materialsText).join('\n\n');
    expect(joined.replaceAll(RegExp(r'\s'), ''), 'а' * 120);
  });

  test('слишком длинный абзац режется жёстко по символам', () {
    final document = docOf('long.txt', <String>['б' * 100]);
    final chunks = chunker.chunkDocuments(<ParsedDocument>[
      document,
    ], maxInputTokens: 10);
    expect(chunks.length, greaterThan(1));
    for (final chunk in chunks) {
      expect(
        const TokenEstimator().estimate(chunk.materialsText),
        lessThanOrEqualTo(10),
      );
    }
    final joined = chunks.map((chunk) => chunk.materialsText).join();
    expect(joined.replaceAll(RegExp(r'\s'), ''), 'б' * 100);
  });

  test('sourceFiles объединяются без дублей', () {
    final document = docOf('один.txt', <String>['Раз', 'Два', 'Три']);
    final chunks = chunker.chunkDocuments(<ParsedDocument>[
      document,
    ], maxInputTokens: 3);
    for (final chunk in chunks) {
      expect(chunk.sourceFiles, <String>['один.txt']);
    }
  });

  test('splitInHalf делит текст, сохраняя содержимое и помечая split', () {
    const chunk = GenerationChunk(
      index: 2,
      materialsText: 'Первая половина текста\n\nВторая половина текста',
      sourceFiles: <String>['x.txt'],
      limit: 10,
    );
    final halves = chunker.splitInHalf(chunk);
    expect(halves, isNotNull);
    expect(halves!, hasLength(2));
    expect(halves[0].index, 2);
    expect(halves[1].index, 3);
    for (final half in halves) {
      expect(half.splitAttempted, isTrue);
      expect(half.limit, chunk.limit);
      expect(half.sourceFiles, chunk.sourceFiles);
    }
    final joined = halves.map((half) => half.materialsText).join();
    expect(joined.replaceAll(RegExp(r'\s'), ''), contains('Перваяполовина'));
    expect(joined.replaceAll(RegExp(r'\s'), ''), contains('Втораяполовина'));
  });

  test('splitInHalf короткого фрагмента возвращает null', () {
    const chunk = GenerationChunk(
      index: 1,
      materialsText: 'а',
      sourceFiles: <String>[],
      limit: 20,
    );
    expect(chunker.splitInHalf(chunk), isNull);
  });
}
