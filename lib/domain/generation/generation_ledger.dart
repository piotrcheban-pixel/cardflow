/// Бухгалтерия прогона генерации v3 (ARCH §2, инварианты §3.1–3.2, ADR-050).
///
/// Заказ карточек считается долгом, а не «сколько вернулось сейчас»: журнал
/// хранит по каждой партии, сколько запрошено, произведено, отброшено
/// валидацией, дублей и принято, а [GenerationLedger] складывает это суммарно и
/// называет класс недобора ([ShortfallKind]). Вердикт Completion (S9) и журнал
/// запуска (S8) читают этот журнал, а не числа одного ответа — поэтому «тихий
/// недобор» становится видимым числом.
///
/// Термины (одинаковы для партии и прогона):
/// - `requested` — бюджет: сколько карточек просили;
/// - `generated` — сколько карточек вернула модель;
/// - `invalid` — сколько отброшено валидацией (структура/схема/контент);
/// - `duplicates` — сколько отброшено как точный дубль колоды;
/// - `accepted = generated − invalid − duplicates`;
/// - `remaining = max(0, requested − accepted)` — долг;
/// - `attempts` — сколько запросов ушло на партию (повторы и добор не живут в
///   отдельном recovery-бюджете, TASK «Срез 5»).
///
/// Инвариант: `invalid + duplicates <= generated` (нарушение — [AssertionError],
/// ошибка программиста). Переполнение (`accepted > requested`) допустимо: план
/// мог попросить меньше, чем модель способна дать, — долг в этом случае 0.
///
/// `requested` журнала — всегда сумма бюджетов партий: журнал не держит
/// отдельную «цель», которая могла бы разойтись с планом (инвариант «Σ
/// бюджетов == requested», DoD среза 2). Нехватка материала, из-за которой план
/// не покрывает заказ, видна в плане (`GenerationPlan.requestedAboveAchievable`),
/// а не подменяет бюджеты журнала.
library;

import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';

/// Класс недобора: почему принято меньше, чем запрошено.
///
/// Код машинный ([wireName]) — строка для журнала запуска и диагностики, а не
/// пользовательский текст (текст — в ARB на слое UI).
enum ShortfallKind {
  /// Материал исчерпан: больше карточек из него не сделать.
  exhaustedMaterial('exhausted_material'),

  /// Провайдер не ответил или ответил ошибкой — партия не сгенерирована.
  providerError('provider_error'),

  /// Ответ модели оборван по лимиту вывода (спасённые карточки учтены).
  truncated('truncated'),

  /// Карточки произведены, но отброшены валидацией или как точные дубли.
  validationRejects('validation_rejects'),

  /// Прогон отменён пользователем.
  cancelled('cancelled');

  const ShortfallKind(this.wireName);

  /// Имя класса в журнале запуска (snake_case, как в TASK.txt).
  final String wireName;

  /// Разбирает класс недобора из строки журнала.
  ///
  /// Неизвестная строка — [FormatException]: журнал повреждён или версия
  /// несовместима, угадывать класс нельзя.
  static ShortfallKind fromWire(String value) {
    for (final ShortfallKind kind in values) {
      if (kind.wireName == value) return kind;
    }
    throw FormatException('Неизвестный класс недобора: $value');
  }
}

/// Журнал одной партии плана: бюджеты и события по ней.
///
/// Неизменяемое значение: события добавляются через [record] и [withCause],
/// которые возвращают копию. Недобор партии ([shortfall]) — явная причина
/// ([cause]) либо выведенная из чисел; у партии без событий причины ещё нет
/// (`null`), потому что неизвестно, почему она не отработала.
class GenerationBatchLedger {
  /// Создаёт журнал партии; нарушения счётчиков — [AssertionError].
  const GenerationBatchLedger({
    required this.batchIndex,
    required this.requested,
    this.generated = 0,
    this.invalid = 0,
    this.duplicates = 0,
    this.attempts = 0,
    this.cause,
  }) : assert(batchIndex >= 0, 'Номер партии не может быть отрицательным'),
       assert(requested >= 0, 'Бюджет партии не может быть отрицательным'),
       assert(generated >= 0, 'Произведено не может быть отрицательным'),
       assert(invalid >= 0, 'Отброшено валидацией не может быть отрицательным'),
       assert(duplicates >= 0, 'Дублей не может быть отрицательным числом'),
       assert(attempts >= 0, 'Число запросов не может быть отрицательным'),
       assert(
         invalid + duplicates <= generated,
         'Валидация и дубли вместе не могут превышать произведённое',
       );

