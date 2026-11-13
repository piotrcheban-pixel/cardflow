# Итерация 2 — числа интервалов FSRS по состояниям (доказательство T17)

**Дата:** 2026-11-13 · **Команда:** `fvm dart run tool/fsrs_intervals_probe.dart`
**Конфигурация (ADR-004):** FSRS-6, `desiredRetention = 0.9`, learningSteps 1 мин / 10 мин, relearningSteps 10 мин, `maximumInterval = 36500` д, fuzzing **выключен**, веса `fsrs.defaultParameters`.
**Карточка-представитель:** строится теми же операциями планировщика, что и в приложении; для review — после Easy из новой (stability 16.151, difficulty 2.482), для learning — после Good (step 1), для relearning — после Again из review (step 0).

| Состояние | Again | Hard | Good | Easy |
|---|---|---|---|---|
| new | 1 мин | 5 мин 30 с | 10 мин | 16 д |
| learning (step 1) | 1 мин | 10 мин | 4 д | 8 д |
| review (S=16.151, D=2.482) | 10 мин | 27 д | 65 д | 164 д |
| relearning (step 0) | 10 мин | 15 мин | 3 д | 7 д |

Вывод команды (сырой):

```text
Состояние            | Again        | Hard         | Good         | Easy
---------------------+--------------+--------------+--------------+--------------
new                 | 1 мин        | 5 мин 30 с   | 10 мин       | 16 д
learning (step 1)   | 1 мин        | 10 мин       | 4 д          | 8 д
review              | 10 мин       | 27 д         | 65 д         | 164 д
relearning (step 0) | 10 мин       | 15 мин       | 3 д          | 7 д

Карточка review: stability=16.151, difficulty=2.482
Карточка learning: step=1, stability=3.260
Карточка relearning: step=0, stability=2.999
```

**Что это доказывает:**
- прогноз детерминирован (fuzzing выключен) и монотонен Again < Hard < Good < Easy для всех четырёх состояний — это же проверено тестами `test/unit/domain/fsrs_scheduler_test.dart` (включая `previewIntervals == фактический due` для learning и relearning);
- интервалы различаются по состояниям: у learning/relearning короткие шаги (минуты) и первые дни; у review зависят от stability/difficulty (числа выше — для карточки-представителя, а не константы интерфейса);
- таблица A7.2 SPEC («<10 мин / 3 д / 7 д / 14 д») иллюстративна: приложение показывает прогноз конкретной карточки над каждой кнопкой (A7.2: «вычисляет планировщик той же операцией, что и при оценке»).
