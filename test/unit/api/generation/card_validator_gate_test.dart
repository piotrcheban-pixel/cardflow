import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/validation/card_validator.dart';
import 'package:cardflow/api/generation/validation/card_validator_gate.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/card_gate.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Срез 11, часть 1: порт `CardGate` на существующем `CardValidator` —
/// три вердикта без новой логики проверок; заблокированное не исчезает.
/// Срез 12, п. 1: коды причин возвращаются вместе с вердиктом, а не теряются.
void main() {
  const String statement = 'Момент силы равен произведению силы на плечо.';

  Document documentOf(String text) => const ContentModelBuilder().build(
    ParsedDocument(
      format: DocumentFormat.txt,
      fileName: 'лекция.txt',
      text: text,
      sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
    ),
  );

  GeneratedCard cardOf({
    String front = 'Чему равно произведение силы на плечо?',
    String back = 'Моменту силы.',
    String? quoteRef = statement,
    String? unitId = 'ku:1',
  }) => GeneratedCard(
    front: front,
    back: back,
    cardType: CardType.basic,
    unitId: unitId,
    quoteRef: quoteRef,
  );

  CardValidatorGate gateOf(Document document) => CardValidatorGate(
    validator: const CardValidator(),
    document: document,
    knownUnitIds: const <String>{'ku:1'},
  );

  test('чистая карточка с дословной цитатой — accepted без кодов', () {
    final CardValidatorGate gate = gateOf(documentOf(statement));

    final CardGateResult result = gate.evaluate(cardOf());
    expect(result.verdict, CardGateVerdict.accepted);
    expect(result.reasons, isEmpty);
    expect(gate.blockedCards, isEmpty);
  });

  test('содержательная пометка — warning с кодом причины', () {
    final CardValidatorGate gate = gateOf(documentOf(statement));

    final CardGateResult result = gate.evaluate(
      cardOf(front: 'Что описано выше?'),
    );
    expect(result.verdict, CardGateVerdict.warning);
    expect(result.reasons, contains(CardReasonCode.questionNotSelfContained));
    expect(gate.blockedCards, isEmpty);
  });

  test(
    'перечисление из 5 пунктов принято, но помечено not_atomic (DoD S12)',
    () {
      final CardValidatorGate gate = gateOf(documentOf(statement));

      final CardGateResult result = gate.evaluate(
        cardOf(
          front:
              '1) атом; 2) молекула; 3) давление; 4) энергия; 5) импульс — '
              'что из этого?',
        ),
      );
      expect(result.verdict, CardGateVerdict.warning);
      expect(result.reasons, contains(CardReasonCode.notAtomic));
      expect(gate.blockedCards, isEmpty);
    },
  );

  test('цитата вне материала — blocked, код и запоминание карточки', () {
    final CardValidatorGate gate = gateOf(documentOf(statement));

    final CardGateResult result = gate.evaluate(
      cardOf(quoteRef: 'цитаты нет в материале'),
    );
    expect(result.verdict, CardGateVerdict.blocked);
    expect(result.reasons, contains(CardReasonCode.quoteOutOfRange));
    expect(gate.blockedCards, hasLength(1));
    expect(gate.blockedCards.single.quoteRef, 'цитаты нет в материале');
  });

  test(
    'структурно отброшенная запись — тоже blocked (порт знает три исхода)',
    () {
      final CardValidatorGate gate = gateOf(documentOf(statement));

      final CardGateResult result = gate.evaluate(cardOf(front: '   '));
      expect(result.verdict, CardGateVerdict.blocked);
      expect(result.reasons, isNotEmpty);
      expect(gate.blockedCards, hasLength(1));
    },
  );
}
