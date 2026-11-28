/// Allocation — этап распределения заказа по единицам карты знаний и упаковка
/// в батчи под профиль модели (TASK «Срез 4», ADR-050).
///
/// Чистые функции: вес единицы (`salience × плотность × тип`), распределение
/// методом наибольших остатков, минимум одна карточка на отобранную единицу,
/// добор «вторым углом» (`reverse | cloze | application`) и упаковка батчей под
/// `ModelProfile.fitsBatch`. Без сети, БД и Flutter. Распределение не считает
/// символы: вес — смысловая насыщенность утверждения (плотность), а не длина.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';

/// Нижняя граница плотности единицы: разбавленное утверждение не обнуляет вес.
const double kMinUnitDensity = 0.25;

/// Множители вида единицы в весе (TASK: вес = salience × плотность × тип).
///
/// Определения и формулы — ядро любого раздела; процедуры и связи важнее
/// отдельных фактов, но не заменяют их.
const Map<KnowledgeUnitKind, double> kKnowledgeKindWeights =
    <KnowledgeUnitKind, double>{
      KnowledgeUnitKind.definition: 1.25,
      KnowledgeUnitKind.formula: 1.2,
      KnowledgeUnitKind.relation: 1.1,
      KnowledgeUnitKind.procedure: 1.05,
      KnowledgeUnitKind.fact: 1,
      // Тема prompt-only — единственная единица карты: вес не нулевой, иначе
      // план не построить (паритет с «фактом»).
      KnowledgeUnitKind.topic: 1,
    };

/// Постоянные накладные расходы запроса: системный промпт и инструкции.
const int kRequestOverheadTokens = 1200;

/// Накладные расходы JSON-схемы ответа (только при `supportsJsonSchema`).
const int kSchemaOverheadTokens = 900;

/// Оформление одной единицы в запросе (`<unit id=…>`, подписи якорей).
const int kUnitFramingTokens = 24;

/// Оценка вывода одной карточки (совпадает с `GenerationPlanningConfig`).
const int kDefaultOutputTokensPerCard = 300;

/// Слова, не несущие утверждения: плотность считается по остальным.
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
  'есть',
  'был',
  'была',
  'было',
  'быть',
  'будет',
  'может',
  'только',
  'чем',
  'тем',
  'так',
  'у',
  'о',
  'об',
  'за',
  'их',
  'его',
  'её',
  'они',
  'мы',
  'вы',
  'я',
  'ты',
  'он',
  'она',
  'оно',
  'этот',
  'эта',
  'эти',
  'тот',
  'та',
  'те',
  'всё',
  'все',
  'весь',
  'про',
  'чтобы',
  'когда',
  'где',
  'который',
  'которая',
  'которое',
  'которые',
  'поэтому',
};

/// Слово утверждения: буквы и цифры (формулы вида `PV`, `nRT` — тоже слова).
final RegExp _wordPattern = RegExp(r'[A-Za-zА-Яа-яЁё0-9]+');

/// Потолок различимых слотов единицы: основная карточка (`null`) и три угла.
///
/// Больше четырёх вопросов об одном утверждении план не заказывает: повтор
/// слота `unit_id + angle` — не новая карточка, а тот же вопрос (TASK «Срез 14»,
/// часть 1). Это **потолок**, а не норма: сколько углов единица выдерживает,
/// решает [unitCapacity] по её богатству (TASK «Срез 16», часть 3).
const int kMaxCardsPerUnit = 4;

/// Порог значимости «богатой» единицы: одна значимая мысль стоит второго угла.
const double kRichSalience = 0.8;

/// Порог числа утверждений/клауз в якорях: составное утверждение стоит угла.
const int kRichClaims = 3;

/// Минимум слов в клаузе, чтобы считать её отдельным утверждением.
const int kMinClaimWords = 3;

