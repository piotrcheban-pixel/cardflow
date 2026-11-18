import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_pricing.dart';

/// TASK 02A: цены генерации и явное состояние неизвестности (раздел G.5).
///
/// Инвариант «неизвестная цена — это null, а не 0» проверяется отдельно:
/// стоимость при неполных ценах не считается вовсе.
void main() {
  group('GenerationPricing', () {
    test('известные цены: состояние complete и точная стоимость', () {
      const GenerationPricing pricing = GenerationPricing(
        inputPerMillion: 2,
        outputPerMillion: 8,
        currency: 'USD',
      );
      expect(pricing.isComplete, isTrue);
      expect(pricing.state, PricingState.complete);

      final GenerationCost? cost = pricing.costFor(
        inputTokens: 1000000,
        outputTokens: 500000,
      );
      expect(cost, isNotNull);
      expect(cost!.input, 2);
      expect(cost.output, 4);
      expect(cost.total, 6);
      expect(cost.currency, 'USD');
    });

    test('нулевая цена — известное значение, а не «неизвестно»', () {
      const GenerationPricing pricing = GenerationPricing(
        inputPerMillion: 0,
        outputPerMillion: 0,
        currency: 'RUB',
      );
      expect(pricing.state, PricingState.complete);
      final GenerationCost? cost = pricing.costFor(
        inputTokens: 1000,
        outputTokens: 1000,
      );
      expect(cost?.total, 0);
    });

    test('одна цена неизвестна — incomplete, стоимость null', () {
      const GenerationPricing pricing = GenerationPricing(
        inputPerMillion: 2,
        currency: 'USD',
      );
      expect(pricing.state, PricingState.incomplete);
      expect(pricing.costFor(inputTokens: 1000, outputTokens: 1000), isNull);
    });

    test('цены нет вовсе — unknown, стоимость null (не 0)', () {
      expect(GenerationPricing.unknown.state, PricingState.unknown);
      expect(
        GenerationPricing.unknown.costFor(
          inputTokens: 1000,
          outputTokens: 1000,
        ),
        isNull,
      );
      const GenerationPricing noCurrency = GenerationPricing(
        inputPerMillion: 1,
        outputPerMillion: 1,
      );
      expect(noCurrency.isComplete, isFalse);
      expect(noCurrency.state, PricingState.incomplete);
    });

    test('некорректная цена не делает структуру полной', () {
      const GenerationPricing negative = GenerationPricing(
        inputPerMillion: -1,
        outputPerMillion: 2,
        currency: 'USD',
      );
      expect(negative.isComplete, isFalse);
      expect(negative.costFor(inputTokens: 1, outputTokens: 1), isNull);
      final GenerationPricing nan = GenerationPricing(
        inputPerMillion: double.nan,
        outputPerMillion: 2,
        currency: 'USD',
      );
      expect(nan.isComplete, isFalse);
    });

    test('JSON round-trip сохраняет известные и неизвестные значения', () {
      const GenerationPricing pricing = GenerationPricing(
        inputPerMillion: 0.27,
        outputPerMillion: 1.1,
        currency: 'USD',
      );
      final GenerationPricing? parsed = GenerationPricing.fromJson(
        pricing.toJson(),
      );
      expect(parsed, pricing);
      expect(parsed!.state, PricingState.complete);
    });

    test('JSON с null внутри — неизвестные поля, а не 0', () {
      final GenerationPricing? pricing = GenerationPricing.fromJson(
        <String, Object?>{
          'input_per_mtok': 1.5,
          'output_per_mtok': null,
          'currency': 'USD',
        },
      );
      expect(pricing, isNotNull);
      expect(pricing!.inputPerMillion, 1.5);
      expect(pricing.outputPerMillion, isNull);
      expect(pricing.state, PricingState.incomplete);
      expect(pricing.costFor(inputTokens: 1, outputTokens: 1), isNull);
    });

    test('JSON: битые значения отбрасываются в неизвестность', () {
      final GenerationPricing? pricing = GenerationPricing.fromJson(
        <String, Object?>{
          'input_per_mtok': -3,
          'output_per_mtok': 'дорого',
          'currency': '   ',
        },
      );
      expect(pricing, isNotNull);
      expect(pricing!.inputPerMillion, isNull);
      expect(pricing.outputPerMillion, isNull);
      expect(pricing.currency, isNull);
      expect(pricing.state, PricingState.unknown);
    });

    test('JSON: не-объект — null (цены отсутствуют)', () {
      expect(GenerationPricing.fromJson(null), isNull);
      expect(GenerationPricing.fromJson(42), isNull);
      expect(GenerationPricing.fromJson(<Object?>[]), isNull);
    });

    test('JSON: пустой объект — неизвестность, а не нули', () {
      final GenerationPricing? pricing = GenerationPricing.fromJson(
        <String, Object?>{},
      );
      expect(pricing, isNotNull);
      expect(pricing!.state, PricingState.unknown);
      expect(pricing.inputPerMillion, isNull);
      expect(pricing.outputPerMillion, isNull);
    });

    test('равенство и hashCode по всем полям', () {
      const GenerationPricing a = GenerationPricing(
        inputPerMillion: 1,
        outputPerMillion: 2,
        currency: 'USD',
      );
      const GenerationPricing b = GenerationPricing(
        inputPerMillion: 1,
        outputPerMillion: 2,
        currency: 'USD',
      );
      const GenerationPricing c = GenerationPricing(
        inputPerMillion: 1,
        outputPerMillion: 3,
        currency: 'USD',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('toString и стоимость: равенство, hashCode, диагностика', () {
      const GenerationPricing pricing = GenerationPricing(
        inputPerMillion: 2,
        outputPerMillion: 8,
        currency: 'USD',
      );
      final GenerationCost? cost = pricing.costFor(
        inputTokens: 1000000,
        outputTokens: 1000000,
      );
      expect(
        cost,
        const GenerationCost(input: 2, output: 8, total: 10, currency: 'USD'),
      );
      expect(
        cost!.hashCode,
        const GenerationCost(
          input: 2,
          output: 8,
          total: 10,
          currency: 'USD',
        ).hashCode,
      );
      expect(cost.toString(), contains('10.000000 USD'));
      expect(pricing.toString(), contains('USD'));
      expect(GenerationPricing.unknown.toString(), contains('unknown'));
    });
  });
}
