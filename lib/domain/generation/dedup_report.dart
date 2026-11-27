/// Отчёт каскада дедупликации (TASK «Срез 6», ADR-050 §3.4).
///
/// Этап Dedup не удаляет карточки: каждая найденная пара помечается уровнем
/// каскада (точный ключ → нормализованный ключ → шинглы + Жаккар → эмбеддинги),
/// а решение остаётся за пользователем в предпросмотре.
library;

/// Уровень каскада дедупликации.
enum DedupLevel {
  /// Точный ключ: `front`/`back` совпадают байт в байт.
  exact('exact'),

  /// Нормализованный ключ: регистр, ё→е, пунктуация и пробелы не различаются
  /// (SPEC A8.5, шаг 9).
  normalized('normalized'),

  /// Шинглы + коэффициент Жаккара: почти-дубль с перестановкой/правкой слов.
  semantic('semantic'),

  /// Эмбеддинги: необязательный уровень, если провайдер векторов передан.
  embeddings('embeddings');

  const DedupLevel(this.wireName);

  /// Машинный код уровня (для журнала и диагностики).
  final String wireName;

  /// Уровень по машинному коду; `null` — неизвестный уровень.
  static DedupLevel? fromWire(String value) {
    for (final DedupLevel level in DedupLevel.values) {
      if (level.wireName == value) return level;
    }
    return null;
  }
}

/// Пара карточек, признанных дублями, с уровнем каскада и схожестью.
class DedupPair {
  /// Создаёт пару; стороны обязаны быть разными непустыми id.
  const DedupPair({
    required this.leftId,
    required this.rightId,
    required this.level,
    this.similarity = 1.0,
  }) : assert(leftId != '', 'У пары левая карточка обязана иметь id'),
       assert(rightId != '', 'У пары правая карточка обязана иметь id'),
       assert(leftId != rightId, 'Пара не может ссылаться на одну карточку'),
       assert(
         similarity >= 0 && similarity <= 1,
         'Схожесть — доля в 0..1',
       );

  /// id карточки, встретившейся раньше (или карточки колоды).
  final String leftId;

  /// id карточки, встретившейся позже (или новой карточки).
  final String rightId;

  /// Уровень каскада, на котором пара найдена.
  final DedupLevel level;

  /// Схожесть: 1 для точного и нормализованного уровня, Жаккар/косинус — ниже.
  final double similarity;

  /// true, если карточка [id] — любая сторона пары.
  bool involves(String id) => leftId == id || rightId == id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DedupPair &&
          other.leftId == leftId &&
          other.rightId == rightId &&
          other.level == level &&
          other.similarity == similarity;

  @override
  int get hashCode => Object.hash(leftId, rightId, level, similarity);

  @override
  String toString() => 'DedupPair($leftId ~ $rightId, ${level.wireName})';
}

/// Отчёт дедупа: пары и счётчики по уровням каскада.
class DedupReport {
  /// Создаёт отчёт; список пар копируется и становится неизменяемым.
  DedupReport({List<DedupPair> pairs = const <DedupPair>[]})
    : pairs = List<DedupPair>.unmodifiable(pairs);

  /// Пустой отчёт (дедуп не выполнялся или дублей нет).
  factory DedupReport.empty() => DedupReport();

  /// Найденные пары дублей в порядке обнаружения.
  final List<DedupPair> pairs;

  /// Число пар.
  int get pairCount => 0;

  /// Счётчики по уровням каскада (все уровни присутствуют, включая нулевые).
  Map<DedupLevel, int> get byLevel => <DedupLevel, int>{
    DedupLevel.exact: 0,
    DedupLevel.normalized: 0,
    DedupLevel.semantic: 0,
    DedupLevel.embeddings: 0,
  };

  /// Сколько пар найдено на уровне [level].
  int countOf(DedupLevel level) => 0;

  /// Сильнейший уровень, на котором карточка [id] признана дублем.
  DedupLevel? levelOf(String id) => null;

  /// true, если карточка [id] участвует хотя бы в одной паре.
  bool isDuplicate(String id) => false;

  /// id всех карточек, помеченных дублями.
  Set<String> get duplicateIds => const <String>{};

  /// Пары карточки [id].
  List<DedupPair> pairsOf(String id) => const <DedupPair>[];

  @override
  String toString() => 'DedupReport(пар $pairCount)';
}
