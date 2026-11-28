/// Пересчёт живого замера среза 16 из пер-ячеечных `cells/*.json`.
///
/// Новых запросов не делает: каждое число — из снимка ячейки
/// `journal/generation-v3/live-s16/cells/<cellId>.json`.
///
/// Критерий флага (TASK «Срез 16», часть 4, п. 12) — три условия на каждой
/// решающей ячейке:
/// 1) `cleanRate(v3) ≥ 95 %` (чистые / все попытки);
/// 2) `dupRate(v3) ≤ dupRate(legacy)` (дубли / все попытки);
/// 3) `absoluteClean(v3) ≥ absoluteClean(legacy)` (число чистых карточек).
///
/// Решающая ячейка — база `MatchedUnitBase` не меньше `kMinMatchedUnits` единиц;
/// меньше — `not_decisive` с причиной, а не «выполнено по умолчанию».
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/recompute_matrix_s16.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/matrix_comparison.dart';

/// Заказы решающих ячеек среза 16.
const List<int> kSizes = <int>[80, 150, 300];

/// Порог cleanRate по TASK.
const double kCleanRateThreshold = 0.95;

/// Одна ячейка замера.
class Cell {
  Cell({
    required this.cellId,
    required this.material,
    required this.requested,
    required this.path,
    required this.status,
    this.codeVersion,
    this.reason,
    this.attempted,
    this.accepted,
    this.duplicates,
    this.clean,
    this.absoluteClean,
    this.cleanRate,
    this.dupRate,
    this.code = const <String, Object?>{},
    required List<ProductionUnit> units,
  }) : units = List<ProductionUnit>.unmodifiable(units);

  final String cellId;
  final String material;
  final int requested;
  final String path;
  final String status;
  final String? codeVersion;
  final String? reason;
  final int? attempted;
  final int? accepted;
  final int? duplicates;
  final int? clean;
  final int? absoluteClean;
  final double? cleanRate;
  final double? dupRate;
  final Map<String, Object?> code;
  final List<ProductionUnit> units;

  bool get isRan => status == 'ran';

  static Cell? fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? metrics = json['metrics'] == null
        ? null
        : (json['metrics']! as Map).cast<String, Object?>();
    // Ячейка без метрик бесполезна для критерия; оставляем status/причину.
    final List<ProductionUnit> units = <ProductionUnit>[];
    final Object? coverage = metrics?['unit_coverage'];
    if (coverage is List) {
      for (final Object? row in coverage) {
        if (row is! Map) continue;
        final Map<String, Object?> unit = row.cast<String, Object?>();
        final Object? produced = unit['produced'];
        final Object? clean = unit['clean'];
        if (produced is! int || clean is! int) continue;
        units.add(
          ProductionUnit(
            unitId: unit['unit_id'] as String? ?? '?',
            sectionId: unit['section_id'] as String?,
            produced: produced,
            clean: clean,
            salience: (unit['salience'] as num?)?.toDouble(),
          ),
        );
      }
    }
    return Cell(
      cellId: json['cell_id'] as String? ?? '?',
      material: json['material'] as String? ?? '?',
      requested: json['requested'] as int? ?? 0,
      path: json['path'] as String? ?? '?',
      status: json['status'] as String? ?? '?',
      codeVersion: json['code_version'] as String?,
      reason: json['reason'] as String?,
      attempted: metrics?['attempted'] as int?,
      accepted: metrics?['accepted'] as int?,
      duplicates: metrics?['duplicates'] as int?,
      clean: metrics?['clean'] as int?,
      absoluteClean: metrics?['absolute_clean'] as int?,
      cleanRate: (metrics?['clean_rate'] as num?)?.toDouble(),
      dupRate: (metrics?['dup_rate'] as num?)?.toDouble(),
      code: metrics ?? const <String, Object?>{},
      units: units,
    );
  }
}

/// Пара ячеек одного материала и заказа.
class Pair {
  Pair(this.material, this.requested, this.legacy, this.v3);

  final String material;
  final int requested;
  final Cell? legacy;
  final Cell? v3;
}

