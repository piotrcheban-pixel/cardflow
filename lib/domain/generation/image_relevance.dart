/// Проверка соответствия найденной картинки смыслу карточки.
///
/// Аудит 2.0 (P1-04): поиск по `image_query` модели возвращал любые совпадения
/// поисковой выдачи — к карточкам про надёжность теста приклеивались фото
/// зданий и чарты «What's Your Personality Type?». Провайдеры отдают метаданные
/// кандидата (заголовок файла/статьи, описание, теги), поэтому до скачивания
/// можно отсеять явно нерелевантное: если ни одно значимое слово запроса не
/// встречается в названии/описании, картинка не прикрепляется.
///
/// Библиотека чистая (без Flutter и HTTP) и тестируется отдельно: правило
/// одно для всех источников, а порог настраивается вызывающим.
library;

/// Минимальная доля значимых слов запроса, найденных в метаданных кандидата.
///
/// 0,5 означает «хотя бы половина слов запроса» — для однословного запроса это
/// одно совпадение. Значение выбрано так, чтобы фото здания не проходило для
/// запроса `test reliability` (одно слово из двух), а `leaf photosynthesis`
/// проходило для «Leaf structure» (одно из двух — ровно порог) — но при этом
/// мусорные выдачи с полностью другим смыслом отсекались.
const double kMinImageRelevance = 0.5;

/// Доля значимых слов запроса, найденных в [title]/[description].
///
/// * `1.0` — метаданных кандидата нет: судить не по чему, кандидат проходит
///   (провайдер без описаний не должен терять все картинки).
/// * `0.0` — ни одного значимого совпадения: картинка не про запрос.
double imageRelevanceScore({
  required String query,
  String? title,
  String? description,
}) {
  final Set<String> queryTokens = significantTokens(query);
  if (queryTokens.isEmpty) return 1;
  final Set<String> candidateTokens = significantTokens(
    '${title ?? ''} ${description ?? ''}',
  );
  if (candidateTokens.isEmpty) return 1;
  var hits = 0;
  for (final String token in queryTokens) {
    if (candidateTokens.any((String other) => _sameStem(token, other))) {
      hits++;
    }
  }
  return hits / queryTokens.length;
}

/// Проходит ли кандидат порог релевантности [threshold].
bool isImageRelevant({
  required String query,
  String? title,
  String? description,
  double threshold = kMinImageRelevance,
}) =>
    imageRelevanceScore(query: query, title: title, description: description) >=
    threshold;

/// Значимые слова текста: нижний регистр, длина ≥ 4, без стоп-слов.
///
/// Стоп-лист — не только служебные слова, но и «пустые» существительные
/// картинок (`photo`, `image`, `chart`, `type`, `test`): модель сама пишет в
/// промпте, что запрос не должен быть абстрактным, а поисковые движки любят
/// добавлять эти слова к любой выдаче. Без их удаления «test reliability»
/// совпадало бы с любым чартом «personality test».
Set<String> significantTokens(String text) {
  final String normalized = text.toLowerCase().replaceAll(
    RegExp(r'[^a-zа-яё0-9]+'),
    ' ',
  );
  final Set<String> tokens = <String>{};
  for (final String raw in normalized.split(' ')) {
    final String token = raw.trim();
    if (token.length < 4) continue;
    if (_stopWords.contains(token)) continue;
    tokens.add(token);
  }
  return tokens;
}

/// Совпадение по корню: `reliability` ≈ `reliable`, `photosynthesis` ≈
/// `photosynthetic` (общий префикс ≥ 5 символов).
bool _sameStem(String a, String b) {
  if (a == b) return true;
  final String shorter = a.length <= b.length ? a : b;
  final String longer = a.length <= b.length ? b : a;
  if (shorter.length < 4) return false;
  if (longer.startsWith(shorter)) return true;
  // Общий префикс ≥ 5 символов: «photosynthesis»/«photosynthetic».
  var common = 0;
  final int limit = shorter.length < longer.length
      ? shorter.length
      : longer.length;
  for (var index = 0; index < limit; index++) {
    if (shorter[index] != longer[index]) break;
    common++;
  }
  return common >= 5;
}

/// Служебные и «пустые» слова, которые не несут предметного смысла.
const Set<String> _stopWords = <String>{
  // русские
  'этот', 'эта', 'эти', 'того', 'чему', 'чем', 'какой', 'какая', 'какие',
  'который', 'которая', 'которые', 'если', 'чтобы', 'также', 'более', 'менее',
  'между', 'после', 'перед', 'через', 'около', 'вместе', 'очень', 'может',
  'можно', 'нужно', 'будет', 'были', 'было', 'есть', 'только', 'даже', 'себя',
  'свой', 'своя', 'свои', 'этом', 'этого', 'всех', 'всем', 'при', 'для', 'или',
  'как', 'что', 'это', 'его', 'она', 'они', 'оно', 'мы', 'вы', 'ты', 'же',
  // английские
  'this', 'that', 'these', 'those', 'with', 'from', 'into', 'over', 'under',
  'about', 'than', 'then', 'when', 'where', 'which', 'what', 'while', 'their',
  'there', 'here', 'have', 'has', 'had', 'will', 'would', 'should', 'could',
  'been', 'being', 'were', 'was', 'are', 'for', 'and', 'the', 'you', 'your',
  // «пустые» существительные картинок
  'photo', 'photos', 'image', 'images', 'picture', 'pictures', 'illustration',
  'diagram', 'diagrams', 'chart', 'charts', 'graph', 'graphs', 'icon', 'logo',
  'type', 'types', 'test', 'tests', 'testing', 'example', 'examples', 'concept',
  'abstract', 'general', 'common', 'typical', 'vector', 'clipart', 'drawing',
  'schematic', 'scheme', 'figure', 'figures', 'card', 'cards', 'sign', 'signs',
};
