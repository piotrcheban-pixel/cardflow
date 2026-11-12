import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/decks/deck.dart';

void main() {
  final created = DateTime.utc(2026, 11, 12, 10);
  final updated = DateTime.utc(2026, 11, 12, 11);

  Deck buildDeck() => Deck(
    id: 'deck-1',
    name: 'Испанский',
    settings: const <String, Object?>{'desiredRetention': 0.9},
    createdAt: created,
    updatedAt: updated,
  );

  group('Deck', () {
    test('по умолчанию не архивная', () {
      expect(buildDeck().isArchived, isFalse);
    });

    test('isArchived истинно при archivedAt', () {
      final archived = buildDeck().copyWith(archivedAt: updated);
      expect(archived.isArchived, isTrue);
      expect(archived.archivedAt, updated);
    });

    test('copyWith без archivedAt сохраняет прежнее значение', () {
      final archived = buildDeck().copyWith(archivedAt: updated);
      final renamed = archived.copyWith(name: 'Испанский 2');
      expect(renamed.archivedAt, updated);
      expect(renamed.name, 'Испанский 2');
    });

    test('copyWith(archivedAt: null) снимает архивность', () {
      final archived = buildDeck().copyWith(archivedAt: updated);
      final restored = archived.copyWith(archivedAt: null);
      expect(restored.archivedAt, isNull);
      expect(restored.isArchived, isFalse);
    });

    test('равенство учитывает все поля и вложенные настройки', () {
      expect(buildDeck(), equals(buildDeck()));
      expect(
        buildDeck() ==
            buildDeck().copyWith(
              settings: const <String, Object?>{'desiredRetention': 0.8},
            ),
        isFalse,
      );
      expect(buildDeck().hashCode, equals(buildDeck().hashCode));
    });

    test('toString содержит id и имя', () {
      final text = buildDeck().toString();
      expect(text, contains('deck-1'));
      expect(text, contains('Испанский'));
    });
  });
}
