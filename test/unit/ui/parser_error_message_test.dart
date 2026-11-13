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
      ParserErrorCode.fileTooLarge: l10n.parserErrorFileTooLarge,
      ParserErrorCode.unreadableFile: l10n.parserErrorUnreadableFile,
      ParserErrorCode.scannedPdf: l10n.parserErrorScannedPdf,
      ParserErrorCode.emptyText: l10n.parserErrorEmptyText,
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
