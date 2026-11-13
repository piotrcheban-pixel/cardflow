/// Ошибки парсинга файлов (SPEC A8.3).
///
/// Наружу (в UI) попадает только код, который маппится в строку ARB; [details]
/// предназначены для журналов/тестов и не показываются пользователю.
library;

/// Коды ошибок парсинга файла.
enum ParserErrorCode {
  /// Формат не поддерживается (`.doc`, `.xls`, неизвестное расширение).
  unsupportedFormat,

  /// Файл больше лимита SPEC A8.3 (25 МБ).
  fileTooLarge,

  /// Не удалось прочитать файл: битый, запароленный, не соответствует формату.
  unreadableFile,

  /// PDF без текстового слоя (скан).
  scannedPdf,

  /// В документе нет извлекаемого текста.
  emptyText,
}

/// Исключение парсера документов.
class ParserException implements Exception {
  /// Создаёт исключение с кодом [code].
  const ParserException(this.code, {this.details});

  /// Код ошибки для маппинга в ARB.
  final ParserErrorCode code;

  /// Диагностическая информация (не показывается пользователю).
  final String? details;

  @override
  String toString() =>
      'ParserException(${code.name}${details == null ? '' : ': $details'})';
}
