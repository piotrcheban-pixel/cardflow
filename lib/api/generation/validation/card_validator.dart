/// Этап Validation (TASK «Срез 6», ADR-050 §3.3): структурные проверки A8.4
/// и семантические эвристики с машинным кодом причины.
///
/// Результат на карточку — `accepted | warning | rejected(code)`:
/// - принятая и помеченная остаются кандидатами предпросмотра;
/// - отброшенная не исчезает: она попадает в [CardValidationReport.rejected]
///   вместе с исходной записью («показать отброшенные»).
///
/// Цитата проверяется **по offsets** `ContentModel`: `quote_ref` обязан
/// буквально совпадать с диапазоном текста блока, иначе карточка помечается
/// (`quoteNotLiteral`/`quoteOutOfRange`), но остаётся — цитата обнуляется
/// (ARCH §3.3).
///
/// Старый валидатор `card_content_validator.dart` не меняется: он обслуживает
/// production-путь `gen-ru-v9` (протокол §9 — старый код не удаляется, пока
/// новый путь не покрыт тестами и не включён флагом).
library;

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_normalizer.dart';
import 'package:cardflow/api/generation/latex_checker.dart';
import 'package:cardflow/api/generation/latex_escape_repair.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';

/// Вердикт этапа Validation.
enum CardVerdict {
  /// Структурно годна, причин нет.
  accepted('accepted'),

  /// Годна с пометками качества; карточка остаётся в предпросмотре.
  warning('warning'),

  /// Непригодна: отброшена с кодом причины, запись сохранена в отчёте.
  rejected('rejected');

  const CardVerdict(this.wireName);

  /// Машинный код вердикта.
  final String wireName;
}

/// Машинный код причины вердикта (A8.4 + семантические эвристики).
enum CardReasonCode {
  /// Структурно невалидная запись: нет `front`/`back`/`card_type` или они не
  /// строки.
  missingRequiredField('missing_required_field'),

  /// Неизвестный `card_type` (A8.4: `basic | basic_reversed | cloze`;
  /// wire-формат допускает `occlusion`).
  unknownCardType('unknown_card_type'),

  /// Пустой `front` (A8.4: вопрос не пустой).
  emptyFront('empty_front'),

  /// `front` длиннее 500 символов (A8.4).
  frontTooLong('front_too_long'),

  /// `back` длиннее 2000 символов (A8.4).
  backTooLong('back_too_long'),

  /// Для `cloze` нет ни одного пропуска `{{cN::…}}` (A8.4).
  clozeMissing('cloze_missing'),

  /// Теги скорректированы: обрезаны до 3, убраны пустые и `#` (A8.4).
  tagsAdjusted('tags_adjusted'),

  /// Формула не парсится (A8.4: пометка, а не отбрасывание).
  latexBroken('latex_broken'),

  /// Ответ (или формула из ответа) целиком содержится во `front` — карточка
  /// проверяет вопрос, в котором уже есть ответ.
  answerInQuestion('answer_in_question'),

  /// Вопрос несамостоятелен: «этот», «выше», «см. рис.» — без материала
  /// нечитаем.
  questionNotSelfContained('question_not_self_contained'),

  /// Перечисление в карточке больше трёх пунктов: не атомарна.
  notAtomic('not_atomic'),

  /// Пропуск cloze бессмысленный: весь вопрос — пропуск, пустые/повторные
  /// пропуски, нумерация не с `c1`.
  clozeMeaningless('cloze_meaningless'),

  /// Текст не на русском (нет кириллицы при латинице).
  languageNotRussian('language_not_russian'),

  /// `quote_ref` не найден в материале — цитата обнулена.
  quoteOutOfRange('quote_out_of_range'),

  /// `quote_ref` найден только после нормализации (пробелы/тире/регистр), но
  /// не буквально: offsets не восстанавливают текст.
  quoteNotLiteral('quote_not_literal'),

  /// `section_id` карточки не из разделов материала.
  sectionUnknown('section_unknown'),

  /// `unit_id` карточки не из единиц батча.
  unitUnknown('unit_unknown');

  const CardReasonCode(this.wireName);

