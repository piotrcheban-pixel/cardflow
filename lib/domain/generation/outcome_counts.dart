/// Исход попыток прогона по определениям среза 16 (часть 1).
///
/// До среза 16 «качество» мерилось одним `cleanRate`, а дубли — счётчиком
/// помеченных принятых карточек. Это смешивало три разных явления: модель
/// вернула дубль, гейт отбросил карточку и принял с пометкой. Здесь они
/// разведены и считаются **одним кодом** для legacy и v3 — из
/// [GenerationReport], без своих счётчиков у путей.
///
/// Определения:
/// - [attempted] — карточки, которые вернула модель и которые путь учёл:
///   принятые + отброшенные валидацией/схемой + дубли (`generated` отчёта);
/// - [accepted] — принятые в колоду (без заблокированных и без дублей);
/// - [unique] — принятые, у которых нет пометки дубля (`accepted − помеченные`);
/// - [clean] — принятые вовсе без пометок гейта;
/// - [duplicates] — отложенные смысловые дубли: у v3 они не приняты (слот
///   открыт), у legacy отброшены;
/// - [blocked] — отброшенные жёстким дефектом.
///
/// Производные: [cleanRate] = clean / attempted, [dupRate] = duplicates /
/// attempted, [blockRate] = blocked / attempted. Знаменатель один — **все**
/// попытки, иначе доля растёт от собственной строгости.
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
       assert(blocked >= 0, 'Блокированные не отрицательны');

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

  /// Принятые без пометки дубля.
  final int unique;

  /// Принятые без любых пометок гейта.
  final int clean;

  /// Отложенные (v3) или отброшенные (legacy) смысловые дубли.
  final int duplicates;

  /// Отброшенные жёстким дефектом.
  final int blocked;

  /// Доля чистых от всех попыток; `null` — попыток не было.
  double? get cleanRate => attempted <= 0 ? null : clean / attempted;

  /// Доля дублей от всех попыток; `null` — попыток не было.
  double? get dupRate => attempted <= 0 ? null : duplicates / attempted;

  /// Доля заблокированных от всех попыток; `null` — попыток не было.
  double? get blockRate => attempted <= 0 ? null : blocked / attempted;

  @override
  String toString() =>
      'OutcomeCounts(попыток $attempted, принято $accepted, уникальных '
      '$unique, чистых $clean, дублей $duplicates, блокировано $blocked)';
}