/// Число утверждений/клауз в тексте: предложения и части через `;`, `,`.
///
/// Считаются только содержательные клаузы (≥ [kMinClaimWords] слов): запятая в
/// перечислении и короткая вставка утверждением не являются. Это признак
/// богатства единицы, а не длины текста.
int claimCountOf(String text) {
  final List<String> segments = text.split(RegExp(r'[.!?…;]|,(?=\s)'));
  var count = 0;
  for (final String segment in segments) {
    if (_wordPattern.allMatches(segment).length >= kMinClaimWords) count++;
  }
  return count;
}

/// Число утверждений в якорях единицы (или в её утверждении, если якорей нет).
int unitClaimCount(KnowledgeUnit unit) {
  var claims = 0;
  for (final KnowledgeAnchor anchor in unit.anchors) {
    claims += claimCountOf(anchor.quote);
  }
  if (claims == 0) claims = claimCountOf(unit.statement);
  return claims;
}

/// Ёмкость единицы по богатству утверждения (TASK «Срез 16», часть 3).
///
/// Одна карточка — всегда; второй-четвёртый угол заказываются только за
/// признак богатства, а не «за объём»:
/// - значимость ≥ [kRichSalience] — утверждение стоит отдельного вопроса;
/// - составной якорь (≥ [kRichClaims] утверждений/клауз) — из него выходит
///   больше одного вопроса без повтора;
/// - формула или процедура — есть что применять и что пропускать.
///
/// Короткий факт (одна клауза, средняя значимость) получает 1–2 карточки, а не
/// четыре: прежняя константа 4 заказывала вопросы, которых в материале нет, и
/// модель отвечала дублями.
int unitCapacity(KnowledgeUnit unit) {
  var capacity = 1;
  if (unit.salience >= kRichSalience) capacity++;
  if (unitClaimCount(unit) >= kRichClaims) capacity++;
  if (unit.kind == KnowledgeUnitKind.formula ||
      unit.kind == KnowledgeUnitKind.procedure) {
    capacity++;
  }
  return math.min(capacity, kMaxCardsPerUnit);
}

/// Угол доборной карточки: та же единица знания, другой вопрос.
///
/// Угол — директива плана, а не текст карточки: модель формулирует её иначе,
/// поэтому дословного повтора утверждения доборная карточка не заказывает.
enum AllocationAngle {
  /// Обратная карточка (термин ↔ определение, следствие → причина).
  reverse('reverse'),

  /// Пропуск в утверждении (cloze).
  cloze('cloze'),

  /// Применение: задача на то же правило или формулу.
  application('application');

  /// Создаёт угол с wire-именем.
  const AllocationAngle(this.wireName);

  /// Wire-имя угла для промпта и журнала.
  final String wireName;
}

/// Плотность единицы: доля значимых слов в утверждении (0..1, пол 0,25).
///
/// Отношение, а не длина: служебные слова не делают утверждение богаче, а
/// короткая формула `PV = nRT` не проигрывает длинной фразе из предлогов.
double unitDensity(KnowledgeUnit unit) {
  final List<String> words = <String>[
    for (final RegExpMatch match in _wordPattern.allMatches(unit.statement))
      match[0]!.toLowerCase(),
  ];
  if (words.isEmpty) return kMinUnitDensity;
  final int significant = words
      .where((String word) => !_stopWords.contains(word))
      .length;
  final double ratio = significant / words.length;
  return ratio < kMinUnitDensity ? kMinUnitDensity : ratio;
}

/// Множитель вида единицы в весе.
double kindWeight(KnowledgeUnitKind kind) => kKnowledgeKindWeights[kind]!;

/// Вес единицы: `salience × плотность × тип`.
///
/// Единица с нулевым весом (модель поставила `salience: 0`) в распределение не
/// попадает: это «не карточкообразующее» утверждение, а не материал.
double unitWeight(KnowledgeUnit unit) =>
    unit.salience * unitDensity(unit) * kindWeight(unit.kind);

