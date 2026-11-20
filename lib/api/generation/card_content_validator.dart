/// Локальная валидация карточек поверх схемы (SPEC A8.4, A8.1).
///
/// Карточку не отбрасывает: правила качества ставят машинные пометки
/// `CardIssueCode`, чтобы предпросмотр (итерация 3c) показал их и дал
/// отредактировать. Структурно невалидная запись (не объект, нет обязательных
/// строк, неизвестный тип) отбрасывается **сама**, а не весь фрагмент
/// (fix-gen, Д6): остальные карточки сохраняются.
library;

import 'package:cardflow/api/generation/image_query_normalizer.dart';
import 'package:cardflow/api/generation/latex_checker.dart';
import 'package:cardflow/api/generation/latex_escape_repair.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';

/// Результат локальной валидации ответа модели.
class CardValidationOutcome {
  /// Создаёт результат.
  const CardValidationOutcome({
    required this.cards,
    required this.rejectedCards,
  });

  /// Валидные карточки (с пометками качества).
  final List<GeneratedCard> cards;

  /// Сколько записей отброшено как структурно невалидные.
  final int rejectedCards;
}

/// Валидатор контентных правил A8.4 и качества (A8.1).
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
  static final RegExp _sentenceEnd = RegExp(r'[.!?…]+(?=\s|$)');
  static final RegExp _subscripts = RegExp('[₀-₉₊₋₌₍₎ₐₑₒₓₔₕₖₗₘₙₚₛₜⁿᵢ]');
  static final RegExp _superscripts = RegExp('[⁰-⁹⁺⁻⁼⁽⁾ⁿⁱ]');
  static final RegExp _greek = RegExp('[Ͱ-Ͽἀ-῿]');

  /// Вопросительные слова, с которых начинается настоящий вопрос.
  ///
  /// Граница слова — lookahead, а не `\b`: в ECMAScript-регексе Dart `\b`
  /// считает словом только ASCII, поэтому после кириллицы не срабатывает.
  static final RegExp _questionWord = RegExp(
    r'^\s*(?:как|что|чему|чем|чьи|чья|чьё|почему|зачем|какой|какая|какое|'
    r'какие|каким|каких|каков|какова|при\s+каком|в\s+каком|где|когда|кто|'
    r'кого|кому|сколько|насколько|является\s+ли|можно\s+ли|верно\s+ли|'
    r'какую|какой\s+вид|what|how|why|when|where|which|who)'
    r'(?=\s|$|[,.!?;:…])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _markdownPattern = RegExp(
    r'(\*\*|__|`|^#{1,6}\s|\[[^\]]+\]\([^)]+\))',
    multiLine: true,
  );

  /// Строка списка обозначений: «x — …» (только типографское тире, не минус).
  static final RegExp _notationItem = RegExp(
    r'^\s*[^—–]{1,24}\s*[—–]\s*\S+',
    unicode: true,
  );

  /// Глаголы/связки, из-за которых ответ — утверждение, а не список обозначений.
  static final RegExp _assertionWord = RegExp(
    r'равен|равна|равно|означает|называется|вычисляется|определяет|'
    r'показывает|является|зависит|обратно|прямо\s+пропорционал',
    caseSensitive: false,
    unicode: true,
  );

  /// Максимальная длина `front` (SPEC A8.4).
  static const int maxFrontLength = 500;

  /// Максимальная длина `back` (SPEC A8.4).
  static const int maxBackLength = 2000;

  /// Максимальное число тегов (SPEC A8.4).
  static const int maxTags = 3;

  /// Мягкий предел длины `back` (A8.1, правило 3).
  static const int softBackLength = 200;

  /// Валидирует декодированный ответ модели (уже прошедший проверку схемы).
  ///
  /// [sourceText] — исходный текст материалов для проверки `source_excerpt`.
  /// [imageIds] — идентификаторы каталога `<images>` этого фрагмента: `image_id`
  /// вне каталога обнуляется (fix-gen, Д3).
  List<GeneratedCard> validateResponse(
    Object? json, {
    required String sourceText,
    Set<String> imageIds = const <String>{},
  }) {
    return validateResponseWithRejects(
      json,
      sourceText: sourceText,
      imageIds: imageIds,
    ).cards;
  }

  /// Валидирует ответ и сообщает, сколько записей отброшено (fix-gen, Д6).
  ///
  /// Бросает [GenerationException] (`validator_rejected`) только если корень
  /// ответа не объект `{"cards": [...]}`: одна плохая карточка фрагмент не
  /// роняет.
  CardValidationOutcome validateResponseWithRejects(
    Object? json, {
    required String sourceText,
    Set<String> imageIds = const <String>{},
  }) {
    if (json is! Map) {
      throw _invalidResponse();
    }
    final cards = json['cards'];
    if (cards is! List) {
      throw _invalidResponse();
    }

    final normalizedSource = _collapseSpaces(sourceText);
    final hasSource = normalizedSource.isNotEmpty;
    final result = <GeneratedCard>[];
    var rejected = 0;
    for (final raw in cards) {
      if (raw is! Map) {
        rejected++;
        continue;
      }
      final card = _tryValidateCard(
        raw.cast<String, Object?>(),
        normalizedSource,
        hasSource: hasSource,
        imageIds: imageIds,
      );
      if (card == null) {
        rejected++;
      } else {
        result.add(card);
      }
    }
    return CardValidationOutcome(
      cards: List<GeneratedCard>.unmodifiable(result),
      rejectedCards: rejected,
    );
  }

  /// Валидирует одну карточку; `null` — запись структурно непригодна.
  GeneratedCard? _tryValidateCard(
    Map<String, Object?> raw,
    String normalizedSource, {
    required bool hasSource,
    required Set<String> imageIds,
  }) {
    final rawFront = raw['front'];
    final rawBack = raw['back'];
    final cardTypeWire = raw['card_type'];
    if (rawFront is! String || rawBack is! String || cardTypeWire is! String) {
      return null;
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
        return null;
      }
    }

    // LaTeX-нормализация до правил качества (fix-gen, Д4): восстановление
    // испорченных escape и чужих разделителей.
    final String front = normalizeLatexDelimiters(
      repairLatexControlCharacters(rawFront),
    );
    final String back = normalizeLatexDelimiters(
      repairLatexControlCharacters(rawBack),
    );

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

    _markFormattingIssues(front, back, issues);
    _markQualityIssues(front, back, cardType, issues);

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
      if (!hasSource) {
        // Prompt-only: цитата невозможна, карточка остаётся (fix-gen, Д1).
        sourceExcerpt = null;
      } else if (normalized.isEmpty || !normalizedSource.contains(normalized)) {
        issues.add(CardIssueCode.excerptMismatch);
      } else {
        sourceExcerpt = normalized;
      }
    }

    final hint = raw['hint'];
    final sourceFile = raw['source_file'];
    final imageSelection = _imageSelectionOf(
      rawId: raw['image_id'],
      rawImage: raw['image'],
      rawLegacyQuery: raw['image_query'],
      front: front,
      back: back,
      imageIds: imageIds,
      issues: issues,
    );
    final Object? rawSection = raw['section_id'];
    return GeneratedCard(
      front: front,
      sectionId: rawSection is String && rawSection.trim().isNotEmpty
          ? rawSection.trim()
          : null,
      back: back,
      cardType: cardType,
      hint: hint is String
          ? normalizeLatexDelimiters(repairLatexControlCharacters(hint))
          : null,
      tags: tags,
      sourceExcerpt: sourceExcerpt,
      sourceFile: sourceFile is String && sourceFile.trim().isNotEmpty
          ? sourceFile.trim()
          : null,
      issues: List<CardIssueCode>.unmodifiable(issues),
      imageQuery: imageSelection.query,
      imageFallbackQuery: imageSelection.fallbackQuery,
      imageKind: imageSelection.kind,
      imageId: imageSelection.id,
      isOcclusion: isOcclusion,
    );
  }

  /// Проверяет `image_id` и `image` (`gen-ru-v6`) или `image_query` (`gen-ru-v5`).
  ///
  /// Правило «абстрактным понятиям картинка не нужна» удалено в 7.14: запрос
  /// нормализуется (`image_query_normalizer.dart`), а не обнуляется, — картинка
  /// нужна каждой карточке. Испорченный запрос не роняет карточку: поиск
  /// просто не выполнится, и пайплайн поставит заглушку.
  ({
    String? id,
    String? query,
    String? fallbackQuery,
    GeneratedCardImageKind kind,
  })
  _imageSelectionOf({
    required Object? rawId,
    required Object? rawImage,
    required Object? rawLegacyQuery,
    required String front,
    required String back,
    required Set<String> imageIds,
    required List<CardIssueCode> issues,
  }) {
    String? id;
    if (rawId is String && rawId.trim().isNotEmpty) {
      final candidate = rawId.trim();
      if (imageIds.contains(candidate)) {
        id = candidate;
      } else {
        issues.add(CardIssueCode.imageIdUnknown);
      }
    }
    final NormalizedImageSpec spec = normalizeImageSpec(
      image: rawImage,
      legacyQuery: rawLegacyQuery,
      front: front,
      back: back,
    );
    if (spec.adjusted) issues.add(CardIssueCode.imageQueryAdjusted);
    return (
      id: id,
      query: spec.query,
      fallbackQuery: spec.fallbackQuery,
      kind: spec.kind,
    );
  }

  /// Пометки форматирования: Unicode-математика и Markdown (A8.1, правило 4).
  void _markFormattingIssues(
    String front,
    String back,
    List<CardIssueCode> issues,
  ) {
    final plain = _withoutFormulas('$front\n$back');
    if (_subscripts.hasMatch(plain) ||
        _superscripts.hasMatch(plain) ||
        _greek.hasMatch(plain)) {
      issues.add(CardIssueCode.unicodeMath);
    }
    if (_markdownPattern.hasMatch(plain)) {
      issues.add(CardIssueCode.markdownInText);
    }
  }

  /// Мягкие правила качества (A8.1, правила 2 и 3) — пометки, не удаление.
  void _markQualityIssues(
    String front,
    String back,
    CardType cardType,
    List<CardIssueCode> issues,
  ) {
    if (cardType != CardType.cloze) {
      if (_answerAppearsInFront(front, back)) {
        issues.add(CardIssueCode.answerInFront);
      }
      if (!_looksLikeQuestion(front)) {
        issues.add(CardIssueCode.frontLooksLikeHeading);
      }
    }
    if (back.trim().isNotEmpty) {
      if (back.length > softBackLength || _sentenceCount(back) > 3) {
        issues.add(CardIssueCode.backTooVerbose);
      }
      if (_looksLikeNotationList(back)) {
        issues.add(CardIssueCode.backOnlyNotation);
      }
    }
  }

  /// Ответ (или формула из ответа) целиком содержится во `front`.
  static bool _answerAppearsInFront(String front, String back) {
    final String normalizedFront = _normalizeForCompare(front);
    final String normalizedBack = _normalizeForCompare(back);
    if (normalizedBack.length >= 8 &&
        normalizedFront.contains(normalizedBack)) {
      return true;
    }
    for (final String formula in extractLatexFormulas(back)) {
      final String normalizedFormula = _normalizeForCompare(formula);
      if (normalizedFormula.length >= 4 &&
          normalizedFront.contains(normalizedFormula)) {
        return true;
      }
    }
    return false;
  }

  /// `front` похож на заголовок: нет «?» и нет вопросительного слова.
  ///
  /// Односложные вопросы («Митохондрия?») не считаются заголовком: правило
  /// ловит именно названия тем («Шкала Мооса», «Формула геометрической
  /// неизменяемости…») — два и более слова без вопросительной формы.
  static bool _looksLikeQuestion(String front) {
    final String text = front.trim();
    if (text.isEmpty) return true;
    if (text.contains('?')) return true;
    if (_questionWord.hasMatch(text)) return true;
    final int words = text
        .split(_whitespace)
        .where((String word) => word.isNotEmpty)
        .length;
    return words < 2;
  }

  static int _sentenceCount(String back) =>
      _sentenceEnd.allMatches(back).length;

  /// `back` — только расшифровка обозначений («x — …, y — …») без утверждения.
  static bool _looksLikeNotationList(String back) {
    final String text = back.trim();
    if (text.isEmpty) return false;
    if (_assertionWord.hasMatch(text)) return false;
    final List<String> items = text
        .split(RegExp(r'[;,\n]'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
    if (items.length < 2) return false;
    return items.every((String item) => _notationItem.hasMatch(item));
  }

  /// Текст без формул `$…$`/`$$…$$` — Markdown и Unicode ищем вне LaTeX.
  static String _withoutFormulas(String text) {
    return text
        .replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), ' ')
        .replaceAll(RegExp(r'\$[^$]*\$'), ' ');
  }

  /// Нормализация для сравнения: без LaTeX-разметки, регистра и пунктуации.
  static String _normalizeForCompare(String value) {
    final String text = value
        .replaceAll(RegExp(r'\$\$?'), ' ')
        .replaceAll(RegExp(r'\{\{c\d+::'), ' ')
        .replaceAll('}}', ' ')
        .replaceAll(RegExp(r'\\(?:[a-zA-Z]+)'), ' ')
        .replaceAll(RegExp(r'[{}\\]'), ' ')
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    return _collapseSpaces(text);
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
    failureReason: GenerationFailureReason.validatorRejected,
  );
}