  /// Партия с бюджетом [requested] и без событий.
  const GenerationBatchLedger.budget({
    required int batchIndex,
    required int requested,
  }) : this(batchIndex: batchIndex, requested: requested);

  /// Номер партии в плане (с 0, без пропусков).
  final int batchIndex;

  /// Бюджет партии: сколько карточек запрошено у модели.
  final int requested;

  /// Сколько карточек вернула модель.
  final int generated;

  /// Сколько отброшено валидацией.
  final int invalid;

  /// Сколько отброшено как точный дубль.
  final int duplicates;

  /// Сколько запросов модели ушло на партию.
  ///
  /// Повторы (429/5xx/обрезка/добор по единицам) считаются **здесь**, а не в
  /// отдельном recovery-бюджете: долг и расход запросов видны в одной
  /// бухгалтерии (TASK «Срез 5», п. 3). Успешный первый запрос — тоже попытка.
  final int attempts;

  /// Явная причина недобора; `null` — не задана (класс выводится из чисел).
  final ShortfallKind? cause;

  /// Принято: произведено минус отброшенное валидацией и дубли.
  int get accepted => generated - invalid - duplicates;

  /// Долг партии: `max(0, requested − accepted)`.
  int get remaining => requested > accepted ? requested - accepted : 0;

  /// true, если партия не добрала бюджет.
  bool get hasDebt => remaining > 0;

  /// Класс недобора партии; `null` — долга нет или причина ещё неизвестна.
  ///
  /// Приоритет: явная [cause] → отброшенные карточки
  /// ([ShortfallKind.validationRejects]) → короткий ответ без ошибок
  /// ([ShortfallKind.exhaustedMaterial]; остальные причины этап объявляет
  /// явно). Партия без событий возвращает `null`: она могла ещё не начаться.
  ShortfallKind? get shortfall {
    if (!hasDebt) return null;
    final ShortfallKind? declared = cause;
    if (declared != null) return declared;
    if (invalid > 0 || duplicates > 0) return ShortfallKind.validationRejects;
    if (generated == 0) return null;
    return ShortfallKind.exhaustedMaterial;
  }

  /// Копия с добавленными счётчиками (партия продолжается).
  ///
  /// Отрицательные приращения — [AssertionError]; превышение
  /// `invalid + duplicates` над `generated` — тоже. Число запросов не
  /// меняется: его считает [attempt].
  GenerationBatchLedger record({
    int generated = 0,
    int invalid = 0,
    int duplicates = 0,
  }) {
    return GenerationBatchLedger(
      batchIndex: batchIndex,
      requested: requested,
      generated: this.generated + generated,
      invalid: this.invalid + invalid,
      duplicates: this.duplicates + duplicates,
      attempts: attempts,
      cause: cause,
    );
  }

  /// Копия с [count] дополнительными запросами к модели (повтор или добор).
  GenerationBatchLedger attempt([int count = 1]) {
    if (count <= 0) {
      throw ArgumentError.value(
        count,
        'count',
        'Приращение попыток положительно',
      );
    }
    return GenerationBatchLedger(
      batchIndex: batchIndex,
      requested: requested,
      generated: generated,
      invalid: invalid,
      duplicates: duplicates,
      attempts: attempts + count,
      cause: cause,
    );
  }

