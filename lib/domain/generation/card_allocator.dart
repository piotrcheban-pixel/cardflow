/// Card Allocator: распределение заказа по разделам по смысловой насыщенности
/// (ADR-040 §5).
///
/// Детерминированный water-filling: `weight = meaningfulTokens^0.8 × density`,
/// `capacity = ceil(meaningfulWords / 40 × density)`, метод наибольших остатков
/// с ограничением ёмкостью; `Σ = min(requested, Σcapacity)`. Служебные разделы
/// получают 0. Домен не зависит от Flutter.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/input_planner.dart' show SectionKind;
export 'package:cardflow/domain/generation/input_planner.dart' show SectionKind;

/// Признаки раздела для распределения (density/weight/capacity).
final class SectionFeatures {
  const SectionFeatures({
    required this.density,
    required this.meaningfulTokens,
    required this.meaningfulWords,
    required this.capacity,
    required this.service,
  });

  /// Оценивает признаки раздела по заголовку и тексту (ADR-040 §5).
  factory SectionFeatures.of({required String title, required String text}) {
    final String normalizedTitle = title.trim().toLowerCase();
    const List<String> serviceMarkers = <String>[
      'оглавление',
      'содержание',
      'список литературы',
      'литература',
      'библиография',
      'колонтитул',
      'источники',
    ];
    final bool service = serviceMarkers.any(
      (String marker) => normalizedTitle.startsWith(marker),
    );
    if (service) {
      return const SectionFeatures(
        density: 0,
        meaningfulTokens: 0,
        meaningfulWords: 0,
        capacity: 0,
        service: true,
      );
    }
    final List<String> words = _significantWords(text);
    final int meaningfulWords = math.max(1, words.length);
    final int meaningfulTokens = math.max(1, (text.runes.length / 2.5).ceil());
    final double density = estimateDensity(text, words: words);
    final int capacity = math.max(1, (meaningfulWords / 40 * density).ceil());
    return SectionFeatures(
      density: density,
      meaningfulTokens: meaningfulTokens,
      meaningfulWords: meaningfulWords,
      capacity: capacity,
      service: false,
    );
  }

  /// Насыщенность `[0, 1.5]`; у служебных разделов 0.
  final double density;

  /// Значимые токены (без обвязки).
  final int meaningfulTokens;

  /// Значимые слова.
  final int meaningfulWords;

  /// Мягкая ёмкость (сколько разных фактов можно извлечь).
  final int capacity;

  /// Служебный раздел (0 карточек).
  final bool service;

  /// Вес раздела `meaningfulTokens^0.8 × density` (ADR-040 §5).
  double get weight => math.pow(meaningfulTokens, 0.8).toDouble() * density;
}

const Set<String> _stopWords = <String>{
  'и',
  'в',
  'во',
  'не',
  'на',
  'с',
  'со',
  'как',
  'что',
  'это',
  'для',
  'по',
  'из',
  'к',
  'от',
  'до',
  'или',
  'а',
  'но',
  'же',
  'ли',
  'при',
  'над',
  'под',
  'без',
  'через',
  'между',
  'также',
  'если',
  'то',
};

List<String> _significantWords(String text) {
  final Iterable<Match> matches = RegExp(
    r'[A-Za-zА-Яа-яЁё0-9]{2,}',
    unicode: true,
  ).allMatches(text);
  final List<String> words = <String>[];
  for (final Match match in matches) {
    final String word = match.group(0)!.toLowerCase();
    if (_stopWords.contains(word)) continue;
    words.add(word);
  }
  return words;
}

/// Насыщенность по локальным признакам на 100 значимых слов.
double estimateDensity(String text, {List<String>? words}) {
  final List<String> significant = words ?? _significantWords(text);
  final int count = math.max(1, significant.length);
  var score = 0.0;
  final String lower = text.toLowerCase();
  const List<String> definitionMarkers = <String>[
    '— это',
    '– это',
    'называется',
    'понимают',
    'понимается',
    'определяется как',
    'является',
    'представляет собой',
  ];
  for (final String marker in definitionMarkers) {
    if (lower.contains(marker)) score += 2;
  }
  final int numbers = RegExp(r'\d+(?:[.,]\d+)?').allMatches(text).length;
  score += math.min(4, numbers / 2);
  final int formulas = RegExp(r'\$[^$]+\$').allMatches(text).length;
  score += math.min(3, formulas);
  final int listItems = RegExp(
    r'^\s*(?:[-–•*]|\d+[.)])\s',
    multiLine: true,
  ).allMatches(text).length;
  score += math.min(3, listItems / 2);
  final int tableRows = RegExp(r'\|.*\|').allMatches(text).length;
  score += math.min(2, tableRows / 3);
  final int latinTerms = significant
      .where((String word) => RegExp(r'^[a-z][a-z0-9-]+$').hasMatch(word))
      .length;
  score += math.min(3, latinTerms / 3);
  final double per100 = score / count * 100;
  return (0.5 + per100 / 40).clamp(0.5, 1.5).toDouble();
}

