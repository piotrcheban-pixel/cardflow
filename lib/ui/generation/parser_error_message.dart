import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Человекочитаемое сообщение для кода ошибки парсинга файла (SPEC A8.3).
///
/// Пользователю показываются только строки из ARB; `ParserException.details`
/// и сырые исключения не выводятся. Функция чистая — покрывается unit-тестом.
String parserErrorCodeMessage(AppLocalizations l10n, ParserErrorCode code) {
  return switch (code) {
    ParserErrorCode.unsupportedFormat => l10n.parserErrorUnsupportedFormat,
    ParserErrorCode.fileTooLarge => l10n.parserErrorFileTooLarge,
    ParserErrorCode.unreadableFile => l10n.parserErrorUnreadableFile,
    ParserErrorCode.scannedPdf => l10n.parserErrorScannedPdf,
    ParserErrorCode.emptyText => l10n.parserErrorEmptyText,
    ParserErrorCode.garbledText => l10n.parserErrorGarbledText,
  };
}

/// Сообщение для произвольной ошибки парсинга.
///
/// [ParserException] маппится по коду; всё остальное — общая строка из ARB,
/// без текста исключения.
String parserErrorMessage(AppLocalizations l10n, Object error) {
  if (error is ParserException) {
    return parserErrorCodeMessage(l10n, error.code);
  }
  return l10n.parserErrorUnreadableFile;
}
