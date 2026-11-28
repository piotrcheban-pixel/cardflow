/// Сравнение замера среза 17B с **уже оплаченной** ячейкой 150 без контекста
/// (TASK «Срез 17B», часть 2, п. 5; ADR-054/ADR-055).
///
/// Новых запросов не делает: читает
/// - `journal/generation-v3/live-s16/cells/*.json` — оплаченная матрица
///   среза 16 (`textbook-v3-150` — v3 **без** контекста «уже создано»);
/// - `journal/generation-v3/live-s17b/cells/*.json` — замер среза 17B
///   (`textbook-v3-150-context` — v3 **с** контекстом; `textbook-legacy-150-cards`
///   — карточки прежнего пути для слепой выборки).
///
/// Пишет `journal/generation-v3/matrix-s17b.md`: четыре величины TASK ч. 2 п. 5
/// (`dupRate`, `unique`, `cleanRate`, запросов на 10 уникальных), предрегистрацию
/// критерия (см. `verify-s17b.md` §0) и его фактический итог.
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/recompute_matrix_s17b.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/generation_path.dart';
import 'package:cardflow/domain/generation/path_rule.dart';

/// Оплаченные ячейки среза 16 (база сравнения).
const String kBaselineCellsDir = 'journal/generation-v3/live-s16/cells';

/// Ячейки замера 17B.
const String kNewCellsDir = 'journal/generation-v3/live-s17b/cells';

/// Куда пишется сравнение.
const String kOutputPath = 'journal/generation-v3/matrix-s17b.md';

/// Слепая выборка среза 17B (для раздела статуса).
const String kBlindSamplePath = 'journal/generation-v3/blind-sample-17b.md';

/// Ключ слепой выборки.
const String kBlindKeyPath = 'journal/generation-v3/blind-key-17b.json';

/// Имя оплаченной ячейки: v3 на учебном материале, заказ 150, без контекста.
const String kBaselineCellId = 'textbook-v3-150';

/// Ячейка замера: тот же материал и заказ, но с контекстом «уже создано».
const String kContextCellId = 'textbook-v3-150-context';

/// Ячейка замера: прежний путь (источник карточек legacy для выборки).
const String kLegacyCardsCellId = 'textbook-legacy-150-cards';

/// Оплаченная ячейка прежнего пути (для справки).
const String kBaselineLegacyCellId = 'textbook-legacy-150';

/// Одна ячейка замера в счётчиках.
class Cell {
  Cell({
    required this.cellId,
    required this.material,
    required this.requested,
    required this.path,
    required this.status,
    required this.codeVersion,
    required this.outcome,
    required this.requests,
    required this.savedCards,
  });

  final String cellId;
  final String material;
  final int requested;
  final String path;
  final String status;
  final String? codeVersion;
  final PathOutcome outcome;

  /// Запросов модели за операцию (включая повтор и добор).
  final int requests;

  /// Сколько карточек сохранено в ячейке (ключ `cards`).
  final int savedCards;

  bool get isV3 => path == GenerationPath.v3.wireName;

  /// Запросов на 10 уникальных карточек (TASK ч. 2 п. 5).
  double? get requestsPer10Unique =>
      outcome.unique <= 0 ? null : requests * 10 / outcome.unique;

  static Cell? fromJson(Map<String, Object?> json) {
    final Object? metricsRaw = json['metrics'];
    if (metricsRaw is! Map) return null;
    final Map<String, Object?> metrics = metricsRaw.cast<String, Object?>();
    int intOf(String key) => (metrics[key] as num?)?.toInt() ?? 0;
    final int attempted = intOf('attempted');
    final int blocked = metrics['blocked'] is num
        ? (metrics['blocked']! as num).toInt()
        : (((metrics['block_rate'] as num?) ?? 0) * attempted + 0.5).floor();
    final Object? rawCards = json['cards'];
    return Cell(
      cellId: json['cell_id'] as String? ?? '?',
      material: json['material'] as String? ?? '?',
      requested: (json['requested'] as num?)?.toInt() ?? 0,
      path: json['path'] as String? ?? '?',
      status: json['status'] as String? ?? '?',
      codeVersion: json['code_version'] as String?,
      outcome: PathOutcome(
        attempted: attempted,
        accepted: intOf('accepted_final'),
        unique: intOf('unique'),
        clean: intOf('clean'),
        duplicates: intOf('duplicates'),
        blocked: blocked,
      ),
      requests: intOf('requests'),
      savedCards: rawCards is List ? rawCards.length : 0,
    );
  }
}

