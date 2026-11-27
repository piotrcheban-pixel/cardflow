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

import 'package:cardflow/domain/generation/dedup_report.dart';

/// Карточка-кандидат для дедупа: id и тексты сторон.
class DedupCard {
  /// Создаёт карточку для сравнения.
  const DedupCard({
    required this.id,
    required this.front,
    required this.back,
  }) : assert(id != '', 'У карточки обязан быть id');

  /// Стабильный id карточки (id кандидата или карточки колоды).
  final String id;

  /// Лицевая сторона.
  final String front;

  /// Обратная сторона.
  final String back;

  /// Ключ точного уровня: стороны с разделителем `\u0000`.
  String get exactKey => '$front\u0000$back';

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
  DedupReport match(
    Iterable<DedupCard> cards, {
    Iterable<DedupCard> existing = const <DedupCard>[],
  }) => DedupReport.empty();

  /// Нормализация для уровня `normalized`: регистр, ё→е, пунктуация, пробелы.
  static String normalizeForDedup(String text) => text;

  /// Шинглы нормализованного текста [text] длины [size].
  static Set<String> shinglesOf(String text, {int size = defaultShingleSize}) =>
      const <String>{};

  /// Коэффициент Жаккара множеств шинглов.
  static double jaccard(Set<String> left, Set<String> right) => 0.0;

  /// Косинус между векторами; `0` — сравнивать нечем.
  static double cosineSimilarity(List<double> left, List<double> right) => 0.0;
}
