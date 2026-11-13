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
  throw UnimplementedError('documentFormatFromFileName');
}

/// Проверяет сигнатуру (магические байты) файла для формата [format].
///
/// Бросает [ParserException] с кодом [ParserErrorCode.unreadableFile], если
/// содержимое не соответствует формату. Для TXT/MD (и неподдерживаемых
/// `.doc`/`.xls`) проверка не выполняется.
void verifyDocumentSignature(DocumentFormat format, List<int> bytes) {
  throw UnimplementedError('verifyDocumentSignature');
}
