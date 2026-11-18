/// Бюджет дополнительных запросов восстановления (TASK 03, L128).
///
/// Фиксированные 12 запросов были скрытым ограничением для больших планов:
/// при сотнях фрагментов несколько переполнений исчерпывали бюджет, и часть
/// материалов оставалась без восстановления. Стратегия — не «больше повторов
/// ради повторов», а запас, пропорциональный числу фрагментов:
///
/// `budget = max(configured, plannedRequests / perPlanDivisor)`, но не больше
/// [cap]. Значение `configured = 0` отключает восстановление явно.
///
/// Почему `/8`: типичная доля фрагментов, требующих дробления/повтора, ниже
/// 10–12 %; деление на 8 даёт запас на один такой фрагмент из восьми, не
/// превращая восстановление в бесконечный цикл. Это конфигурация приложения,
/// а не гарантия провайдера.
library;

/// Верхняя граница бюджета восстановления (защита от runaway).
const int kRecoveryBudgetCap = 64;

/// Делитель числа фрагментов плана для бюджета восстановления.
const int kRecoveryBudgetFragmentsDivisor = 8;

/// Считает бюджет дополнительных запросов восстановления.
///
/// [plannedRequests] — число фрагментов плана; [configured] — явное значение
/// `GenerationPipeline.maxRecoveryRequests` (0 — выключено).
int generationRecoveryBudget({
  required int plannedRequests,
  required int configured,
  int cap = kRecoveryBudgetCap,
  int divisor = kRecoveryBudgetFragmentsDivisor,
}) {
  if (configured <= 0) return 0;
  assert(cap > 0);
  assert(divisor > 0);
  final int planned = plannedRequests < 0 ? 0 : plannedRequests;
  final int scaled = planned ~/ divisor;
  final int budget = scaled > configured ? scaled : configured;
  return budget > cap ? cap : budget;
}
