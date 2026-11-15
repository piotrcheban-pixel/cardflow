/// Производный поисковый запрос для иллюстрации (ADR-028, итерация 7.12).
///
/// Модель не всегда возвращает `image_query` (deepseek-flash на определениях
/// отдаёт `null`), но пользователь ждёт картинку. Для предметных вопросов вида
/// «Что такое спайность минерала?» запрос выводится из текста карточки: это
/// лучше, чем оставить карточку без иллюстрации. Чистые правила без Flutter/сети.
library;

import '../cards/card.dart';

/// Префиксы вопросов, из которых берётся предмет определения.
final List<RegExp> _definitionPrefixes = <RegExp>[
  RegExp(
    r'^(?:что\s+такое|что\s+называ(?:ется|ют)|что\s+понима(?:ют|ется)\s+под|'
    r'что\s+представля(?:ет|ют)\s+собой|как\s+называ(?:ется|ют)|'
    r'дай\s+определение|определение|понятие|what\s+is|what\s+are)\s+',
    caseSensitive: false,
    unicode: true,
  ),
];

/// «X — это …» / «X — …»: предмет определения стоит до тире.
final RegExp _definitionDash = RegExp(
  r'^(.+?)\s+[—–-]\s+(?:это\s+)?',
  unicode: true,
);

/// Хвостовая пунктуация и мусор, которые не нужны поисковику.
final RegExp _trailingNoise = RegExp(r'[\s?!.:;,«»"()]+$', unicode: true);

/// Пробелы подряд.
final RegExp _spaces = RegExp(r'\s+');

/// Максимум слов в производном запросе.
const int derivedImageQueryMaxWords = 8;

/// Максимум символов в производном запросе.
const int derivedImageQueryMaxLength = 80;

/// Возвращает поисковый запрос, выведенный из текста карточки, или `null`.
///
/// Правила (осознанно узкие, чтобы не искать картинку ко всему подряд):
/// - только `basic` (у `basic_reversed` две стороны одной карточки, у `cloze`
///   предмет вопроса размыт разметкой пропусков);
/// - вопрос должен выглядеть как определение: «Что такое X?», «Что называют
///   X?», «X — это …»;
/// - результат — до [derivedImageQueryMaxWords] слов и
///   [derivedImageQueryMaxLength] символов, без пунктуации по краям;
/// - чисто числовой/служебный текст запросом не становится.
String? derivedImageQuery({
  required String front,
  required String back,
  required CardType cardType,
}) {
  if (cardType != CardType.basic) return null;
  final String text = front.replaceAll(_spaces, ' ').trim();
  if (text.length < 6) return null;
  if (text.contains('{{')) return null;
  String? subject;
  for (final RegExp prefix in _definitionPrefixes) {
    final Match? match = prefix.firstMatch(text);
    if (match != null) {
      subject = text.substring(match.end);
      break;
    }
  }
  if (subject == null) {
    final Match? dash = _definitionDash.firstMatch(text);
    if (dash != null) subject = dash.group(1);
  }
  if (subject == null) return null;
  var query = subject.replaceAll(_trailingNoise, '').trim();
  if (query.isEmpty) return null;
  final List<String> words = query
      .split(_spaces)
      .where((String word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return null;
  query = words.take(derivedImageQueryMaxWords).join(' ');
  if (query.length > derivedImageQueryMaxLength) {
    query = query.substring(0, derivedImageQueryMaxLength).trim();
  }
  final bool hasLetter = RegExp(
    r'[A-Za-zА-Яа-яЁё]',
    unicode: true,
  ).hasMatch(query);
  if (!hasLetter || query.length < 3) return null;
  return query;
}

/// Пользователь запретил картинки в пожеланиях к генерации.
///
/// Промпт (правило 14) просит модель не добавлять `image_query` в этом случае;
/// производный запрос тоже не должен появляться.
bool wishesForbidImages(String? wishes) {
  if (wishes == null || wishes.trim().isEmpty) return false;
  final String value = wishes.toLowerCase();
  final List<RegExp> patterns = <RegExp>[
    RegExp(r'без\s+(?:картин|изображен|иллюстрац|фото)', unicode: true),
    RegExp(
      r'не\s+(?:добав|встав|ищ|рис)\S*\s+'
      r'(?:картин|изображен|иллюстрац|фото)',
      unicode: true,
    ),
    RegExp(r'без\s+картинок|no\s+(?:images?|pictures?|photos?)', unicode: true),
    RegExp(
      r"(?:don'?t|do\s+not)\s+(?:add|include|use|search)[^.!?]{0,30}"
      r'(?:image|picture|photo)',
      unicode: true,
    ),
  ];
  return patterns.any((RegExp pattern) => pattern.hasMatch(value));
}