  /// Машинный код причины.
  final String wireName;

  /// true, если код — причина отбрасывания, а не пометки.
  bool get isRejecting => switch (this) {
    missingRequiredField || unknownCardType || emptyFront => true,
    _ => false,
  };
}

/// Совпадение цитаты с диапазоном текста блока.
class QuoteMatch {
  /// Создаёт совпадение.
  const QuoteMatch({
    required this.blockId,
    required this.start,
    required this.end,
    required this.literal,
  }) : assert(blockId != '', 'У совпадения обязан быть блок'),
       assert(start >= 0, 'Начало не может быть отрицательным'),
       assert(end >= start, 'Конец не раньше начала');

  /// id блока `ContentModel`.
  final String blockId;

  /// Смещение начала цитаты в тексте документа (включительно).
  final int start;

  /// Смещение конца цитаты в тексте документа (исключительно).
  final int end;

  /// true — цитата совпала дословно; false — только после нормализации.
  final bool literal;

  /// Длина цитаты в UTF-16 code units.
  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuoteMatch &&
          other.blockId == blockId &&
          other.start == start &&
          other.end == end &&
          other.literal == literal;

  @override
  int get hashCode => Object.hash(blockId, start, end, literal);

  @override
  String toString() =>
      'QuoteMatch($blockId, $start..$end${literal ? '' : ', нормализовано'})';
}

/// Кандидат предпросмотра: карточка и её вердикт с причинами.
class CardCandidate {
  /// Создаёт кандидата.
  CardCandidate({
    required this.card,
    required this.verdict,
    List<CardReasonCode> reasons = const <CardReasonCode>[],
    this.quote,
  }) : assert(
         verdict != CardVerdict.rejected,
         'Отброшенная карточка не может быть кандидатом',
       ),
       reasons = List<CardReasonCode>.unmodifiable(reasons);

  /// Карточка домена (A8.4 + поля v3).
  final GeneratedCard card;

  /// `accepted` или `warning`.
  final CardVerdict verdict;

  /// Причины пометок в порядке объявления [CardReasonCode].
  final List<CardReasonCode> reasons;

  /// Совпадение цитаты с блоком (если цитата проверялась и найдена).
  final QuoteMatch? quote;

  /// true, если карточка помечена, но остаётся.
  bool get hasWarnings => verdict == CardVerdict.warning;

  /// true, если вердикт — `accepted`.
  bool get isAccepted => verdict == CardVerdict.accepted;

  @override
  String toString() => 'CardCandidate(${verdict.wireName}, $reasons)';
}

/// Отброшенная запись: исходный JSON сохранён для «показать отброшенные».
class RejectedCard {
  /// Создаёт запись.
  const RejectedCard({
    required this.index,
    required this.code,
    required this.raw,
  }) : assert(index >= 0, 'Индекс не может быть отрицательным');

  /// Номер записи в массиве `cards` ответа модели.
  final int index;

  /// Причина отбрасывания (всегда с кодом — TASK: «не удалять без
  /// reason_code»).
  final CardReasonCode code;

  /// Исходная запись ответа (объект или что угодно другое).
  final Object? raw;

  /// Исходная запись как карта, если это объект.
  Map<String, Object?>? get rawMap {
    final Object? value = raw;
    if (value is Map) return value.cast<String, Object?>();
    return null;
  }

