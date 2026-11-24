import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/image_relevance.dart';

/// Аудит 2.0 (P1-04): автопоиск прикреплял нерелевантные изображения.
///
/// Правило: картинка проходит, только если хотя бы половина значимых слов
/// запроса встречается в заголовке/описании кандидата (совпадение по корню).
void main() {
  group('significantTokens', () {
    test('отбрасывает короткие слова и служебные', () {
      expect(significantTokens('The reliability of this test'), <String>{
        'reliability',
      });
    });

    test('удаляет «пустые» существительные картинок', () {
      expect(significantTokens('photo image chart diagram'), isEmpty);
    });

    test('кириллица нормализуется', () {
      expect(significantTokens('Надёжность теста: валидность'), <String>{
        'надёжность',
        'теста',
        'валидность',
      });
    });
  });

  group('isImageRelevant', () {
    test('фото здания не проходит для запроса о надёжности теста', () {
      expect(
        isImageRelevant(
          query: 'test reliability',
          title: 'Moscow State University main building',
          description: 'Building of the university, 1953',
        ),
        isFalse,
        reason: 'именно этот случай прикрепил фото здания (P1-04)',
      );
    });

    test('чарт личности не проходит для запроса о типах заданий', () {
      expect(
        isImageRelevant(
          query: 'test types of tasks',
          title: "What's Your Personality Type?",
          description: 'Myers-Briggs chart',
        ),
        isFalse,
      );
    });

    test('релевантная иллюстрация проходит', () {
      expect(
        isImageRelevant(
          query: 'leaf structure photosynthesis',
          title: 'Leaf structure diagram',
          description: 'Cross section of a leaf',
        ),
        isTrue,
      );
    });

    test('совпадение по корню (reliability/reliable, photosynthesis…)', () {
      expect(
        isImageRelevant(query: 'reliability', title: 'Reliable measurement'),
        isTrue,
      );
      expect(
        isImageRelevant(
          query: 'photosynthesis',
          title: 'Photosynthetic pigments',
        ),
        isTrue,
      );
      expect(
        isImageRelevant(query: 'leaves', title: 'Leaf'),
        isFalse,
        reason: 'leaves/leaf — разные корни: слишком смелая нормализация',
      );
    });

    test('без метаданных кандидат не отбрасывается', () {
      expect(
        isImageRelevant(
          query: 'electric motor',
          title: null,
          description: null,
        ),
        isTrue,
        reason: 'провайдер без описаний не должен терять все картинки',
      );
    });

    test('пустой запрос не ограничивает', () {
      expect(isImageRelevant(query: '', title: 'Anything'), isTrue);
    });

    test('порог можно повысить для строгих сценариев', () {
      expect(
        isImageRelevant(
          query: 'three phase transformer winding',
          title: 'Transformer winding',
          threshold: 0.9,
        ),
        isFalse,
        reason: 'совпало 2 слова из 4 — ниже строгого порога',
      );
    });
  });

  test('оценка релевантности лежит в 0..1', () {
    final double score = imageRelevanceScore(
      query: 'voltage current resistance',
      title: 'Voltage and current',
      description: 'Ohm law resistance measurement',
    );
    expect(score, inInclusiveRange(0, 1));
    expect(score, greaterThanOrEqualTo(kMinImageRelevance));
  });
}