/// Читает каталог ячеек; нет каталога — пустой список.
Map<String, Cell> readCells(String dir) {
  final Directory directory = Directory(dir);
  if (!directory.existsSync()) return <String, Cell>{};
  final Map<String, Cell> cells = <String, Cell>{};
  for (final FileSystemEntity entity in directory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final Map<String, Object?> json = (jsonDecode(
      File(entity.path).readAsStringSync(),
    ) as Map).cast<String, Object?>();
    final Cell? cell = Cell.fromJson(json);
    if (cell != null) cells[cell.cellId] = cell;
  }
  return cells;
}

String _percent(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

String _signed(double? a, double? b, {int digits = 1, String unit = ''}) {
  if (a == null || b == null) return '—';
  final double delta = a - b;
  final String sign = delta > 0 ? '+' : '';
  return '$sign${delta.toStringAsFixed(digits)}$unit';
}

/// Разница долей в процентных пунктах (доли — 0..1).
String _signedPoints(double? a, double? b) {
  if (a == null || b == null) return '—';
  final double delta = (a - b) * 100;
  final String sign = delta > 0 ? '+' : '';
  return '$sign${delta.toStringAsFixed(1)} п.п.';
}

/// Разница целых чисел со знаком.
String _signedInt(int a, int b) {
  final int delta = a - b;
  return '${delta > 0 ? '+' : ''}$delta';
}

String _row(String label, Cell cell) {
  final PathOutcome o = cell.outcome;
  return '| $label | ${cell.cellId} | ${o.attempted} | ${o.accepted} '
      '| ${o.unique} | ${o.clean} | ${o.duplicates} '
      '| ${_percent(o.cleanRate)} | ${_percent(o.dupRate)} '
      '| ${cell.requests} '
      '| ${cell.requestsPer10Unique?.toStringAsFixed(2) ?? '—'} '
      '| ${cell.savedCards} |';
}

/// Сколько карточек в выборке размечено владельцем.
int countMarks(String path) {
  final File file = File(path);
  if (!file.existsSync()) return 0;
  final String text = file.readAsStringSync();
  return RegExp(r'- \[x\]').allMatches(text.toLowerCase()).length;
}

void main() {
  final Map<String, Cell> baseline = readCells(kBaselineCellsDir);
  final Map<String, Cell> fresh = readCells(kNewCellsDir);
  final Cell? baselineV3 = baseline[kBaselineCellId];
  final Cell? contextV3 = fresh[kContextCellId];
  final Cell? legacyCards = fresh[kLegacyCardsCellId];
  final Cell? baselineLegacy = baseline[kBaselineLegacyCellId];

  final StringBuffer out = StringBuffer()
    ..writeln('# Срез 17B — замер гипотезы «контекст „уже создано“»')
    ..writeln()
    ..writeln(
      'Пересчёт **существующих** ячеек: `$kBaselineCellsDir` (срез 16, '
      'оплачено ранее) и `$kNewCellsDir` (замер 17B). Новых запросов этот '
      'инструмент не делает. Определения заморожены срезом 17 (ADR-054): '
      '`cleanRate = clean / unique`, `dupRate = duplicates / unique`, '
      '`acceptanceRate = accepted / attempted`.',
    )
    ..writeln()
    ..writeln('## 1. Ячейки сравнения')
    ..writeln()
    ..writeln(
      '| Роль | Ячейка | Попыток | Принято | Уникальных | Чистых | Дублей '
      '| cleanRate | dupRate | Запросов | Запросов на 10 уникальных '
      '| Карточек сохранено |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  if (baselineV3 != null) {
    out.writeln(_row('база: v3 без контекста', baselineV3));
  }
  if (contextV3 != null) out.writeln(_row('замер: v3 с контекстом', contextV3));
  if (baselineLegacy != null) {
    out.writeln(_row('база: legacy (справка)', baselineLegacy));
  }
  if (legacyCards != null) {
    out.writeln(_row('замер: legacy с карточками', legacyCards));
  }
  out.writeln();

  final bool measured = baselineV3 != null && contextV3 != null;
  out
    ..writeln('## 2. Сравнение с оплаченной ячейкой (TASK ч. 2 п. 5)')
    ..writeln();
  if (!measured) {
    out
      ..writeln(
        '**Не измерено:** нет ячейки базы (`$kBaselineCellId`) или замера '
        '(`$kContextCellId`) — сравнение не построить, числа не додумываются.',
      )
      ..writeln();
  } else {
    final PathOutcome before = baselineV3.outcome;
    final PathOutcome after = contextV3.outcome;
    final bool dupLower =
        before.dupRate != null &&
        after.dupRate != null &&
        after.dupRate! < before.dupRate!;
    final int minUnique = (before.unique * kComparableVolumeThreshold).ceil();
    final bool volumeOk = after.unique >= minUnique;
    final bool cleanOk =
        before.cleanRate != null &&
        after.cleanRate != null &&
        after.cleanRate! >= before.cleanRate! - 0.05;
    final bool accepted0 = dupLower && volumeOk && cleanOk;
    out
      ..writeln(
        '| Величина | Без контекста (`$kBaselineCellId`) | С контекстом '
        '(`$kContextCellId`) | Разница |',
      )
      ..writeln('|---|---:|---:|---:|')
      ..writeln(
        '| `dupRate` | ${_percent(before.dupRate)} | '
        '${_percent(after.dupRate)} '
        '| ${_signedPoints(after.dupRate, before.dupRate)} |',
      )
      ..writeln(
        '| `unique` | ${before.unique} | ${after.unique} '
        '| ${_signedInt(after.unique, before.unique)} |',
      )
      ..writeln(
        '| `cleanRate` | ${_percent(before.cleanRate)} | '
        '${_percent(after.cleanRate)} '
        '| ${_signedPoints(after.cleanRate, before.cleanRate)} |',
      )
      ..writeln(
        '| запросов на 10 уникальных | '
        '${baselineV3.requestsPer10Unique?.toStringAsFixed(2) ?? '—'} | '
        '${contextV3.requestsPer10Unique?.toStringAsFixed(2) ?? '—'} '
        '| ${_signed(contextV3.requestsPer10Unique, baselineV3.requestsPer10Unique, digits: 2)} |',
      )
      ..writeln(
        '| принято (для объёма) | ${before.accepted} | ${after.accepted} '
        '| ${_signedInt(after.accepted, before.accepted)} |',
      )
      ..writeln()
      ..writeln('**Критерий из `verify-s17b.md` §0:**')
      ..writeln(
        '1. `dupRate` строго ниже: ${dupLower ? 'да' : 'нет'} '
        '(${_percent(before.dupRate)} → ${_percent(after.dupRate)});',
      )
      ..writeln(
        '2. `unique ≥ 0,8 × базы` (≥ $minUnique): '
        '${volumeOk ? 'да' : 'нет'} (${after.unique});',
      )
      ..writeln(
        '3. `cleanRate` не ниже базы − 5 п.п.: ${cleanOk ? 'да' : 'нет'};',
      )
      ..writeln()
      ..writeln(
        '**Итог: контекст ${accepted0 ? 'снизил' : 'НЕ снизил'} dupRate по '
        'критерию.**',
      )
      ..writeln();
  }

  // 3. Форма запросов: дошёл ли контекст до платного запроса.
  out
    ..writeln('## 3. Дошёл ли контекст до платного запроса')
    ..writeln();
  final Map<String, Object?> run = _readRunJson();
  final Object? shapes = run['request_shapes'];
  if (shapes is Map && shapes.isNotEmpty) {
    out
      ..writeln(
        'Наблюдатель формы стоит на транспорте **пути v3**; у прежнего пути '
        'запросы идут мимо него, поэтому его строка — `—`. Число утверждений '
        '`20` — это предел усечения контекста ([kRunContextMaxStatements]).',
      )
      ..writeln()
      ..writeln(
        '| Ячейка | Запросов | С `<already_created>` | Утверждений в запросе '
        '| Байты тел |',
      )
      ..writeln('|---|---:|---:|---|---|');
    for (final MapEntry<Object?, Object?> entry in shapes.entries) {
      final Object? raw = entry.value;
      if (raw is! List || raw.isEmpty) {
        out.writeln('| ${entry.key} | — | — | — | — |');
        continue;
      }
      final List<Map<String, Object?>> list = <Map<String, Object?>>[
        for (final Object? item in raw)
          if (item is Map) item.cast<String, Object?>(),
      ];
      final int withContext = list.where((Map<String, Object?> shape) {
        final Object? value = shape['already_created'];
        return value is num && value > 0;
      }).length;
      out.writeln(
        '| ${entry.key} | ${list.length} | $withContext '
        '| ${list.map((Map<String, Object?> s) => s['statements']).join('/')} '
        '| ${list.map((Map<String, Object?> s) => s['bytes']).join('/')} |',
      );
    }
    out.writeln();
  } else {
    out
      ..writeln(
        '**Нет данных формы запросов** (`run.json` без `request_shapes`): '
        'дошёл ли контекст до платного запроса, неизвестно.',
      )
      ..writeln();
  }

  // 4. Слепая выборка.
  final int marks = countMarks(kBlindSamplePath);
  final bool sampleFilled = marks > 0;
  out
    ..writeln('## 4. Слепая выборка (TASK ч. 3)')
    ..writeln();
  if (!File(kBlindSamplePath).existsSync()) {
    out
      ..writeln(
        'Файл выборки `$kBlindSamplePath` не создан: сборка — '
        '`dart run tool/blind_sample_s17b.dart`.',
      )
      ..writeln();
  } else if (!sampleFilled) {
    out
      ..writeln(
        'Файл `$kBlindSamplePath` собран, но **не заполнен владельцем**: '
        'доля годных по путям = `not_measured` до разметки. Ключ — '
        '`$kBlindKeyPath` (открывать после заполнения). Расчёт — '
        '`dart run tool/blind_score_s17b.dart`.',
      )
      ..writeln();
  } else {
    out
      ..writeln(
        'Файл `$kBlindSamplePath` размечен ($marks отметок). Доля годных по '
        'путям — `dart run tool/blind_score_s17b.dart` → '
        '`journal/generation-v3/blind-score-17b.md`.',
      )
      ..writeln();
  }

  // 5. Вердикт.
  out
    ..writeln('## 5. Вердикт')
    ..writeln();
  if (!measured) {
    out
      ..writeln('Замер не выполнен: вердикта по гипотезе нет.')
      ..writeln();
  } else {
    final PathOutcome before = baselineV3.outcome;
    final PathOutcome after = contextV3.outcome;
    final bool dupLower =
        before.dupRate != null &&
        after.dupRate != null &&
        after.dupRate! < before.dupRate!;
    final int minUnique = (before.unique * kComparableVolumeThreshold).ceil();
    final bool volumeOk = after.unique >= minUnique;
    final bool cleanOk =
        before.cleanRate != null &&
        after.cleanRate != null &&
        after.cleanRate! >= before.cleanRate! - 0.05;
    if (dupLower && volumeOk && cleanOk) {
      out
        ..writeln(
          'Критерий §0 выполнен: контекст «уже создано» остаётся включённым '
          'постоянно (это исправление, а не эксперимент). Перемер шести '
          'решающих ячеек и пересчёт N*/критерия — следующий шаг (TASK ч. 4 '
          'п. 10, потолок 1,00 USD).',
        )
        ..writeln();
    } else {
      out
        ..writeln(
          'Критерий §0 **не выполнен** (`dupRate` ${_percent(before.dupRate)} → '
          '${_percent(after.dupRate)}, уникальных ${before.unique} → '
          '${after.unique}, cleanRate ${_percent(before.cleanRate)} → '
          '${_percent(after.cleanRate)}). Факт фиксируется числами; работа над '
          'дублями уходит в промпт `gen-cards-v3` (S18). Пороги валидатора, '
          'определения метрик и формулировки промптов этим срезом не менялись.',
        )
        ..writeln();
    }
  }
  out.writeln(
    '_Снимок кода ячеек:_ '
    '${<String>{...baseline.values.map((Cell c) => c.codeVersion ?? '?'), ...fresh.values.map((Cell c) => c.codeVersion ?? '?')}.join(', ')}.',
  );

  File(kOutputPath).parent.createSync(recursive: true);
  File(kOutputPath).writeAsStringSync(out.toString(), flush: true);
  stdout
    ..writeln('Записано: $kOutputPath')
    ..writeln(
      'Ячеек: база ${baseline.length}, замер ${fresh.length}; '
      'измерено: ${measured ? 'да' : 'нет'}',
    );
}

Map<String, Object?> _readRunJson() {
  final File file = File('$kNewCellsDir/../run.json');
  if (!file.existsSync()) return const <String, Object?>{};
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}
