import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:enough_convert/enough_convert.dart';
import 'package:image/image.dart' as image;

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

/// RTF-представление текста в KOI8-R через `\'hh`.
String rtfEscapedKoi8r(String text) {
  final List<int> bytes = const Koi8rCodec().encode(text);
  return bytes
      .map((int byte) => "\\'${byte.toRadixString(16).padLeft(2, '0')}")
      .join();
}

/// Абзац DOCX с таб-стопами в `w:pPr` (разметка не должна попадать в текст).
String docxParagraphWithTabStops(String text, {int position = 720}) =>
    '<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="$position"/>'
    '</w:tabs></w:pPr><w:r><w:t xml:space="preserve">'
    '${xmlEscape(text)}</w:t></w:r></w:p>';

/// Блок content control (`w:sdt`) с абзацами.
String docxSdt(List<String> paragraphs) =>
    '<w:sdt><w:sdtPr/><w:sdtContent>'
    '${paragraphs.map((String p) => docxParagraph(p)).join()}'
    '</w:sdtContent></w:sdt>';

/// Блок `w:customXml` с абзацами.
String docxCustomXml(List<String> paragraphs) =>
    '<w:customXml w:element="item">'
    '${paragraphs.map((String p) => docxParagraph(p)).join()}'
    '</w:customXml>';

