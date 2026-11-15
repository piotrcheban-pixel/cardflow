/// Локальная валидация карточек поверх схемы (SPEC A8.4).
///
/// Карточку не отбрасывает: правила качества ставят машинные пометки
/// `CardIssueCode`, чтобы предпросмотр (итерация 3c) показал их и дал
/// отредактировать.
library;

import 'package:cardflow/api/generation/latex_checker.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';

/// Валидатор контентных правил A8.4.
class CardContentValidator {
  /// Создаёт валидатор.
  ///
  /// [latexChecker] — инъекция проверки LaTeX (по умолчанию `latexIsValid`
  /// из `latex_checker.dart`); в тестах можно подменить.
  const CardContentValidator({this.latexChecker});

  /// Проверка LaTeX-разметки текста; `null` — использовать `latexIsValid`.
  final bool Function(String text)? latexChecker;

  static final RegExp _clozePattern = RegExp(r'\{\{c\d+::.+?\}\}');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Максимальная длина `front` (SPEC A8.4).
  static const int maxFrontLength = 500;

  /// Максимальная длина `back` (SPEC A8.4).
  static const int maxBackLength = 2000;

  /// Максимальное число тегов (SPEC A8.4).
  static const int maxTags = 3;

  /// Максимальная длина `image_query` (итерация 7.9).
  static const int maxImageQueryLength = 200;

  /// Валидирует декодированный ответ модели (уже прошедший проверку схемы).
  ///
  /// [sourceText] — исходный текст материалов для проверки `source_excerpt`.
  List<GeneratedCard> validateResponse(
    Object? json, {
    required String sourceText,
  }) {
    if (json is! Map) {
      throw _invalidResponse();
    }
    final cards = json['cards'];
    if (cards is! List) {
      throw _invalidResponse();
    }

    final normalizedSource = _collapseSpaces(sourceText);
    final result = <GeneratedCard>[];
    for (final raw in cards) {
      if (raw is! Map) throw _invalidResponse();
      result.add(_validateCard(raw.cast<String, Object?>(), normalizedSource));
    }
    return result;
  }

  GeneratedCard _validateCard(
    Map<String, Object?> raw,
    String normalizedSource,
  ) {
    final front = raw['front'];
    final back = raw['back'];
    final cardTypeWire = raw['card_type'];
    if (front is! String || back is! String || cardTypeWire is! String) {
      throw _invalidResponse();
    }
    final CardType cardType;
    final bool isOcclusion = cardTypeWire == 'occlusion';
    if (isOcclusion) {
      // SPEC A5: occlusion — разметка внутри basic, а не тип карточки.
      cardType = CardType.basic;
    } else {
      try {
        cardType = CardType.fromWire(cardTypeWire);
      } on FormatException {
        throw _invalidResponse();
      }
    }

    final issues = <CardIssueCode>[];
    if (front.trim().isEmpty) issues.add(CardIssueCode.emptyFront);
    if (front.length > maxFrontLength) issues.add(CardIssueCode.frontTooLong);
    if (back.length > maxBackLength) issues.add(CardIssueCode.backTooLong);
    if (cardType == CardType.cloze && !_clozePattern.hasMatch(front)) {
      issues.add(CardIssueCode.clozeMissing);
    }

    final isLatexOk = latexChecker ?? latexIsValid;
    if (!isLatexOk(front) || !isLatexOk(back)) {
      issues.add(CardIssueCode.latexBroken);
    }

    final rawTags = raw['tags'];
    final tags = <String>[];
    final normalizedInputTags = <String>[];
    if (rawTags is List) {
      for (final rawTag in rawTags) {
        final tag = rawTag is String ? _normalizeTag(rawTag) : '';
        normalizedInputTags.add(tag);
        if (tag.isNotEmpty && tags.length < maxTags) tags.add(tag);
      }
    }
    if (!_listsEqual(normalizedInputTags, tags)) {
      issues.add(CardIssueCode.tagsAdjusted);
    }

    String? sourceExcerpt;
    final rawExcerpt = raw['source_excerpt'];
    if (rawExcerpt is String) {
      final normalized = _collapseSpaces(rawExcerpt);
      if (normalized.isEmpty || !normalizedSource.contains(normalized)) {
        issues.add(CardIssueCode.excerptMismatch);
      } else {
        sourceExcerpt = normalized;
      }
    }

    final hint = raw['hint'];
    final sourceFile = raw['source_file'];
    final rawQuery = raw['image_query'];
    final String? imageQuery = rawQuery is String && rawQuery.trim().isNotEmpty
        ? _limitQuery(rawQuery.trim())
        : null;
    return GeneratedCard(
      front: front,
      back: back,
      cardType: cardType,
      hint: hint is String ? hint : null,
      tags: tags,
      sourceExcerpt: sourceExcerpt,
      sourceFile: sourceFile is String ? sourceFile : null,
      issues: List<CardIssueCode>.unmodifiable(issues),
      imageQuery: imageQuery,
      isOcclusion: isOcclusion,
    );
  }

  /// Обрезает поисковый запрос до [maxImageQueryLength] символов.
  static String _limitQuery(String value) {
    return value.length <= maxImageQueryLength
        ? value
        : value.substring(0, maxImageQueryLength).trim();
  }

  static String _normalizeTag(String tag) {
    var value = tag.trim();
    while (value.startsWith('#')) {
      value = value.substring(1).trim();
    }
    return value;
  }

  static String _collapseSpaces(String value) =>
      value.replaceAll(_whitespace, ' ').trim();

  static bool _listsEqual(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static GenerationException _invalidResponse() => const GenerationException(
    GenerationErrorCode.invalidResponse,
    details: 'Ответ модели не соответствует структуре карточек (A8.4)',
  );
}
