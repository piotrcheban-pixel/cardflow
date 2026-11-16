/// Нормализация поля `image` ответа модели (итерация 7.14, схема `gen-ru-v6`).
///
/// Модель не всегда соблюдает правила промпта: присылает русские слова, слова
/// `image`/`photo of`, имена файлов, LaTeX, лишние слова или один запрос вместо
/// двух. Генерацию из-за этого не роняем: запрос чинится локально, а карточка
/// остаётся. Если починить нельзя — `query == null`, поиск не выполняется,
/// карточка получает заглушку (шаг 3 итерации).
///
/// Обратная совместимость: ответ `gen-ru-v5` содержит `image_query` строкой или
/// `null` — он тоже проходит через этот нормализатор (тип выводится из текста).
library;

import 'package:cardflow/domain/generation/card_image_kind.dart';

/// Нормализованная спецификация картинки карточки.
class NormalizedImageSpec {
  /// Создаёт спецификацию.
  const NormalizedImageSpec({
    this.query,
    this.fallbackQuery,
    this.kind = GeneratedCardImageKind.photo,
    this.adjusted = false,
    this.legacy = false,
  });

  /// Основной поисковый запрос; `null` — поиск невозможен/не задан.
  final String? query;

  /// Запасной, более общий запрос; `null` — не задан/не удалось собрать.
  final String? fallbackQuery;

  /// Вид иллюстрации.
  final GeneratedCardImageKind kind;

  /// Запрос пришлось нормализовать (пустой/не латиница/длиннее 7 слов/…).
  final bool adjusted;

  /// Спецификация получена из устаревшего `image_query` (v5).
  final bool legacy;

  /// Есть ли что искать.
  bool get hasQuery => query != null;

  @override
  String toString() =>
      'NormalizedImageSpec(query: $query, fallback: $fallbackQuery, '
      'kind: ${kind.wireName}, adjusted: $adjusted, legacy: $legacy)';
}

/// Максимум слов в основном запросе (A8.1, правило 7; схема `gen-ru-v6`).
const int kMaxImageQueryWords = 7;

/// Максимум слов в запасном запросе (`fallback_query`, 2–4 слова).
const int kMaxImageFallbackWords = 4;

/// Слова, которые нельзя нести в поисковый запрос: они ничего не уточняют.
const Set<String> _stopWords = <String>{
  'image',
  'images',
  'picture',
  'pictures',
  'photo',
  'photos',
  'pic',
  'pics',
  'img',
  'of',
  'the',
  'a',
  'an',
  'изображение',
  'картинка',
  'картинку',
  'фото',
};

/// Слова-контексты вида иллюстрации: их добавляем, если запрос из одного слова.
const Map<GeneratedCardImageKind, String> _kindContext =
    <GeneratedCardImageKind, String>{
      GeneratedCardImageKind.photo: 'photo',
      GeneratedCardImageKind.diagram: 'diagram',
      GeneratedCardImageKind.illustration: 'illustration',
    };

/// Абстрактные понятия: для v5-запроса выводим `illustration`.
final RegExp _abstractConcept = RegExp(
  r'аксиом|закон|теорем|определен|свойств|принцип|классификац|поняти|'
  r'термин|алгоритм|справедлив|равновеси|вероятност|порядок|время|'
  r'свобод[аы]|эффективност',
  caseSensitive: false,
  unicode: true,
);

/// Метафора в запросе: для v5-запроса выводим `illustration`.
final RegExp _illustrationConcept = RegExp(
  r'concept|metaphor|illustration|symbol|abstract',
  caseSensitive: false,
);

/// Процессы/структуры/формулы: для v5-запроса выводим `diagram`.
final RegExp _diagramConcept = RegExp(
  r'формул|процесс|структур|схем|график|зависимост|строени|ферм|'
  r'механизм|траектор|цикл|'
  r'diagram|scheme|chart|graph|process|structure|formula|free body|'
  r'circuit|anatomy',
  caseSensitive: false,
  unicode: true,
);

/// Разделитель слов: всё, кроме ASCII-букв, цифр, дефиса и апострофа.
final RegExp _wordSplit = RegExp(r"""[^A-Za-z0-9'\u002D]+""");

