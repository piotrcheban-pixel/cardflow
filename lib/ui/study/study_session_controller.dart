/// Общий контроллер новых режимов изучения (итерация 7.15).
///
/// Очередь, прогресс, итоги и политика FSRS — в одном месте, чтобы «Тест»,
/// «Ввод ответа» и «Верно/Неверно» (7.16) не дублировали логику:
/// - карточка, которую пора повторять (due или новая), оценивается через FSRS
///   (`Scheduler` + `ReviewRepository`);
/// - карточка с `due` в будущем работает как тренировка (`PracticeRepository`:
///   только `review_logs`, без `cards.state`/`fsrs_json`/`due`);
/// - в журнал пишется `mode` режима (7.15).
library;

import 'package:flutter/foundation.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_scheduling.dart';
import 'package:cardflow/domain/review/practice_repository.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/review/review_repository.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/domain/study/study_fsrs_policy.dart';
import 'package:cardflow/domain/study/study_mode.dart';
import 'package:cardflow/domain/study/study_queue.dart';

/// Элемент очереди режима: карточка и её снимок FSRS на момент старта.
class StudySessionItem {
  /// Создаёт элемент.
  const StudySessionItem({
    required this.card,
    required this.scheduling,
    required this.writesFsrs,
  });

  /// Карточка.
  final Card card;

  /// Снимок FSRS-состояния на старт сессии.
  final SchedulingCard scheduling;

  /// Писать ли оценку в FSRS (due/новая и режим это поддерживает).
  final bool writesFsrs;
}

/// Состояние сессии нового режима.
class StudySessionState {
  /// Создаёт состояние.
  const StudySessionState({
    required this.items,
    required this.index,
    required this.busy,
    required this.undoCount,
    required this.correctCount,
    required this.wrongCount,
  });

  /// Очередь.
  final List<StudySessionItem> items;

  /// Индекс текущей карточки; `items.length` — завершено.
  final int index;

  /// Идёт запись в БД.
  final bool busy;

  /// Сколько откатов доступно.
  final int undoCount;

  /// Верных ответов за сессию (без откатанных).
  final int correctCount;

  /// Неверных ответов за сессию.
  final int wrongCount;

  /// Всего карточек.
  int get total => items.length;

  /// Сколько карточек пройдено.
  int get answeredCount => correctCount + wrongCount;

  /// Сессия завершена.
  bool get isCompleted => index >= items.length;

  /// Текущая карточка; `null` после завершения.
  StudySessionItem? get current => isCompleted ? null : items[index];

  /// Точность в процентах (0 — нет ответов).
  int get accuracy =>
      answeredCount == 0 ? 0 : (correctCount * 100 / answeredCount).round();
}

/// Контроллер очереди/оценок нового режима.
class StudySessionController extends ChangeNotifier {
  /// Создаёт контроллер.
  StudySessionController({
    required this.cards,
    required this.mode,
    required this.scheduler,
    required this.reviewRepository,
    required this.practiceRepository,
    required this.clock,
  }) : assert(mode != StudyMode.constructor, 'Конструктор — не сессия');

  /// Снимок карточек колоды на момент старта.
  final List<Card> cards;

  /// Режим (пишется в `review_logs.mode`).
  final StudyMode mode;

  /// Планировщик FSRS.
  final Scheduler scheduler;

  /// Порт записей FSRS.
  final ReviewRepository reviewRepository;

  /// Порт записей тренировки (для карточек с `due` в будущем).
  final PracticeRepository practiceRepository;

  /// Источник времени (в тестах — управляемый).
  final DateTime Function() clock;

  StudySessionState _state = const StudySessionState(
    items: <StudySessionItem>[],
    index: 0,
    busy: false,
    undoCount: 0,
    correctCount: 0,
    wrongCount: 0,
  );

  final List<_UndoEntry> _undoStack = <_UndoEntry>[];
  final List<bool> _outcomes = <bool>[];
  final List<Card> _wrongCards = <Card>[];
  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  bool _initialized = false;
  bool _disposed = false;

  /// Текущее состояние.
  StudySessionState get state => _state;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Строит очередь. Вызывается один раз экраном.
  void start() {
    if (_initialized) return;
    final DateTime now = clock().toUtc();
    _initWith(buildStudyQueue(cards, now: now), now);
    _initialized = true;
  }

  /// Перезапускает сессию только с ошибочными карточками («Повторить ошибки»).
  void repeatMistakes() {
    if (_wrongCards.isEmpty) return;
    final DateTime now = clock().toUtc();
    final List<Card> mistakes = List<Card>.of(_wrongCards);
    _wrongCards.clear();
    _outcomes.clear();
    _undoStack.clear();
    _initWith(mistakes, now);
  }

