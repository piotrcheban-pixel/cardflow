/// Определения метрики исхода, **замороженные** срезом 17 (ADR-054).
///
/// До среза 16 «качество» мерилось одним `cleanRate`, а дубли — счётчиком
/// помеченных принятых карточек. Срез 16 развёл явления, но считал все доли от
/// попыток — из-за этого дубль штрафовал качество дважды: и как грязная
/// карточка, и как доля в знаменателе. Срез 17 (часть 0) фиксирует четыре
/// величины, каждая отвечает на **один** вопрос и не входит в другую:
///
/// - `acceptanceRate = accepted / attempted` — сколько попыток дожило до колоды;
/// - `blockRate = blocked / attempted` — сколько отсек жёсткий гейт;
/// - `cleanRate = clean / unique` — качество **сохранённой** карточки;
/// - `dupRate = duplicates / unique` — какая доля сохранённого — повтор.
///
/// Счётчики (один код для legacy и v3, из [GenerationReport], без своих
/// счётчиков у путей):
/// - [attempted] — карточки, которые вернула модель и которые путь учёл:
///   принятые + отброшенные валидацией/схемой + дубли (`generated` отчёта);
/// - [accepted] — принятые в колоду (без заблокированных и без дублей);
/// - [unique] — принятые, у которых нет пометки дубля (`accepted − помеченные`);
/// - [clean] — принятые вовсе без пометок гейта;
/// - [duplicates] — отложенные смысловые дубли: у v3 они не приняты (слот
///   открыт), у legacy отброшены;
/// - [blocked] — отброшенные жёстким дефектом.
///
/// Дубль не двигает `cleanRate`: он меняет [duplicates] (свою долю) и
/// [attempted], но не [clean] и не [unique] — это DoD среза 17, часть 0, п. 1
/// и тест `outcome_counts_test` («дубль не двигает cleanRate»).
///
/// Любая следующая смена определений — только через ADR с явным «почему
/// прежнее определение неверно» (TASK «Срез 17», п. 4).
library;

import 'package:cardflow/domain/generation/generation_report.dart';

/// Исход попыток одного прогона.
final class OutcomeCounts {
  /// Создаёт счётчики; отрицательных значений не бывает.
  const OutcomeCounts({
    required this.attempted,
    required this.accepted,
    required this.unique,
    required this.clean,
    required this.duplicates,
    required this.blocked,
  }) : assert(attempted >= 0, 'Попытки не отрицательны'),
       assert(accepted >= 0, 'Принятое не отрицательно'),
       assert(unique >= 0, 'Уникальные не отрицательны'),
       assert(clean >= 0, 'Чистые не отрицательны'),
       assert(duplicates >= 0, 'Дубли не отрицательны'),
       assert(blocked >= 0, 'Заблокированные не отрицательны');

  /// Собирает счётчики из отчёта пути (единая точка для legacy и v3).
  factory OutcomeCounts.fromReport(GenerationReport report) => OutcomeCounts(
    attempted: report.generated,
    accepted: report.accepted,
    unique: report.accepted - report.acceptedDuplicates,
    clean: report.cleanAccepted,
    duplicates: report.duplicates,
    blocked: report.blocked,
  );

  /// Карточки, учтённые путём: принятые + отброшенные + дубли.
  final int attempted;

  /// Принятые в колоду.
  final int accepted;

  /// Принятые без пометки дубля — знаменатель качества и доли дублей.
  final int unique;

  /// Принятые без любых пометок гейта.
  final int clean;

  /// Отложенные (v3) или отброшенные (legacy) смысловые дубли.
  final int duplicates;

  /// Отброшенные жёстким дефектом.
  final int blocked;

  /// Доля принятых от всех попыток; `null` — попыток не было.
  double? get acceptanceRate => attempted <= 0 ? null : accepted / attempted;

  /// Качество сохранённой карточки: чистые / уникальные принятые.
  ///
  /// Знаменатель — [unique], а не [attempted]: дубль не должен делать
  /// сохранённое «грязнее», это отдельная величина [dupRate].
  /// `null` — сохранённых нет: «0 из 0» не качество.
  double? get cleanRate => unique <= 0 ? null : clean / unique;

  /// Доля дублей от уникальных; `null` — сохранённых нет.
  double? get dupRate => unique <= 0 ? null : duplicates / unique;

  /// Доля заблокированных от всех попыток; `null` — попыток не было.
  double? get blockRate => attempted <= 0 ? null : blocked / attempted;

  @override
  String toString() =>
      'OutcomeCounts(попыток $attempted, принято $accepted, уникальных '
      '$unique, чистых $clean, дублей $duplicates, блокировано $blocked)';
}
