/// Каскад дедупликации карточек (TASK «Срез 6», ADR-050 §3.4).
///
/// Порядок уровней — от самого дешёвого и точного к приблизительному:
/// 1. **точный ключ** — `front`/`back` совпадают байт в байт;
/// 2. **нормализованный ключ** — регистр, ё→е, пунктуация и пробелы не
///    различаются (SPEC A8.5, шаг 9);
/// 3. **шинглы + коэффициент Жаккара** — почти-дубль с правкой/перестановкой
///    слов;
/// 4. **эмбеддинги** — только если передан [TextEmbeddingProvider]:
///    ML-зависимостей домен не тянет (TASK: «не тянуть ML-зависимости»).
///
/// Дубль **помечается парой**, а не удаляется: [SemanticMatcher.match]
/// возвращает [DedupReport], список карточек не меняется.
library;

import 'dart:math' show sqrt;

import 'package:cardflow/domain/generation/dedup_report.dart';

/// Карточка-кандидат для дедупа: id и тексты сторон.
class DedupCard {
  /// Создаёт карточку для сравнения.
  const DedupCard({required this.id, required this.front, required this.back})
    : assert(id != '', 'У карточки обязан быть id');

  /// Стабильный id карточки (id кандидата или карточки колоды).
  final String id;

  /// Лицевая сторона.
  final String front;

  /// Обратная сторона.
  final String back;

  /// Ключ точного уровня: стороны с разделителем `\u0000`.
  String get exactKey => '$front\u0000$back';

  /// Ключ нормализованного уровня: стороны нормализованы **по отдельности**,
  /// чтобы граница вопроса/ответа не склеивала слова.
  String get normalizedKey =>
      '${SemanticMatcher.normalizeForDedup(front)}\u0000'
      '${SemanticMatcher.normalizeForDedup(back)}';

  @override
  String toString() => 'DedupCard($id)';
}

/// Необязательный поставщик эмбеддингов (TASK: «за интерфейсом,
/// необязательны»): домен не знает, кто и как считает вектор.
abstract interface class TextEmbeddingProvider {
  /// Вектор текста; `null` — поставщик не умеет считать этот текст.
  List<double>? embed(String text);
}

/// Матчер каскада дедупликации.
class SemanticMatcher {
  /// Создаёт матчер.
  ///
  /// [shingleSize] — длина шингла (в символах нормализованного текста),
  /// [similarityThreshold] — порог Жаккара для уровня `semantic`,
  /// [embeddingThreshold] — порог косинуса для уровня `embeddings`,
  /// [embeddingProvider] — необязательный поставщик векторов.
  const SemanticMatcher({
    this.shingleSize = defaultShingleSize,
    this.similarityThreshold = 0.7,
    this.embeddingThreshold = 0.9,
    this.embeddingProvider,
  });

  /// Длина шингла по умолчанию.
  static const int defaultShingleSize = 3;

  /// Длина шингла (в символах).
  final int shingleSize;

  /// Порог Жаккара для почти-дублей.
  final double similarityThreshold;

  /// Порог косинуса для эмбеддингов.
  final double embeddingThreshold;

  /// Поставщик эмбеддингов; `null` — уровень `embeddings` выключен.
  final TextEmbeddingProvider? embeddingProvider;

