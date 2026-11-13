import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:enough_convert/enough_convert.dart';

/// Программные фикстуры документов для тестов парсеров (SPEC A8.3).
///
/// Бинарные файлы в репозитории не храним: все контейнеры (DOCX/PPTX/ODT/XLSX),
/// PDF, RTF и тексты в кодировках собираются кодом — фикстуры детерминированы
/// и читаемы в тестах.

/// Экранирует текст для вставки в XML.
String xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Собирает ZIP из строковых записей (UTF-8).
Uint8List zipFixture(Map<String, String> files) {
  final Archive archive = Archive();
  files.forEach((String name, String content) {
    final List<int> bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const String _contentTypesDocx = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

const String _relsDocx = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

/// Абзац DOCX; [style] — стиль абзаца (`Heading1`, `Title`, ...).
String docxParagraph(String text, {String? style}) {
  final String properties = style == null
      ? ''
      : '<w:pPr><w:pStyle w:val="${xmlEscape(style)}"/></w:pPr>';
  return '<w:p>$properties<w:r><w:t xml:space="preserve">'
      '${xmlEscape(text)}</w:t></w:r></w:p>';
}

/// Абзац DOCX из нескольких runs (проверка склейки `w:t`).
String docxParagraphRuns(List<String> runs) {
  final String content = runs
      .map(
        (String run) =>
            '<w:r><w:t xml:space="preserve">${xmlEscape(run)}</w:t></w:r>',
      )
      .join();
  return '<w:p>$content</w:p>';
}

/// Таблица DOCX: строки и ячейки (`w:tbl`/`w:tr`/`w:tc`).
String docxTable(List<List<String>> rows) {
  final String content = rows
      .map(
        (List<String> cells) =>
            '<w:tr>${cells.map((String cell) => '<w:tc>${docxParagraph(cell)}</w:tc>').join()}</w:tr>',
      )
      .join();
  return '<w:tbl>$content</w:tbl>';
}

/// Собирает DOCX с заданным содержимым `w:body`.
Uint8List buildDocx({required String bodyXml}) => zipFixture(<String, String>{
  '[Content_Types].xml': _contentTypesDocx,
  '_rels/.rels': _relsDocx,
  'word/document.xml':
      '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>$bodyXml</w:body>
</w:document>''',
});

/// Собирает DOCX из абзацев (без таблиц).
Uint8List buildDocxFromParagraphs(List<String> paragraphs) =>
    buildDocx(bodyXml: paragraphs.map((String p) => docxParagraph(p)).join());

/// XML одного слайда PPTX (`a:t` — текстовые прогоны).
String pptxSlideXml(List<String> paragraphs) {
  final String content = paragraphs
      .map(
        (String paragraph) =>
            '<a:p><a:r><a:t>${xmlEscape(paragraph)}</a:t></a:r></a:p>',
      )
      .join();
  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree><p:sp><p:txBody>$content</p:txBody></p:sp></p:spTree></p:cSld>
</p:sld>''';
}

/// Собирает PPTX.
///
/// [slideTexts] — тексты слайдов в порядке файлов `slide1.xml`, `slide2.xml`, ...;
/// [presentationOrder] — порядок показа (1-based номера файлов). Если `null`,
/// порядок равен порядку файлов. Если `presentationOrder` равен пустому списку —
/// `presentation.xml` не добавляется (проверка fallback по номерам файлов).
Uint8List buildPptx({
  required List<List<String>> slideTexts,
  List<int>? presentationOrder,
}) {
  final Map<String, String> files = <String, String>{
    '[Content_Types].xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
</Types>''',
    '_rels/.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''',
  };
  for (int i = 0; i < slideTexts.length; i++) {
    files['ppt/slides/slide${i + 1}.xml'] = pptxSlideXml(slideTexts[i]);
  }
  final List<int> order =
      presentationOrder ??
      <int>[for (int i = 0; i < slideTexts.length; i++) i + 1];
  final StringBuffer rels = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
  );
  for (int i = 0; i < order.length; i++) {
    rels.write(
      '<Relationship Id="rId${i + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
      'Target="slides/slide${order[i]}.xml"/>',
    );
  }
  rels.write('</Relationships>');
  files['ppt/_rels/presentation.xml.rels'] = rels.toString();
  final StringBuffer presentation = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<p:sldIdLst>',
  );
  for (int i = 0; i < order.length; i++) {
    presentation.write('<p:sldId id="${256 + i}" r:id="rId${i + 1}"/>');
  }
  presentation.write('</p:sldIdLst></p:presentation>');
  if (order.isNotEmpty) {
    files['ppt/presentation.xml'] = presentation.toString();
  }
  return zipFixture(files);
}

/// Собирает ODT с заголовками и абзацами.
Uint8List buildOdt({required List<({String text, bool heading})> blocks}) {
  final String content = blocks
      .map(
        (({String text, bool heading}) block) => block.heading
            ? '<text:h text:outline-level="1">${xmlEscape(block.text)}</text:h>'
            : '<text:p>${xmlEscape(block.text)}</text:p>',
      )
      .join();
  return zipFixture(<String, String>{
    'mimetype': 'application/vnd.oasis.opendocument.text',
    '[Content_Types].xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xhtml" ContentType="application/xhtml+xml"/>
</Types>''',
    'content.xml':
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<office:document-content
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:body><office:text>$content</office:text></office:body>
</office:document-content>''',
  });
}

/// Ячейка XLSX с текстом.
String xlsxTextCell(String reference, String text) =>
    '<c r="$reference" t="inlineStr"><is><t>${xmlEscape(text)}</t></is></c>';

/// Ячейка XLSX с числом.
String xlsxNumberCell(String reference, num value) =>
    '<c r="$reference"><v>$value</v></c>';

/// Ячейка XLSX с формулой и кэшированным значением.
String xlsxFormulaCell(String reference, String formula, String cachedValue) =>
    '<c r="$reference"><f>${xmlEscape(formula)}</f><v>$cachedValue</v></c>';

/// Ячейка XLSX с датой (OOXML `t="d"`, ISO-8601).
String xlsxDateCell(String reference, String isoDate) =>
    '<c r="$reference" t="d"><v>${xmlEscape(isoDate)}</v></c>';

/// Строка XLSX из готовых ячеек.
String xlsxRow(int rowNumber, List<String> cells) =>
    '<row r="$rowNumber">${cells.join()}</row>';

/// Собирает XLSX: ключи [sheets] — имена листов, значения — XML `<sheetData>`.
Uint8List buildXlsx(Map<String, String> sheets) {
  final List<String> sheetNames = sheets.keys.toList();
  final Map<String, String> files = <String, String>{
    '[Content_Types].xml':
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
${sheetNames.asMap().entries.map((MapEntry<int, String> entry) => '  <Override PartName="/xl/worksheets/sheet${entry.key + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join('\n')}
</Types>''',
    '_rels/.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''',
    'xl/workbook.xml':
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>${sheetNames.asMap().entries.map((MapEntry<int, String> entry) => '<sheet name="${xmlEscape(entry.value)}" sheetId="${entry.key + 1}" r:id="rId${entry.key + 1}"/>').join()}</sheets>
</workbook>''',
  };
  final StringBuffer rels = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
  );
  for (int i = 0; i < sheetNames.length; i++) {
    rels.write(
      '<Relationship Id="rId${i + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet${i + 1}.xml"/>',
    );
  }
  rels.write('</Relationships>');
  files['xl/_rels/workbook.xml.rels'] = rels.toString();
  sheets.forEach((String name, String sheetData) {
    files['xl/worksheets/sheet${sheetNames.indexOf(name) + 1}.xml'] =
        '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>$sheetData</sheetData>
</worksheet>''';
  });
  return zipFixture(files);
}

/// Минимальный валидный PDF с текстовым слоем (Helvetica, одна страница).
Uint8List buildPdf(String text) {
  final StringBuffer buffer = StringBuffer('%PDF-1.4\n');
  final List<int> offsets = <int>[];
  final String content = 'BT /F1 24 Tf 72 720 Td ($text) Tj ET';
  final List<String> objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (int i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final int xrefOffset = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final int offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// Минимальный PDF без текстового слоя (страница без содержимого) — «скан».
Uint8List buildPdfWithoutText() {
  final StringBuffer buffer = StringBuffer('%PDF-1.4\n');
  final List<int> offsets = <int>[];
  final List<String> objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>',
  ];
  for (int i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final int xrefOffset = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final int offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// Собирает RTF-документ с заданным телом (latin1-совместимым; кириллица —
/// через [rtfEscapedCp1251]/[rtfUnicodeChar]).
Uint8List buildRtf(String body, {int codepage = 1251}) =>
    Uint8List.fromList(latin1.encode('{\\rtf1\\ansi\\ansicpg$codepage $body}'));

/// RTF-представление текста в cp1251 через `\'hh` (для ANSI-ветки).
String rtfEscapedCp1251(String text) {
  final List<int> bytes = const Windows1251Codec().encode(text);
  return bytes
      .map((int byte) => "\\'${byte.toRadixString(16).padLeft(2, '0')}")
      .join();
}

/// RTF-представление code unit через `\uN` (signed 16-bit).
String rtfUnicodeChar(int codeUnit) {
  final int signed = codeUnit > 32767 ? codeUnit - 65536 : codeUnit;
  return '\\u$signed?';
}

/// Кодировки текстовых фикстур.
Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// UTF-8 с BOM (EF BB BF).
Uint8List utf8BomBytes(String text) =>
    Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);

/// UTF-16 LE с BOM (FF FE).
Uint8List utf16LeBomBytes(String text) {
  final List<int> bytes = <int>[0xFF, 0xFE];
  for (final int codeUnit in text.codeUnits) {
    bytes
      ..add(codeUnit & 0xFF)
      ..add((codeUnit >> 8) & 0xFF);
  }
  return Uint8List.fromList(bytes);
}

/// UTF-16 BE с BOM (FE FF).
Uint8List utf16BeBomBytes(String text) {
  final List<int> bytes = <int>[0xFE, 0xFF];
  for (final int codeUnit in text.codeUnits) {
    bytes
      ..add((codeUnit >> 8) & 0xFF)
      ..add(codeUnit & 0xFF);
  }
  return Uint8List.fromList(bytes);
}

/// Windows-1251.
Uint8List cp1251Bytes(String text) =>
    Uint8List.fromList(const Windows1251Codec().encode(text));

/// KOI8-R.
Uint8List koi8rBytes(String text) =>
    Uint8List.fromList(const Koi8rCodec().encode(text));
