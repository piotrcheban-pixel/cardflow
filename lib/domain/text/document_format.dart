import 'dart:convert';

import 'package:cardflow/domain/text/parser_exception.dart';

/// Форматы документов, которые принимает генерация карточек (SPEC A8.3).
///
/// `.doc`/`.xls` присутствуют в перечислении, потому что пользователь может их
/// прикрепить; нативный парсер для них не поддерживается (ADR-003).
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
  xls('xls');

  const DocumentFormat(this.extension);

  /// Расширение файла без точки (нижний регистр).
  final String extension;

  /// Поддерживается ли нативный парсинг этого формата (ADR-003).
  bool get isSupportedForParsing => this != doc && this != xls;
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

const List<int> _zipSignature = <int>[0x50, 0x4B];
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
      if (!_startsWith(bytes, _zipSignature) || !_hasZipMarker(bytes)) {
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
      if (!_startsWithAscii(bytes, _rtfSignature)) {
        throw const ParserException(
          ParserErrorCode.unreadableFile,
          details: 'Файл не является RTF (нет сигнатуры {\\rtf)',
        );
      }
    case DocumentFormat.txt:
    case DocumentFormat.md:
    case DocumentFormat.doc:
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

/// Проверяет байты 3–4 ZIP-заголовка (`\x03\x04`, `\x05\x06`, `\x07\x08`).
bool _hasZipMarker(List<int> bytes) {
  if (bytes.length < 4) {
    return false;
  }
  final int marker = bytes[2];
  final int tail = bytes[3];
  return (marker == 0x03 || marker == 0x05 || marker == 0x07) &&
      (tail == 0x04 || tail == 0x06 || tail == 0x08);
}

bool _startsWithAscii(List<int> bytes, String prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  final List<int> expected = latin1.encode(prefix);
  return _startsWith(bytes, expected);
}