  /// Копия с явной причиной недобора (сбой, обрезка, отмена, исчерпание).
  GenerationBatchLedger withCause(ShortfallKind kind) {
    return GenerationBatchLedger(
      batchIndex: batchIndex,
      requested: requested,
      generated: generated,
      invalid: invalid,
      duplicates: duplicates,
      attempts: attempts,
      cause: kind,
    );
  }

  @override
  String toString() =>
      'GenerationBatchLedger(партия $batchIndex, произведено '
      '$generated/$requested, принято $accepted, валидация $invalid, '
      'дубли $duplicates, запросов $attempts'
      '${cause == null ? '' : ', причина ${cause!.wireName}'})';
}

/// Журнал прогона: журналы партий и суммарная бухгалтерия.
///
/// Партии нумеруются подряд с 0 (номер == позиция): так [batch] и [replace]
/// не ищут партию перебором, а пропуск номера — ошибка программиста
/// ([AssertionError]). Список партий неизменяемый.
class GenerationLedger {
  /// Создаёт журнал из [batches]; партии должны идти подряд с 0.
  ///
  /// [dedup] — отчёт каскада дедупликации (TASK «Срез 6»): журнал отвечает за
  /// арифметику заказа, отчёт — за то, на каком уровне карточка помечена
  /// дублем. По умолчанию отчёт пуст.
  GenerationLedger({
    required List<GenerationBatchLedger> batches,
    DedupReport? dedup,
  }) : batches = List<GenerationBatchLedger>.unmodifiable(batches),
       dedup = dedup ?? DedupReport.empty() {
    assert(
      _numberedFromZero(this.batches),
      'Партии журнала обязаны нумероваться подряд с 0',
    );
  }

  /// Пустой журнал (план ещё не строили).
  factory GenerationLedger.empty() =>
      GenerationLedger(batches: const <GenerationBatchLedger>[]);

  /// Журнал по бюджетам партий (обычно `GenerationPlan.batchSizes`).
  ///
  /// `requested` журнала равен сумме бюджетов — отдельной «цели», способной
  /// разойтись с планом, журнал не держит.
  factory GenerationLedger.fromBudgets(Iterable<int> budgets) {
    final List<GenerationBatchLedger> batches = <GenerationBatchLedger>[];
    for (final int budget in budgets) {
      batches.add(
        GenerationBatchLedger.budget(
          batchIndex: batches.length,
          requested: budget,
        ),
      );
    }
    return GenerationLedger(batches: batches);
  }

  /// Журнал по плану: бюджеты партий — лимиты фрагментов плана.
  factory GenerationLedger.fromPlan(GenerationPlan plan) =>
      GenerationLedger.fromBudgets(plan.batchSizes);

  /// Партии журнала в порядке плана (для UI «по партиям» и журнала запуска).
  final List<GenerationBatchLedger> batches;

  /// Отчёт каскада дедупликации: сколько пар на каждом уровне (TASK «Срез 6»).
  final DedupReport dedup;

  /// Копия журнала с отчётом дедупа [report].
  GenerationLedger withDedup(DedupReport report) =>
      GenerationLedger(batches: batches, dedup: report);

  /// Запрошено карточек: сумма бюджетов партий.
  int get requested => _sum((GenerationBatchLedger batch) => batch.requested);

  /// Произведено карточек моделью.
  int get generated => _sum((GenerationBatchLedger batch) => batch.generated);

  /// Отброшено валидацией.
  int get invalid => _sum((GenerationBatchLedger batch) => batch.invalid);

  /// Отброшено как точные дубли.
  int get duplicates => _sum((GenerationBatchLedger batch) => batch.duplicates);

  /// Сколько запросов к модели ушло на прогон (включая повторы и добор).
  int get attempts => _sum((GenerationBatchLedger batch) => batch.attempts);

  /// Принято карточек: сумма принятых по партиям.
  int get accepted => _sum((GenerationBatchLedger batch) => batch.accepted);

  /// Долг прогона: `max(0, requested − accepted)`.
  int get remaining => requested > accepted ? requested - accepted : 0;

