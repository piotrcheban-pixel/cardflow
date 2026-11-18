/// Запрос генерации без материалов (prompt-only, ADR-024).
///
/// Отдельный тип вместо пустого `ContentInventory`, пустого `TextPiece` или
/// фиктивного `ContentUnit`: у сценария «сгенерируй карточки по теме» нет
/// материалов по определению, и план обязан это фиксировать явно.
///
/// Тема и пожелания пользователя — единый текстовый запрос (в текущем UI это
/// поле «Дополнительные пожелания»); `requestedCards` — число карточек из
/// поля/пожеланий (без искусственного среза). Домен не зависит от Flutter.
library;

/// Запрос «сгенерируй карточки по теме» без прикреплённых файлов.
class PromptOnlyRequest {
  /// Создаёт запрос; [prompt] — тема/пожелания, [requestedCards] — заказ.
  const PromptOnlyRequest({required this.prompt, this.requestedCards})
    : assert(
        requestedCards == null || requestedCards > 0,
        'Заказ карточек должен быть положительным или null',
      );

  /// Тема и пожелания пользователя (единый запрос к модели).
  final String prompt;

  /// Сколько карточек запрошено; `null` — пользователь не указал число.
  final int? requestedCards;

  /// true, если тема пустая (после trim) — генерировать не по чему.
  bool get isEmpty => prompt.trim().isEmpty;

  @override
  String toString() =>
      'PromptOnlyRequest(${prompt.length} симв., '
      'cards: ${requestedCards ?? 'auto'})';
}