/// Предпочтительный угол добора по виду единицы.
///
/// Определение удобно проверять с обратной стороны, формулу и факт — пропуском,
/// порядок действий — применением.
AllocationAngle preferredAngleForKind(KnowledgeUnitKind kind) => switch (kind) {
  KnowledgeUnitKind.definition => AllocationAngle.reverse,
  KnowledgeUnitKind.fact => AllocationAngle.cloze,
  KnowledgeUnitKind.relation => AllocationAngle.reverse,
  KnowledgeUnitKind.formula => AllocationAngle.cloze,
  KnowledgeUnitKind.procedure => AllocationAngle.application,
  KnowledgeUnitKind.topic => AllocationAngle.reverse,
};

/// Порядок углов единицы: предпочтительный по виду, затем остальные.
///
/// Нужен повтору на слот, у которого кандидат оказался смысловым дублем (срез
/// 16): следующий запрос идёт с первым свободным углом этого порядка, а не с
/// тем же вопросом.
List<AllocationAngle> angleCycleFor(KnowledgeUnit unit) {
  final AllocationAngle preferred = preferredAngleForKind(unit.kind);
  return <AllocationAngle>[
    preferred,
    for (final AllocationAngle angle in AllocationAngle.values)
      if (angle != preferred) angle,
  ];
}

/// Распределение заказа по единицам: минимум 1 карточка каждой отобранной,
/// остаток — методом наибольших остатков по весам.
///
/// Когда заказ больше числа единиц, остаток — добор «вторым углом»; когда
/// меньше, отбираются самые весомые единицы (при равенстве — раньше в карте).
/// Добор ограничен ёмкостью единицы ([kMaxCardsPerUnit]): сумма карточек равна
/// `min(заказ, ёмкость)`, а не заказу — повторять занятый слот план не может
/// (TASK «Срез 14», часть 1). Недобор до заказа показывается планом, а не
/// прячется в повторе вопросов.
List<UnitBudget> allocateUnits({
  required List<KnowledgeUnit> units,
  required int requestedCards,
}) {
  if (requestedCards <= 0) {
    throw ArgumentError.value(
      requestedCards,
      'requestedCards',
      'Заказ карточек должен быть положительным',
    );
  }
  final List<KnowledgeUnit> selected = <KnowledgeUnit>[
    for (final KnowledgeUnit unit in units)
      if (unitWeight(unit) > 0) unit,
  ];
  if (selected.isEmpty) return const <UnitBudget>[];
  if (requestedCards < selected.length) {
    // Отбор: самые весомые единицы, при равном весе — раньше в карте.
    final List<int> order =
        List<int>.generate(selected.length, (int index) => index)
          ..sort((int a, int b) {
            final int byWeight = unitWeight(selected[b])
                .compareTo(unitWeight(selected[a]));
            return byWeight != 0 ? byWeight : a.compareTo(b);
          });
    final Set<int> chosen = order.take(requestedCards).toSet();
    return <UnitBudget>[
      for (var index = 0; index < selected.length; index++)
        if (chosen.contains(index)) UnitBudget(unit: selected[index], cards: 1),
    ];
  }
  final int extra = requestedCards - selected.length;
  final List<int> caps = <int>[
    for (final KnowledgeUnit unit in selected) unitCapacity(unit) - 1,
  ];
  final int capacityExtra = caps.fold<int>(0, (int sum, int cap) => sum + cap);
  final int sharesTotal = math.min(extra, capacityExtra);
  final List<int> shares = _largestRemainderBounded(sharesTotal, <double>[
    for (final KnowledgeUnit unit in selected) unitWeight(unit),
  ], caps);
  return <UnitBudget>[
    for (var index = 0; index < selected.length; index++)
      UnitBudget(unit: selected[index], cards: 1 + shares[index]),
  ];
}

/// Ёмкость плана по различимым слотам: `Σ min(карточек единицы, её ёмкость)`.
///
/// Это верхняя граница числа карточек, которое план может заказать: у единицы
/// не больше [unitCapacity] различных вопросов (`unit_id + angle`), и «богатая»
/// единица их не растягивает до [kMaxCardsPerUnit] по умолчанию (срез 16).
int allocationCapacity(Iterable<UnitBudget> units) => units.fold<int>(
  0,
  (int sum, UnitBudget budget) =>
      sum + math.min(budget.cards, unitCapacity(budget.unit)),
);

