/// Распределение общего числа карточек по фрагментам (итерация fix-gen).
///
/// Если пользователь указал в пожеланиях общее число карточек («20 карточек»),
/// приложение распределяет его по фрагментам пропорционально объёму текста и
/// кладёт результат в `<limit>` каждого запроса. Если число не указано —
/// действует обычный лимит фрагмента. Чистые правила без Flutter.
library;

import 'package:cardflow/domain/generation/generation_chunker.dart';

/// Максимальное число, которое имеет смысл разбирать из пожеланий.
const int kMaxRequestedCards = 200;

/// Общее число карточек, указанное в пожеланиях; `null` — не указано.
///
/// Понимает «20 карточек», «сделайте 20 карточек», «около 15 карт», «20 cards».
/// Числа без слова «карточк*» не считаются количеством: «глава 3» не означает
/// три карточки.
int? requestedCardCount(String? wishes) {
  final String text = wishes?.trim() ?? '';
  if (text.isEmpty) return null;
  final List<RegExp> patterns = <RegExp>[
    RegExp(
      r'(\d{1,4})\s*(?:шт\.?\s*)?(?:карточ|карт(?=\s|$|[,.;:!?])|карт[аыу])',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(?:карточ\w*|cards?)\s*[:=\-—]?\s*(\d{1,4})',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(\d{1,4})\s*cards?(?=\s|$|[,.;:!?])',
      caseSensitive: false,
      unicode: true,
    ),
  ];
  for (final RegExp pattern in patterns) {
    final Match? match = pattern.firstMatch(text);
    if (match == null) continue;
    final int value = int.parse(match.group(1)!);
    if (value <= 0) continue;
    return value > kMaxRequestedCards ? kMaxRequestedCards : value;
  }
  return null;
}

/// Делит [total] карточек между фрагментами пропорционально [volumes].
///
/// Сумма результата равна [total] (если хватает на все фрагменты), ни один
/// фрагмент с текстом не получает 0, когда карточек не меньше, чем фрагментов,
/// и каждый лимит не больше [maxPerChunk].
List<int> distributeCardLimits({
  required List<int> volumes,
  required int total,
  int maxPerChunk = kMaxCardsPerChunk,
}) {
  if (volumes.isEmpty || total <= 0) {
    return List<int>.filled(volumes.length, 0);
  }
  final int capped = total > maxPerChunk * volumes.length
      ? maxPerChunk * volumes.length
      : total;
  final List<int> weights = <int>[
    for (final int volume in volumes) (volume < 0 ? 0 : volume),
  ];
  final int weightSum = weights.fold<int>(
    0,
    (int sum, int value) => sum + value,
  );
  final List<int> allocation = List<int>.filled(volumes.length, 0);
  if (weightSum == 0) {
    // Объёма нет (например, фрагмент без текста): делим поровну.
    var remaining = capped;
    for (var i = 0; i < volumes.length && remaining > 0; i++) {
      allocation[i] = 1;
      remaining--;
    }
    return allocation;
  }

  final List<double> fractions = List<double>.filled(volumes.length, 0);
  var assigned = 0;
  for (var i = 0; i < volumes.length; i++) {
    final double exact = capped * weights[i] / weightSum;
    final int base = exact.floor();
    allocation[i] = base;
    fractions[i] = exact - base;
    assigned += base;
  }
  final List<int> order = List<int>.generate(volumes.length, (int i) => i)
    ..sort((int a, int b) {
      final int byFraction = fractions[b].compareTo(fractions[a]);
      if (byFraction != 0) return byFraction;
      return weights[b].compareTo(weights[a]);
    });
  var index = 0;
  while (assigned < capped) {
    final int target = order[index % order.length];
    allocation[target]++;
    assigned++;
    index++;
  }

  // Каждый непустой фрагмент получает хотя бы одну карточку, если карточек
  // хватает: забираем у самого большого лимита.
  final int nonEmpty = weights.where((int weight) => weight > 0).length;
  if (capped >= nonEmpty) {
    for (var i = 0; i < volumes.length; i++) {
      if (weights[i] == 0 || allocation[i] > 0) continue;
      int largest = 0;
      for (var j = 1; j < allocation.length; j++) {
        if (allocation[j] > allocation[largest]) largest = j;
      }
      if (allocation[largest] > 1) {
        allocation[largest]--;
        allocation[i]++;
      }
    }
  }

  for (var i = 0; i < allocation.length; i++) {
    if (allocation[i] > maxPerChunk) allocation[i] = maxPerChunk;
  }
  return allocation;
}
