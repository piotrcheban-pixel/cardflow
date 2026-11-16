import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/answer_matcher.dart';
import 'package:cardflow/domain/study/answer_type.dart';

/// Сравнение ответов: нормализация, опечатки, числа, diff (7.15).
void main() {
  test('нормализация: регистр, ё/е, пробелы, пунктуация по краям, NFC', () {
    expect(
      matchAnswer(back: 'Митохондрия', input: '  митохондрия. ').result,
      AnswerMatchResult.exact,
    );
    expect(
      matchAnswer(back: 'Ещё', input: 'еще').result,
      AnswerMatchResult.exact,
    );
    expect(
      matchAnswer(back: 'café', input: 'cafe\u0301').result,
      AnswerMatchResult.exact,
      reason: 'NFC: é и e + combining acute — одно и то же',
    );
  });

  test('несколько допустимых ответов через «/» и «;»', () {
    for (final String input in <String>['Ньютон', 'Newton']) {
      expect(
        matchAnswer(back: 'Ньютон / Newton', input: input).result,
        AnswerMatchResult.exact,
        reason: input,
      );
    }
    expect(
      matchAnswer(back: 'авогадро; Авогадро', input: 'АВОГАДРО').result,
      AnswerMatchResult.exact,
    );
  });

  test('опечатка: almost при расстоянии ≤ 1 для коротких', () {
    // «митохондрия» (11) — длинный ответ, допуск 2.
    final long = matchAnswer(back: 'Митохондрия', input: 'Митохондрия');
    expect(long.result, AnswerMatchResult.exact);
    expect(
      matchAnswer(back: 'Митохондрия', input: 'Митохондрий').result,
      AnswerMatchResult.almost,
    );
    // Короткий ответ (≤ 6) — допуск 1.
    expect(
      matchAnswer(back: 'Ньютон', input: 'Нютон').result,
      AnswerMatchResult.almost,
    );
    expect(
      matchAnswer(back: 'Ньютон', input: 'Ньютоны').result,
      AnswerMatchResult.almost,
    );
    // Две ошибки в коротком ответе — wrong; в длинном (≤2) — almost.
    expect(
      matchAnswer(back: 'Ферма', input: 'Ферм').result,
      AnswerMatchResult.almost,
    );
    expect(
      matchAnswer(back: 'Митохондрия', input: 'Митахондрия').result,
      AnswerMatchResult.almost,
    );
    expect(
      matchAnswer(back: 'Ферма', input: 'Фрм').result,
      AnswerMatchResult.wrong,
    );
  });

  test('числа: 3,5 = 3.5, иначе wrong (без almost)', () {
    expect(
      matchAnswer(back: '3,5', input: '3.5', type: AnswerType.number).result,
      AnswerMatchResult.exact,
    );
    expect(
      matchAnswer(back: '3,5', input: ' 3,50 ', type: AnswerType.number).result,
      AnswerMatchResult.exact,
    );
    expect(
      matchAnswer(back: '3,5', input: '3.6', type: AnswerType.number).result,
      AnswerMatchResult.wrong,
    );
    expect(
      matchAnswer(back: '-12', input: '+(-12)', type: AnswerType.number).result,
      isNot(AnswerMatchResult.exact),
    );
  });

  test('diff: лишние символы зачёркиваются, недостающие подсвечиваются', () {
    final match = matchAnswer(back: 'Ньютон', input: 'Ньютоны');
    expect(match.result, AnswerMatchResult.almost);
    final String extra = match.diff
        .where((AnswerDiffOp op) => op.kind == AnswerDiffKind.extra)
        .map((AnswerDiffOp op) => op.text)
        .join();
    expect(extra, 'ы');

    final missing = matchAnswer(back: 'Ньютон', input: 'Нютон');
    final String miss = missing.diff
        .where((AnswerDiffOp op) => op.kind == AnswerDiffKind.missing)
        .map((AnswerDiffOp op) => op.text)
        .join();
    expect(miss, 'ь');

    final wrong = matchAnswer(back: 'Ферма', input: 'Блк');
    expect(wrong.result, AnswerMatchResult.wrong);
    expect(wrong.diff, isNotEmpty);
    expect(
      wrong.diff.every((AnswerDiffOp op) => op.kind != AnswerDiffKind.equal),
      isTrue,
    );
  });

  test('пустой ввод — wrong, пустой back — wrong', () {
    expect(
      matchAnswer(back: 'Ньютон', input: '   ').result,
      AnswerMatchResult.wrong,
    );
    expect(
      matchAnswer(back: '', input: 'что-то').result,
      AnswerMatchResult.wrong,
    );
  });

  test('matchCardAnswer использует тип карточки', () {
    final card = Card(
      id: 'c',
      deckId: 'd',
      front: 'Чему равно?',
      back: '3,5',
      cardType: CardType.basic,
      state: CardState.newCard,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(matchCardAnswer(card, '3.5').result, AnswerMatchResult.exact);
  });

  test('Levenshtein по Unicode-символам', () {
    expect(levenshteinDistance('кот', 'кот'), 0);
    expect(levenshteinDistance('кот', 'кит'), 1);
    expect(levenshteinDistance('', 'абв'), 3);
    expect(levenshteinDistance('ёж', 'еж'), 1);
  });
}
