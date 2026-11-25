import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/l10n/app_localizations_ru.dart';
import 'package:cardflow/ui/decks/archive_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// Красная фаза: маппинг кодов ошибок архива в строки ARB (SPEC A6.9).
///
/// Пользователю не должны утекать сырые исключения и `ArchiveException.details`
/// — только человекочитаемые сообщения из `app_ru.arb`.
void main() {
  final AppLocalizations l10n = AppLocalizationsRu();

  group('archiveErrorCodeMessage: каждый код → отдельная строка ARB', () {
    test('все коды ArchiveErrorCode покрыты и различаются', () {
      final Map<ArchiveErrorCode, String> expected = <ArchiveErrorCode, String>{
        ArchiveErrorCode.unsupportedVersion:
            l10n.archiveErrorUnsupportedVersion,
        ArchiveErrorCode.corruptZip: l10n.archiveErrorCorruptZip,
        ArchiveErrorCode.missingEntry: l10n.archiveErrorMissingEntry,
        ArchiveErrorCode.invalidMeta: l10n.archiveErrorInvalidMeta,
        ArchiveErrorCode.invalidCards: l10n.archiveErrorInvalidCards,
        ArchiveErrorCode.tooLarge: l10n.archiveErrorTooLarge,
        ArchiveErrorCode.mediaMissing: l10n.archiveErrorMediaMissing,
        ArchiveErrorCode.deckNotFound: l10n.archiveErrorDeckNotFound,
        ArchiveErrorCode.invalidEntryName: l10n.archiveErrorInvalidEntryName,
        ArchiveErrorCode.writeDenied: l10n.archiveErrorWriteDenied,
      };

      expect(
        expected.keys.toSet(),
        ArchiveErrorCode.values.toSet(),
        reason: 'Не все коды ArchiveErrorCode имеют сообщение',
      );

      expected.forEach((ArchiveErrorCode code, String message) {
        expect(
          archiveErrorCodeMessage(l10n, code),
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
        hasLength(ArchiveErrorCode.values.length),
        reason: 'У разных кодов должна быть разная строка ARB',
      );
    });

    test('ArchiveException маппится по коду, details не утекают', () {
      for (final ArchiveErrorCode code in ArchiveErrorCode.values) {
        final String message = archiveErrorMessage(
          l10n,
          ArchiveException(code, details: 'сырой стектрейс: boom'),
        );
        expect(
          message,
          archiveErrorCodeMessage(l10n, code),
          reason:
              'ArchiveException(${code.name}) должен дать строку своего кода',
        );
        expect(
          message,
          isNot(contains('сырой стектрейс')),
          reason: 'details не должны попадать в сообщение пользователю',
        );
        expect(
          message,
          isNot(contains(code.name)),
          reason: 'машинный код не должен попадать в сообщение пользователю',
        );
      }
    });

    test('неизвестная ошибка → общая строка без текста исключения', () {
      final String message = archiveErrorMessage(
        l10n,
        StateError('internal boom: /home/user/secret'),
      );
      expect(message, l10n.archiveErrorUnknown);
      expect(message, isNot(contains('internal boom')));
      expect(message, isNot(contains('/home/user/secret')));
    });

    test('обычная ошибка импорта не раскрывает сообщение', () {
      final String message = archiveErrorMessage(
        l10n,
        const FormatException('bad json at offset 42'),
      );
      expect(message, l10n.archiveErrorUnknown);
      expect(message, isNot(contains('bad json')));
      expect(message, isNot(contains('42')));
    });
  });
}