/// Раздел для распределения карточек.
final class AllocationSection {
  /// Создаёт раздел распределения.
  const AllocationSection({
    required this.id,
    this.title = '',
    this.weight = 1,
    this.capacity,
    this.kind = SectionKind.content,
    this.meaningfulTokens = 0,
    this.density = 1,
  }) : assert(id != ''),
       assert(weight >= 0),
       assert(capacity == null || capacity >= 0);

  /// Создаёт раздел из признаков текста.
  factory AllocationSection.fromFeatures({
    required String id,
    required String title,
    required SectionFeatures features,
  }) => AllocationSection(
    id: id,
    title: title,
    weight: features.service ? 0 : features.weight,
    capacity: features.service ? 0 : features.capacity,
    kind: features.service ? SectionKind.service : SectionKind.content,
    meaningfulTokens: features.meaningfulTokens,
    density: features.density,
  );

  /// Стабильный id раздела.
  final String id;

  /// Заголовок (для совпадений с пожеланиями).
  final String title;

  /// Вес раздела (`meaningfulTokens^0.8 × density`, с поправкой на пожелания).
  final double weight;

  /// Мягкая ёмкость (сколько разных фактов можно извлечь); `null` — без предела.
  final int? capacity;

  /// Служебный или содержательный раздел.
  final SectionKind kind;

  /// Значимые токены раздела.
  final int meaningfulTokens;

  /// Насыщенность `[0.5, 1.5]` (0 у служебных).
  final double density;

  /// Ёмкость для режима «авто»: подтверждённая или выведенная из текста.
  int effectiveCapacity() {
    final int? cap = capacity;
    if (cap != null) return cap;
    return math.max(1, (meaningfulTokens / 40).ceil());
  }
}

/// Результат распределения карточек по разделам.
final class CardAllocation {
  /// Создаёт распределение.
  CardAllocation({
    required Map<String, int> planned,
    required this.requested,
    required this.achievable,
    required this.belowRequested,
  }) : planned = Map<String, int>.unmodifiable(planned);

  /// Карточки по разделам (`id → число`), без отрицательных значений.
  final Map<String, int> planned;

  /// Заказ пользователя (`null` — «авто»).
  final int? requested;

  /// Сумма распределённых карточек.
  final int achievable;

  /// true, если материала не хватает на заказ.
  final bool belowRequested;

  /// Карточки, выделенные разделу (0, если раздела нет).
  int forSection(String id) => planned[id] ?? 0;

  /// Сумма распределённых карточек.
  int get total => achievable;

  /// Разделы, получившие хотя бы одну карточку, в порядке передачи.
  List<String> get sectionsWithCards => List<String>.unmodifiable(<String>[
    for (final MapEntry<String, int> entry in planned.entries)
      if (entry.value > 0) entry.key,
  ]);

  @override
  String toString() =>
      'CardAllocation(total: $achievable, requested: ${requested ?? 'auto'}, '
      'below: $belowRequested)';
}

/// Распределяет заказ карточек между разделами.
final class CardAllocator {
  /// Создаёт распределитель.
  const CardAllocator();

  /// Вес с поправкой на пожелания: совпадение заголовка по основе слова
  /// (первые 5 букв) умножает вес на 1.5.
  static double weightedForWishes(
    double weight,
    String title,
    Iterable<String> wishKeywords,
  ) {
    if (weight <= 0 || wishKeywords.isEmpty) return weight;
    final String normalized = title.toLowerCase();
    for (final String keyword in wishKeywords) {
      final String stem = _stem(keyword);
      if (stem.isEmpty) continue;
      for (final Match match in RegExp(
        r'[A-Za-zА-Яа-яЁё0-9]{2,}',
        unicode: true,
      ).allMatches(normalized)) {
        final String word = _stem(match.group(0)!);
        if (word.length >= 2 && word.startsWith(stem)) {
          return weight * 1.5;
        }
      }
    }
    return weight;
  }

  static String _stem(String value) {
    final String trimmed = value.toLowerCase().trim();
    if (trimmed.isEmpty) return '';
    return trimmed.length <= 5 ? trimmed : trimmed.substring(0, 5);
  }

