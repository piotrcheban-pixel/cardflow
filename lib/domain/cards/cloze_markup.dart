/// Текстовый фрагмент или пропуск cloze.
class ClozeSegment {
  const ClozeSegment.text(this.text) : number = null, answer = null;

  const ClozeSegment.gap({required this.number, required this.answer})
    : text = null;

  final String? text;
  final int? number;
  final String? answer;

  bool get isGap => number != null;
}

/// Пример синтаксиса для подсказки в форме карточки (находка F2 аудита).
///
/// Строка без кириллицы: её подставляет ARB-шаблон
/// `cardFormClozeHint({example})`, поэтому текст интерфейса остаётся
/// локализованным, а пример не дублируется в трёх местах.
const String clozeSyntaxExample = '{{c1::…}}';

/// Разобранная разметка `{{cN::ответ}}` (а также `{{ответ}}` — номер 1).
///
/// Находка F2: пользователь, не читавший исходников, писал `{{ответ}}` и
/// получал «Добавьте хотя бы один пропуск». Теперь формат без номера
/// принимается как первый пропуск: `{{Париж}}` ≡ `{{c1::Париж}}`. Строки,
/// похожие на испорченный нумерованный синтаксис (`{{c0::…}}`, `{{c::…}}`,
/// `{{c-1::…}}`, `{{c1::}}`), по-прежнему остаются обычным текстом.
class ClozeMarkup {
  const ClozeMarkup({required this.segments});

  final List<ClozeSegment> segments;

  bool get hasGaps => segments.any((segment) => segment.isGap);

  /// Нумерованный пропуск: `cN::текст`.
  static final RegExp _numbered = RegExp(r'^c([1-9]\d*)::([\s\S]+)$');

  /// Любая пара двойных фигурных скобок.
  static final RegExp _pattern = RegExp(r'\{\{([\s\S]+?)\}\}');

  static ClozeMarkup parse(String source) {
    final matches = _pattern.allMatches(source).toList(growable: false);
    if (matches.isEmpty) return _plain(source);
    final segments = <ClozeSegment>[];
    var cursor = 0;
    for (final match in matches) {
      final String content = match.group(1)!;
      final RegExpMatch? numbered = _numbered.firstMatch(content);
      final int number;
      final String answer;
      if (numbered != null) {
        number = int.parse(numbered.group(1)!);
        answer = numbered.group(2)!;
      } else if (_looksLikeBrokenNumbered(content)) {
        return _plain(source);
      } else {
        number = 1;
        answer = content;
      }
      if (answer.trim().isEmpty) return _plain(source);
      final String before = source.substring(cursor, match.start);
      if (_containsMarkup(before)) return _plain(source);
      if (before.isNotEmpty) segments.add(ClozeSegment.text(before));
      segments.add(ClozeSegment.gap(number: number, answer: answer));
      cursor = match.end;
    }
    final String after = source.substring(cursor);
    if (_containsMarkup(after)) return _plain(source);
    if (after.isNotEmpty) segments.add(ClozeSegment.text(after));
    return ClozeMarkup(segments: List<ClozeSegment>.unmodifiable(segments));
  }

  /// Испорченный вид нумерованного пропуска: `c::`, `c0::`, `c-1::`.
  static bool _looksLikeBrokenNumbered(String content) {
    if (!content.contains('::')) return false;
    final int index = content.indexOf('::');
    final String prefix = content.substring(0, index);
    return prefix.startsWith('c');
  }

  static bool _containsMarkup(String value) =>
      value.contains('{{') || value.contains('}}');

  static ClozeMarkup _plain(String source) =>
      ClozeMarkup(segments: <ClozeSegment>[ClozeSegment.text(source)]);
}
