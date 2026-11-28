/// Машинный код причины вердикта карточки (A8.4 + семантические эвристики).
///
/// Код живёт в домене, а не в слое API: его возвращает гейт `CardGate`
/// (TASK «Срез 12», п. 1), он же доезжает до `GenerationReport` и
/// предпросмотра. Правила проверок по-прежнему в `CardValidator`
/// (`lib/api/generation/validation/`), который этот тип только использует.
library;

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

  /// Формула не парсится (A8.4). Жёсткий дефект среза 10: карточка с
  /// нечитаемой формулой не идёт в колоду (Q22).
  unparseableLatex('unparseable_latex'),

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

  /// Текст не на русском (нет кириллицы при латинице). Жёсткий дефект среза 10
  /// (`TASK.txt` п. 2): карточка не на языке колоды не идёт в колоду (Q22).
  wrongLanguage('wrong_language'),

  /// После нормализации не осталось ни букв, ни цифр хотя бы на одной стороне:
  /// учить нечего (`TASK.txt` срез 10, п. 2). Жёсткий дефект.
  emptyAfterNormalization('empty_after_normalization'),

  /// Цитаты нет, а у единицы знания нет якорей (prompt-only, `kind=topic`):
  /// проверить нечего, карточка помечается «без источника», но остаётся
  /// (`TASK.txt` срез 10, п. 3; Q22).
  quoteUnverified('quote_unverified'),

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

  /// true, если код — жёсткий дефект: карточка блокируется (`CardVerdict.blocked`).
  ///
  /// Список задан владельцем (`TASK.txt` срез 10, п. 2): цитата вне материала,
  /// ответ внутри вопроса, чужой язык, пустое после нормализации, нечитаемая
  /// формула. Остальные содержательные проверки A8.4 остаются пометками —
  /// «не отбрасывать молча» (A8.4) сохраняется для них.
  bool get isBlocking => switch (this) {
    quoteOutOfRange ||
    answerInQuestion ||
    wrongLanguage ||
    emptyAfterNormalization ||
    unparseableLatex => true,
    _ => false,
  };
}