/// Разворачивает бюджеты в карточки: основная (`angle == null`) и доборные
/// «вторым углом».
///
/// Порядок карточек детерминирован: единицы — в порядке карты, внутри единицы —
/// основная, затем углы циклом от предпочтительного.
List<AllocatedCard> allocateCards(List<UnitBudget> budgets) {
  final List<AllocatedCard> cards = <AllocatedCard>[];
  for (final UnitBudget budget in budgets) {
    cards.add(AllocatedCard(unitId: budget.unit.id));
    if (budget.cards <= 1) continue;
    final AllocationAngle preferred = preferredAngleForKind(budget.unit.kind);
    for (var extra = 0; extra < budget.cards - 1; extra++) {
      cards.add(
        AllocatedCard(
          unitId: budget.unit.id,
          angle: _angleAt(preferred, extra),
        ),
      );
    }
  }
  return List<AllocatedCard>.unmodifiable(cards);
}

/// Упаковка карточек в батчи: вход + оценка выхода ≤ бюджета профиля.
///
/// Вход батча считается **по единицам** (утверждение, якоря, оформление и
/// обвязка запроса): карточки одной единицы делят вход. Не влезает следующая
/// карточка — батч закрывается, и начинается следующий; цель не уменьшается.
/// Одна карточка, не влезающая в бюджет профиля, — ошибка: материал больше
/// запроса, и молча терять его нельзя.
List<AllocationBatch> packBatches({
  required List<UnitBudget> units,
  required List<AllocatedCard> cards,
  required ModelProfile profile,
  TokenEstimator estimator = const TokenEstimator(),
  int outputTokensPerCard = kDefaultOutputTokensPerCard,
}) {
  if (outputTokensPerCard <= 0) {
    throw ArgumentError.value(
      outputTokensPerCard,
      'outputTokensPerCard',
      'Оценка вывода карточки должна быть положительной',
    );
  }
  if (cards.isEmpty) return const <AllocationBatch>[];
  final Map<String, int> unitTokens = <String, int>{
    for (final UnitBudget budget in units)
      budget.unit.id: _unitInputTokens(budget.unit, estimator),
  };
  for (final AllocatedCard card in cards) {
    if (!unitTokens.containsKey(card.unitId)) {
      throw ArgumentError.value(
        card.unitId,
        'cards',
        'Карточка ссылается на единицу вне карты',
      );
    }
  }
  final int fixedInput =
      kRequestOverheadTokens +
      (profile.supportsJsonSchema ? kSchemaOverheadTokens : 0);
  final List<AllocationBatch> batches = <AllocationBatch>[];
  var batchCards = <AllocatedCard>[];
  var batchUnits = <String>{};
  var batchUnitTokens = 0;

  void closeBatch() {
    batches.add(
      AllocationBatch(
        index: batches.length,
        profile: profile,
        cards: batchCards,
        inputTokens: fixedInput + batchUnitTokens,
        outputTokens: batchCards.length * outputTokensPerCard,
      ),
    );
    batchCards = <AllocatedCard>[];
    batchUnits = <String>{};
    batchUnitTokens = 0;
  }

  int inputWith(AllocatedCard card) =>
      fixedInput +
      batchUnitTokens +
      (batchUnits.contains(card.unitId) ? 0 : unitTokens[card.unitId]!);

  for (final AllocatedCard card in cards) {
    final int output = (batchCards.length + 1) * outputTokensPerCard;
    if (batchCards.isNotEmpty &&
        !profile.fitsBatch(
          inputTokens: inputWith(card),
          outputTokens: output,
        )) {
      closeBatch();
    }
    final int input = inputWith(card);
    final int singleOutput = (batchCards.length + 1) * outputTokensPerCard;
    if (batchCards.isEmpty &&
        !profile.fitsBatch(inputTokens: input, outputTokens: singleOutput)) {
      throw ArgumentError.value(
        card.unitId,
        'cards',
        'Единица не влезает в бюджет одного батча профиля ${profile.id}',
      );
    }
    if (!batchUnits.contains(card.unitId)) {
      batchUnits.add(card.unitId);
      batchUnitTokens += unitTokens[card.unitId]!;
    }
    batchCards.add(card);
  }
  if (batchCards.isNotEmpty) closeBatch();
  return List<AllocationBatch>.unmodifiable(batches);
}

