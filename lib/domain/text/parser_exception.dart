/// Ошибки парсинга файлов (SPEC A8.3).
///
/// Наружу (в UI) попадает только код, который маппится в строку ARB; [details]
/// предназначены для журналов/тестов и не показываются пользователю.
library;

/// Коды ошибок парсинга файла.
enum ParserErrorCode {
  /// Формат не поддерживается (неизвестное расширение, `.xls`).
  unsupportedFormat,

  /// Старый бинарный Word (`.doc`): читать нечем, просим пересохранить в DOCX.
  ///
  /// TASK 04: приложение раньше показывало общее «формат не поддерживается»
  /// для любого неподдержанного файла. Пользователю нужен конкретный шаг —
  /// «Сохраните файл как .docx».
  docFormatNotSupported,

  /// Старый бинарный PowerPoint (`.ppt`): просим пересохранить в PPTX.
  pptFormatNotSupported,

  /// Файл больше лимита SPEC A8.3 (25 МБ).
  fileTooLarge,

  /// Нет доступа к выбранному файлу: URI провайдера не читается, локальной
  /// копии нет (TASK 04, Android `content://`).
  fileAccessDenied,

  /// Не удалось прочитать файл: битый, не соответствует формату.
  unreadableFile,

  /// PDF повреждён: PDFium не смог открыть документ (TASK 04).
  corruptFile,

  /// PDF защищён паролем: без него текстовый слой недоступен (TASK 04).
  passwordProtected,

  /// PDF без текстового слоя (скан).
  scannedPdf,

  /// В документе нет извлекаемого текста.
  emptyText,

  /// Текстовый слой PDF нечитаем: символы замены/битая кодировка
  /// (итерация 7.10, ADR-024).
  garbledText,
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
