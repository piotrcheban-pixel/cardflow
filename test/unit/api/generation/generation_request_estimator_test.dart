import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_request_estimator.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';

/// TASK 03, раздел 2: единая оценка собранного запроса.
void main() {
  const GenerationRequestEstimator estimator = GenerationRequestEstimator();

  GenerationAttachment image(int bytes) {
    return GenerationAttachment(
      fileName: 'рис.png',
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(List<int>.filled(bytes, 7)),
      label: 'img1 | рис.png | схема | стр. 1, схема фермы',
    );
  }

  GenerationRequestEstimate estimate(
    String userContent, {
    List<GenerationAttachment> images = const <GenerationAttachment>[],
    int maxOutputTokens = 1024,
    List<String> unknownFields = const <String>[],
  }) {
    return estimator.estimate(
      userContent: userContent,
      attachments: images,
      maxOutputTokens: maxOutputTokens,
      unknownFields: unknownFields,
    );
  }

  test('короткий текст: компоненты неотрицательны, итог = сумма', () {
    final GenerationRequestEstimate result = estimate(
      '<materials>Текст.</materials><wishes></wishes><limit>1</limit>',
    );
    expect(result.systemPrompt.tokens, greaterThan(0));
    expect(result.schema.tokens, greaterThan(0));
    expect(result.userContent.tokens, greaterThan(0));
    expect(result.images.tokens, 0);
    expect(
      result.inputTotal.tokens,
      result.systemPrompt.tokens! +
          result.schema.tokens! +
          result.userContent.tokens!,
    );
    expect(result.outputReserve.tokens, 1024);
    expect(result.outputReserve.kind, TokenValueKind.reserve);
    expect(result.inputTotal.kind, TokenValueKind.estimate);
    expect(result.estimatorVersion, contains('request-1'));
  });

  test('длинный текст растёт линейно и остаётся оценкой', () {
    final GenerationRequestEstimate short = estimate('слово ' * 10);
    final GenerationRequestEstimate long = estimate('слово ' * 1000);
    expect(long.userContent.tokens, greaterThan(short.userContent.tokens!));
    expect(long.inputTotal.kind, TokenValueKind.estimate);
  });

  test('JSON и специальные символы не теряются из оценки', () {
    final GenerationRequestEstimate result = estimate(
      '{"cards":[{"front":"\\"кавычки\\"","back":"\\\\frac{a}{b}"}]}',
    );
    expect(result.userContent.tokens, greaterThan(0));
    expect(result.inputTotal.isKnown, isTrue);
  });

  test('кириллица и смешанный язык оцениваются одним механизмом', () {
    final GenerationRequestEstimate cyrillic = estimate(
      'Фотосинтез — процесс.',
    );
    final GenerationRequestEstimate mixed = estimate(
      'Photosynthesis (фотосинтез) — process 2026.',
    );
    expect(cyrillic.inputTotal.isKnown, isTrue);
    expect(mixed.inputTotal.isKnown, isTrue);
    expect(cyrillic.estimatorVersion, mixed.estimatorVersion);
  });

  test('большой системный промпт входит в итог', () {
    final GenerationRequestEstimate result = estimate('материал');
    expect(result.systemPrompt.tokens, greaterThan(500));
  });

  test('одно изображение добавляет image-часть и подпись', () {
    final GenerationRequestEstimate withoutImages = estimate('материал');
    final GenerationRequestEstimate withImage = estimate(
      'материал',
      images: <GenerationAttachment>[image(100000)],
    );
    expect(withImage.images.tokens, greaterThan(0));
    expect(
      withImage.inputTotal.tokens,
      greaterThan(withoutImages.inputTotal.tokens!),
    );
    expect(withImage.assumptions, contains('image_tokens'));
  });

  test('много изображений: сумма частей и подписей', () {
    final GenerationRequestEstimate result = estimate(
      'материал',
      images: <GenerationAttachment>[
        for (var index = 0; index < 20; index++) image(50000 + index),
      ],
    );
    expect(result.images.tokens, greaterThan(20 * 100));
    expect(result.inputTotal.kind, TokenValueKind.estimate);
  });

  test('неизвестные возможности попадают в assumptions', () {
    final GenerationRequestEstimate result = estimate(
      'материал',
      unknownFields: const <String>['context_window', 'pricing', ''],
    );
    expect(result.assumptions, contains('context_window'));
    expect(result.assumptions, contains('pricing'));
    expect(result.assumptions, isNot(contains('')));
  });

  test('длинные пожелания входят в пользовательское сообщение', () {
    final GenerationRequestEstimate short = estimate('материал');
    final String longWishes = List<String>.filled(1000, 'пожелание').join(' ');
    final GenerationRequestEstimate long = estimate('материал\n\n$longWishes');
    expect(long.userContent.tokens, greaterThan(short.userContent.tokens!));
    expect(
      long.userContent.tokens! - short.userContent.tokens!,
      greaterThan(1000),
      reason: '1000 слов пожеланий заметно увеличивают оценку',
    );
  });

  test('комбинация текста, изображений и подписей учитывается', () {
    final GenerationRequestEstimate textOnly = estimate(
      '<materials>Текст материала.</materials>',
    );
    final GenerationRequestEstimate mixed = estimate(
      '<materials>Текст материала.</materials><images>img1 | рис.png | схема</images>',
      images: <GenerationAttachment>[image(120000), image(80000)],
    );
    expect(mixed.inputTotal.tokens, greaterThan(textOnly.inputTotal.tokens!));
    expect(mixed.images.tokens, greaterThan(0));
    expect(mixed.assumptions, contains('image_tokens'));
  });

  test('резерв вывода — верхняя граница, не фактический расход', () {
    final GenerationRequestEstimate result = estimate('материал');
    expect(result.outputReserve.kind, TokenValueKind.reserve);
    expect(result.outputReserve.source, 'request.maxOutputTokens');
    expect(result.inputTotal.isEstimate, isTrue);
  });

  test('оценка детерминирована (одинаковый вход — одинаковый результат)', () {
    final GenerationRequestEstimate first = estimate('Текст для оценки.');
    final GenerationRequestEstimate second = estimate('Текст для оценки.');
    expect(first.inputTotal.tokens, second.inputTotal.tokens);
    expect(first.estimatorVersion, second.estimatorVersion);
  });
}
