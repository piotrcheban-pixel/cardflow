import 'dart:typed_data';

import 'package:cardflow/domain/transfer/deck_archive.dart';

/// Кодек публичного `.zip`-формата колоды (SPEC 0.4.4, ADR-006).
///
/// Реализация — `ZipDeckArchiveCodec` в `lib/data/transfer/`; интерфейс
/// позволяет подменить кодек в тестах сервиса и не тянет IO в domain.
abstract interface class DeckArchiveCodec {
  /// Собирает zip-байты из разобранного архива.
  ///
  /// Бросает [ArchiveException] (`mediaMissing`, если байты медиа отсутствуют).
  Uint8List encode(DeckArchive archive);

  /// Разбирает и валидирует zip-байты.
  ///
  /// Бросает [ArchiveException] (`corruptZip`, `missingEntry`,
  /// `unsupportedVersion`, `invalidMeta`, `invalidCards`, `tooLarge`,
  /// `invalidEntryName`).
  DeckArchive decode(Uint8List zipBytes);
}