  /// Ищет дубли: `cards` сравниваются между собой, `existing` — с колодой.
  ///
  /// Карточки `existing` идут в парах левой стороной (встретились раньше).
  /// Повтор id — [ArgumentError]: пара, ссылающаяся на неоднозначную сторону,
  /// не имеет смысла. Список карточек не меняется — возвращается только отчёт.
  DedupReport match(
    Iterable<DedupCard> cards, {
    Iterable<DedupCard> existing = const <DedupCard>[],
  }) {
    final List<DedupCard> known = existing.toList(growable: false);
    final List<DedupCard> incoming = cards.toList(growable: false);
    final List<DedupCard> all = <DedupCard>[...known, ...incoming];
    final Set<String> ids = <String>{};
    for (final DedupCard card in all) {
      if (!ids.add(card.id)) {
        throw ArgumentError.value(
          card.id,
          'cards',
          'Повтор id карточки: пара была бы неоднозначной',
        );
      }
    }

    final List<Set<String>> shingles = <Set<String>>[
      for (final DedupCard card in all)
        shinglesOf(
          card.front,
          size: shingleSize,
        ).union(shinglesOf(card.back, size: shingleSize)),
    ];
    final List<List<double>?>? vectors = embeddingProvider == null
        ? null
        : <List<double>?>[
            for (final DedupCard card in all)
              embeddingProvider!.embed(
                '${SemanticMatcher.normalizeForDedup(card.front)} '
                '${SemanticMatcher.normalizeForDedup(card.back)}',
              ),
          ];

    final List<DedupPair> pairs = <DedupPair>[];
    for (var right = 0; right < all.length; right++) {
      final DedupCard card = all[right];
      for (var left = 0; left < right; left++) {
        final DedupCard earlier = all[left];
        final DedupLevel? level = _levelOf(
          earlier,
          card,
          shingles[left],
          shingles[right],
          vectors?[left],
          vectors?[right],
        );
        if (level == null) continue;
        final double similarity = switch (level) {
          DedupLevel.exact || DedupLevel.normalized => 1.0,
          DedupLevel.semantic => jaccard(shingles[left], shingles[right]),
          DedupLevel.embeddings => cosineSimilarity(
            vectors![left] ?? const <double>[],
            vectors[right] ?? const <double>[],
          ),
        };
        pairs.add(
          DedupPair(
            leftId: earlier.id,
            rightId: card.id,
            level: level,
            similarity: similarity,
          ),
        );
      }
    }
    return DedupReport(pairs: pairs);
  }

  /// Сильнейший уровень каскада для пары; `null` — не дубли.
  ///
  /// Порядок — от точного к приблизительному: первый сработавший уровень и
  /// есть вердикт пары (каскад не понижает уровень).
  DedupLevel? _levelOf(
    DedupCard earlier,
    DedupCard card,
    Set<String> earlierShingles,
    Set<String> cardShingles,
    List<double>? earlierVector,
    List<double>? cardVector,
  ) {
    if (earlier.exactKey == card.exactKey) return DedupLevel.exact;
    if (earlier.normalizedKey == card.normalizedKey) {
      return DedupLevel.normalized;
    }
    if (jaccard(earlierShingles, cardShingles) >= similarityThreshold) {
      return DedupLevel.semantic;
    }
    if (earlierVector != null && cardVector != null) {
      if (cosineSimilarity(earlierVector, cardVector) >= embeddingThreshold) {
        return DedupLevel.embeddings;
      }
    }
    return null;
  }

  /// Нормализация для уровня `normalized`: регистр, ё→е, пунктуация, пробелы.
  static String normalizeForDedup(String text) {
    final String lowered = text.toLowerCase().replaceAll('ё', 'е');
    return lowered
        .replaceAll(_punctuation, ' ')
        .replaceAll(_spaceRun, ' ')
        .trim();
  }

  /// Шинглы нормализованного текста [text] длины [size].
  ///
  /// Текст короче шингла даёт один шингл — он сам (иначе короткие карточки
  /// сравнивать было бы нечем).
  static Set<String> shinglesOf(String text, {int size = defaultShingleSize}) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Длина шингла обязана быть > 0');
    }
    final String normalized = normalizeForDedup(text);
    if (normalized.isEmpty) return const <String>{};
    final List<int> runes = normalized.runes.toList(growable: false);
    if (runes.length <= size) return <String>{normalized};
    final Set<String> result = <String>{};
    for (var index = 0; index + size <= runes.length; index++) {
      result.add(String.fromCharCodes(runes, index, index + size));
    }
    return result;
  }

  /// Коэффициент Жаккара множеств шинглов.
  ///
  /// Пустые множества равны (1.0); пустое против непустого — 0.0.
  static double jaccard(Set<String> left, Set<String> right) {
    if (left.isEmpty && right.isEmpty) return 1.0;
    if (left.isEmpty || right.isEmpty) return 0.0;
    final int intersection = left.intersection(right).length;
    final int union = left.length + right.length - intersection;
    return union == 0 ? 1.0 : intersection / union;
  }

  /// Косинус между векторами; `0` — сравнивать нечем.
  static double cosineSimilarity(List<double> left, List<double> right) {
    if (left.isEmpty || right.isEmpty || left.length != right.length) {
      return 0.0;
    }
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }
    if (leftNorm == 0 || rightNorm == 0) return 0.0;
    return dot / (sqrt(leftNorm) * sqrt(rightNorm));
  }
}

/// Пунктуация и прочие не-буквы/не-цифры: для сравнения заменяются пробелом.
final RegExp _punctuation = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Пробельные серии (включая переводы строк).
final RegExp _spaceRun = RegExp(r'\s+');
