import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_continuity.dart';

/// TASK 03, раздел 4: компактное состояние prompt-only запуска.
void main() {
  const ContentTokenEstimator estimator = HeuristicContentTokenEstimator();

  GeneratedCard card(int index, {String? front}) {
    return GeneratedCard(
      front: front ?? 'Вопрос номер $index о теме фотосинтеза?',
      back: 'Ответ $index.',
      cardType: CardType.basic,
      tags: <String>['тема$index', 'фотосинтез'],
    );
  }

  test('пустое состояние не передаёт блок', () {
    final GenerationContinuityState state = GenerationContinuityState(
      estimator: estimator,
    );
    expect(state.isEmpty, isTrue);
    expect(state.block, isNull);
    expect(state.tokens, 0);
  });

  test('сводка содержит уже созданные вопросы и темы', () {
    final GenerationContinuityState state = GenerationContinuityState(
      estimator: estimator,
    )..addAll(<GeneratedCard>[card(1), card(2)]);
    final String block = state.block!;
    expect(block, contains('не повторяй'));
    expect(block, contains('Вопрос номер 1'));
    expect(block, contains('Вопрос номер 2'));
    expect(block, contains('фотосинтез'));
    expect(state.cardCount, 2);
    expect(state.tokens, greaterThan(0));
  });

  test('одинаковые карточки не дублируются в сводке', () {
    final GenerationContinuityState state = GenerationContinuityState(
      estimator: estimator,
    )..addAll(<GeneratedCard>[card(1), card(1)]);
    expect(state.cardCount, 1);
    expect(
      '- Вопрос номер 1 о теме фотосинтеза?'.allMatches(state.block!).length,
      1,
    );
  });

  test('длинный front обрезается', () {
    final GenerationContinuityState state =
        GenerationContinuityState(estimator: estimator, maxFrontChars: 20)
          ..addAll(<GeneratedCard>[
            card(1, front: 'Очень длинный вопрос ${'слово ' * 30}?'),
          ]);
    final String block = state.block!;
    expect(block, contains('…'));
    expect(block.length, lessThan(600));
  });

  test('20/50/100/200 карточек: блок не растёт бесконечно', () {
    for (final int count in <int>[20, 50, 100, 200]) {
      final GenerationContinuityState state = GenerationContinuityState(
        estimator: estimator,
      )..addAll(<GeneratedCard>[for (var i = 0; i < count; i++) card(i)]);
      expect(state.cardCount, count);
      expect(
        state.tokens,
        lessThanOrEqualTo(kPromptOnlyContinuationMaxTokens),
        reason: 'сводка на $count карточек должна помещаться в резерв',
      );
      expect(
        state.block,
        isNotNull,
        reason: 'блок не должен исчезать при большом числе карточек',
      );
    }
  });

  test('равномерная выборка сохраняет начало и конец запуска', () {
    final GenerationContinuityState state = GenerationContinuityState(
      estimator: estimator,
      maxCards: 5,
    )..addAll(<GeneratedCard>[for (var i = 0; i < 100; i++) card(i)]);
    final String block = state.block!;
    expect(block, contains('Вопрос номер 0 '));
    expect(block, contains('Ещё'));
  });

  test('исходный порядок и терминология не зависят от дублей', () {
    final GenerationContinuityState state = GenerationContinuityState(
      estimator: estimator,
    )..addAll(<GeneratedCard>[card(1), card(2), card(1), card(3)]);
    final String block = state.block!;
    expect(
      block.indexOf('Вопрос номер 1'),
      lessThan(block.indexOf('Вопрос номер 2')),
    );
    expect(
      block.indexOf('Вопрос номер 2'),
      lessThan(block.indexOf('Вопрос номер 3')),
    );
  });
}
