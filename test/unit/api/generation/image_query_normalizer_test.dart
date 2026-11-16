import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/image_query_normalizer.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';

/// Нормализация `image`/`image_query` ответа модели (7.14).
void main() {
  test('корректный объект v6 остаётся как есть', () {
    final spec = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'truss bridge structure engineering',
        'fallback_query': 'truss bridge',
        'kind': 'photo',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(spec.query, 'truss bridge structure engineering');
    expect(spec.fallbackQuery, 'truss bridge');
    expect(spec.kind, GeneratedCardImageKind.photo);
    expect(spec.adjusted, isFalse);
    expect(spec.legacy, isFalse);
  });

  test('пустой query собирается из fallback_query', () {
    final spec = normalizeImageSpec(
      image: <String, Object?>{
        'query': '   ',
        'fallback_query': 'force diagram',
        'kind': 'diagram',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(spec.query, 'force diagram');
    expect(spec.adjusted, isTrue);
  });

  test('кириллица вычищается; не осталось латиницы → fallback', () {
    final spec = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'схема фермы',
        'fallback_query': 'truss structure',
        'kind': 'diagram',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(spec.query, 'truss structure');

    final none = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'схема фермы',
        'fallback_query': 'ферма',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(none.query, isNull);
    expect(none.hasQuery, isFalse);
  });

  test('больше 7 слов режется, служебные слова удаляются', () {
    final long = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'photo of one two three four five six seven eight',
        'fallback_query': 'x y',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(long.query, 'one two three four five six seven');

    final cleaned = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'photo of mitochondria cell 3.jpg',
        'fallback_query': 'mitochondria',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(cleaned.query, 'mitochondria cell');
  });

  test('LaTeX и имена файлов не попадают в запрос', () {
    final spec = normalizeImageSpec(
      image: <String, Object?>{
        'query': r'$\frac{a}{b}$ diagram figure1.png lever',
        'fallback_query': 'lever physics',
        'kind': 'diagram',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(spec.query, 'diagram lever');
  });

  test('одно слово дополняется контекстом вида', () {
    final spec = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'mitochondria',
        'fallback_query': 'mitochondria',
        'kind': 'photo',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(spec.query, 'mitochondria photo');
    expect(spec.adjusted, isTrue);
  });

  test('fallback_query не длиннее 4 слов', () {
    final spec = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'truss bridge structure engineering',
        'fallback_query': 'one two three four five six',
        'kind': 'photo',
      },
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(spec.fallbackQuery, 'one two three four');
  });

  test('v5 image_query строкой: legacy-флаг и вывод вида', () {
    final spec = normalizeImageSpec(
      image: null,
      legacyQuery: '  photosynthesis process diagram  ',
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(spec.legacy, isTrue);
    expect(spec.query, 'photosynthesis process diagram');
    expect(spec.kind, GeneratedCardImageKind.diagram);
    expect(spec.adjusted, isFalse);
    expect(spec.fallbackQuery, 'photosynthesis process');
  });

  test('v5 image_query null → спецификации нет', () {
    final spec = normalizeImageSpec(
      image: null,
      legacyQuery: null,
      front: 'Вопрос',
      back: 'Ответ',
    );
    expect(spec.query, isNull);
    expect(spec.legacy, isFalse);
  });

  test('неизвестный kind выводится из текста карточки', () {
    final formula = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'moment of force',
        'fallback_query': 'torque',
        'kind': 'weird',
      },
      front: 'Чему равен момент силы?',
      back: r'$M = F d$',
    );
    expect(formula.kind, GeneratedCardImageKind.diagram);

    final abstract = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'time concept',
        'fallback_query': 'time',
        'kind': 'weird',
      },
      front: 'Что такое свобода?',
      back: 'Философское понятие',
    );
    expect(abstract.kind, GeneratedCardImageKind.illustration);

    final object = normalizeImageSpec(
      image: <String, Object?>{
        'query': 'mitochondria',
        'fallback_query': 'mitochondria',
        'kind': 'weird',
      },
      front: 'Какой органоид синтезирует АТФ?',
      back: 'Митохондрия',
    );
    expect(object.kind, GeneratedCardImageKind.photo);
  });
}
