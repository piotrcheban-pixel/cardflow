import 'package:flutter/foundation.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/practice_queue.dart';
import 'package:cardflow/domain/review/practice_repository.dart';
import 'package:cardflow/domain/scheduling/rating.dart';

/// Состояние тренировки (ADR-025, итерация 7.11).
class PracticeSessionState {
  /// Создаёт состояние.
  const PracticeSessionState({
    required this.cards,
    required this.index,
    required this.revealed,
    required this.busy,
    required this.undoCount,
  });

  /// Очередь тренировки (фиксированная на момент старта).
  final List<Card> cards;

  /// Индекс текущей карточки; `cards.length` — тренировка завершена.
  final int index;

  /// Показан ли ответ текущей карточки.
  final bool revealed;

  /// Идёт запись в БД (кнопки/undo заблокированы).
  final bool busy;

  /// Сколько откатов доступно.
  final int undoCount;

  /// Всего карточек.
  int get total => cards.length;

  /// Сколько карточек уже пройдено.
  int get ratedCount => index;

  /// Тренировка завершена.
  bool get isCompleted => index >= cards.length;

  /// Текущая карточка; `null` после завершения.
  Card? get current => isCompleted ? null : cards[index];
}

/// Движок тренировки: раскрытие, оценка, undo — без планировщика.
///
/// В отличие от [ReviewSessionEngine] не считает прогноз интервалов и не пишет
/// `cards.state`/`fsrs_json`/`due`: оценки идут в журнал с
/// `mode = 'practice'` (ADR-025).
class PracticeSessionEngine extends ChangeNotifier {
  /// Создаёт движок поверх снимка карточек колоды.
  PracticeSessionEngine({
    required this.cards,
    required this.practiceRepository,
    required this.clock,
  });

  /// Снимок карточек колоды на момент старта.
  final List<Card> cards;

  /// Порт записи оценок тренировки.
  final PracticeRepository practiceRepository;

  /// Источник текущего времени (в тестах — управляемый).
  final DateTime Function() clock;

  PracticeSessionState _state = const PracticeSessionState(
    cards: <Card>[],
    index: 0,
    revealed: false,
    busy: false,
    undoCount: 0,
  );

  final List<String> _undoLogs = <String>[];
  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  bool _initialized = false;
  bool _disposed = false;

  /// Текущее состояние.
  PracticeSessionState get state => _state;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Строит очередь тренировки. Вызывается один раз экраном.
  void start() {
    if (_initialized) return;
    final List<Card> queue = PracticeQueue.build(cards);
    _shownAt = clock().toUtc();
    _initialized = true;
    _emit(cards: queue, index: 0, revealed: false, busy: false);
  }

  /// Раскрывает ответ текущей карточки.
  void reveal() {
    if (!_initialized || _state.isCompleted || _state.revealed) return;
    _emit(index: _state.index, revealed: true, busy: _state.busy);
  }

  /// Записывает оценку и переходит к следующей карточке.
  Future<bool> rate(Rating rating) async {
    if (!_initialized || _state.busy || _state.isCompleted) return false;
    final Card card = _state.current!;
    final DateTime reviewedAt = clock().toUtc();
    _emit(index: _state.index, revealed: _state.revealed, busy: true);
    final String logId;
    try {
      logId = await practiceRepository.recordPractice(
        cardId: card.id,
        rating: rating,
        reviewedAt: reviewedAt,
        elapsed: reviewedAt.difference(_shownAt),
      );
    } catch (_) {
      _emit(index: _state.index, revealed: _state.revealed, busy: false);
      rethrow;
    }
    _undoLogs.add(logId);
    _shownAt = clock().toUtc();
    _emit(index: _state.index + 1, revealed: false, busy: false);
    return true;
  }

  /// Откатывает последнюю оценку тренировки.
  Future<bool> undo() async {
    if (!_initialized || _state.busy || _undoLogs.isEmpty) return false;
    _emit(index: _state.index, revealed: _state.revealed, busy: true);
    try {
      await practiceRepository.undoPractice(_undoLogs.last);
    } catch (_) {
      _emit(index: _state.index, revealed: _state.revealed, busy: false);
      rethrow;
    }
    _undoLogs.removeLast();
    _shownAt = clock().toUtc();
    _emit(index: _state.index - 1, revealed: true, busy: false);
    return true;
  }

  void _emit({
    List<Card>? cards,
    required int index,
    required bool revealed,
    required bool busy,
  }) {
    // Асинхронная запись может завершиться после закрытия экрана.
    if (_disposed) return;
    _state = PracticeSessionState(
      cards: cards ?? _state.cards,
      index: index,
      revealed: revealed,
      busy: busy,
      undoCount: _undoLogs.length,
    );
    notifyListeners();
  }

  @override
  String toString() =>
      'PracticeSessionEngine(cards: ${cards.length}, rated: ${_state.index})';
}
