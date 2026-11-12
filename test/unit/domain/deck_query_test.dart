import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/text/normalization.dart';

void main() {
  group('normalizeForComparison', () {
    test('нижний регистр, ё→е, пунктуация и пробелы', () {
      expect(normalizeForComparison('  Ёжик,  В Тумане! '), 'ежик в тумане');
      expect(normalizeForComparison('ЧТО-ТО...'), 'что то');
      expect(normalizeForComparison(''), isEmpty);
    });
  });

  group('DeckQuery', () {
    test('по умолчанию: пустой поиск, фильтр all, без архива', () {
      const query = DeckQuery();
      expect(query.search, isEmpty);
      expect(query.filter, DeckFilter.all);
      expect(query.includeArchived, isFalse);
    });

    test('normalizedSearch нормализует поиск', () {
      const query = DeckQuery(search: 'ИСПАНСКИЙ ЁЖ');
      expect(query.normalizedSearch, 'испанский еж');
      expect(query.isEmptySearch, isFalse);
      expect(const DeckQuery().isEmptySearch, isTrue);
    });

    test('copyWith меняет только указанные поля', () {
      const query = DeckQuery(search: 'a', filter: DeckFilter.due);
      final changed = query.copyWith(filter: DeckFilter.withNewCards);
      expect(changed.search, 'a');
      expect(changed.filter, DeckFilter.withNewCards);
      expect(changed.includeArchived, isFalse);
    });

    test('равенство и hashCode', () {
      expect(
        const DeckQuery(search: 'x'),
        equals(const DeckQuery(search: 'x')),
      );
      expect(
        const DeckQuery(search: 'x') == const DeckQuery(search: 'y'),
        isFalse,
      );
      expect(const DeckQuery().hashCode, const DeckQuery().hashCode);
    });

    test('toString содержит параметры', () {
      expect(const DeckQuery(search: 'x').toString(), contains('x'));
    });
  });
}
