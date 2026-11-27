import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/l10n/app_localizations_ru.dart';
import 'package:cardflow/ui/generation/parser_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// Красная фаза итерации 3a: коды ошибок парсинга → строки ARB (SPEC A8.3).
///
/// Пользователю не должны утекать сырые исключения и `ParserException.details`
/// — только человекочитаемые сообщения из `app_ru.arb`.
void main() {
  final AppLocalizations l10n = AppLocalizationsRu();

  test('каждый код ParserErrorCode покрыт отдельной непустой строкой ARB', () {
    final Map<ParserErrorCode, String> expected = <ParserErrorCode, String>{
      ParserErrorCode.unsupportedFormat: l10n.parserErrorUnsupportedFormat,
      ParserErrorCode.docFormatNotSupported: l10n.parserErrorDocNotSupported,
      ParserErrorCode.pptFormatNotSupported: l10n.parserErrorPptNotSupported,
      ParserErrorCode.fileTooLarge: l10n.parserErrorFileTooLarge,
      ParserErrorCode.fileAccessDenied: l10n.parserErrorFileAccessDenied,
      ParserErrorCode.unreadableFile: l10n.parserErrorUnreadableFile,
      ParserErrorCode.corruptFile: l10n.parserErrorCorruptFile,
      ParserErrorCode.passwordProtected: l10n.parserErrorPasswordProtected,
      ParserErrorCode.scannedPdf: l10n.parserErrorScannedPdf,
      ParserErrorCode.emptyText: l10n.parserErrorEmptyText,
      ParserErrorCode.garbledText: l10n.parserErrorGarbledText,
    };

    expect(
      expected.keys.toSet(),
      ParserErrorCode.values.toSet(),
      reason: 'Не все коды ParserErrorCode имеют сообщение',
    );

    expected.forEach((ParserErrorCode code, String message) {
      expect(
        parserErrorCodeMessage(l10n, code),
        message,
        reason: 'Неверное сообщение для кода ${code.name}',
      );
      expect(
        message.trim(),
        isNotEmpty,
        reason: 'Пустое сообщение для кода ${code.name}',
      );
    });

    expect(
      expected.values.toSet(),
      hasLength(ParserErrorCode.values.length),
      reason: 'У разных кодов должна быть разная строка ARB',
    );
  });

  test('пустой текст: сообщение говорит о скане и пустой форме', () {
    expect(l10n.parserErrorEmptyText, contains('скан'));
    expect(l10n.parserErrorEmptyText, contains('пустая форма'));
  });

  // Итерация 7.10, ADR-024: битый текстовый слой PDF.
  test('нечитаемый PDF: сообщение говорит о нечитаемом тексте', () {
    expect(l10n.parserErrorGarbledText, contains('PDF'));
    expect(l10n.parserErrorGarbledText, contains('нечитаем'));
  });

  test('ParserException маппится по коду, details не утекают', () {
    for (final ParserErrorCode code in ParserErrorCode.values) {
      final String message = parserErrorMessage(
        l10n,
        ParserException(code, details: 'сырой стектрейс: boom'),
      );
      expect(message, parserErrorCodeMessage(l10n, code));
      expect(message, isNot(contains('boom')));
      expect(message, isNot(contains('ParserException')));
    }
  });

  test(
    'произвольная ошибка → общее сообщение из ARB без текста исключения',
    () {
      final String message = parserErrorMessage(
        l10n,
        StateError('внутренний сбой'),
      );
      expect(message, l10n.parserErrorUnreadableFile);
      expect(message, isNot(contains('внутренний сбой')));
    },
  );
}
