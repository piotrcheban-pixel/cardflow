import 'dart:typed_data';

import 'package:cardflow/api/parsers/txt_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/document_fixtures.dart';

/// Красная фаза итерации 3a: TXT/MD и определение кодировки (SPEC A8.3).
void main() {
  const TxtParser txtParser = TxtParser();
  const TxtParser mdParser = TxtParser(format: DocumentFormat.md);
  const String russian = 'Привет как дела Это проверка кодировки текста';

  Future<ParsedDocument> parseTxt(List<int> bytes) =>
      txtParser.parse(Uint8List.fromList(bytes), fileName: 'конспект.txt');

  test('форматы парсеров: txt и md', () {
    expect(txtParser.format, DocumentFormat.txt);
    expect(mdParser.format, DocumentFormat.md);
  });

  test('UTF-8 без BOM: текст и кодировка в метаданных', () async {
    final ParsedDocument document = await parseTxt(utf8Bytes(russian));
    expect(document.text, russian);
    expect(document.metadata.encoding, 'utf-8');
    expect(document.sections, hasLength(1));
  });

  test('UTF-8 с BOM: BOM удаляется, кодировка utf-8-bom', () async {
    final ParsedDocument document = await parseTxt(utf8BomBytes(russian));
    expect(document.text, russian);
    expect(document.metadata.encoding, 'utf-8-bom');
    expect(document.text.startsWith('\uFEFF'), isFalse);
  });

  test('UTF-16 LE/BE с BOM распознаются', () async {
    final ParsedDocument le = await parseTxt(utf16LeBomBytes(russian));
    expect(le.text, russian);
    expect(le.metadata.encoding, 'utf-16le');

    final ParsedDocument be = await parseTxt(utf16BeBomBytes(russian));
    expect(be.text, russian);
    expect(be.metadata.encoding, 'utf-16be');
  });

  test('Windows-1251 определяется по частоте русских букв', () async {
    final ParsedDocument document = await parseTxt(cp1251Bytes(russian));
    expect(document.text, russian);
    expect(document.metadata.encoding, 'windows-1251');
  });

  test('KOI8-R определяется по частоте русских букв', () async {
    final ParsedDocument document = await parseTxt(koi8rBytes(russian));
    expect(document.text, russian);
    expect(document.metadata.encoding, 'koi8-r');
  });

  test('MD читается тем же декодером, текст сохраняется как есть', () async {
    const String markdown = '# Заголовок\n\nСписок:\n- раз\n- два';
    final ParsedDocument document = await mdParser.parse(
      utf8Bytes(markdown),
      fileName: 'заметки.md',
    );
    expect(document.format, DocumentFormat.md);
    expect(document.text, markdown);
  });

  test('пустой файл → ParserException(emptyText)', () async {
    await expectLater(
      parseTxt(<int>[]),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.emptyText,
        ),
      ),
    );
  });

  test('текст из пробелов/переводов строк → ParserException(emptyText)', () async {
    await expectLater(
      parseTxt(utf8Bytes('   \r\n\t\n  ')),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.emptyText,
        ),
      ),
    );
  });
}

