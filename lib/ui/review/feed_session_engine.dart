import 'package:flutter/foundation.dart';

import 'package:cardflow/domain/cards/card.dart';

/// Элемент ленты: карточка и раскрыт ли её ответ.
///
/// Лента — режим свободного просмотра (ADR-044): у карточки нет оценки,
/// снимка FSRS и записи в журнал. Единственное состояние — показан ли ответ.
class FeedSessionItem {
  /// Создаёт элемент ленты.
  const FeedSessionItem({required this.card, this.revealed = false});

  /// Доменная карточка.
  final Card card;

  /// Показан ли ответ.
  final bool revealed;

  /// Копия с изменённым состоянием раскрытия.
  FeedSessionItem copyWith({bool? revealed}) =>
      FeedSessionItem(card: card, revealed: revealed ?? this.revealed);
}

/// Состояние ленты для UI-слоя (ADR-044).
class FeedSessionState {
  /// Создаёт состояние.
  const FeedSessionState({required this.items, required this.index});

  /// Карточки ленты в порядке показа.
  final List<FeedSessionItem> items;

  /// Индекс текущей карточки.
  final int index;

  /// Всего карточек.
  int get total => items.length;

  /// Текущая карточка; `null` — лента пуста.
  FeedSessionItem? get current =>
      index < 0 || index >= items.length ? null : items[index];

  /// Есть ли следующая карточка.
  bool get canGoNext => index + 1 < items.length;

  /// Есть ли предыдущая карточка.
  bool get canGoPrevious => index > 0;
}

/// Движок ленты свободного просмотра (ADR-044).
///
/// Отличия от классической сессии и от прежней «Ленты» ADR-016:
///
/// * **не пишет в FSRS и `review_logs`**: нет ни `ReviewRepository`, ни
///   планировщика, ни режима `feed` в журнале; свайп/листание не могут
///   изменить `due`, `fsrs_json` или историю повторений;
/// * **не оценивает карточки**: нет `Rating`, нет undo, нет авто-продвижения;
/// * в очередь входят **все** карточки колоды, кроме приостановленных
///   (`suspended`), в стабильном порядке создания — свободный просмотр не
///   зависит от дневных лимитов и расписания;
/// * раскрытие ответа хранится по карточке, поэтому возврат назад по ленте
///   показывает карточку в том виде, в каком её оставил пользователь.
class FeedSessionEngine extends ChangeNotifier {
  /// Создаёт движок поверх снимка карточек колоды.
  FeedSessionEngine({required this.cards, this.prebuilt = false});

  /// Снимок карточек колоды на момент открытия ленты.
  final List<Card> cards;

  /// `true` — [cards] уже отобраны и упорядочены конструктором (ADR-018);
  /// `false` — движок сам собирает полную очередь просмотра.
  final bool prebuilt;

  List<FeedSessionItem> _items = const <FeedSessionItem>[];
  int _index = 0;
  bool _initialized = false;
  bool _disposed = false;

  /// Текущее состояние ленты.
  FeedSessionState get state => FeedSessionState(
    items: List<FeedSessionItem>.unmodifiable(_items),
    index: _index,
  );

  /// Строит очередь просмотра. Вызывается экраном один раз.
  void start() {
    if (_initialized) return;
    final List<Card> queue = prebuilt
        ? List<Card>.unmodifiable(cards)
        : buildBrowseQueue(cards);
    _items = <FeedSessionItem>[
      for (final Card card in queue) FeedSessionItem(card: card),
    ];
    _index = 0;
    _initialized = true;
    notifyListeners();
  }

  /// Очередь свободного просмотра: все карточки, кроме приостановленных.
  ///
  /// Порядок — `createdAt` ASC, тай-брек `id` ASC: тот же стабильный список,
  /// что у колоды и тренировки, без перемешивания. Просмотр не зависит от
  /// `due`: карточка, которую по FSRS учить рано, остаётся доступной для
  /// ознакомления.
  static List<Card> buildBrowseQueue(List<Card> source) {
    final List<Card> eligible =
        <Card>[
          for (final Card card in source)
            if (!card.suspended) card,
        ]..sort((Card a, Card b) {
          final int byCreated = a.createdAt.compareTo(b.createdAt);
          return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
        });
    return List<Card>.unmodifiable(eligible);
  }

  /// Переходит на карточку [index] (без записи и без оценки).
  ///
  /// Вызывается PageView при завершении вертикального перехода; повторный
  /// вызов на тот же индекс ничего не делает (нет лишних rebuild).
  void visit(int index) {
    if (!_initialized ||
        index == _index ||
        index < 0 ||
        index >= _items.length) {
      return;
    }
    _index = index;
    notifyListeners();
  }

  /// Раскрывает/скрывает ответ текущей карточки.
  void toggleReveal() => toggleRevealAt(_index);

  /// Раскрывает/скрывает ответ карточки [index].
  ///
  /// Индекс — из видимой страницы: во время анимации PageView может показать
  /// соседнюю карточку раньше, чем `onPageChanged` обновит текущий индекс, и
  /// тап обязан попадать в ту карточку, которую видит пользователь.
  void toggleRevealAt(int index) {
    if (!_initialized || index < 0 || index >= _items.length) return;
    final FeedSessionItem item = _items[index];
    final List<FeedSessionItem> next = List<FeedSessionItem>.of(_items);
    next[index] = item.copyWith(revealed: !item.revealed);
    _items = next;
    notifyListeners();
  }

  /// Закрывает ответ текущей карточки (если он был открыт).
  void hideAnswer() {
    final FeedSessionItem? item = state.current;
    if (item == null || !item.revealed) return;
    toggleReveal();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    // Асинхронных записей в ленте нет, но экран может быть закрыт во время
    // кадра — защита от `notifyListeners` после dispose остаётся дешёвой.
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  String toString() =>
      'FeedSessionEngine(cards: ${cards.length}, index: $_index, '
      'total: ${_items.length})';
}
