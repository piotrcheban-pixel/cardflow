# Verify — срез 4 «Allocation: веса, Гамильтон, упаковка батчей» (2026-11-27)

**Срез:** `TASK.txt` «Срез 4. Allocation: веса, Гамильтон, упаковка батчей».
Контракт этапов — `docs/generation/ARCH.md`, BACKLOG, ADR-050. Толкования
расхождений и неоднозначностей — `journal/QUESTIONS.md` Q10/Q11 (Q10 —
«плотность» единицы, 40 % окна и место файлов; Q11 — что значит «добор не
повторяет statement»).
**Старт:** ветка `main`, `HEAD = b926b28` (docs среза 3); baseline
`flutter test --no-pub --exclude-tags golden` — **2905 passed + 17 skipped**.

## Что сделано

| Файл | Назначение |
|---|---|
| `lib/domain/generation/model_profile.dart` | `ModelProfile` (`id`, `provider`, `contextWindow`, `maxOutputTokens`, `supportsJsonSchema`, `supportsVision`, `concurrency`), `batchTokenBudget` (40 % окна — именованная константа `batchWindowShare`), `maxCardsPerBatch`, `fitsBatch`; каталог `kModelProfiles` для **4 провайдеров** (DeepSeek, OpenAI, Anthropic, Gemini, 8 моделей — те же id, что в `kProviderPresets`), консервативный профиль для неизвестной модели — данные, а не числа в логике |
| `lib/domain/generation/allocation.dart` | вес единицы (`salience × unitDensity × kindWeight`), распределение методом наибольших остатков (`BigInt`, точная арифметика), минимум одна карточка на отобранную единицу, добор «вторым углом» (`AllocationAngle.reverse/cloze/application`, `AllocatedCard.angle`), отбор самых весомых при заказе меньше числа единиц, упаковка батчей по единицам под `ModelProfile` (`вход + оценка выхода ≤ 40 % окна`, выход ≤ `maxOutputTokens`), `waves` по `concurrency`, `AllocationPlan` с инвариантом «Σ бюджетов == заказ» |
| `test/unit/domain/generation/model_profile_test.dart` | 9 тестов: бюджет 40 %, `fitsBatch` на границах, `maxCardsPerBatch`, инварианты конструктора, 3+ провайдера, согласованность с каталогом пресетов, fallback, DeepSeek без strict-схемы |
| `test/unit/domain/generation/allocation_test.dart` | 34 теста: плотность/пол, множители видов, вес, распределение (равные/разные веса, отбор, BigInt на 1 000 000, крошечный вес, нулевой вес, ArgumentError), углы и цикл, упаковка (предел вывода, 40 % окна, резерв схемы, общий вход единиц, переиспользование, ошибки, волны), инварианты типов, два DoD-property-теста |

Существующий планировщик (`CardAllocator`, `GenerationChunkPlanner`,
`OutputBatchPlanner`), конвейер, UI, схема БД и публичные типы провайдеров **не
менялись**: новый этап пока не подключён к старому пути (протокол §9 — старый
код не удаляется, пока новый путь не покрыт тестами и не включён флагом).

## DoD из TASK.txt

1. **Property-тест «сумма == цель»** — `allocation_test.dart` «DoD: property-тесты
   плана…»: 200 случайных карт (0–11 единиц, заказ 1–150, все виды и salience
   0,05–1) — `plan.plannedCards == requested`, `Σ budget.cards == requested`;
   отдельно «полный план» 12 единиц → 40 карточек.
2. **Минимум 1 для каждой отобранной** — в том же property-тесте
   (`budget.cards >= 1`), плюс тесты 3/10/1 000 000 карточек и «крошечный вес не
   обнуляется» (заказ 4 на весах 1 и 1e-9 → 3 + 1).
3. **Детерминизм (один вход → один план)** — в property-тесте план строится
   дважды и сравниваются карточки, батчи, вход/выход каждого батча; отдельные
   тесты «равные остатки — по порядку единиц» и «заказ меньше единиц: первые по
   порядку».
4. **Ни один батч не превышает профиль** — в property-тесте у каждого батча
   `fitsProfile == true`, `totalTokens <= batchTokenBudget`,
   `outputTokens <= maxOutputTokens`; конструктор `AllocationBatch` дополнительно
   утверждает пределы (`throwsAssertionError` на 4 нарушениях), а упаковка
   ограничивает батч пределом вывода (3 карточки при 900/300), 40 % окна
   (2 карточки при бюджете 2000), резервом схемы (9 → 6 карточек) и уменьшает
   размер батча, а не цель.
