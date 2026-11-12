// Общие помощники тестов data-слоя: прямой посев строк БД.
//
// Файл не является тестом (не заканчивается на `_test.dart`) и подключается
// из тестов schema/deck/card. Посев идёт через сгенерированные drift-компанионы,
// чтобы тестировать репозитории на «боевой» схеме, а не на фейковых строках.
import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';

/// Вставляет строку колоды напрямую в БД.
Future<void> insertDeckRow(
  AppDatabase db, {
  required String id,
  required String name,
  String settingsJson = '{}',
  int? archivedAt,
  required int createdAt,
  required int updatedAt,
}) {
  return db
      .into(db.decks)
      .insert(
        DecksCompanion.insert(
          id: id,
          name: name,
          settingsJson: Value(settingsJson),
          archivedAt: Value(archivedAt),
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
}

/// Вставляет строку карточки напрямую в БД (все поля `cards` SPEC A5).
Future<void> insertCardRow(
  AppDatabase db, {
  required String id,
  required String deckId,
  String front = 'Вопрос',
  String back = 'Ответ',
  String? hint,
  String cardType = 'basic',
  String tagsJson = '[]',
  String mediaJson = '[]',
  String? latex,
  String? occlusionJson,
  String? sourceDocId,
  String? sourceExcerpt,
  String state = 'new',
  String? fsrsJson,
  int? due,
  int suspended = 0,
  int? buriedUntil,
  int flagged = 0,
  String? siblingId,
  String? contentHash,
  int createdAt = 0,
  int updatedAt = 0,
}) {
  return db
      .into(db.cards)
      .insert(
        CardsCompanion.insert(
          id: id,
          deckId: deckId,
          front: front,
          back: back,
          hint: Value(hint),
          cardType: cardType,
          tagsJson: Value(tagsJson),
          mediaJson: Value(mediaJson),
          latex: Value(latex),
          occlusionJson: Value(occlusionJson),
          sourceDocId: Value(sourceDocId),
          sourceExcerpt: Value(sourceExcerpt),
          state: state,
          fsrsJson: Value(fsrsJson),
          due: Value(due),
          suspended: Value(suspended),
          buriedUntil: Value(buriedUntil),
          flagged: Value(flagged),
          siblingId: Value(siblingId),
          contentHash: Value(contentHash),
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
}
