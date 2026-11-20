/// Output Batch Planner: сколько карточек просить в одном ответе и какие
/// разделы в него входят (`focus`) — ADR-040 §6.
///
/// Решает **только** бюджет выхода: партии строятся по распределению карточек,
/// а не по числу частей входа. В whole-режиме все партии используют полный
/// материал и различаются `focus`. Домен не зависит от Flutter.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/input_planner.dart';

/// Одна партия (один API-запрос).
final class PlannedBatch {
  /// Создаёт партию.
  const PlannedBatch({
    required this.index,
    required this.partIndex,
    required this.partCount,
    required this.focusSectionIds,
    required this.limit,
  }) : assert(index >= 0),
       assert(limit >= 1),
       assert(partCount >= 0);

  /// Номер партии (с нуля).
  final int index;

  /// Часть входа: индекс в `InputPlan.parts`; `-1` — prompt-only.
  final int partIndex;

  /// Всего частей входа (0 — prompt-only).
  final int partCount;

  /// Короткие id разделов `focus` в порядке документа.
  final List<String> focusSectionIds;

  /// Сколько карточек просить в этой партии (≥ 1).
  final int limit;

  @override
  String toString() =>
      'PlannedBatch(#$index, part: $partIndex/$partCount, '
      'limit: $limit, focus: ${focusSectionIds.join(',')})';
}

/// Строит партии запросов по плану входа и распределению карточек.
final class OutputBatchPlanner {
  /// Создаёт планировщик партий.
  const OutputBatchPlanner({this.config = const GenerationPlanningConfig()});

  /// Коэффициенты бюджета вывода.
  final GenerationPlanningConfig config;

  /// Строит партии.
  ///
  /// [maxTokensPerBatch] — резерв вывода одного запроса (whole: `maxTokens`,
  /// fragmented: `R`). [promptOnlyRequestedCards] используется только для
  /// prompt-only плана (разделов нет).
  List<PlannedBatch> plan({
    required InputPlan input,
    required CardAllocation allocation,
    required int maxTokensPerBatch,
    int? promptOnlyRequestedCards,
  }) {
    // RED-фаза итерации 7.18: контракт зафиксирован, алгоритм — следующий шаг.
    return const <PlannedBatch>[];
  }

  /// Карточек на ответ: `min(ceiling, cardsFor(maxTokens))`, но не меньше 1.
  int cardsPerBatch(int maxTokensPerBatch) {
    final int byBudget = config.cardsFor(maxTokensPerBatch);
    return math.max(1, math.min(config.batchCardsCeiling, byBudget));
  }
}
