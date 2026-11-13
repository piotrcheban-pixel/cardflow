import 'dart:typed_data';

import 'package:cardflow/api/parsers/rtf_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/document_fixtures.dart';

/// Красная фаза итерации 3a: минимальный RTF-конвертер (SPEC A8.3, ADR-010).
void main() {
  const RtfParser parser = RtfParser();

  Future<ParsedDocument> parse(Uint8List bytes) =>
      parser.parse(bytes, fileName: 'заметка.rtf');

  test('формат парсера — rtf', () {
    expect(parser.format, DocumentFormat.rtf);
  });

  test('простой ASCII-текст и \\par', () async {
    final ParsedDocument document = await parse(
      buildRtf('Line one\\par Line two'),
    );
    expect(document.text, 'Line one\nLine two');
  });

  test('\\line и \\tab дают перевод строки и табуляцию', () async {
    final ParsedDocument document = await parse(
      buildRtf('Label\\tab value\\line next'),
    );
    expect(
      document.text,
      'Label\tvalue\nnext',
      reason: '\\tab → \\t, \\line → \\n',
    );
  });

  test('русский текст через \\\'hh с ansicpg1251', () async {
    const String russian = 'Привет как дела';
    final ParsedDocument document = await parse(
      buildRtf(rtfEscapedCp1251(russian)),
    );
    expect(document.text, russian);
  });

  test('\\uN декодируется, fallback-символ пропускается (\\uc1)', () async {
    final String body =
        'Code: ${rtfUnicodeChar(0x041F)}${rtfUnicodeChar(0x0440)}'
        '${rtfUnicodeChar(0x0438)}';
    final ParsedDocument document = await parse(buildRtf(body));
    expect(document.text, 'Code: При');
  });

  test('группы fonttbl/colortbl/stylesheet/pict/info пропускаются', () async {
    final ParsedDocument document = await parse(
      buildRtf(
        '{\\fonttbl{\\f0 Arial;}}'
        '{\\colortbl;\\red0\\green0\\blue0;}'
        '{\\stylesheet{\\s0 Normal;}}'
        '{\\pict\\pngblip 89504e47}'
        '{\\info{\\title Hidden title}}'
        'Visible text',
      ),
    );
    expect(document.text, 'Visible text');
  });

  test('экранирование \\\\, \\{ и \\} даёт литералы', () async {
    final ParsedDocument document = await parse(
      buildRtf('Braces \\{x\\} and slash \\\\'),
    );
    expect(document.text, 'Braces {x} and slash \\');
  });

  test('не-RTF вход → ParserException(unreadableFile)', () async {
    await expectLater(
      parse(Uint8List.fromList(<int>[0x50, 0x4B, 3, 4])),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.unreadableFile,
        ),
      ),
    );
  });

  test('пустой текст RTF → ParserException(emptyText)', () async {
    await expectLater(
      parse(buildRtf('{\\fonttbl{\\f0 Arial;}}')),
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