/// Строит полный план этапа Allocation для карты знаний.
///
/// Один вход (карта + заказ + профиль) даёт один план: ни времени, ни
/// случайности в правилах нет.
AllocationPlan planAllocation({
  required KnowledgeMap map,
  required int requestedCards,
  required ModelProfile profile,
  TokenEstimator estimator = const TokenEstimator(),
  int outputTokensPerCard = kDefaultOutputTokensPerCard,
}) {
  final List<UnitBudget> budgets = allocateUnits(
    units: map.units,
    requestedCards: requestedCards,
  );
  final List<AllocatedCard> cards = allocateCards(budgets);
  return AllocationPlan(
    requested: requestedCards,
    profile: profile,
    units: budgets,
    cards: cards,
    batches: packBatches(
      units: budgets,
      cards: cards,
      profile: profile,
      estimator: estimator,
      outputTokensPerCard: outputTokensPerCard,
    ),
  );
}

/// true — у карточек плана нет двух одинаковых ключей слота.
bool _slotsAreUnique(List<AllocatedCard> cards) {
  final Set<String> seen = <String>{};
  for (final AllocatedCard card in cards) {
    if (!seen.add(card.slotKey)) return false;
  }
  return true;
}

/// Делит [total] по [weights] методом наибольших остатков, не больше
/// `caps[index]` на элемент.
///
/// Сначала считается обычная раздача наибольших остатков; превысившие свой
/// предел доли обрезаются, а остаток раздаётся по одной карточке в порядке
/// убывания веса (при равном весе — раньше в карте). Детерминизм сохраняется:
/// один вход — один результат. Нужен, чтобы добор «вторым углом» не повторял
/// занятые слоты единицы и не превышал её ёмкость ([unitCapacity]).
List<int> _largestRemainderBounded(
  int total,
  List<double> weights,
  List<int> caps,
) {
  final List<int> shares = _largestRemainder(total, weights);
  var capped = false;
  for (var index = 0; index < shares.length; index++) {
    if (shares[index] > caps[index]) {
      shares[index] = caps[index];
      capped = true;
    }
  }
  if (!capped) return shares;
  var left = total - shares.fold<int>(0, (int sum, int share) => sum + share);
  if (left <= 0) return shares;
  final List<int> order = List<int>.generate(weights.length, (int a) => a)
    ..sort((int a, int b) {
      final int byWeight = weights[b].compareTo(weights[a]);
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  while (left > 0) {
    var placed = false;
    for (final int index in order) {
      if (left == 0) break;
      if (shares[index] >= caps[index]) continue;
      shares[index]++;
      left--;
      placed = true;
    }
    if (!placed) break;
  }
  return shares;
}

/// Делит [total] по [weights] методом наибольших остатков.
///
/// Точная арифметика: вес масштабируется до `BigInt`, поэтому произведение
/// «заказ × вес» не переполняется и сумма долей всегда равна [total].
List<int> _largestRemainder(int total, List<double> weights) {
  final List<int> shares = List<int>.filled(weights.length, 0);
  if (total <= 0) return shares;
  final List<BigInt> scaled = <BigInt>[
    for (final double weight in weights)
      BigInt.from(math.max(1, (weight * 1000).round())),
  ];
  final BigInt totalWeight = scaled.fold<BigInt>(
    BigInt.zero,
    (BigInt sum, BigInt value) => sum + value,
  );
  final BigInt bigTotal = BigInt.from(total);
  final List<BigInt> products = <BigInt>[
    for (final BigInt value in scaled) bigTotal * value,
  ];
  var distributed = 0;
  for (var index = 0; index < weights.length; index++) {
    shares[index] = (products[index] ~/ totalWeight).toInt();
    distributed += shares[index];
  }
  var left = total - distributed;
  if (left <= 0) return shares;
  final List<int> order =
      List<int>.generate(weights.length, (int index) => index)
        ..sort((int a, int b) {
          final int byRemainder = (products[b] % totalWeight).compareTo(
            products[a] % totalWeight,
          );
          return byRemainder != 0 ? byRemainder : a.compareTo(b);
        });
  for (final int index in order) {
    if (left <= 0) break;
    shares[index]++;
    left--;
  }
  return shares;
}

/// Угол на позиции [index] в цикле от предпочтительного.
AllocationAngle _angleAt(AllocationAngle preferred, int index) {
  final List<AllocationAngle> cycle = <AllocationAngle>[
    preferred,
    for (final AllocationAngle angle in AllocationAngle.values)
      if (angle != preferred) angle,
  ];
  return cycle[index % cycle.length];
}

/// Оценка входа единицы: оформление, утверждение и дословные якоря.
int _unitInputTokens(KnowledgeUnit unit, TokenEstimator estimator) {
  var tokens = kUnitFramingTokens + estimator.estimate(unit.statement);
  for (final KnowledgeAnchor anchor in unit.anchors) {
    tokens += estimator.estimate(anchor.quote);
  }
  return tokens;
}

/// Сколько карточек заказано единице: основная и доборные «вторым углом».
final class UnitBudget {
  /// Создаёт бюджет единицы; карточек не меньше одной.
  const UnitBudget({required this.unit, required this.cards})
    : assert(cards >= 1, 'На отобранную единицу — минимум 1 карточка');

  /// Единица карты знаний.
  final KnowledgeUnit unit;

  /// Всего карточек по единице (основная + доборные).
  final int cards;

  /// Доборные карточки «вторым углом».
  int get angledCards => cards - 1;

  @override
  String toString() => 'UnitBudget(${unit.id}, $cards)';
}

/// Карточка плана: единица и угол (`null` — основная карточка по statement).
final class AllocatedCard {
  /// Создаёт карточку плана.
  const AllocatedCard({required this.unitId, this.angle});

  /// id единицы карты знаний.
  final String unitId;

  /// Угол доборной карточки; `null` — основная карточка.
  final AllocationAngle? angle;

  /// true — основная карточка (несёт statement единицы).
  bool get isPrimary => angle == null;

  /// Ключ различимого слота: единица и угол (`primary` — основная карточка).
  ///
  /// Два вопроса с одним ключом — один и тот же слот, даже если план заказал
  /// его дважды (TASK «Срез 14», часть 1).
  String get slotKey => '$unitId\u0000${angle?.wireName ?? 'primary'}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AllocatedCard && other.unitId == unitId && other.angle == angle;

  @override
  int get hashCode => Object.hash(unitId, angle);

  @override
  String toString() =>
      'AllocatedCard($unitId, ${angle?.wireName ?? 'primary'})';
}

/// Батч: карточки и оценка токенов входа/выхода; влезает в профиль.
final class AllocationBatch {
  /// Создаёт батч; непустой список карточек и пределы профиля — инвариант.
  AllocationBatch({
    required this.index,
    required this.profile,
    required List<AllocatedCard> cards,
    required this.inputTokens,
    required this.outputTokens,
  }) : cards = List<AllocatedCard>.unmodifiable(cards),
       assert(index >= 0, 'Номер батча неотрицателен'),
       assert(cards.isNotEmpty, 'Батч не пуст'),
       assert(
         profile.fitsBatch(
           inputTokens: inputTokens,
           outputTokens: outputTokens,
         ),
         'Батч обязан влезать в профиль модели',
       );

  /// Номер батча с 0.
  final int index;

  /// Профиль модели, под который упакован батч.
  final ModelProfile profile;

  /// Карточки батча.
  final List<AllocatedCard> cards;

  /// Оценка входа батча.
  final int inputTokens;

  /// Оценка выхода батча.
  final int outputTokens;

  /// Суммарная оценка батча.
  int get totalTokens => inputTokens + outputTokens;

  /// true — батч влезает в профиль модели.
  bool get fitsProfile =>
      profile.fitsBatch(inputTokens: inputTokens, outputTokens: outputTokens);

  @override
  String toString() =>
      'AllocationBatch($index, ${cards.length} карт., '
      '$inputTokens+$outputTokens т.)';
}

/// План этапа Allocation: заказ, бюджеты единиц, карточки и батчи.
final class AllocationPlan {
  /// Создаёт план; инварианты проверяются здесь, а не тестом постфактум:
  /// - два одинаковых слота (`unit_id + angle`) невозможны;
  /// - карточек ровно столько, сколько различимых слотов у единиц
  ///   ([capacity]); повтор слота «для объёма» не конструируем;
  /// - пустые единицы — только пустой план (материала нет вовсе), иначе сумма
  ///   бюджетов единиц равна числу карточек.
  AllocationPlan({
    required this.requested,
    required this.profile,
    required List<UnitBudget> units,
    required List<AllocatedCard> cards,
    required List<AllocationBatch> batches,
  }) : units = List<UnitBudget>.unmodifiable(units),
       cards = List<AllocatedCard>.unmodifiable(cards),
       batches = List<AllocationBatch>.unmodifiable(batches) {
    assert(requested > 0, 'Заказ положителен');
    assert(
      this.cards.length <= requested,
      'Карточек не больше заказа: повтор слотов не увеличивает план',
    );
    assert(
      this.cards.length == allocationCapacity(this.units),
      'Число карточек равно ёмкости различимых слотов единиц',
    );
    assert(
      _slotsAreUnique(this.cards),
      'План не может содержать два одинаковых слота (unit_id + angle)',
    );
  }

  /// Заказ карточек.
  final int requested;

  /// Профиль модели, под который построен план.
  final ModelProfile profile;

  /// Бюджеты отобранных единиц (в порядке карты).
  final List<UnitBudget> units;

  /// Карточки плана: основная на единицу и доборные углами.
  final List<AllocatedCard> cards;

  /// Батчи в порядке отправки.
  final List<AllocationBatch> batches;

  /// Сколько карточек запланировано.
  int get plannedCards => cards.length;

  /// Различимая ёмкость плана: `Σ min(карточек единицы, kMaxCardsPerUnit)`.
  ///
  /// Совпадает с [plannedCards]; отдельный геттер нужен отчёту и вердикту —
  /// «материала примерно на N карточек», где N — ёмкость, а не заказ.
  int get capacity => allocationCapacity(units);

  /// Недобор до заказа (0 — заказ покрыт).
  int get shortfall => math.max(0, requested - cards.length);

  /// Число различных утверждений (единиц) в плане.
  int get distinctStatements => units.length;

  /// Единиц меньше заказа — остальные карточки добраны вторым углом.
  bool get unitsBelowRequested => units.length < requested;

  /// Заказ больше различимой ёмкости материала (TASK «Срез 14», часть 1).
  ///
  /// Это не «материала нет вовсе»: карточки есть, но их меньше заказа, потому
  /// что слоты `unit_id + angle` кончились. `planned == capacity < requested`,
  /// `requested` не меняется, а итог прогона — `partial` с `exhausted_material`.
  bool get materialLimited => cards.length < requested;

  /// Сколько карточек добрано вторым углом.
  int get angledCards =>
      cards.where((AllocatedCard card) => !card.isPrimary).length;

  /// Волны исполнения: не больше `profile.concurrency` батчей параллельно.
  List<List<AllocationBatch>> get waves {
    if (batches.isEmpty) return const <List<AllocationBatch>>[];
    final List<List<AllocationBatch>> result = <List<AllocationBatch>>[];
    for (var start = 0; start < batches.length; start += profile.concurrency) {
      final int end = math.min(start + profile.concurrency, batches.length);
      result.add(
        List<AllocationBatch>.unmodifiable(batches.sublist(start, end)),
      );
    }
    return List<List<AllocationBatch>>.unmodifiable(result);
  }

  @override
  String toString() =>
      'AllocationPlan($requested, ${cards.length} карт., '
      '${batches.length} батч.)';
}
