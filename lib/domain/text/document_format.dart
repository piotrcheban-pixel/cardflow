import 'dart:convert';

import 'package:cardflow/domain/text/parser_exception.dart';

/// Форматы документов, которые принимает генерация карточек (SPEC A8.3).
///
/// `.doc`/`.ppt`/`.xls` присутствуют в перечислении, потому что пользователь
/// может их прикрепить; нативный парсер для них не поддерживается (ADR-003,
/// ADR-049). В экосистеме Dart нет надёжного парсера CFB (Compound File
/// Binary), поэтому приложение не пытается читать старые бинарные форматы, а
/// просит пересохранить файл в OOXML.
enum DocumentFormat {
  pdf('pdf'),
  docx('docx'),
  xlsx('xlsx'),
  pptx('pptx'),
  odt('odt'),
  txt('txt'),
  md('md'),
  rtf('rtf'),
  doc('doc'),
  ppt('ppt'),
  xls('xls');

  const DocumentFormat(this.extension);

  /// Расширение файла без точки (нижний регистр).
  final String extension;

  /// Поддерживается ли нативный парсинг этого формата (ADR-003, ADR-049).
  bool get isSupportedForParsing => this != doc && this != ppt && this != xls;

  /// Старый бинарный формат Word/PowerPoint (CFB): нужен отдельный совет.
  bool get isLegacyBinary => this == doc || this == ppt;
}

/// Определяет формат документа по расширению имени файла (регистр не важен).
///
/// Возвращает `null`, если расширение не входит в набор SPEC A8.3.
DocumentFormat? documentFormatFromFileName(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) {
    return null;
  }
  final String extension = fileName.substring(dot + 1).toLowerCase();
  for (final DocumentFormat format in DocumentFormat.values) {
    if (format.extension == extension) {
      return format;
    }
  }
  return null;
}

const List<int> _zipSignature = <int>[0x50, 0x4B, 0x03, 0x04];
const List<int> _pdfSignature = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
const String _rtfSignature = '{\\rtf';

/// Проверяет сигнатуру (магические байты) файла для формата [format].
///
/// Бросает [ParserException] с кодом [ParserErrorCode.unreadableFile], если
/// содержимое не соответствует формату. Для TXT/MD (и неподдерживаемых
/// `.doc`/`.xls`) проверка не выполняется.
void verifyDocumentSignature(DocumentFormat format, List<int> bytes) {
  switch (format) {
    case DocumentFormat.docx:
    case DocumentFormat.xlsx:
    case DocumentFormat.pptx:
    case DocumentFormat.odt:
      if (!_startsWith(bytes, _zipSignature)) {
        throw const ParserException(
          ParserErrorCode.unreadableFile,
          details: 'Файл не является ZIP-контейнером OOXML/ODF',
        );
      }
    case DocumentFormat.pdf:
      if (!_startsWith(bytes, _pdfSignature)) {
        throw const ParserException(
          ParserErrorCode.unreadableFile,
          details: 'Файл не является PDF (нет сигнатуры %PDF-)',
        );
      }
    case DocumentFormat.rtf:
      // RTF-поток может начинаться с пробельных символов до `{\rtf`.
      if (!_startsWithAsciiSkippingWhitespace(bytes, _rtfSignature)) {
        throw const ParserException(
          ParserErrorCode.unreadableFile,
          details: 'Файл не является RTF (нет сигнатуры {\\rtf)',
        );
      }
    case DocumentFormat.txt:
    case DocumentFormat.md:
    case DocumentFormat.doc:
    case DocumentFormat.ppt:
    case DocumentFormat.xls:
      return;
  }
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (int i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

/// Проверка ASCII-сигнатуры с пропуском ведущих пробельных байтов (для RTF).
bool _startsWithAsciiSkippingWhitespace(List<int> bytes, String prefix) {
  int offset = 0;
  while (offset < bytes.length && _isWhitespaceByte(bytes[offset])) {
    offset++;
  }
  final List<int> expected = latin1.encode(prefix);
  if (bytes.length - offset < expected.length) {
    return false;
  }
  for (int i = 0; i < expected.length; i++) {
    if (bytes[offset + i] != expected[i]) {
      return false;
    }
  }
  return true;
}

bool _isWhitespaceByte(int byte) =>
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D;
