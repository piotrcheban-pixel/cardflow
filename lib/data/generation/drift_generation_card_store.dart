/// Импорт сгенерированных карточек в drift-БД (SPEC A8.5 шаги 9–11, ADR-015).
library;

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';

/// Импорт карточек поверх drift-БД.
class DriftGenerationCardStore implements GenerationCardStore {
  /// Создаёт хранилище поверх БД.
  DriftGenerationCardStore(this.database);

  /// БД приложения.
  final AppDatabase database;

  @override
  Future<Set<String>> existingContentHashes(String deckId) {
    throw UnimplementedError('DriftGenerationCardStore.existingContentHashes');
  }

  @override
  Future<GenerationImportResult> importGeneratedCards({
    required String? deckId,
    required String deckName,
    required List<GeneratedCard> cards,
    required String jobId,
    required DateTime now,
  }) {
    throw UnimplementedError('DriftGenerationCardStore.importGeneratedCards');
  }
}
