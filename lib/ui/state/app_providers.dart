import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/decks/drift_deck_repository.dart';
import 'package:cardflow/data/transfer/drift_deck_transfer_service.dart';
import 'package:cardflow/data/transfer/file_picker_gateway.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/data/transfer/zip_deck_archive_codec.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/decks/deck_repository.dart';
import 'package:cardflow/domain/transfer/archive_codec.dart';
import 'package:cardflow/domain/transfer/deck_transfer_service.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';

/// Провайдеры приложения (ADR-002: Riverpod 3 без кодогенерации).
///
/// Здесь собирается граф зависимостей data-слоя. Платформенные вещи,
/// которые нельзя создать без `WidgetsFlutterBinding` (`AppDatabase`,
/// `MediaStore`), передаются через `ProviderScope(overrides: …)` в `main.dart`.
/// В widget-тестах провайдеры подменяются фейками.

/// БД приложения; в `main.dart` переопределяется реальным открытым экземпляром.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider должен быть переопределён');
});

/// Репозиторий колод.
final deckRepositoryProvider = Provider<DeckRepository>((ref) {
  return DriftDeckRepository(ref.watch(appDatabaseProvider));
});

/// Репозиторий карточек.
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  return DriftCardRepository(ref.watch(appDatabaseProvider));
});

/// Кодек `.zip`-архива колоды.
final deckArchiveCodecProvider = Provider<DeckArchiveCodec>((ref) {
  return const ZipDeckArchiveCodec();
});

/// Хранилище медиа; в `main.dart` переопределяется каталогом приложения.
final mediaStoreProvider = Provider<MediaStore>((ref) {
  throw UnimplementedError('mediaStoreProvider должен быть переопределён');
});

/// Сервис импорта/экспорта колод.
final deckTransferServiceProvider = Provider<DeckTransferService>((ref) {
  return DriftDeckTransferService(
    appDatabase: ref.watch(appDatabaseProvider),
    codec: ref.watch(deckArchiveCodecProvider),
    mediaStore: ref.watch(mediaStoreProvider),
  );
});

/// Файловый шлюз (системный пикер/сохранение `.zip`).
final fileGatewayProvider = Provider<FileGateway>((ref) {
  return FilePickerGateway();
});
