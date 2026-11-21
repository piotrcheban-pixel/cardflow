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
    int? maxCardsPerRequest,
    int reasoningReserveTokens = 0,
  }) {
    final int perBatch = cardsPerBatch(
      maxTokensPerBatch,
      maxCardsPerRequest: maxCardsPerRequest,
      reasoningReserveTokens: reasoningReserveTokens,
    );
    if (input.isPromptOnly) {
      final int total = promptOnlyRequestedCards ?? allocation.achievable;
      if (total <= 0) return const <PlannedBatch>[];
      final List<int> sizes = batchSizes(total, perBatch);
      return List<PlannedBatch>.unmodifiable(<PlannedBatch>[
        for (var index = 0; index < sizes.length; index++)
          PlannedBatch(
            index: index,
            partIndex: -1,
            partCount: 0,
            focusSectionIds: const <String>[],
            limit: sizes[index],
          ),
      ]);
    }
    final List<InputPart> parts = input.parts;
    if (parts.isEmpty) return const <PlannedBatch>[];
    final List<PlannedBatch> batches = <PlannedBatch>[];
    var index = 0;
    if (input.isWholeDocument) {
      final InputPart part = parts.first;
      final int total = _totalFor(part, allocation);
      if (total <= 0) return const <PlannedBatch>[];
      final List<int> sizes = batchSizes(total, perBatch);
      final List<List<String>> focus = _focusGroups(
        part.sections,
        allocation,
        sizes,
      );
      for (var i = 0; i < sizes.length; i++) {
        batches.add(
          PlannedBatch(
            index: index++,
            partIndex: part.index,
            partCount: parts.length,
            focusSectionIds: focus[i],
            limit: sizes[i],
          ),
        );
      }
      return List<PlannedBatch>.unmodifiable(batches);
    }
    for (final InputPart part in parts) {
      final int total = _totalFor(part, allocation);
      if (total <= 0) continue;
      final List<int> sizes = batchSizes(total, perBatch);
      final List<List<String>> focus = _focusGroups(
        part.sections,
        allocation,
        sizes,
      );
      for (var i = 0; i < sizes.length; i++) {
        batches.add(
          PlannedBatch(
            index: index++,
            partIndex: part.index,
            partCount: parts.length,
            focusSectionIds: focus[i],
            limit: sizes[i],
          ),
        );
      }
    }
    return List<PlannedBatch>.unmodifiable(batches);
  }

  /// Число партий для [total] карточек при вместимости [perBatch].
  ///
  /// `⌈total / perBatch⌉` в целых числах: `(total + perBatch - 1) ~/ perBatch`
  /// переполняет `int` на больших заказах, поэтому остаток считается отдельно.
  /// `total ≤ 0` → 0.
  static int batchCount(int total, int perBatch) {
    if (total <= 0) return 0;
    final int safe = math.max(1, perBatch);
    final int whole = total ~/ safe;
    return total % safe == 0 ? whole : whole + 1;
  }

  /// Размеры партий: каждая, кроме последней, заполняется до [perBatch],
  /// последняя получает остаток. `Σ sizes == total`, ни одна не превышает
  /// вместимость, лишний запрос не создаётся (7.20).
  static List<int> batchSizes(int total, int perBatch) {
    final int safe = math.max(1, perBatch);
    final int count = batchCount(total, safe);
    if (count <= 0) return const <int>[];
    return batchSizesFor(total, count, safe);
  }

  /// Размеры ровно [count] партий при вместимости [cap], `Σ == total`.
  ///
  /// Нужен, когда число партий задаёт не только бюджет ответа, но и раскладка
  /// изображений по запросам (`GenerationChunkPlanner`): каждая партия всё
  /// равно остаётся не больше [cap]. Если [count] меньше минимально нужного
  /// `⌈total / cap⌉`, число партий поднимается до него — иначе сумма размеров
  /// была бы меньше [total] и карточки заказа потерялись бы.
  static List<int> batchSizesFor(int total, int count, int cap) {
    if (total <= 0) return const <int>[];
    final int safeCap = math.max(1, cap);
    final int minCount = batchCount(total, safeCap);
    final int effectiveCount = math.max(
      math.max(1, math.min(count, total)),
      minCount,
    );
    if (effectiveCount == minCount) {
      // Минимальное число партий: заполнение до вместимости, остаток последней.
      return <int>[
        for (var index = 0; index < effectiveCount - 1; index++) safeCap,
        total - safeCap * (effectiveCount - 1),
      ];
    }
    // Здесь count > minCount: размеры сбалансированы в пределах вместимости
    // (остаток распределяется по одной карточке первым партиям).
    final int base = total ~/ effectiveCount;
    final int remainder = total % effectiveCount;
    return <int>[
      for (var index = 0; index < effectiveCount; index++)
        base + (index < remainder ? 1 : 0),
    ];
  }

  /// Карточек на ответ: `min(ceiling, cardsFor(maxTokens − резерв), cap)`, но
  /// не меньше 1.
  ///
  /// [reasoningReserveTokens] — часть `max_tokens`, которую reasoning-модель
  /// потратит на рассуждение (§3.4): карточки считаются от остатка.
  int cardsPerBatch(
    int maxTokensPerBatch, {
    int? maxCardsPerRequest,
    int reasoningReserveTokens = 0,
  }) {
    final int budget = maxTokensPerBatch - reasoningReserveTokens;
    final int byBudget = config.cardsFor(budget < 0 ? 0 : budget);
    var cap = math.min(config.batchCardsCeiling, byBudget);
    if (maxCardsPerRequest != null) {
      cap = math.min(cap, math.max(1, maxCardsPerRequest));
    }
    return math.max(1, cap);
  }

  int _totalFor(InputPart part, CardAllocation allocation) {
    var total = 0;
    for (final InputSection section in part.sections) {
      total += allocation.forSection(section.id);
    }
    return total;
  }

  /// Непрерывные по порядку документа группы `focus` под размеры партий.
  ///
  /// Публичный: планировщик пересобирает партии части, когда изображения не
  /// помещаются в один запрос (лимиты image-частей/байт).
  static List<List<String>> focusGroupsFor(
    List<InputSection> sections,
    CardAllocation allocation,
    List<int> sizes,
  ) => _focusGroups(sections, allocation, sizes);

  static List<List<String>> _focusGroups(
    List<InputSection> sections,
    CardAllocation allocation,
    List<int> sizes,
  ) {
    final List<List<String>> groups = <List<String>>[
      for (var index = 0; index < sizes.length; index++) <String>[],
    ];
    var batch = 0;
    var filled = 0;
    for (final InputSection section in sections) {
      var remaining = allocation.forSection(section.id);
      while (remaining > 0 && batch < sizes.length) {
        final int room = sizes[batch] - filled;
        if (room <= 0) {
          batch++;
          filled = 0;
          continue;
        }
        final int take = math.min(remaining, room);
        final String id = section.promptId;
        if (!groups[batch].contains(id)) groups[batch].add(id);
        remaining -= take;
        filled += take;
        if (filled >= sizes[batch]) {
          batch++;
          filled = 0;
        }
      }
    }
    return groups;
  }
}
