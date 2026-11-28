/// Контекст прогона «уже создано» для запроса этапа Generation (TASK «Срез 17B»,
/// часть 1; ADR-055).
///
/// Диагноз среза 17B: в запрос `gen-cards-v3` попадало только принятое **текущего
/// батча** ([CardsBatch.accepted]) — партия не видела, что уже создано другими
/// партиями прогона. Между тем заказ делится на партии по единицам, а дубли
/// рождаются и на стыке партий: модель повторяет уже покрытое утверждение,
/// потому что ей об этом не сказали.
///
/// В `<already_created>` уходят:
/// - краткие утверждения единиц, по которым карточка уже **принята** (одно
///   утверждение на единицу, не полный текст карточки: ни `front`, ни `back`);
/// - занятые `unit_id` — единицы, у которых есть принятая карточка.
///
/// Предел роста — **по числу**, а не по байтам: заказ растёт, а запрос нет
/// ([kRunContextMaxStatements]/[kRunContextMaxTakenUnits]). Усечение делает
/// сборщик сообщения (`buildCardsUserContent`), поэтому обойти предел нельзя.
library;

/// Сколько утверждений максимум попадает в `<already_created>`.
const int kRunContextMaxStatements = 20;

/// Предел длины одного утверждения в контексте (символы; длинное — с «…»).
const int kRunContextStatementMaxChars = 160;

/// Сколько занятых `unit_id` максимум перечисляется в `<taken>`.
const int kRunContextMaxTakenUnits = 40;

/// Краткое утверждение единицы, по которой в прогоне уже принята карточка.
final class CreatedStatement {
  /// Создаёт запись утверждения.
  const CreatedStatement({
    required this.unitId,
    required this.statement,
    this.sectionId,
  });

  /// Единица карты знаний.
  final String unitId;

  /// Утверждение единицы (одна мысль; полный текст карточки не передаётся).
  final String statement;

  /// Раздел материала — только для приоритета усечения, в запрос не идёт.
  final String? sectionId;

  /// Утверждение в форме запроса: длинное обрезается по
  /// [kRunContextStatementMaxChars] с многоточием.
  String get text => statement.length <= kRunContextStatementMaxChars
      ? statement
      : '${statement.substring(0, kRunContextStatementMaxChars)}…';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreatedStatement &&
          other.unitId == unitId &&
          other.statement == statement &&
          other.sectionId == sectionId;

  @override
  int get hashCode => Object.hash(unitId, statement, sectionId);

  @override
  String toString() => 'CreatedStatement($unitId)';
}

/// Контекст «уже создано»: утверждения принятых единиц и занятые `unit_id`.
final class RunCardContext {
  /// Создаёт контекст из уже накопленного.
  const RunCardContext({
    this.statements = const <CreatedStatement>[],
    this.takenUnitIds = const <String>[],
  });

  /// Пустой контекст: прогон ещё ничего не принял.
  const RunCardContext.empty()
    : statements = const <CreatedStatement>[],
      takenUnitIds = const <String>[];

  /// Утверждения принятых единиц в порядке принятия (до усечения).
  final List<CreatedStatement> statements;

  /// Занятые единицы в порядке принятия (до усечения).
  final List<String> takenUnitIds;

  /// Контекст пуст — блок `<already_created>` в запрос не пишется.
  bool get isEmpty => statements.isEmpty && takenUnitIds.isEmpty;

  /// Не пуст.
  bool get isNotEmpty => !isEmpty;

  /// Копия с добавленной принятой карточкой: утверждение единицы — один раз,
  /// сколько бы карточек (углов) по ней ни приняли.
  RunCardContext withStatement(CreatedStatement statement) {
    if (statements.any(
      (CreatedStatement existing) => existing.unitId == statement.unitId,
    )) {
      return this;
    }
    return RunCardContext(
      statements: List<CreatedStatement>.unmodifiable(<CreatedStatement>[
        ...statements,
        statement,
      ]),
      takenUnitIds: List<String>.unmodifiable(<String>[
        ...takenUnitIds,
        statement.unitId,
      ]),
    );
  }

  /// Усечение **по числу** перед сборкой запроса.
  ///
  /// Приоритет — единицы разделов текущей партии ([sectionIds]): их утверждения
  /// чаще пересекаются с материалом запроса (тот же порядок, что у legacy
  /// `_digestOf`). Остальные идут после, в порядке принятия; лишнее отбрасывается
  /// целиком, а не обрезается по байтам.
  RunCardContext limited({Set<String> sectionIds = const <String>{}}) {
    final List<CreatedStatement> prioritized = <CreatedStatement>[
      for (final CreatedStatement statement in statements)
        if (statement.sectionId != null &&
            sectionIds.contains(statement.sectionId))
          statement,
      for (final CreatedStatement statement in statements)
        if (statement.sectionId == null ||
            !sectionIds.contains(statement.sectionId))
          statement,
    ];
    return RunCardContext(
      statements: List<CreatedStatement>.unmodifiable(
        prioritized.take(kRunContextMaxStatements),
      ),
      takenUnitIds: List<String>.unmodifiable(
        takenUnitIds.take(kRunContextMaxTakenUnits),
      ),
    );
  }

  @override
  String toString() =>
      'RunCardContext(${statements.length} утверждений, '
      '${takenUnitIds.length} единиц)';
}
