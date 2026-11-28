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

  test('чистая карточка с дословной цитатой — accepted', () {
    final CardValidatorGate gate = gateOf(documentOf(statement));

    expect(gate.evaluate(cardOf()), CardGateVerdict.accepted);
    expect(gate.blockedCards, isEmpty);
  });

  test('содержательная пометка — warning, карточка остаётся', () {
    final CardValidatorGate gate = gateOf(documentOf(statement));

    expect(
      gate.evaluate(cardOf(front: 'Что описано выше?')),
      CardGateVerdict.warning,
    );
    expect(gate.blockedCards, isEmpty);
  });

  test('цитата вне материала — blocked и запоминается', () {
    final CardValidatorGate gate = gateOf(documentOf(statement));

    expect(
      gate.evaluate(cardOf(quoteRef: 'цитаты нет в материале')),
      CardGateVerdict.blocked,
    );
    expect(gate.blockedCards, hasLength(1));
    expect(gate.blockedCards.single.quoteRef, 'цитаты нет в материале');
  });

  test(
    'структурно отброшенная запись — тоже blocked (порт знает три исхода)',
    () {
      final CardValidatorGate gate = gateOf(documentOf(statement));

      expect(gate.evaluate(cardOf(front: '   ')), CardGateVerdict.blocked);
      expect(gate.blockedCards, hasLength(1));
    },
  );
}
