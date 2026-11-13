import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';

/// Красная фаза итерации 2: валидация и нормализация черновика ручной формы
/// (SPEC A8.4, ADR-009). Ожидаемое поведение — в expect до реализации.
void main() {
  group('CardDraft.parseTags (SPEC A8.4)', () {
    test('разбивает строку, убирает # и пустые, сохраняет порядок', () {
      expect(
        CardDraft.parseTags(' тег1, #тег2 ,, тег1  , # '),
        <String>['тег1', 'тег2'],
      );
    });

    test('пустая строка — пустой список', () {
      expect(CardDraft.parseTags('   '), isEmpty);
      expect(CardDraft.parseTags(''), isEmpty);
    });

    test('два тега с решёткой и дубликатами после нормализации', () {
      expect(
        CardDraft.parseTags('#а, б, #а, #б, в'),
        <String>['а', 'б', 'в'],
      );
    });
  });

  group('CardDraft.normalized', () {
    test('trim полей, пустые hint/sourceExcerpt → null, теги нормализуются', () {
      const draft = CardDraft(
        front: '  Вопрос  ',
        back: ' Ответ\n',
        hint: '   ',
        tags: <String>[' #тег ', ''],
        sourceExcerpt: '  Цитата  ',
      );

      final normalized = draft.normalized();

      expect(normalized.front, 'Вопрос');
      expect(normalized.back, 'Ответ');
      expect(normalized.hint, isNull);
      expect(normalized.tags, <String>['тег']);
      expect(normalized.sourceExcerpt, 'Цитата');
    });

    test('нормализация не теряет тип карточки', () {
      const draft = CardDraft(
        front: 'А',
        back: 'Б',
        cardType: CardType.basicReversed,
      );
      expect(draft.normalized().cardType, CardType.basicReversed);
    });
  });

  group('CardDraft.validate (SPEC A8.4, ADR-009)', () {
    test('валидный черновик — пустая карта ошибок, isValid true', () {
      const draft = CardDraft(
        front: 'Столица Франции?',
        back: 'Париж',
        tags: <String>['география', 'европа'],
        sourceExcerpt: 'Париж — столица Франции.',
      );

      expect(draft.validate(), isEmpty);
      expect(draft.isValid, isTrue);
    });

    test('пустой front — frontEmpty', () {
      const draft = CardDraft(front: '   ', back: 'Ответ');
      expect(draft.validate(), <CardDraftField, CardValidationError>{
        CardDraftField.front: CardValidationError.frontEmpty,
      });
    });

    test('front длиной ровно 500 валиден, 501 — frontTooLong', () {
      final ok = CardDraft(front: 'а' * 500, back: 'Ответ');
      final tooLong = CardDraft(front: 'а' * 501, back: 'Ответ');

      expect(ok.validate(), isEmpty);
      expect(tooLong.validate(), <CardDraftField, CardValidationError>{
        CardDraftField.front: CardValidationError.frontTooLong,
      });
      expect(CardDraft.frontMaxLength, 500);
    });

    test('пустой back у basic — backEmpty', () {
      const draft = CardDraft(front: 'Вопрос', back: '   ');
      expect(draft.validate(), <CardDraftField, CardValidationError>{
        CardDraftField.back: CardValidationError.backEmpty,
      });
    });

    test('пустой back у cloze допустим (SPEC A8.1, правило 3)', () {
      const draft = CardDraft(
        front: 'Пропуск {{c1::слово}}',
        back: '',
        cardType: CardType.cloze,
      );
      expect(draft.validate(), isEmpty);
    });

    test('back длиной ровно 2000 валиден, 2001 — backTooLong', () {
      final ok = CardDraft(front: 'Вопрос', back: 'б' * 2000);
      final tooLong = CardDraft(front: 'Вопрос', back: 'б' * 2001);

      expect(ok.validate(), isEmpty);
      expect(tooLong.validate(), <CardDraftField, CardValidationError>{
        CardDraftField.back: CardValidationError.backTooLong,
      });
      expect(CardDraft.backMaxLength, 2000);
    });

    test('четыре тега — tagsTooMany, три — валидно', () {
      final tooMany = const CardDraft(
        front: 'Вопрос',
        back: 'Ответ',
      ).normalized();
      final withFour = CardDraft(
        front: 'Вопрос',
        back: 'Ответ',
        tags: <String>['а', 'б', 'в', 'г'],
      );

      expect(tooMany.validate(), isEmpty);
      expect(withFour.validate(), <CardDraftField, CardValidationError>{
        CardDraftField.tags: CardValidationError.tagsTooMany,
      });
      expect(CardDraft.maxTags, 3);
    });

    test('цитата длиннее 400 — sourceExcerptTooLong', () {
      final draft = CardDraft(
        front: 'Вопрос',
        back: 'Ответ',
        sourceExcerpt: 'ц' * 401,
      );
      expect(draft.validate(), <CardDraftField, CardValidationError>{
        CardDraftField.sourceExcerpt:
            CardValidationError.sourceExcerptTooLong,
      });
      expect(CardDraft.sourceExcerptMaxLength, 400);
    });

    test('несколько ошибок возвращаются сразу по своим полям', () {
      const draft = CardDraft(front: '', back: '');
      expect(draft.validate(), <CardDraftField, CardValidationError>{
        CardDraftField.front: CardValidationError.frontEmpty,
        CardDraftField.back: CardValidationError.backEmpty,
      });
    });
  });

  group('CardDraft.empty', () {
    test('пустой черновик basic с пустыми полями', () {
      final draft = CardDraft.empty();

      expect(draft.front, isEmpty);
      expect(draft.back, isEmpty);
      expect(draft.hint, isNull);
      expect(draft.tags, isEmpty);
      expect(draft.cardType, CardType.basic);
      expect(draft.sourceExcerpt, isNull);
      expect(draft.isValid, isFalse);
    });
  });
}
