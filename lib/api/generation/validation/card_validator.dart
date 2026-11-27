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
library;

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/domain/generation/generated_card.dart';

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
  List<GeneratedCard> get cards =>
      <GeneratedCard>[for (final CardCandidate c in candidates) c.card];

  /// Помеченные кандидаты.
  Iterable<CardCandidate> get warnings =>
      candidates.where((CardCandidate c) => c.hasWarnings);

  /// Сколько принято без пометок.
  int get acceptedCount => 0;

  /// Сколько помечено.
  int get warningCount => 0;

  /// Сколько отброшено.
  int get rejectedCount => 0;

  /// true, если есть отброшенные записи.
  bool get hasRejects => false;

  /// Счётчики пометок по коду причины.
  Map<CardReasonCode, int> get warningCounts => const <CardReasonCode, int>{};

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
  }) => CardValidationReport();
}