/// Собирает ODT с произвольным XML внутри `office:text`.
Uint8List buildOdtRaw({required String bodyXml}) => zipFixture(<String, String>{
  'mimetype': 'application/vnd.oasis.opendocument.text',
  'content.xml':
      '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<office:document-content
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:body><office:text>$bodyXml</office:text></office:body>
</office:document-content>''',
});

/// Оглавление ODT: `text:table-of-content` → `text:index-body`.
String odtTableOfContent(List<String> entries) =>
    '<text:table-of-content><text:index-body>'
    '${entries.map((String entry) => '<text:p>${xmlEscape(entry)}</text:p>').join()}'
    '</text:index-body></text:table-of-content>';

/// Примечание рецензента ODT (`office:annotation`).
String odtAnnotation(String text) =>
    '<office:annotation><text:p>${xmlEscape(text)}</text:p></office:annotation>';

/// Ячейка XLSX с формулой без кэшированного значения.
String xlsxFormulaWithoutCache(String reference, String formula) =>
    '<c r="$reference"><f>${xmlEscape(formula)}</f></c>';

/// PDF из нескольких страниц; пустая строка — страница без текстового слоя.
Uint8List buildPdfPages(List<String> pageTexts) {
  final int pageCount = pageTexts.length;
  final int fontNumber = 3 + 2 * pageCount;
  final StringBuffer buffer = StringBuffer('%PDF-1.4\n');
  final List<int> offsets = <int>[];

  final List<String> kids = <String>[
    for (int i = 0; i < pageCount; i++) '${3 + 2 * i} 0 R',
  ];
  final List<String> objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${kids.join(' ')}] /Count $pageCount >>',
    for (int i = 0; i < pageCount; i++) ...<String>[
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Contents ${4 + 2 * i} 0 R '
          '/Resources << /Font << /F1 $fontNumber 0 R >> >> >>',
      if (pageTexts[i].isEmpty)
        '<< /Length 0 >>\nstream\n\nendstream'
      else
        () {
          final String content =
              'BT /F1 24 Tf 72 720 Td (${pageTexts[i]}) Tj ET';
          return '<< /Length ${content.length} >>\n'
              'stream\n$content\nendstream';
        }(),
    ],
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

// --- PDF с Type0/Identity-H и заданным ToUnicode (итерация 7.10, ADR-024) ---

/// PDF с Type0-шрифтом (`Identity-H`) и ToUnicode, который отображает CIDs на
/// заданные 16-битные code units.
///
/// Нужен, чтобы программно получить «битый» текстовый слой: PDFium отдаёт из
/// такого PDF ровно то, что записано в `beginbfchar` — например, U+FFFD или
/// одиночные суррогаты (`D800`), которые ломают запрос к API провайдера.
Uint8List buildType0UnicodePdf(List<String> unicodeTargets) {
  final StringBuffer cmap = StringBuffer()
    ..writeln('/CIDInit /ProcSet findresource begin')
    ..writeln('12 dict begin')
    ..writeln('begincmap')
    ..writeln(
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def',
    )
    ..writeln('/CMapName /Adobe-Identity-UCS def')
    ..writeln('/CMapType 2 def')
    ..writeln('1 begincodespacerange')
    ..writeln('<0000> <FFFF>')
    ..writeln('endcodespacerange')
    ..writeln('${unicodeTargets.length} beginbfchar');
  for (int i = 0; i < unicodeTargets.length; i++) {
    final String cid = (i + 1).toRadixString(16).padLeft(4, '0');
    cmap.writeln('<$cid> <${unicodeTargets[i]}>');
  }
  cmap
    ..writeln('endbfchar')
    ..writeln('endcmap')
    ..writeln('CMapName currentdict /CMap defineresource pop')
    ..writeln('end')
    ..writeln('end');
  final String cmapText = cmap.toString();

  final String hex = <String>[
    for (int i = 0; i < unicodeTargets.length; i++)
      (i + 1).toRadixString(16).padLeft(4, '0'),
  ].join();
  final String content = 'BT /F1 24 Tf 72 720 Td <$hex> Tj ET';

  final StringBuffer buffer = StringBuffer('%PDF-1.4\n');
  final List<int> offsets = <int>[];
  final List<String> objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type0 /BaseFont /Dummy /Encoding /Identity-H '
        '/DescendantFonts [6 0 R] /ToUnicode 7 0 R >>',
    '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Dummy '
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> '
        '/FontDescriptor 8 0 R /DW 1000 >>',
    '<< /Length ${cmapText.length} >>\nstream\n$cmapText\nendstream',
    '<< /Type /FontDescriptor /FontName /Dummy /Flags 4 '
        '/FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 '
        '/CapHeight 700 /StemV 80 >>',
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

/// PDF, текстовый слой которого целиком состоит из символов замены U+FFFD.
Uint8List buildGarbledPdf({int replacements = 10}) =>
    buildType0UnicodePdf(List<String>.filled(replacements, 'FFFD'));

// --- Зашифрованный PDF (стандартный security handler V1/R2, RC4 40 бит) ---

/// Стандартный padding-пароль PDF (PDF 1.7, Algorithm 2).
const List<int> _pdfPasswordPadding = <int>[
  0x28,
  0xBF,
  0x4E,
  0x5E,
  0x4E,
  0x75,
  0x8A,
  0x41,
  0x64,
  0x00,
  0x4E,
  0x56,
  0xFF,
  0xFA,
  0x01,
  0x08,
  0x2E,
  0x2E,
  0x00,
  0xB6,
  0xD0,
  0x68,
  0x3E,
  0x80,
  0x2F,
  0x0C,
  0xA9,
  0xFE,
  0x64,
  0x53,
  0x69,
  0x7A,
];

List<int> _padPdfPassword(String password) {
  final List<int> bytes = <int>[
    ...latin1.encode(password),
    ..._pdfPasswordPadding,
  ];
  return bytes.take(32).toList();
}

List<int> _md5Bytes(List<int> data) => crypto.md5.convert(data).bytes;

List<int> _rc4(List<int> key, List<int> data) {
  final List<int> state = List<int>.generate(256, (int i) => i);
  int j = 0;
  for (int i = 0; i < 256; i++) {
    j = (j + state[i] + key[i % key.length]) & 0xFF;
    final int tmp = state[i];
    state[i] = state[j];
    state[j] = tmp;
  }
  final List<int> output = List<int>.filled(data.length, 0);
  int i = 0;
  j = 0;
  for (int k = 0; k < data.length; k++) {
    i = (i + 1) & 0xFF;
    j = (j + state[i]) & 0xFF;
    final int tmp = state[i];
    state[i] = state[j];
    state[j] = tmp;
    output[k] = data[k] ^ state[(state[i] + state[j]) & 0xFF];
  }
  return output;
}

String _hexString(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Минимальный PDF, зашифрованный паролем (открытие без пароля → ошибка).
///
/// Считает `/O` и `/U` по Algorithm 2/3 PDF для пользовательского пароля
/// [userPassword]; [ownerPassword] — пароль владельца. Нужен для проверки
/// ветки «запароленный PDF → unreadableFile».
Uint8List buildEncryptedPdf({
  required String userPassword,
  required String ownerPassword,
}) {
  final List<int> userPad = _padPdfPassword(userPassword);
  final List<int> ownerPad = _padPdfPassword(ownerPassword);
  final List<int> ownerKey = _md5Bytes(ownerPad).sublist(0, 5);
  final List<int> o = _rc4(ownerKey, userPad);
  final List<int> fileId = List<int>.generate(
    16,
    (int i) => (i * 37 + 11) & 0xFF,
  );
  const int permissions = -4;
  final List<int> permissionsLe = <int>[
    permissions & 0xFF,
    (permissions >> 8) & 0xFF,
    (permissions >> 16) & 0xFF,
    (permissions >> 24) & 0xFF,
  ];
  final List<int> key = _md5Bytes(<int>[
    ...userPad,
    ...o,
    ...permissionsLe,
    ...fileId,
  ]).sublist(0, 5);
  final List<int> u = _rc4(key, _pdfPasswordPadding);

  final StringBuffer buffer = StringBuffer('%PDF-1.4\n');
  final List<int> offsets = <int>[];
  final List<String> objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R >>',
    '<< /Length 0 >>\nstream\n\nendstream',
    '<< /Filter /Standard /V 1 /R 2 /Length 40 '
        '/O <${_hexString(o)}> /U <${_hexString(u)}> /P $permissions >>',
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
  final String fileIdHex = _hexString(fileId);
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R '
    '/Encrypt 5 0 R /ID [<$fileIdHex> <$fileIdHex>] >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// Собирает ZIP из бинарных записей (изображения в фикстурах документов).
Uint8List zipFixtureBytes(Map<String, List<int>> files) {
  final Archive archive = Archive();
  files.forEach((String name, List<int> content) {
    archive.addFile(ArchiveFile(name, content.length, content));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// PNG-фикстура с шумом: больше порога фильтра и по байтам, и по сторонам.
Uint8List pngFixture({int width = 200, int height = 150, int seed = 7}) {
  final image.Image picture = image.Image(width: width, height: height);
  var state = seed;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      final int r = state & 0xFF;
      final int g = (state >> 8) & 0xFF;
      final int b = (state >> 16) & 0xFF;
      picture.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(image.encodePng(picture));
}

/// Абзац DOCX с изображением-связью (`r:embed`).
String docxParagraphWithImage(String relationshipId, {String text = ''}) {
  final String run = text.isEmpty
      ? ''
      : '<w:r><w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r>';
  return '<w:p>$run<w:r><w:drawing>'
      '<a:blip r:embed="$relationshipId"/>'
      '</w:drawing></w:r></w:p>';
}

/// DOCX с изображением: абзацы + рисунок + связи + запись media.
Uint8List buildDocxWithImage({
  required List<String> paragraphs,
  required List<int> imageBytes,
  String entryName = 'word/media/image1.png',
  String relationshipId = 'rId5',
  String mediaTarget = 'media/image1.png',
  String? caption,
}) {
  final StringBuffer body = StringBuffer();
  for (final String paragraph in paragraphs) {
    body.write(docxParagraph(paragraph));
  }
  body.write(docxParagraphWithImage(relationshipId));
  if (caption != null) body.write(docxParagraph(caption));
  final String documentXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:body>$body</w:body></w:document>';
  return zipFixtureBytes(<String, List<int>>{
    '[Content_Types].xml': utf8.encode(_contentTypesDocx),
    '_rels/.rels': utf8.encode(_relsDocx),
    'word/document.xml': utf8.encode(documentXml),
    'word/_rels/document.xml.rels': utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="$relationshipId" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="$mediaTarget"/>'
      '</Relationships>',
    ),
    entryName: imageBytes,
  });
}

/// XML слайда PPTX с изображением-связью.
String pptxSlideXmlWithImage(List<String> paragraphs, String relationshipId) {
  final String content = paragraphs
      .map(
        (String paragraph) =>
            '<a:p><a:r><a:t>${xmlEscape(paragraph)}</a:t></a:r></a:p>',
      )
      .join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<p:cSld><p:spTree>'
      '<p:pic><p:blipFill><a:blip r:embed="$relationshipId"/></p:blipFill></p:pic>'
      '<p:sp><p:txBody>$content</p:txBody></p:sp>'
      '</p:spTree></p:cSld></p:sld>';
}

/// PPTX, где первый слайд содержит изображение из `ppt/media`.
Uint8List buildPptxWithImage({
  required List<List<String>> slideTexts,
  required List<int> imageBytes,
  String relationshipId = 'rId7',
  String entryName = 'ppt/media/image1.png',
}) {
  final Map<String, List<int>> files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '</Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="ppt/presentation.xml"/>'
      '</Relationships>',
    ),
    'ppt/presentation.xml': utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:presentation '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<p:sldIdLst>'
      '${<String>[for (var i = 0; i < slideTexts.length; i++) '<p:sldId id="${256 + i}" r:id="rId${i + 1}"/>'].join()}'
      '</p:sldIdLst></p:presentation>',
    ),
    'ppt/_rels/presentation.xml.rels': utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${<String>[for (var i = 0; i < slideTexts.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>'].join()}'
      '</Relationships>',
    ),
    entryName: imageBytes,
  };
  for (var i = 0; i < slideTexts.length; i++) {
    if (i == 0) {
      files['ppt/slides/slide1.xml'] = utf8.encode(
        pptxSlideXmlWithImage(slideTexts[i], relationshipId),
      );
      files['ppt/slides/_rels/slide1.xml.rels'] = utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="$relationshipId" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="../media/image1.png"/>'
        '</Relationships>',
      );
    } else {
      files['ppt/slides/slide${i + 1}.xml'] = utf8.encode(
        pptxSlideXml(slideTexts[i]),
      );
    }
  }
  return zipFixtureBytes(files);
}

/// ODT с изображением из `Pictures/` и подписью.
Uint8List buildOdtWithImage({
  required List<({String text, bool heading})> blocks,
  required List<int> imageBytes,
  String entryName = 'Pictures/image1.png',
  String? caption,
}) {
  final StringBuffer content = StringBuffer();
  for (final ({String text, bool heading}) block in blocks) {
    content.write(
      block.heading
          ? '<text:h text:outline-level="1">${xmlEscape(block.text)}</text:h>'
          : '<text:p>${xmlEscape(block.text)}</text:p>',
    );
  }
  content.write(
    '<text:p><draw:frame><draw:image xlink:href="$entryName"/></draw:frame></text:p>',
  );
  if (caption != null) content.write('<text:p>${xmlEscape(caption)}</text:p>');
  return zipFixtureBytes(<String, List<int>>{
    'mimetype': utf8.encode('application/vnd.oasis.opendocument.text'),
    'content.xml': utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<office:document-content '
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
      'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
      'xmlns:xlink="http://www.w3.org/1999/xlink">'
      '<office:body><office:text>$content</office:text></office:body>'
      '</office:document-content>',
    ),
    entryName: imageBytes,
  });
}

/// JPEG-фикстура минимального размера: только заголовок SOF0 + паддинг.
Uint8List jpegFixture({int width = 200, int height = 100, int size = 5000}) {
  final List<int> bytes = <int>[
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x10, // APP0, длина 16
    ...'JFIF'.codeUnits, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01,
    0x00, 0x00,
    0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, длина 17, точность 8
    (height >> 8) & 0xFF, height & 0xFF,
    (width >> 8) & 0xFF, width & 0xFF,
    0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    0xFF, 0xD9, // EOI
  ];
  while (bytes.length < size) {
    bytes.add(0x00);
  }
  return Uint8List.fromList(bytes);
}
