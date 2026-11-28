/// Партия этапа Generation (TASK «Срез 5», ARCH §2 этап 4, ADR-050).
///
/// Партия — не «кусок текста», а **единицы карты знаний** с якорями и карточки
/// плана по ним: ответ модели привязывается к `unit_id`, поэтому потерянная
/// карточка видна как долг по конкретной единице, а не «модель вернула меньше».
///
/// Контекст «уже принято» — только **этого** батча ([accepted]): чужой батч не
/// подсказывает модели, что отвечать, и не растит запрос с числом батчей
/// (TASK: «Контекст „уже принято“ — только front + statement текущего батча»).
///
/// Второй, отдельный контекст — «уже создано» прогона ([runContext], срез 17B):
/// краткие утверждения принятых единиц и занятые `unit_id`. Он собирается по
/// партиям, но усечён **по числу** ([RunCardContext.limited]), поэтому запрос не
/// растёт с заказом. Промпт `gen-cards-v3` при этом не менялся: блок
/// `<already_created>` — данные, а не формулировка.
library;

import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/run_card_context.dart';

/// Уже принятая карточка текущего батча: front и утверждение её единицы.
///
/// Только эти два поля уходят в `<already_accepted>`: ответ (`back`), подсказки
/// и изображения не передаются, иначе модель начнёт копировать прошлые ответы.
class AcceptedCard {
  /// Создаёт пару «принятый front + утверждение единицы».
  const AcceptedCard({required this.front, required this.statement})
    : assert(front != '', 'У принятой карточки обязан быть front');

  /// Лицевая сторона принятой карточки (как её увидит пользователь).
  final String front;

  /// Утверждение единицы, по которой построена карточка.
  final String statement;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcceptedCard &&
          other.front == front &&
          other.statement == statement;

  @override
  int get hashCode => Object.hash(front, statement);

  @override
  String toString() => 'AcceptedCard($front)';
}

/// Запрос одной партии: единицы с якорями, карточки плана и принятое батча.
///
/// Инварианты: номер партии неотрицателен, карточки есть, каждая карточка
/// ссылается на единицу из [units] (единица с якорем обязана быть в запросе,
/// иначе модель не увидит материал).
class CardsBatch {
  /// Создаёт партию.
  CardsBatch({
    required this.index,
    required List<KnowledgeUnit> units,
    required List<AllocatedCard> cards,
    List<AcceptedCard> accepted = const <AcceptedCard>[],
    this.runContext = const RunCardContext.empty(),
    this.topUp = false,
  }) : units = List<KnowledgeUnit>.unmodifiable(units),
       cards = List<AllocatedCard>.unmodifiable(cards),
       accepted = List<AcceptedCard>.unmodifiable(accepted),
       _unitsById = <String, KnowledgeUnit>{
         for (final KnowledgeUnit unit in units) unit.id: unit,
       } {
    assert(index >= 0, 'Номер партии не может быть отрицательным');
    assert(cards.isNotEmpty, 'Партия не может быть пустой');
    for (final AllocatedCard card in cards) {
      assert(
        _unitsById.containsKey(card.unitId),
        'Карточка партии ссылается на единицу вне партии: ${card.unitId}',
      );
    }
  }

  /// Номер партии в плане (совпадает с `AllocationBatch.index`).
  final int index;

  /// Единицы карты знаний, входящие в партию (с утверждениями и якорями).
  final List<KnowledgeUnit> units;

  /// Карточки плана: единица и угол (`null` — основная карточка).
  final List<AllocatedCard> cards;

  /// Уже принятое **этого** батча (front + утверждение единицы).
  final List<AcceptedCard> accepted;

  /// «Уже создано» прогона: утверждения принятых единиц и занятые `unit_id`.
  ///
  /// В запрос уходит только усечённый по числу срез ([RunCardContext.limited]) —
  /// его выбирает сборщик сообщения, поэтому контекст не растёт с заказом.
  final RunCardContext runContext;

  /// true — это добор после обрезки ответа (`finish_reason: length`).
  ///
  /// Пометка нужна, чтобы не делить единицу бесконечно: второй обрез по
  /// одной единице считается исчерпанием и записывается в журнал, а не
  /// запускает новый круг запросов.
  final bool topUp;