String _pct(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

void main() {
  final Directory dir = Directory('journal/generation-v3/live-s16/cells');
  if (!dir.existsSync()) {
    stderr.writeln('Нет каталога ${dir.path}: сначала живой перемер.');
    exitCode = 1;
    return;
  }
  final List<Cell> cells = <Cell>[];
  for (final FileSystemEntity entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final Object? decoded = jsonDecode(entity.readAsStringSync());
    if (decoded is! Map) continue;
    final Cell? cell = Cell.fromJson(decoded.cast<String, Object?>());
    if (cell != null) cells.add(cell);
  }
  cells.sort((Cell a, Cell b) {
    final int byMaterial = a.material.compareTo(b.material);
    if (byMaterial != 0) return byMaterial;
    final int byRequested = a.requested.compareTo(b.requested);
    if (byRequested != 0) return byRequested;
    return a.path.compareTo(b.path);
  });

  final Map<String, Cell> byKey = <String, Cell>{
    for (final Cell cell in cells)
      '${cell.material}|${cell.requested}|${cell.path}': cell,
  };
  final Set<String> materials = <String>{
    for (final Cell c in cells) c.material,
  };
  final List<Pair> pairs = <Pair>[];
  for (final String material in materials.toList()..sort()) {
    for (final int size in kSizes) {
      final Cell? legacy = byKey['$material|$size|legacy'];
      final Cell? v3 = byKey['$material|$size|v3'];
      if (legacy == null && v3 == null) continue;
      pairs.add(Pair(material, size, legacy, v3));
    }
  }

  final StringBuffer out = StringBuffer()
    ..writeln('# Срез 16 — перемер решающих ячеек и критерий флага')
    ..writeln()
    ..writeln(
      'Источник — пер-ячеечные `live-s16/cells/<cellId>.json` (без повторных '
      'запросов). `cleanRate` = чистые / **все попытки**, `dupRate` = отложенные '
      'дубли / все попытки, `absoluteClean` — число чистых карточек. Критерий '
      'TASK: `cleanRate(v3) ≥ 95 %` **и** `dupRate(v3) ≤ dupRate(legacy)` '
      '**и** `absoluteClean(v3) ≥ absoluteClean(legacy)`; база меньше '
      '$kMinMatchedUnits единиц — ячейка нерешающая.',
    )
    ..writeln()
    ..writeln('## Ячейки')
    ..writeln()
    ..writeln(
      '| Материал | Заказ | Путь | Статус | Попытки | Принято | Дубли | '
      'absoluteClean | cleanRate | dupRate | codeVersion | Примечание |',
    )
    ..writeln('|---|---:|---|---|---:|---:|---:|---:|---:|---:|---|---|');
  for (final Pair pair in pairs) {
    for (final Cell? cell in <Cell?>[pair.legacy, pair.v3]) {
      if (cell == null) continue;
      out.writeln(
        '| ${cell.material} | ${cell.requested} | ${cell.path} | '
        '${cell.status} | ${cell.attempted ?? '—'} | ${cell.accepted ?? '—'} | '
        '${cell.duplicates ?? '—'} | ${cell.absoluteClean ?? '—'} | '
        '${_pct(cell.cleanRate)} | ${_pct(cell.dupRate)} | '
        '${cell.codeVersion ?? '—'} | ${cell.reason ?? ''} |',
      );
    }
  }

  out
    ..writeln()
    ..writeln('## Критерий флага: решающие пары')
    ..writeln()
    ..writeln(
      '| Материал | Заказ | legacy absoluteClean | v3 absoluteClean | '
      'legacy dupRate | v3 dupRate | v3 cleanRate | Чистых ≥ 95 % | '
      'Дубли ≤ legacy | Объём ≥ legacy | Единиц | Вердикт |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---|---|---|---:|---|');
  var decisive = 0;
  var met = 0;
  var notMet = 0;
  var notDecisive = 0;
  final StringBuffer reasons = StringBuffer();
  for (final Pair pair in pairs) {
    final Cell? legacy = pair.legacy;
    final Cell? v3 = pair.v3;
    if (legacy == null || v3 == null || !legacy.isRan || !v3.isRan) {
      notDecisive++;
      out.writeln(
        '| ${pair.material} | ${pair.requested} | — | — | — | — | — | — | — | '
        '— | — | не сравнивалась: не было прогона |',
      );
      continue;
    }
    final MatchedUnitBase base = MatchedUnitBase.of(
      legacy: legacy.units,
      v3: v3.units,
    );
    final bool isDecisive = base.isDecisive;
    final bool cleanOk = (v3.cleanRate ?? 0) >= kCleanRateThreshold;
    final bool dupOk =
        v3.dupRate != null &&
        legacy.dupRate != null &&
        v3.dupRate! <= legacy.dupRate!;
    final bool volumeOk =
        (v3.absoluteClean ?? 0) >= (legacy.absoluteClean ?? 0);
    final bool pairMet = cleanOk && dupOk && volumeOk;
    final String verdict;
    if (!isDecisive) {
      notDecisive++;
      verdict = 'нерешающая';
    } else {
      decisive++;
      if (pairMet) {
        met++;
        verdict = 'выполнен';
      } else {
        notMet++;
        verdict = 'не выполнен';
      }
      if (!pairMet) {
        reasons.writeln(
          '- ${pair.material}, заказ ${pair.requested}: '
          '${!cleanOk ? 'cleanRate ${_pct(v3.cleanRate)} < 95 %; ' : ''}'
          '${!dupOk ? 'dupRate ${_pct(v3.dupRate)} > legacy ${_pct(legacy.dupRate)}; ' : ''}'
          '${!volumeOk ? 'absoluteClean ${v3.absoluteClean} < ${legacy.absoluteClean}; ' : ''}',
        );
      }
    }
    out.writeln(
      '| ${pair.material} | ${pair.requested} | ${legacy.absoluteClean} | '
      '${v3.absoluteClean} | ${_pct(legacy.dupRate)} | ${_pct(v3.dupRate)} | '
      '${_pct(v3.cleanRate)} | ${cleanOk ? 'да' : 'нет'} | '
      '${dupOk ? 'да' : 'нет'} | ${volumeOk ? 'да' : 'нет'} | '
      '${base.v3UnitCount} | $verdict |',
    );
  }
  out
    ..writeln()
    ..writeln(
      'Пар: ${pairs.length}; решающих: $decisive; критерий выполнен: $met; '
      'не выполнен: $notMet; нерешающих: $notDecisive.',
    );
  if (reasons.isNotEmpty) {
    out
      ..writeln()
      ..writeln('### Почему не выполнен')
      ..writeln()
      ..write(reasons);
  }
  final String verdictText = notMet == 0 && decisive > 0
      ? '**Критерий выполнен** — флаг `generationPipelineV3` включается по '
            'умолчанию, legacy остаётся выключением флага.'
      : '**Критерий НЕ выполнен** — флаг остаётся выключенным, расхождения '
            'уходят в следующий срез.';
  out
    ..writeln()
    ..writeln(verdictText)
    ..writeln();
  final File report = File('journal/generation-v3/live-s16/matrix-s16.md');
  report.writeAsStringSync(out.toString());
  stdout.writeln(out.toString());
  stdout.writeln('Записано: ${report.path}');
}