  /// Распределяет [requestedCards] между [sections].
  ///
  /// `requestedCards == null` — «авто»: каждый раздел получает свою ёмкость.
  /// Заказ `≤ 0` — ошибка (невалидный ввод не превращается в 0 молча).
  CardAllocation allocate({
    required List<AllocationSection> sections,
    int? requestedCards,
  }) {
    if (requestedCards != null && requestedCards <= 0) {
      throw ArgumentError.value(
        requestedCards,
        'requestedCards',
        'Заказ карточек должен быть положительным',
      );
    }
    final Map<String, int> planned = <String, int>{
      for (final AllocationSection section in sections) section.id: 0,
    };
    final List<AllocationSection> items = <AllocationSection>[
      for (final AllocationSection section in sections)
        if (section.kind == SectionKind.content &&
            section.weight > 0 &&
            (section.capacity == null || section.capacity! > 0))
          section,
    ];
    if (items.isEmpty) {
      return CardAllocation(
        planned: planned,
        requested: requestedCards,
        achievable: 0,
        belowRequested: requestedCards != null && requestedCards > 0,
      );
    }
    if (requestedCards == null) {
      var total = 0;
      for (final AllocationSection section in items) {
        final int value = section.effectiveCapacity();
        planned[section.id] = value;
        total += value;
      }
      return CardAllocation(
        planned: planned,
        requested: null,
        achievable: total,
        belowRequested: false,
      );
    }

    final int requested = requestedCards;
    final bool unlimited = items.any(
      (AllocationSection section) => section.capacity == null,
    );
    final int totalCapacity = unlimited
        ? requested
        : items.fold<int>(
            0,
            (int sum, AllocationSection section) => sum + section.capacity!,
          );
    final int target = math.min(requested, totalCapacity);
    final Map<String, double> weights = <String, double>{
      for (final AllocationSection section in items) section.id: section.weight,
    };

    // Water-filling: пропорционально весам, ёмкости фиксируются.
    var remaining = target;
    final List<String> active = <String>[
      for (final AllocationSection section in items) section.id,
    ];
    while (remaining > 0 && active.isNotEmpty) {
      final double totalWeight = active.fold<double>(
        0,
        (double sum, String id) => sum + weights[id]!,
      );
      if (totalWeight <= 0) break;
      final Map<String, double> share = <String, double>{
        for (final String id in active)
          id: remaining * weights[id]! / totalWeight,
      };
      var added = 0;
      for (final String id in List<String>.of(active)) {
        final AllocationSection section = _sectionOf(items, id);
        final int? cap = section.capacity;
        final int room = cap == null ? remaining : cap - planned[id]!;
        final int take = math.min(share[id]!.floor(), math.max(0, room));
        if (take <= 0) continue;
        planned[id] = planned[id]! + take;
        added += take;
      }
      remaining -= added;
      active.removeWhere((String id) {
        final int? cap = _sectionOf(items, id).capacity;
        return cap != null && planned[id]! >= cap;
      });
      if (added == 0 && remaining > 0) {
        // Остаток — по наибольшей дробной части; равные доли — по порядку.
        final List<String> ordered = List<String>.of(active)
          ..sort((String a, String b) {
            final int byFraction = share[b]!
                .remainder(1)
                .compareTo(share[a]!.remainder(1));
            if (byFraction != 0) return byFraction;
            return active.indexOf(a).compareTo(active.indexOf(b));
          });
        for (final String id in ordered) {
          if (remaining == 0) break;
          final int? cap = _sectionOf(items, id).capacity;
          if (cap != null && planned[id]! >= cap) continue;
          planned[id] = planned[id]! + 1;
          remaining--;
        }
      }
    }

    // Минимум 1 при заказе ≥ числа значимых разделов.
    if (requested >= items.length) {
      for (final AllocationSection section in items) {
        if (planned[section.id]! > 0) continue;
        if (section.effectiveCapacity() < 1) continue;
        final String? donor = _largestDonor(items, planned);
        if (donor == null) break;
        planned[donor] = planned[donor]! - 1;
        planned[section.id] = 1;
      }
    }

    final int achievable = planned.values.fold<int>(0, (int a, int b) => a + b);
    return CardAllocation(
      planned: planned,
      requested: requested,
      achievable: achievable,
      belowRequested: achievable < requested,
    );
  }

  AllocationSection _sectionOf(List<AllocationSection> items, String id) =>
      items.firstWhere((AllocationSection section) => section.id == id);

  String? _largestDonor(
    List<AllocationSection> items,
    Map<String, int> planned,
  ) {
    String? donor;
    for (final AllocationSection section in items) {
      final int value = planned[section.id] ?? 0;
      if (value <= 1) continue;
      if (donor == null || value > planned[donor]!) donor = section.id;
    }
    return donor;
  }
}
