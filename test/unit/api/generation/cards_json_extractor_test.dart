import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/cards_json_extractor.dart';
import 'package:cardflow/domain/generation/generation_error.dart';

/// Разбор текста ответа модели (ADR-021): чистый JSON, markdown-ограждение,
/// пояснения вокруг JSON и BOM.
void main() {
  const extractor = CardsJsonExtractor();

  Matcher throwsInvalidResponse() => throwsA(
    isA<GenerationException>().having(
      (exception) => exception.code,
      'code',
      GenerationErrorCode.invalidResponse,
    ),
  );

  group('чистый JSON', () {
    test('объект декодируется', () {
      final decoded = extractor.decode('{"cards":[]}', tolerant: false);
      expect(decoded, <String, Object?>{'cards': <Object?>[]});
    });

    test('пустые карточки и пробелы вокруг — валидный разбор', () {
      final decoded = extractor.decode(
        '  \n {"cards": [ ]} \n ',
        tolerant: false,
      );
      expect(decoded, <String, Object?>{'cards': <Object?>[]});
    });

    test('вложенные объекты и скобки в строках сохраняются', () {
      const raw = '{"cards":[{"front":"{x}","back":"y"}]}';
      final decoded = extractor.decode(raw, tolerant: false);
      final cards = (decoded! as Map<String, Object?>)['cards']! as List;
      expect(cards, hasLength(1));
      expect((cards.first as Map<String, Object?>)['front'], '{x}');
    });

    test('невалидный JSON → invalidResponse без текста ответа', () {
      expect(
        () => extractor.decode('{"cards":[', tolerant: false),
        throwsInvalidResponse(),
      );
      expect(
        () => extractor.decode('совсем не JSON', tolerant: true),
        throwsInvalidResponse(),
      );
    });
  });

  group('markdown-ограждение (кейс владельца, owner note)', () {
    test('```json { "cards": [] } ``` разбирается', () {
      final decoded = extractor.decode(
        '```json\n{ "cards": [] }\n```',
        tolerant: true,
      );
      expect(decoded, <String, Object?>{'cards': <Object?>[]});
    });

    test('ограждение без указания языка разбирается', () {
      final decoded = extractor.decode(
        '```\n{"cards":[{"front":"Вопрос","back":"Ответ"}]}\n```',
        tolerant: true,
      );
      final cards = (decoded! as Map<String, Object?>)['cards']! as List;
      expect(cards, hasLength(1));
    });

    test('язык fences в верхнем регистре разбирается', () {
      final decoded = extractor.decode(
        '```JSON\n{"cards":[]}\n```',
        tolerant: true,
      );
      expect(decoded, <String, Object?>{'cards': <Object?>[]});
    });

    test('пояснение до и после JSON отбрасывается', () {
      final decoded = extractor.decode(
        'Вот карточки:\n```json\n{"cards":[]}\n```\nГотово.',
        tolerant: true,
      );
      expect(decoded, <String, Object?>{'cards': <Object?>[]});
    });

    test('strict-протоколы (tolerant=false) ограждение не принимают', () {
      expect(
        () => extractor.decode('```json\n{"cards":[]}\n```', tolerant: false),
        throwsInvalidResponse(),
      );
    });
  });

  group('BOM и текст вокруг JSON', () {
    test('ведущий BOM снимается', () {
      expect(CardsJsonExtractor.stripBom('\uFEFF{"cards":[]}'), '{"cards":[]}');
      expect(CardsJsonExtractor.stripBom('\uFEFF \n {"a":1}'), '{"a":1}');
      expect(CardsJsonExtractor.stripBom('без BOM'), 'без BOM');
    });

    test('BOM перед JSON в tolerant-режиме разбирается', () {
      final decoded = extractor.decode(
        '\uFEFF```json\n{"cards":[]}\n```',
        tolerant: true,
      );
      expect(decoded, <String, Object?>{'cards': <Object?>[]});
    });

    test('JSON без ограждения в тексте извлекается', () {
      final decoded = extractor.decode(
        'Ответ модели: {"cards":[{"front":"a","back":"b"}]} — всё.',
        tolerant: true,
      );
      final cards = (decoded! as Map<String, Object?>)['cards']! as List;
      expect(cards, hasLength(1));
    });

    test('объекта в тексте нет → null', () {
      expect(CardsJsonExtractor.extractJsonObject('просто текст'), isNull);
      expect(CardsJsonExtractor.extractJsonObject('{"a":1'), isNull);
    });
  });

  // TASK 04: модель, упёршаяся в лимит вывода, присылает незакрытый JSON.
  // Раньше это была доменная ошибка `truncated` и ВСЕ карточки фрагмента
  // терялись (заказ 50 → «сгенерировано 32»). Теперь полные карточки спасаются.
  group('спасение карточек из оборванного ответа (TASK 04)', () {
    test('полный JSON: карточки возвращаются как есть', () {
      final List<Map<String, Object?>> cards = extractor.salvageCards(
        '{"cards":[{"front":"a","back":"b"},{"front":"c","back":"d"}]}',
      );
      expect(cards, hasLength(2));
      expect(cards.first['front'], 'a');
    });

    test('оборванный JSON: спасаются только закрытые карточки', () {
      const raw =
          '{"cards":['
          '{"front":"Вопрос 1","back":"Ответ 1"},'
          '{"front":"Вопрос 2","back":"Ответ 2"},'
          '{"front":"Вопрос 3","back":"Отв';
      final List<Map<String, Object?>> cards = extractor.salvageCards(raw);
      expect(cards, hasLength(2));
      expect(cards.map((Map<String, Object?> c) => c['front']), <String>[
        'Вопрос 1',
        'Вопрос 2',
      ]);
    });

    test('скобки и запятые внутри строк не ломают разбор', () {
      const raw =
          '{"cards":[{"front":"a {б} c","back":"x, y"},'
          '{"front":"b","back":"d';
      final List<Map<String, Object?>> cards = extractor.salvageCards(raw);
      expect(cards, hasLength(1));
      expect(cards.single['front'], 'a {б} c');
    });

    test('обрыв до первой карточки → пусто (восстановление пайплайна)', () {
      expect(extractor.salvageCards('{"cards":['), isEmpty);
      expect(extractor.salvageCards('{"cards":[{"front":'), isEmpty);
      expect(extractor.salvageCards('модель молчит'), isEmpty);
    });

    test('невалидные карточки отбрасываются поштучно, полные остаются', () {
      const raw = '{"cards":[{"front":"a"},{"front":"b","back":"c"},{"fron';
      final List<Map<String, Object?>> cards = extractor.salvageCards(raw);
      // Обе закрытые карточки возвращены: строгость проверяет схема сервиса.
      expect(cards, hasLength(2));
    });
  });
}
