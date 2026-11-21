/// Изображения карточки по сторонам (`media_json` v2, итерация 7.19).
///
/// До 7.19 `cards.media_json` был плоским массивом id: одна иллюстрация на
/// карточку, которую `CardContentView` рисовал на **обеих** сторонах. С 7.19
/// сторона хранится в JSON, схема БД не меняется:
///
/// ```json
/// {"version": 2, "question": ["id…"], "answer": ["id…"]}
/// ```
///
/// Старый формат (`["id…"]`) читается как изображения **вопроса**: до 7.19
/// единственная иллюстрация показывалась на лицевой стороне, и это поведение
/// сохраняется для уже созданных карточек.
///
/// Домен не зависит от Flutter.
library;

import 'dart:convert';

/// Сторона карточки, к которой относится изображение.
enum CardMediaSide {
  /// Лицевая сторона (вопрос): видна до переворота.
  question('question'),

  /// Обратная сторона (ответ): видна только после переворота.
  answer('answer');

  const CardMediaSide(this.wireName);

  /// Значение в JSON/метаданных.
  final String wireName;

  /// Разбирает wire-значение; `null` — неизвестно.
  static CardMediaSide? tryParse(Object? value) {
    if (value is! String) return null;
    for (final CardMediaSide side in values) {
      if (side.wireName == value) return side;
    }
    return null;
  }
}

/// Коллекции изображений вопроса и ответа (`media_json` v2).
class CardMediaSides {
  /// Создаёт коллекции; элементы неизменяемы для вызывающего кода.
  const CardMediaSides({
    this.question = const <String>[],
    this.answer = const <String>[],
  });

  /// Версия формата `media_json`, которую пишет 7.19.
  static const int version = 2;

  /// Идентификаторы изображений лицевой стороны (порядок показа).
  final List<String> question;

  /// Идентификаторы изображений обратной стороны (порядок показа).
  final List<String> answer;

  /// Все id карточки: вопрос, затем ответ (порядок стабилен).
  List<String> get all => <String>[...question, ...answer];

  /// Обе коллекции пусты.
  bool get isEmpty => question.isEmpty && answer.isEmpty;

  /// Карточка с изображениями хотя бы одной стороны.
  bool get isNotEmpty => !isEmpty;

  /// JSON-представление v2.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'question': question,
    'answer': answer,
  };

  /// Сериализует в строку `media_json`.
  String encode() => jsonEncode(toJson());

  /// Стороны для legacy-массива (формат до 7.19 не хранил сторону).
  ///
  /// Безопасная политика 7.19: [stimulus] = true — изображение является
  /// холстом/стимулом вопроса (occlusion, cloze) и остаётся у вопроса; иначе
  /// сторона неизвестна, и изображение считается стороной **ответа**, чтобы
  /// не раскрывать ответ до переворота. Пользователь может перенести его в
  /// редакторе.
  static CardMediaSides fromLegacy(List<String> ids, {required bool stimulus}) {
    return CardMediaSides(
      question: stimulus ? List<String>.unmodifiable(ids) : const <String>[],
      answer: stimulus ? const <String>[] : List<String>.unmodifiable(ids),
    );
  }

  /// Читает `media_json` любого поддерживаемого формата.
  ///
  /// Бросает [FormatException], если значение не JSON или не поддерживаемая
  /// форма (битые данные не должны молча превращаться в «нет изображений»).
  static CardMediaSides decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is List) {
      // Legacy: плоский массив → сторона вопроса.
      return CardMediaSides(question: _stringsOf(decoded));
    }
    if (decoded is Map) {
      final Object? version = decoded['version'];
      if (version != null && version != CardMediaSides.version) {
        throw FormatException('Неизвестная версия media_json: $version');
      }
      final Object? question = decoded['question'];
      final Object? answer = decoded['answer'];
      if (question != null && question is! List) {
        throw const FormatException('media_json.question: ожидался массив');
      }
      if (answer != null && answer is! List) {
        throw const FormatException('media_json.answer: ожидался массив');
      }
      return CardMediaSides(
        question: question == null
            ? const <String>[]
            : _stringsOf(question as List),
        answer: answer == null ? const <String>[] : _stringsOf(answer as List),
      );
    }
    throw const FormatException('media_json: ожидался JSON-объект или массив');
  }

  /// Как [decode], но `null` вместо исключения (GC/диагностика).
  static CardMediaSides? tryDecode(String raw) {
    try {
      return decode(raw);
    } on FormatException {
      return null;
    }
  }

  /// Строковые элементы списка; нестроковые отбрасываются (совместимость).
  static List<String> _stringsOf(List<Object?> values) {
    return List<String>.unmodifiable(values.whereType<String>());
  }

  @override
  String toString() => 'CardMediaSides(question: $question, answer: $answer)';
}
