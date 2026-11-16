import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/domain/generation/generated_card.dart';

/// Мягкие проверки качества карточек (fix-gen, Д5): пометки, не удаление.
void main() {
  const validator = CardContentValidator();
  const source =
      'Ферма — стержневая система. Аксиомы статики описывают '
      'равновесие твёрдого тела.';

  Map<String, Object?> card({
    required String front,
    required String back,
    String cardType = 'basic',
    String? imageQuery,
  }) {
    return <String, Object?>{
      'front': front,
      'back': back,
      'hint': null,
      'tags': <Object?>['тег'],
      'card_type': cardType,
      'source_excerpt': null,
      'source_file': null,
      'image_id': null,
      'image_query': imageQuery,
    };
  }

  List<CardIssueCode> issuesOf(Map<String, Object?> value) {
    return validator
        .validateResponseWithRejects(<String, Object?>{
          'cards': <Object?>[value],
        }, sourceText: source)
        .cards
        .single
        .issues;
  }

  test('Д5-пример: ответ в вопросе (формула из back во front)', () {
    final issues = issuesOf(
      card(
        front:
            r'Формула геометрической неизменяемости плоской фермы $s = 2n - 3$',
        back: r'$s = 2n - 3$',
      ),
    );
    expect(issues, contains(CardIssueCode.answerInFront));
    expect(issues, contains(CardIssueCode.frontLooksLikeHeading));
  });

  test('«Шкала Мооса» во front — заголовок, не вопрос', () {
    final issues = issuesOf(
      card(
        front: 'Шкала относительной твёрдости минералов',
        back: 'Шкала Мооса',
      ),
    );
    expect(issues, contains(CardIssueCode.frontLooksLikeHeading));
  });

  test('вопрос с «?» и вопросительным словом не помечается', () {
    expect(
      issuesOf(
        card(
          front: 'При каком условии две силы уравновешивают друг друга?',
          back: 'Когда они равны по модулю и противоположны.',
        ),
      ),
      isNot(contains(CardIssueCode.frontLooksLikeHeading)),
    );
  });

  test('back длиннее ~200 символов и трёх предложений — пометка', () {
    final issues = issuesOf(
      card(
        front: 'Что такое ферма?',
        back: '${'Очень длинное объяснение. ' * 4}Конец.',
      ),
    );
    expect(issues, contains(CardIssueCode.backTooVerbose));
  });

  test('back — только расшифровка обозначений без утверждения', () {
    final issues = issuesOf(
      card(
        front: 'Что означают буквы в формуле фермы?',
        back: r'$s$ — число стержней, $n$ — число узлов',
      ),
    );
    expect(issues, contains(CardIssueCode.backOnlyNotation));
  });

  test('back с утверждением не считается только расшифровкой', () {
    final issues = issuesOf(
      card(
        front: 'Чему равно число стержней фермы?',
        back: r'$s = 2n - 3$, где $s$ — число стержней, $n$ — число узлов',
      ),
    );
    expect(issues, isNot(contains(CardIssueCode.backOnlyNotation)));
  });

  test('image_query абстрактного понятия сохраняется (7.14)', () {
    final parsed = validator.validateResponse(<String, Object?>{
      'cards': <Object?>[
        card(
          front: 'При каком условии две силы уравновешены?',
          back: 'Аксиома о равновесии двух сил',
          imageQuery: 'balance scale equilibrium',
        ),
      ],
    }, sourceText: source).single;
    expect(parsed.imageQuery, 'balance scale equilibrium');
    expect(parsed.issues, isNot(contains(CardIssueCode.abstractImageQuery)));
  });

  test('Unicode-индексы и греческие буквы вне формул — пометка', () {
    final issues = issuesOf(card(front: 'Чему равна F₁?', back: 'α-частица'));
    expect(issues, contains(CardIssueCode.unicodeMath));
  });

  test('Markdown-выделение в тексте — пометка', () {
    final issues = issuesOf(
      card(front: 'Что такое **ферма**?', back: 'Стержневая система.'),
    );
    expect(issues, contains(CardIssueCode.markdownInText));
  });

  test('хорошая карточка без пометок качества', () {
    final issues = issuesOf(
      card(
        front: 'При каком условии две силы уравновешивают друг друга?',
        back: 'Когда они равны по модулю и противоположны вдоль одной прямой.',
      ),
    );
    expect(issues, isEmpty);
  });
}