5. **Добор только флагами angle и не повторяет statement** — 5 карточек на 2
   единицы: ровно две основные (`angle == null`), три доборные, углы
   `reverse → cloze` (definition) и `application` (procedure); у каждой единицы
   ровно одна основная карточка (второй «основной», повторяющей statement, нет);
   цикл углов проверен на 4 доборных подряд.
6. **Покрытие `allocation.dart` ≥ 95 %** — **100.0 % (190/190)**
   (`journal/generation-v3/coverage-s4.txt`).

Дополнительно: `preferredAngleForKind` покрывает все 5 видов; плотность не
зависит от длины (`PV = nRT` не проигрывает длинной фразе); переполнение
исключено `BigInt`; единица, не влезающая в бюджет одного батча, — явный
`ArgumentError`, а не молчаливая потеря.

## Красная фаза

`journal/generation-v3/red-s4.txt` — тесты и скелеты типов написаны до
реализации; падения **assertion-level**, а не только компиляцией:
`Expected: <40000> Actual: <0>` (бюджет батча), `Expected: <27> Actual: <0>`
(`maxCardsPerBatch`), `Expected: a numeric value within <1e-9> of <0.8333…>
Actual: <0.0>` (плотность), `Expected: [5, 3, 2] Actual: []` (наибольшие
остатки), `Expected: <1000000> Actual: <0>`, `Expected:
AllocationAngle.<cloze> Actual: AllocationAngle.<reverse>` (угол по виду),
`Expected: <5> Actual: <0>` (план). Итог: **9 прошло / 33 упало**.

## Гейты итогового снимка

- `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` →
  **No issues found!** (0 issues).
- `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` →
  **643 files, 0 changed**.
- `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
  --exclude-tags golden` → **2948 passed + 17 skipped**, `exit 0`
  (baseline 2905 + 43 новых). Полный лог —
  `journal/generation-v3/green-s4-full.txt`.
- `.\.fvm\versions\3.47.9\bin\dart.bat run tool/coverage_check.dart --min=80` →
  **90.9 % (24302/26744)**, порог 80 % пройден;
  `lib/domain/generation/allocation.dart` — **100.0 % (190/190)**,
  `lib/domain/generation/model_profile.dart` — 100.0 % (30/30).

## Решения среза (полностью — Q10/Q11)

- Файлы — в домене (`lib/domain/generation/`): правила без сети, БД и Flutter
  (AGENTS.md/ADR-050).
- Вес единицы: `salience × плотность × множитель вида`; плотность — **доля
  значимых слов** утверждения (пол 0,25), а не длина в символах: распределение
  по символам TASK запрещает прямо.
- 40 % окна — бюджет **одного батча** на `вход + оценка выхода`, вторая граница —
  `maxOutputTokens`; обе — в `ModelProfile.fitsBatch`, доля — в
  `ModelProfile.batchWindowShare`, а не в коде упаковки.
- Вход батча считается **по единицам** (утверждение, якоря, оформление, обвязка
  запроса и резерв схемы при `supportsJsonSchema`): карточки одной единицы вход
  не дублируют.
- Наибольшие остатки — точная `BigInt`-арифметика (заказ 1 000 000 не теряет
  карточек), при равных остатках — порядок единиц в карте (детерминизм).
- Угол — директива плана: основная карточка несёт statement, доборная
  формулируется иначе; угол по виду единицы, далее цикл
  `reverse → cloze → application`.
- `concurrency` — размер «волны» (`AllocationPlan.waves`), а не число
  одновременных запросов внутри одного шага: исполнение — следующий срез.

## Ограничения / что осталось

- Этап не подключён к `GenerationChunkPlanner`/конвейеру и не включён флагом:
  старый путь планирования остаётся; подключение — после этапов
  Generation/Replenish (BACKLOG S4/S7), иначе два плана разойдутся.
- `OrderBudget` из BACKLOG S3 как отдельный тип не создавался: его контракт
  несёт `AllocationPlan` (Q10); если S7 понадобится другая форма, это одна
  проекция, а не смена этапа.
- Оценка входа/выхода — эвристика `TokenEstimator` + константы обвязки; точный
  `count_tokens` и калибровка остаются за существующим пайплайном (ADR-040).
- Плотность считается по `statement` единицы; якоря в оценку входят только
  токенами входа (`anchors`), их смысловая насыщенность не пересчитывается.
- Карточка, ссылающаяся на единицу вне плана, — `ArgumentError`: план обязан
  быть замкнут на карту, иначе вход батча посчитать нечем.
- Проверки на реальных моделях/ключах нет: срез сетевых вызовов не делает
  (TASK: «никаких сетевых вызовов и БД»); значения профилей — статические
  данные, не измерение.
