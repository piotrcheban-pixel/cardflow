// Маппинг строки `cards` ↔ доменная сущность `Card` (SPEC A5).
//
// Вынесено из `drift_card_repository.dart`, чтобы CRUD карточек и запись
// повторений (`drift_review_repository.dart`) пользовались одним маппингом:
// поля `fsrs_json`, `due`, `state` не должны разъезжаться между репозиториями.
import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_media_json.dart';

/// Строка `cards` → доменная карточка.
Card cardFromRow(CardRow row) {
  // `media_json` v2: стороны независимы. Legacy-массив не знает стороны:
  // холст occlusion/cloze — стимул вопроса, остальные изображения — сторона
  // ответа (безопасная политика, ADR-042; ответ не раскрывается до переворота).
  final CardMediaSides media = _mediaSidesOf(row);
  return Card(
    id: row.id,
    deckId: row.deckId,
    front: row.front,
    back: row.back,
    hint: row.hint,
    cardType: CardType.fromWire(row.cardType),
    tags: decodeStringList(row.tagsJson),
    questionMediaIds: media.question,
    answerMediaIds: media.answer,
    latex: row.latex,
    occlusionJson: row.occlusionJson,
    sourceDocId: row.sourceDocId,
    sourceExcerpt: row.sourceExcerpt,
    state: CardState.fromWire(row.state),
    fsrsJson: row.fsrsJson,
    due: row.due == null ? null : fromEpochMs(row.due!),
    suspended: row.suspended != 0,
    buriedUntil: row.buriedUntil == null ? null : fromEpochMs(row.buriedUntil!),
    flagged: row.flagged != 0,
    siblingId: row.siblingId,
    contentHash: row.contentHash,
    createdAt: fromEpochMs(row.createdAt),
    updatedAt: fromEpochMs(row.updatedAt),
  );
}

/// Стороны `media_json` строки: v2 как есть, legacy — по безопасной политике.
CardMediaSides _mediaSidesOf(CardRow row) {
  final String raw = row.mediaJson.trimLeft();
  if (!raw.startsWith('[')) return CardMediaSides.decode(row.mediaJson);
  final CardMediaSides legacy = CardMediaSides.decode(row.mediaJson);
  final bool stimulus =
      row.occlusionJson != null || row.cardType == CardType.cloze.wireName;
  return CardMediaSides.fromLegacy(legacy.question, stimulus: stimulus);
}

/// Доменная карточка → companion для вставки/обновления.
CardsCompanion cardToCompanion(Card card) {
  return CardsCompanion(
    id: Value<String>(card.id),
    deckId: Value<String>(card.deckId),
    front: Value<String>(card.front),
    back: Value<String>(card.back),
    hint: Value<String?>(card.hint),
    cardType: Value<String>(card.cardType.wireName),
    tagsJson: Value<String>(encodeStringList(card.tags)),
    mediaJson: Value<String>(
      CardMediaSides(
        question: card.questionMediaIds,
        answer: card.answerMediaIds,
      ).encode(),
    ),
    latex: Value<String?>(card.latex),
    occlusionJson: Value<String?>(card.occlusionJson),
    sourceDocId: Value<String?>(card.sourceDocId),
    sourceExcerpt: Value<String?>(card.sourceExcerpt),
    state: Value<String>(card.state.wireName),
    fsrsJson: Value<String?>(card.fsrsJson),
    due: Value<int?>(card.due == null ? null : toEpochMs(card.due!)),
    suspended: Value<int>(card.suspended ? 1 : 0),
    buriedUntil: Value<int?>(
      card.buriedUntil == null ? null : toEpochMs(card.buriedUntil!),
    ),
    flagged: Value<int>(card.flagged ? 1 : 0),
    siblingId: Value<String?>(card.siblingId),
    contentHash: Value<String?>(card.contentHash),
    createdAt: Value<int>(toEpochMs(card.createdAt)),
    updatedAt: Value<int>(toEpochMs(card.updatedAt)),
  );
}

/// JSON-массив строк (`tags_json`/`media_json` в SPEC A5).
List<String> decodeStringList(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    throw FormatException('Ожидался JSON-массив строк, получено: $raw');
  }
  return decoded
      .map((value) {
        if (value is! String) {
          throw FormatException('Элемент JSON-массива не строка: $raw');
        }
        return value;
      })
      .toList(growable: false);
}

/// Список строк → JSON-массив (для `tags_json`/`media_json`).
String encodeStringList(List<String> values) =>
    jsonEncode(values.map((String value) => value).toList(growable: false));
