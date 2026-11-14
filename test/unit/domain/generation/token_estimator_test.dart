import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/token_estimator.dart';

void main() {
  const estimator = TokenEstimator();

  test('пустой текст — 0 токенов', () {
    expect(estimator.estimate(''), 0);
  });

  test('оценка непустого текста положительна и растёт с длиной', () {
    final int short = estimator.estimate('Короткий текст');
    final int long = estimator.estimate('Короткий текст' * 10);
    expect(short, greaterThan(0));
    expect(long, greaterThan(short));
  });

  test('оценка по эвристике ≈ 2,5 символа на токен (кириллица)', () {
    // 25 символов → 10 токенов.
    expect(estimator.estimate('а' * 25), 10);
    // 26 символов → 11 токенов (округление вверх).
    expect(estimator.estimate('а' * 26), 11);
  });

  test('Unicode-символы считаются по runes, а не по code units', () {
    // Эмодзи — суррогатная пара: code units 2, rune 1.
    expect(estimator.estimate('😀'), 1);
    expect(estimator.estimate('😀' * 25), 10);
  });

  test('estimateAll суммирует оценки фрагментов', () {
    expect(estimator.estimateAll(<String>['а' * 25, 'а' * 25, '']), 20);
  });

  test('кастомный charsPerToken меняет оценку', () {
    const two = TokenEstimator(charsPerToken: 2);
    expect(two.estimate('а' * 20), 10);
  });
}