/// Нормализует поле `image` (v6) или `image_query` (v5).
///
/// [image] — значение ключа `image` (ожидается объект), [legacyQuery] —
/// значение `image_query`. Если передан объект `image`, его поля в приоритете;
/// [legacyQuery] нужен только для старых ответов.
NormalizedImageSpec normalizeImageSpec({
  Object? image,
  Object? legacyQuery,
  required String front,
  required String back,
}) {
  final Map<Object?, Object?>? spec = image is Map
      ? Map<Object?, Object?>.from(image)
      : null;
  final bool legacy = spec == null && legacyQuery is String;
  final String? rawQuery = spec != null
      ? _asString(spec['query'])
      : _asString(legacyQuery);
  final String? rawFallback = spec != null
      ? _asString(spec['fallback_query'])
      : null;
  final GeneratedCardImageKind kind =
      GeneratedCardImageKind.tryParse(spec?['kind']) ??
      _deriveKind(front, back, rawQuery);

  String? fallbackQuery = _normalizeWords(
    rawFallback,
    maxWords: kMaxImageFallbackWords,
  );
  // Нормализация изменила запасной запрос (лишние слова/не латиница/LaTeX).
  var adjusted = rawFallback != null && fallbackQuery != _collapse(rawFallback);

  String? query = _normalizeWords(rawQuery, maxWords: kMaxImageQueryWords);
  if (rawQuery != null && query != _collapse(rawQuery)) adjusted = true;

  // Пустой/испорченный основной запрос: собираем из запасного.
  if (query == null && fallbackQuery != null) {
    query = _padToMinimum(fallbackQuery, kind, maxWords: kMaxImageQueryWords);
    adjusted = true;
  }
  // Один запрос из одного слова: дополняем контекстом вида.
  if (query != null) {
    final String padded = _padToMinimum(
      query,
      kind,
      maxWords: kMaxImageQueryWords,
    );
    if (padded != query) {
      adjusted = true;
      query = padded;
    }
  }
  // Запасной запрос: более общий (2–4 слова), при пустом — из основного.
  if (fallbackQuery == null && query != null) {
    final List<String> words = query.split(' ');
    if (words.length >= 2) fallbackQuery = words.take(2).join(' ');
  } else if (fallbackQuery != null) {
    final String padded = _padToMinimum(
      fallbackQuery,
      kind,
      maxWords: kMaxImageFallbackWords,
    );
    if (padded != fallbackQuery) {
      adjusted = true;
      fallbackQuery = padded;
    }
  }
  if (fallbackQuery == query) fallbackQuery = null;
  return NormalizedImageSpec(
    query: query,
    fallbackQuery: fallbackQuery,
    kind: kind,
    adjusted: adjusted,
    legacy: legacy,
  );
}

/// Приводит строку к списку английских слов и обрезает до [maxWords].
///
/// Возвращает `null`, если после чистки не осталось ни одного слова.
String? _normalizeWords(String? raw, {required int maxWords}) {
  if (raw == null) return null;
  String text = raw
      .replaceAll(RegExp(r'\$[^$]*\$'), ' ')
      .replaceAll(RegExp(r'\\[a-zA-Z]+'), ' ')
      .replaceAll(RegExp(r'[{}]'), ' ')
      .replaceAll(RegExp(r'\b\S+\.(?:png|jpe?g|webp|svg|gif)\b'), ' ')
      .replaceAll(RegExp(r'https?://\S+'), ' ');
  final List<String> words = <String>[];
  final Set<String> seen = <String>{};
  for (final String token in text.toLowerCase().split(_wordSplit)) {
    final String word = token.replaceAll(RegExp(r"^[-']+|[-']+$"), '');
    if (word.isEmpty) continue;
    if (!RegExp(r"^[a-z][a-z0-9\-']*$").hasMatch(word)) continue;
    if (_stopWords.contains(word)) continue;
    if (word.length < 2) continue;
    if (!seen.add(word)) continue;
    words.add(word);
    if (words.length >= maxWords) break;
  }
  if (words.isEmpty) return null;
  return words.join(' ');
}

/// Дополняет запрос до двух слов контекстом вида иллюстрации.
String _padToMinimum(
  String query,
  GeneratedCardImageKind kind, {
  required int maxWords,
}) {
  final List<String> words = query.split(' ');
  if (words.length >= 2) return query;
  final String context = _kindContext[kind]!;
  if (!words.contains(context)) {
    words.add(context);
  } else {
    words.add('concept');
  }
  return words.take(maxWords).join(' ');
}

/// Выводит вид иллюстрации из текста карточки и запроса (ответ v5).
GeneratedCardImageKind _deriveKind(String front, String back, String? query) {
  final String text = '$front\n$back';
  final String searchable = '$text ${query ?? ''}';
  if (text.contains(r'$')) return GeneratedCardImageKind.diagram;
  if (_diagramConcept.hasMatch(searchable)) {
    return GeneratedCardImageKind.diagram;
  }
  if (_illustrationConcept.hasMatch(searchable)) {
    return GeneratedCardImageKind.illustration;
  }
  if (_abstractConcept.hasMatch(searchable)) {
    return GeneratedCardImageKind.illustration;
  }
  return GeneratedCardImageKind.photo;
}

/// Схлопывает пробелы (для сравнения «изменилось ли значение»).
String _collapse(String? value) =>
    value == null ? '' : value.replaceAll(RegExp(r'\s+'), ' ').trim();

String? _asString(Object? value) {
  if (value is! String) return null;
  return value;
}
