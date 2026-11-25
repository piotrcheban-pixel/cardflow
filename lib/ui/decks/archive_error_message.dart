import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Человекочитаемое сообщение для кода ошибки архива (SPEC A6.9).
///
/// Пользователю показываются только строки из ARB; сырые исключения и их
/// `details` не выводятся. Функция чистая — покрывается unit-тестом.
String archiveErrorCodeMessage(AppLocalizations l10n, ArchiveErrorCode code) {
  return switch (code) {
    ArchiveErrorCode.unsupportedVersion => l10n.archiveErrorUnsupportedVersion,
    ArchiveErrorCode.corruptZip => l10n.archiveErrorCorruptZip,
    ArchiveErrorCode.missingEntry => l10n.archiveErrorMissingEntry,
    ArchiveErrorCode.invalidMeta => l10n.archiveErrorInvalidMeta,
    ArchiveErrorCode.invalidCards => l10n.archiveErrorInvalidCards,
    ArchiveErrorCode.tooLarge => l10n.archiveErrorTooLarge,
    ArchiveErrorCode.mediaMissing => l10n.archiveErrorMediaMissing,
    ArchiveErrorCode.deckNotFound => l10n.archiveErrorDeckNotFound,
    ArchiveErrorCode.invalidEntryName => l10n.archiveErrorInvalidEntryName,
    ArchiveErrorCode.writeDenied => l10n.archiveErrorWriteDenied,
  };
}

/// Сообщение для произвольной ошибки импорта/экспорта.
///
/// [ArchiveException] маппится по коду; всё остальное — общая строка из ARB,
/// без текста исключения.
String archiveErrorMessage(AppLocalizations l10n, Object error) {
  if (error is ArchiveException) {
    return archiveErrorCodeMessage(l10n, error.code);
  }
  return l10n.archiveErrorUnknown;
}
