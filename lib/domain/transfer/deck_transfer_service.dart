import 'dart:typed_data';

import 'package:cardflow/domain/transfer/deck_archive.dart';

/// Сервис импорта/экспорта колод `.zip` (SPEC A6.9, ADR-006).
///
/// Реализация — drift-сервис в `lib/data/transfer/`: экспорт читает колоду,
/// карточки и медиа из БД/хранилища, импорт пишет всё одной транзакцией.
abstract interface class DeckTransferService {
  /// Экспортирует колоду [deckId] в zip-байты.
  ///
  /// Бросает [ArchiveException] (`deckNotFound`, `mediaMissing`).
  Future<Uint8List> exportDeckZip(String deckId);

  /// Разбирает и валидирует архив для предпросмотра, не изменяя БД.
  ///
  /// Бросает [ArchiveException].
  Future<ImportPreview> previewImport(Uint8List zipBytes);

  /// Импортирует архив: создаёт новую колоду и карточки одной транзакцией.
  ///
  /// [deckName] переопределяет имя колоды из архива (опционально).
  /// Бросает [ArchiveException].
  Future<ImportResult> importZip(Uint8List zipBytes, {String? deckName});
}
