import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_recovery_budget.dart';

/// TASK 03, L128: бюджет восстановления — обоснованная стратегия, не магия.
void main() {
  test('ноль отключает восстановление явно', () {
    expect(generationRecoveryBudget(plannedRequests: 100, configured: 0), 0);
  });

  test('малый план: конфигурационный минимум', () {
    expect(generationRecoveryBudget(plannedRequests: 1, configured: 12), 12);
    expect(generationRecoveryBudget(plannedRequests: 40, configured: 12), 12);
  });

  test('большой план: бюджет растёт пропорционально фрагментам', () {
    expect(generationRecoveryBudget(plannedRequests: 200, configured: 12), 25);
    expect(
      generationRecoveryBudget(plannedRequests: 1000, configured: 12),
      64,
      reason: 'верхняя граница защищает от runaway',
    );
  });

  test('верхняя граница применяется и к большому configured', () {
    expect(generationRecoveryBudget(plannedRequests: 10, configured: 100), 64);
  });

  test('отрицательное число фрагментов не ломает расчёт', () {
    expect(generationRecoveryBudget(plannedRequests: -5, configured: 12), 12);
  });
}