  /// true, если прогон не добрал заказ.
  bool get hasDebt => remaining > 0;

  /// Класс недобора всего прогона; `null` — долга нет или причина неизвестна.
  ///
  /// Приоритет (сначала более корневая причина, затем более «внутренняя»):
  /// отмена → ошибка провайдера → обрезка ответа → исчерпание материала →
  /// отброшенные карточки. Дубли отдельного класса не имеют: они входят в
  /// `validation_rejects` (см. `journal/QUESTIONS.md` Q5).
  ShortfallKind? get shortfall {
    if (!hasDebt) return null;
    const List<ShortfallKind> priority = <ShortfallKind>[
      ShortfallKind.cancelled,
      ShortfallKind.providerError,
      ShortfallKind.truncated,
      ShortfallKind.exhaustedMaterial,
      ShortfallKind.validationRejects,
    ];
    for (final ShortfallKind kind in priority) {
      for (final GenerationBatchLedger batch in batches) {
        if (batch.shortfall == kind) return kind;
      }
    }
    return null;
  }

  /// Журнал партии [batchIndex]; `null` — такой партии нет.
  GenerationBatchLedger? batch(int batchIndex) {
    if (batchIndex < 0 || batchIndex >= batches.length) return null;
    return batches[batchIndex];
  }

  /// Копия журнала с заменённой партией [batch].
  ///
  /// Партия с неизвестным номером — [ArgumentError]: опечатка в номере не
  /// должна молча добавлять партию, которой нет в плане.
  GenerationLedger replace(GenerationBatchLedger batch) {
    final int index = batch.batchIndex;
    if (index < 0 || index >= batches.length) {
      throw ArgumentError.value(
        index,
        'batch.batchIndex',
        'В журнале нет такой партии',
      );
    }
    final List<GenerationBatchLedger> next = List<GenerationBatchLedger>.of(
      batches,
    );
    next[index] = batch;
    return GenerationLedger(batches: next, dedup: dedup);
  }

  /// Записывает события партии [batchIndex] и возвращает новый журнал.
  GenerationLedger record(
    int batchIndex, {
    int generated = 0,
    int invalid = 0,
    int duplicates = 0,
  }) {
    final GenerationBatchLedger? batch = this.batch(batchIndex);
    if (batch == null) {
      throw ArgumentError.value(
        batchIndex,
        'batchIndex',
        'В журнале нет такой партии',
      );
    }
    return replace(
      batch.record(
        generated: generated,
        invalid: invalid,
        duplicates: duplicates,
      ),
    );
  }

  /// Записывает [count] запросов к модели по партии [batchIndex].
  GenerationLedger attempt(int batchIndex, {int count = 1}) {
    final GenerationBatchLedger? batch = this.batch(batchIndex);
    if (batch == null) {
      throw ArgumentError.value(
        batchIndex,
        'batchIndex',
        'В журнале нет такой партии',
      );
    }
    return replace(batch.attempt(count));
  }

  /// Ставит явную причину недобора партии [batchIndex].
  GenerationLedger markCause(int batchIndex, ShortfallKind cause) {
    final GenerationBatchLedger? batch = this.batch(batchIndex);
    if (batch == null) {
      throw ArgumentError.value(
        batchIndex,
        'batchIndex',
        'В журнале нет такой партии',
      );
    }
    return replace(batch.withCause(cause));
  }

  @override
  String toString() =>
      'GenerationLedger(партий ${batches.length}, принято '
      '$accepted/$requested, долг $remaining, запросов $attempts'
      '${shortfall == null ? '' : ', причина ${shortfall!.wireName}'})';

  int _sum(int Function(GenerationBatchLedger batch) field) {
    var total = 0;
    for (final GenerationBatchLedger batch in batches) {
      total += field(batch);
    }
    return total;
  }

  static bool _numberedFromZero(List<GenerationBatchLedger> batches) {
    for (var index = 0; index < batches.length; index++) {
      if (batches[index].batchIndex != index) return false;
    }
    return true;
  }
}