  final Map<String, KnowledgeUnit> _unitsById;

  /// Бюджет партии: сколько карточек просим у модели.
  int get budget => cards.length;

  /// Единица по id; `null` — такой единицы в партии нет.
  KnowledgeUnit? unit(String id) => _unitsById[id];

  /// Карточки единицы [unitId] в порядке плана.
  List<AllocatedCard> cardsOf(String unitId) => <AllocatedCard>[
    for (final AllocatedCard card in cards)
      if (card.unitId == unitId) card,
  ];

  /// id единиц партии в порядке первого появления в карточках.
  List<String> get unitIds {
    final List<String> ids = <String>[];
    for (final AllocatedCard card in cards) {
      if (!ids.contains(card.unitId)) ids.add(card.unitId);
    }
    return List<String>.unmodifiable(ids);
  }

  /// Копия с другим набором карточек и принятым (для деления и добора).
  CardsBatch slice(
    List<AllocatedCard> cards, {
    List<AcceptedCard>? accepted,
    bool topUp = false,
  }) {
    final Set<String> unitIds = <String>{
      for (final AllocatedCard card in cards) card.unitId,
    };
    return CardsBatch(
      index: index,
      units: <KnowledgeUnit>[
        for (final KnowledgeUnit unit in units)
          if (unitIds.contains(unit.id)) unit,
      ],
      cards: cards,
      accepted: accepted ?? this.accepted,
      runContext: runContext,
      topUp: topUp,
    );
  }

  /// Копия с добавленными принятыми карточками.
  CardsBatch withAccepted(Iterable<AcceptedCard> more) => CardsBatch(
    index: index,
    units: units,
    cards: cards,
    accepted: <AcceptedCard>[...accepted, ...more],
    runContext: runContext,
    topUp: topUp,
  );

  /// Копия с актуальным контекстом «уже принято» батча.
  ///
  /// Партия в очереди создаётся до того, как предыдущая часть ответит: к моменту
  /// запроса контекст мог пополниться, поэтому перед отправкой он подставляется
  /// заново (только принятое этого батча).
  CardsBatch withAcceptedContext(List<AcceptedCard> context) => CardsBatch(
    index: index,
    units: units,
    cards: cards,
    accepted: context,
    runContext: runContext,
    topUp: topUp,
  );

  /// Копия с контекстом «уже создано» прогона (срез 17B).
  CardsBatch withRunContext(RunCardContext context) => CardsBatch(
    index: index,
    units: units,
    cards: cards,
    accepted: accepted,
    runContext: context,
    topUp: topUp,
  );

  @override
  String toString() =>
      'CardsBatch($index, ${cards.length} карт., ${units.length} ед.'
      '${topUp ? ', добор' : ''})';
}

/// Делит партию по **границе единиц**, а не по половине карточек.
///
/// Обрезка ответа (`max_tokens`) означает, что модель не успела часть карточек.
/// Делить заказ пополам по числу карточек нельзя: карточки одной единицы делят
/// вход, и половина карточек может снова не влезть. Делим список **единиц**:
/// первая часть — первая половина единиц (с округлением вверх), вторая —
/// остальные; карточки следуют за своими единицами.
///
/// Если единица одна, делить не по чему: возвращается та же партия, и добор
/// делает следующий шаг (одна повторная попытка, см. [CardsBatch.topUp]).
List<CardsBatch> splitBatchByUnits(CardsBatch batch) {
  final List<String> unitIds = batch.unitIds;
  if (unitIds.length < 2) return <CardsBatch>[batch];
  final int firstCount = (unitIds.length + 1) ~/ 2;
  final Set<String> firstUnits = <String>{
    for (final String id in unitIds.take(firstCount)) id,
  };
  return <CardsBatch>[
    batch.slice(<AllocatedCard>[
      for (final AllocatedCard card in batch.cards)
        if (firstUnits.contains(card.unitId)) card,
    ]),
    batch.slice(<AllocatedCard>[
      for (final AllocatedCard card in batch.cards)
        if (!firstUnits.contains(card.unitId)) card,
    ]),
  ];
}