  void _initWith(List<Card> queue, DateTime now) {
    final List<StudySessionItem> items = <StudySessionItem>[
      for (final Card card in queue)
        StudySessionItem(
          card: card,
          scheduling: CardSchedulingMapper.toSchedulingCard(card, now: now),
          writesFsrs: shouldWriteFsrs(
            card,
            now,
            modeSupportsFsrs: mode.canWriteFsrs,
          ),
        ),
    ];
    _shownAt = now;
    _emit(items: items, index: 0, busy: false);
  }

  /// Записывает ответ на текущую карточку и переходит к следующей.
  ///
  /// [rating] — оценка FSRS (для тренировочной карточки просто журнал),
  /// [wasCorrect] — для итогов режима.
  Future<bool> answer({
    required Rating rating,
    required bool wasCorrect,
  }) async {
    if (!_initialized || _state.busy || _state.isCompleted) return false;
    final StudySessionItem item = _state.current!;
    final DateTime reviewedAt = clock().toUtc();
    _emit(index: _state.index, busy: true);
    final String modeWire = mode.wireName;
    try {
      if (item.writesFsrs) {
        final SchedulingCard outcome = scheduler
            .review(item.scheduling, rating, now: reviewedAt)
            .card;
        final ReviewUndo undo = await reviewRepository.recordReview(
          cardId: item.card.id,
          rating: rating,
          reviewedAt: reviewedAt,
          outcome: outcome,
          mode: modeWire,
          elapsed: reviewedAt.difference(_shownAt),
        );
        _undoStack.add(_UndoEntry.fsrs(undo, wasCorrect: wasCorrect));
      } else {
        final String logId = await practiceRepository.recordPractice(
          cardId: item.card.id,
          rating: rating,
          reviewedAt: reviewedAt,
          elapsed: reviewedAt.difference(_shownAt),
          mode: modeWire,
        );
        _undoStack.add(_UndoEntry.practice(logId, wasCorrect: wasCorrect));
      }
    } catch (_) {
      _emit(index: _state.index, busy: false);
      rethrow;
    }
    _outcomes.add(wasCorrect);
    if (!wasCorrect && !_wrongCards.any((Card c) => c.id == item.card.id)) {
      _wrongCards.add(item.card);
    }
    _shownAt = clock().toUtc();
    _emit(index: _state.index + 1, busy: false);
    return true;
  }

  /// Откатывает последний ответ.
  Future<bool> undo() async {
    if (!_initialized || _state.busy || _undoStack.isEmpty) return false;
    _emit(index: _state.index, busy: true);
    final _UndoEntry entry = _undoStack.last;
    try {
      if (entry.fsrsUndo != null) {
        await reviewRepository.undoReview(entry.fsrsUndo!);
      } else {
        await practiceRepository.undoPractice(
          entry.logId!,
          mode: mode.wireName,
        );
      }
    } catch (_) {
      _emit(index: _state.index, busy: false);
      rethrow;
    }
    _undoStack.removeLast();
    if (_outcomes.isNotEmpty) _outcomes.removeLast();
    _shownAt = clock().toUtc();
    _emit(index: _state.index - 1, busy: false);
    return true;
  }

  /// Откатывается ли последний ответ как «ошибочный» (для «Повторить ошибки»).
  List<Card> get wrongCards => List<Card>.unmodifiable(_wrongCards);

  void _emit({
    List<StudySessionItem>? items,
    required int index,
    required bool busy,
  }) {
    if (_disposed) return;
    var correct = 0;
    var wrong = 0;
    for (final bool outcome in _outcomes) {
      if (outcome) {
        correct++;
      } else {
        wrong++;
      }
    }
    _state = StudySessionState(
      items: items ?? _state.items,
      index: index,
      busy: busy,
      undoCount: _undoStack.length,
      correctCount: correct,
      wrongCount: wrong,
    );
    notifyListeners();
  }
}

/// Откат одной оценки: FSRS-транзакция или запись журнала.
class _UndoEntry {
  _UndoEntry.fsrs(ReviewUndo undo, {required this.wasCorrect})
    : fsrsUndo = undo,
      logId = null;

  _UndoEntry.practice(String id, {required this.wasCorrect})
    : logId = id,
      fsrsUndo = null;

  final ReviewUndo? fsrsUndo;
  final String? logId;
  final bool wasCorrect;
}