  /// Лицевая сторона исходной записи, если она читается.
  String? get front {
    final Object? value = rawMap?['front'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  /// Обратная сторона исходной записи, если она читается.
  String? get back {
    final Object? value = rawMap?['back'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  @override
  String toString() => 'RejectedCard($index, ${code.wireName})';
}

/// Отчёт валидации ответа модели.
class CardValidationReport {
  /// Создаёт отчёт; списки копируются и становятся неизменяемыми.
  CardValidationReport({
    List<CardCandidate> candidates = const <CardCandidate>[],
    List<RejectedCard> rejected = const <RejectedCard>[],
  }) : candidates = List<CardCandidate>.unmodifiable(candidates),
       rejected = List<RejectedCard>.unmodifiable(rejected);

  /// Принятые и помеченные карточки в порядке ответа.
  final List<CardCandidate> candidates;

  /// Отброшенные записи в порядке ответа (не исчезают).
  final List<RejectedCard> rejected;

  /// Карточки для предпросмотра (принятые и помеченные).
  List<GeneratedCard> get cards => <GeneratedCard>[
    for (final CardCandidate candidate in candidates) candidate.card,
  ];

  /// Помеченные кандидаты.
  Iterable<CardCandidate> get warnings =>
      candidates.where((CardCandidate candidate) => candidate.hasWarnings);

  /// Сколько принято без пометок.
  int get acceptedCount => candidates.length - warningCount;

  /// Сколько помечено.
  int get warningCount => candidates
      .where((CardCandidate candidate) => candidate.hasWarnings)
      .length;

  /// Сколько отброшено.
  int get rejectedCount => rejected.length;

  /// true, если есть отброшенные записи.
  bool get hasRejects => rejected.isNotEmpty;

  /// Счётчики пометок по коду причины (только встреченные коды).
  Map<CardReasonCode, int> get warningCounts {
    final Map<CardReasonCode, int> counts = <CardReasonCode, int>{};
    for (final CardCandidate candidate in candidates) {
      for (final CardReasonCode reason in candidate.reasons) {
        counts[reason] = (counts[reason] ?? 0) + 1;
      }
    }
    return Map<CardReasonCode, int>.unmodifiable(counts);
  }

  @override
  String toString() =>
      'CardValidationReport(принято $acceptedCount, помечено $warningCount, '
      'отброшено $rejectedCount)';
}

/// Валидатор ответа модели: A8.4 + семантические эвристики + цитата.
class CardValidator {
  /// Создаёт валидатор.
  ///
  /// [latexChecker] — инъекция проверки LaTeX (по умолчанию `latexIsValid` из
  /// `latex_checker.dart`); в тестах можно подменить.
  const CardValidator({this.latexChecker});

  /// Проверка LaTeX-разметки текста; `null` — использовать `latexIsValid`.
  final bool Function(String text)? latexChecker;

  /// Максимальная длина `front` (SPEC A8.4).
  static const int maxFrontLength = 500;

  /// Максимальная длина `back` (SPEC A8.4).
  static const int maxBackLength = 2000;

  /// Максимальное число тегов (SPEC A8.4).
  static const int maxTags = 3;

  static final RegExp _clozePattern = RegExp(r'\{\{c\d+::.+?\}\}');
  static final RegExp _clozeFull = RegExp(r'\{\{c(\d+)::(.+?)\}\}');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _cyrillic = RegExp('[\u0400-\u04FF]');
  static final RegExp _latin = RegExp('[A-Za-z]');

  /// Перечисление: «1)», «2.», «а)» — пункты списка внутри стороны.
  static final RegExp _enumerationMarker = RegExp(
    r'(?:^|[\s(])(?:\d{1,2}[).](?![0-9])|[а-е][)](?=\s))',
    unicode: true,
  );

  /// Указательное слово в начале вопроса: вопрос несамостоятелен.
  static final RegExp _leadingReference = RegExp(
    r'^\s*(?:этот|эта|эти|тот|та|те|это|данный|данная|данное|данные|'
    r'указанный|названный|такой|такая|такое|такие)'
    r'(?=\s|$|[,.!?;:…—–-])',
    caseSensitive: false,
    unicode: true,
  );

  /// Указательное слово внутри вопроса как определение («этот процесс»).
  ///
  /// Граница слова — lookahead, а не `\b`: в ECMAScript-регексе Dart `\b`
  /// считает словом только ASCII и после кириллицы не срабатывает.
  static final RegExp _inlineReference = RegExp(
    r'(?:^|[\s(«"])(?:этот|эта|эти|тот|та|те|данн\p{L}+|указанн\p{L}+|'
    r'названн\p{L}+|вышеуказанн\p{L}+|нижеуказанн\p{L}+|предыдущ\p{L}+|'
    r'следующ\p{L}+)\s+\p{L}+',
    caseSensitive: false,
    unicode: true,
  );

  /// Ссылка на текст/рисунок вместо материала: «см.», «сказано выше»,
  /// «рис. 4». Голое «выше» намеренно не ловится: «давление выше уровня моря» —
  /// не ссылка на текст.
  static final RegExp _textualReference = RegExp(
    r'(?:^|[\s(])(?:см\.|смотри|§)'
    r'|(?:сказан|описан|указан|приведен|приведён|рассмотрен)\p{L}*\s+'
    r'(?:выше|ниже)'
    r'|(?:^|[\s(])(?:рис|табл)\.?\s*\d',
    caseSensitive: false,
    unicode: true,
  );

  /// Валидирует ответ модели `{"cards": [...]}`.
  ///
  /// [document] — модель материала для проверки цитаты по offsets (`null` —
  /// цитата не проверяется). [knownUnitIds]/[knownSectionIds] — id единиц и
  /// разделов партии: id вне набора помечается, но не принимается как факт.
  CardValidationReport validate(
    Object? json, {
    Document? document,
    Set<String> knownUnitIds = const <String>{},
    Set<String> knownSectionIds = const <String>{},
  }) {
    if (json is! Map) throw _invalidResponse();
    final Object? rawCards = json['cards'];
    if (rawCards is! List) throw _invalidResponse();

    final List<CardCandidate> candidates = <CardCandidate>[];
    final List<RejectedCard> rejected = <RejectedCard>[];
    for (var index = 0; index < rawCards.length; index++) {
      final Object? raw = rawCards[index];
      if (raw is! Map) {
        rejected.add(
          RejectedCard(
            index: index,
            code: CardReasonCode.missingRequiredField,
            raw: raw,
          ),
        );
        continue;
      }
      final CardCandidate? candidate = _validateCard(
        index: index,
        raw: raw.cast<String, Object?>(),
        document: document,
        knownUnitIds: knownUnitIds,
        knownSectionIds: knownSectionIds,
        rejected: rejected,
      );
      if (candidate != null) candidates.add(candidate);
    }
    return CardValidationReport(candidates: candidates, rejected: rejected);
  }

  /// Валидирует одну запись; `null` — запись отброшена (добавлена в [rejected]).
  CardCandidate? _validateCard({
    required int index,
    required Map<String, Object?> raw,
    required Document? document,
    required Set<String> knownUnitIds,
    required Set<String> knownSectionIds,
    required List<RejectedCard> rejected,
  }) {
    final Object? rawFront = raw['front'];
    final Object? rawBack = raw['back'];
    final Object? rawType = raw['card_type'];
    if (rawFront is! String || rawBack is! String || rawType is! String) {
      rejected.add(
        RejectedCard(
          index: index,
          code: CardReasonCode.missingRequiredField,
          raw: raw,
        ),
      );
      return null;
    }

    // SPEC A5: occlusion — разметка внутри basic, а не тип карточки.
    final bool isOcclusion = rawType == 'occlusion';
    final CardType cardType;
    if (isOcclusion) {
      cardType = CardType.basic;
    } else {
      try {
        cardType = CardType.fromWire(rawType);
      } on FormatException {
        rejected.add(
          RejectedCard(
            index: index,
            code: CardReasonCode.unknownCardType,
            raw: raw,
          ),
        );
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
    if (front.trim().isEmpty) {
      rejected.add(
        RejectedCard(index: index, code: CardReasonCode.emptyFront, raw: raw),
      );
      return null;
    }

    final List<CardReasonCode> reasons = <CardReasonCode>[];
    if (front.length > maxFrontLength) {
      reasons.add(CardReasonCode.frontTooLong);
    }
    if (back.length > maxBackLength) {
      reasons.add(CardReasonCode.backTooLong);
    }
    if (cardType == CardType.cloze) {
      if (!_clozePattern.hasMatch(front)) {
        reasons.add(CardReasonCode.clozeMissing);
      } else if (!_clozeIsMeaningful(front)) {
        reasons.add(CardReasonCode.clozeMeaningless);
      }
    }
    final bool Function(String) isLatexOk = latexChecker ?? latexIsValid;
    if (!isLatexOk(front) || !isLatexOk(back)) {
      reasons.add(CardReasonCode.latexBroken);
    }
    if (_looksNotRussian(front, back)) {
      reasons.add(CardReasonCode.languageNotRussian);
    }
    if (cardType != CardType.cloze && _answerAppearsInFront(front, back)) {
      reasons.add(CardReasonCode.answerInQuestion);
    }
    if (_questionNotSelfContained(front)) {
      reasons.add(CardReasonCode.questionNotSelfContained);
    }
    if (_enumerationCount(front) > 3 || _enumerationCount(back) > 3) {
      reasons.add(CardReasonCode.notAtomic);
    }

    final ({List<String> tags, bool adjusted}) tags = _normalizeTags(
      raw['tags'],
    );
    if (tags.adjusted) reasons.add(CardReasonCode.tagsAdjusted);

    final String? sectionId = _stringOrNull(raw['section_id']);
    final String? unitId = _stringOrNull(raw['unit_id']);
    if (sectionId != null &&
        knownSectionIds.isNotEmpty &&
        !knownSectionIds.contains(sectionId)) {
      reasons.add(CardReasonCode.sectionUnknown);
    }
    if (unitId != null &&
        knownUnitIds.isNotEmpty &&
        !knownUnitIds.contains(unitId)) {
      reasons.add(CardReasonCode.unitUnknown);
    }

    final String? quoteRef = _stringOrNull(raw['quote_ref']);
    QuoteMatch? quote;
    if (document != null && quoteRef != null) {
      quote = _findLiteralQuote(document, quoteRef);
      if (quote == null) {
        reasons.add(
          _hasNormalizedQuote(document, quoteRef)
              ? CardReasonCode.quoteNotLiteral
              : CardReasonCode.quoteOutOfRange,
        );
      }
    }

    reasons.sort(
      (CardReasonCode left, CardReasonCode right) =>
          left.index.compareTo(right.index),
    );
    final CardVerdict verdict = reasons.isEmpty
        ? CardVerdict.accepted
        : CardVerdict.warning;

    return CardCandidate(
      card: GeneratedCard(
        front: front,
        back: back,
        cardType: cardType,
        hint: _hintOf(raw['hint']),
        tags: tags.tags,
        sourceExcerpt: _stringOrNull(raw['source_excerpt']),
        sourceFile: _stringOrNull(raw['source_file']),
        issues: const <CardIssueCode>[],
        sectionId: sectionId,
        unitId: unitId,
        angle: _angleOf(raw['angle']),
        quoteRef: quoteRef,
        isOcclusion: isOcclusion,
      ),
      verdict: verdict,
      reasons: reasons,
      quote: quote,
    );
  }

  /// Теги: обрезать до 3, убрать пустые и `#` (A8.4); `adjusted` — были ли
  /// изменения.
  static ({List<String> tags, bool adjusted}) _normalizeTags(Object? rawTags) {
    final List<String> tags = <String>[];
    final List<String> inputTags = <String>[];
    if (rawTags is List) {
      for (final Object? rawTag in rawTags) {
        var tag = rawTag is String ? rawTag.trim() : '';
        while (tag.startsWith('#')) {
          tag = tag.substring(1).trim();
        }
        inputTags.add(tag);
        if (tag.isNotEmpty && tags.length < maxTags) tags.add(tag);
      }
    }
    var adjusted = inputTags.length != tags.length;
    if (!adjusted) {
      for (var index = 0; index < tags.length; index++) {
        if (inputTags[index] != tags[index]) {
          adjusted = true;
          break;
        }
      }
    }
    return (tags: List<String>.unmodifiable(tags), adjusted: adjusted);
  }

  /// Угол карточки: `primary` — основная (`null`), остальные — как есть.
  static String? _angleOf(Object? rawAngle) {
    if (rawAngle is! String) return null;
    final String angle = rawAngle.trim();
    if (angle.isEmpty || angle == 'primary') return null;
    return angle;
  }

  /// Подсказка: пустая — `null`, иначе с нормализованной LaTeX-разметкой.
  static String? _hintOf(Object? rawHint) {
    if (rawHint is! String || rawHint.trim().isEmpty) return null;
    return normalizeLatexDelimiters(repairLatexControlCharacters(rawHint));
  }

  /// Строка с обрезанными краями; пустая — `null`.
  static String? _stringOrNull(Object? value) {
    if (value is! String) return null;
    final String text = value.trim();
    return text.isEmpty ? null : text;
  }

  /// Буквальное совпадение цитаты с блоком: `substring(start, end) == quote`.
  static QuoteMatch? _findLiteralQuote(Document document, String quote) {
    for (final Block block in document.contentBlocks) {
      final int index = block.text.indexOf(quote);
      if (index < 0) continue;
      final int start = block.start + index;
      final int end = start + quote.length;
      if (document.text.substring(start, end) == quote) {
        return QuoteMatch(
          blockId: block.id,
          start: start,
          end: end,
          literal: true,
        );
      }
    }
    return null;
  }

  /// Почти-цитата: совпадает только после нормализации (пробелы/регистр/тире).
  ///
  /// Используется лишь для отличия `quoteNotLiteral` от `quoteOutOfRange`:
  /// offsets такой цитаты не восстанавливают текст, поэтому они не пишутся.
  static bool _hasNormalizedQuote(Document document, String quote) {
    const ContentNormalizer normalizer = ContentNormalizer();
    final String normalizedQuote = normalizer.normalize(quote).toLowerCase();
    if (normalizedQuote.isEmpty) return false;
    for (final Block block in document.contentBlocks) {
      final String normalizedBlock = normalizer
          .normalize(block.text)
          .toLowerCase();
      if (normalizedBlock.contains(normalizedQuote)) return true;
    }
    return false;
  }

  /// Вопрос несамостоятелен, если ссылается на текст/рисунок или начинается
  /// указательным словом без антецедента.
  static bool _questionNotSelfContained(String front) {
    return _leadingReference.hasMatch(front) ||
        _inlineReference.hasMatch(front) ||
        _textualReference.hasMatch(front);
  }

  /// Число пунктов перечисления: максимум из явных маркеров и частей через
  /// `;`.
  static int _enumerationCount(String text) {
    final int markers = _enumerationMarker.allMatches(text).length;
    final int parts = text
        .split(';')
        .where((String part) => part.trim().isNotEmpty)
        .length;
    return markers > parts ? markers : parts;
  }

  /// Осмысленный cloze: нумерация с `c1` подряд, пропуски непустые и разные,
  /// вокруг пропуска остаётся контекст.
  static bool _clozeIsMeaningful(String front) {
    final List<RegExpMatch> matches = _clozeFull.allMatches(front).toList();
    if (matches.isEmpty) return false;
    final List<int> numbers = <int>[
      for (final RegExpMatch match in matches)
        int.tryParse(match.group(1) ?? '') ?? -1,
    ];
    final List<int> sorted = List<int>.of(numbers)..sort();
    for (var index = 0; index < sorted.length; index++) {
      if (sorted[index] != index + 1) return false;
    }
    final List<String> bodies = <String>[
      for (final RegExpMatch match in matches)
        _normalizeForCompare(match.group(2) ?? ''),
    ];
    if (bodies.any((String body) => body.isEmpty)) return false;
    if (bodies.toSet().length != bodies.length) return false;
    final String context = _normalizeForCompare(
      front.replaceAll(_clozeFull, ' '),
    );
    return context.isNotEmpty;
  }

  /// Текст не на русском: нет ни одной кириллической буквы, но есть латиница.
  ///
  /// Формулы исключены (сравнивается «плоский» текст): карточка с одной
  /// формулой не получает пометку.
  static bool _looksNotRussian(String front, String back) {
    final String plain = _withoutFormulas('$front\n$back');
    if (_cyrillic.hasMatch(plain)) return false;
    return _latin.hasMatch(plain);
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

  /// Текст без формул `$…$`/`$$…$$`.
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
    return text.replaceAll(_whitespace, ' ').trim();
  }

  static GenerationException _invalidResponse() => const GenerationException(
    GenerationErrorCode.invalidResponse,
    details: 'Ответ модели не соответствует структуре карточек (A8.4)',
    failureReason: GenerationFailureReason.validatorRejected,
  );
}
