/// Импорт сгенерированных карточек в колоду (SPEC A8.5 шаги 9–11, ADR-015).
///
/// Домен не зависит от БД: реализация — `lib/data/generation/`.
library;

import 'package:cardflow/domain/generation/generated_card.dart';

/// Результат импорта карточек.
class GenerationImportResult {
  /// Создаёт результат.
  const GenerationImportResult({
    required this.deckId,
    required this.importedCards,
    required this.skippedDuplicates,
  });

  /// Колода, куда импортированы карточки.
  final String deckId;

  /// Сколько логических карточек импортировано.
  final int importedCards;

  /// Сколько дублей отсеяно внутри транзакции.
  final int skippedDuplicates;
}

/// Хранилище-импортёр сгенерированных карточек.
abstract interface class GenerationCardStore {
  /// Хеши `front + "\\u0000" + back` карточек колоды (для дедупликации).
  Future<Set<String>> existingContentHashes(String deckId);

  /// Импортирует [cards] одной транзакцией: создаёт колоду [deckName] или
  /// добавляет в [deckId]; повторно дедуплицирует и обновляет задание [jobId].
  Future<GenerationImportResult> importGeneratedCards({
    required String? deckId,
    required String deckName,
    required List<GeneratedCard> cards,
    required String jobId,
    required DateTime now,
  });
}
