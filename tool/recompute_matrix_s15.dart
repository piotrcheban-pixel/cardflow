/// Пересчёт живого замера среза 15 **из пер-ячеечных `run.json`** (TASK, часть
/// 2, п. 6 и часть 3): новых запросов не делает, каждое число — из снимка
/// ячейки `journal/generation-v3/live-s15/cells/<cellId>.json`.
///
/// Что считается:
/// 1) `absoluteClean` и `cleanRate` (общий) — из агрегата ячейки;
/// 2) `matchedSubset` — **из пер-юнитных данных** (`metrics.unit_coverage`):
///    разделы, где оба пути произвели карточки; единицы карты v3 внутри них;
///    значимость — фактическая (`salience` единиц), «топ-80» — по разделам;
/// 3) критерий флага — `cleanRate_matched(v3) ≥ 95 %` и
///    `absoluteClean(v3) ≥ absoluteClean(legacy)` на всех решающих ячейках;
///    меньше 10 единиц в базе — ячейка нерешающая.
///
/// Строки без `code_version` — `legacy-schema`: в сравнение не идут.
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/recompute_matrix_s15.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/matrix_comparison.dart';

/// Заказы решающих ячеек среза 15 (те же, что мерил стенд).
const List<int> kDecisiveSizes = <int>[80, 150, 300];

/// Одна ячейка замера из `cells/<cellId>.json`.
class S15Cell {
  S15Cell({
    required this.cellId,
    required this.material,
    required this.requested,
    required this.path,
    required this.status,
    required this.codeVersion,
    required List<ProductionUnit> units,
    required this.promptVersions,
    this.accepted,
    this.generated,
    this.cleanAccepted,
    this.cleanRate,
    this.stage,
    this.reason,
    this.errorCode,
    this.durationMs,
  }) : units = List<ProductionUnit>.unmodifiable(units);

  /// Идентификатор ячейки.
  final String cellId;

  /// Материал.
  final String material;

  /// Заказ карточек.
  final int requested;

  /// Путь: `legacy` или `v3`.
  final String path;

  /// Статус (`ran`/`not_run`/`failed`).
  final String status;

  /// Короткий хеш кода снятия; `null` — строка старой схемы.
  final String? codeVersion;

  /// Пер-юнитные данные (`metrics.unit_coverage`).
  final List<ProductionUnit> units;

  /// Версии промптов прогона.
  final Map<String, String> promptVersions;

  /// Принято карточек.
  final int? accepted;

  /// Произведено моделью (принято + отброшено + дубли).
  final int? generated;

  /// Принято без пометок.
  final int? cleanAccepted;

  /// cleanRate отчёта (общий, знаменатель — произведённые).
  final double? cleanRate;

  /// Терминальный этап.
  final String? stage;

  /// Причина `not_run`/`failed`.
  final String? reason;

  /// Код ошибки.
  final String? errorCode;

  /// Длительность.
  final int? durationMs;

  /// Абсолютное число чистых карточек.
  int get absoluteClean => cleanAccepted ?? 0;

  /// true — строка снята без `code_version`: в сравнение не идёт.
  bool get isLegacySchema => codeVersion == null || codeVersion!.trim().isEmpty;

  /// true — отчёт есть: можно сравнивать числа.
  bool get hasMetrics => status == 'ran' && cleanRate != null;

  /// Ключ пары «материал + заказ».
  String get pairKey => '$material\u0000$requested';

  /// Разбор снимка ячейки; `null` — файл не той формы.
  static S15Cell? fromJson(Map<String, Object?> json) {
    final Object? cellId = json['cell_id'];
    final Object? material = json['material'];
    final Object? requested = json['requested'];
    final Object? path = json['path'];
    final Object? status = json['status'];
    if (cellId is! String ||
        material is! String ||
        requested is! num ||
        path is! String ||
        status is! String) {
      return null;
    }
    final Object? metrics = json['metrics'];
    final Map<String, Object?> metricMap = metrics is Map<String, Object?>
        ? metrics
        : const <String, Object?>{};
    int? number(Object? value) => value is num ? value.toInt() : null;
    final Object? unitsRaw = metricMap['unit_coverage'];
    final List<ProductionUnit> units = <ProductionUnit>[
      if (unitsRaw is List)
        for (final Object? item in unitsRaw)
          if (item is Map<String, Object?>)
            if (_unitOf(item) case final ProductionUnit unit) unit,
    ];
    final Object? prompts = json['prompt_versions'];
    return S15Cell(
      cellId: cellId,
      material: material,
      requested: requested.toInt(),
      path: path,
      status: status,
      codeVersion: json['code_version'] as String?,
      units: units,
      promptVersions: <String, String>{
        if (prompts is Map)
          for (final MapEntry<Object?, Object?> entry in prompts.entries)
            if (entry.key is String && entry.value is String)
              entry.key! as String: entry.value! as String,
      },
      accepted: number(metricMap['accepted']),
      generated: number(metricMap['generated']),
      cleanAccepted: number(metricMap['clean_accepted']),
      cleanRate: metricMap['clean_rate'] is num
          ? (metricMap['clean_rate']! as num).toDouble()
          : null,
      stage: json['stage'] as String?,
      reason: json['reason'] as String?,
      errorCode: json['error_code'] as String?,
      durationMs: number(json['duration_ms']),
    );
  }

  static ProductionUnit? _unitOf(Map<String, Object?> json) {
    final Object? unitId = json['unit_id'];
    final Object? produced = json['produced'];
    final Object? clean = json['clean'];
    if (unitId is! String || produced is! num || clean is! num) return null;
    final Map<String, int> codes = <String, int>{};
    final Object? rawCodes = json['warning_codes'];
    if (rawCodes is Map) {
      for (final MapEntry<Object?, Object?> entry in rawCodes.entries) {
        if (entry.key is String && entry.value is num) {
          codes[entry.key! as String] = (entry.value! as num).toInt();
        }
      }
    }
    return ProductionUnit(
      unitId: unitId,
      sectionId: json['section_id'] as String?,
      salience: json['salience'] is num
          ? (json['salience']! as num).toDouble()
          : null,
      produced: produced.toInt(),
      clean: clean.toInt(),
      warningCodes: codes,
    );
  }
}

/// Пара ячеек одного материала и заказа.
class S15Pair {
  S15Pair({
    required this.material,
    required this.requested,
    this.legacy,
    this.v3,
  });

  final String material;
  final int requested;
  S15Cell? legacy;
  S15Cell? v3;

  /// Ключ пары.
  String get key => '$material\u0000$requested';

  /// Сопоставимая база пары (из пер-юнитных данных); `null` — обеих ячеек нет.
  MatchedUnitBase? get base {
    final S15Cell? left = legacy;
    final S15Cell? right = v3;
    if (left == null || right == null) return null;
    if (!left.hasMetrics || !right.hasMetrics) return null;
    return MatchedUnitBase.of(
      legacy: left.units,
      v3: right.units,
      topUnits: 80,
    );
  }

  /// Ячейка пути.
  S15Cell? cellOf(String path) => path == 'legacy' ? legacy : v3;

  /// Вердикт критерия по паре.
  FlagCriterionVerdict get verdict {
    final MatchedUnitBase? matched = base;
    final S15Cell? right = v3;
    final S15Cell? left = legacy;
    if (matched == null || right == null || left == null) {
      return FlagCriterionVerdict.notDecisive;
    }
    return flagCriterion(
      requested: requested,
      v3CleanRateMatched: matched.v3CleanRate,
      v3AbsoluteClean: right.absoluteClean,
      legacyAbsoluteClean: left.absoluteClean,
      matchedUnits: matched.v3UnitCount,
    );
  }
}

void main() {
  final Directory cellsDir = Directory('journal/generation-v3/live-s15/cells');
  if (!cellsDir.existsSync()) {
    stderr.writeln('Нет каталога ${cellsDir.path}: сначала живой перемер S15');
    exitCode = 1;
    return;
  }
  final List<S15Cell> cells = <S15Cell>[
    for (final FileSystemEntity entity in cellsDir.listSync())
      if (entity is File && entity.path.endsWith('.json'))
        if (S15Cell.fromJson(
              jsonDecode(entity.readAsStringSync()) as Map<String, Object?>,
            )
            case final S15Cell cell)
          cell,
  ]..sort((S15Cell a, S15Cell b) => a.cellId.compareTo(b.cellId));

  final List<S15Cell> comparable = <S15Cell>[
    for (final S15Cell cell in cells)
      if (!cell.isLegacySchema) cell,
  ];
  final List<S15Cell> legacySchema = <S15Cell>[
    for (final S15Cell cell in cells)
      if (cell.isLegacySchema) cell,
  ];

  final Map<String, S15Pair> pairs = <String, S15Pair>{};
  for (final S15Cell cell in comparable) {
    final S15Pair pair = pairs.putIfAbsent(
      cell.pairKey,
      () => S15Pair(material: cell.material, requested: cell.requested),
    );
    if (cell.path == 'legacy') {
      pair.legacy = cell;
    } else {
      pair.v3 = cell;
    }
  }
  final List<S15Pair> ordered = pairs.values.toList()
    ..sort((S15Pair a, S15Pair b) {
      final int byMaterial = a.material.compareTo(b.material);
      return byMaterial != 0 ? byMaterial : a.requested.compareTo(b.requested);
    });
  final Map<String, S15Pair> byKey = <String, S15Pair>{
    for (final S15Pair pair in ordered) pair.key: pair,
  };

  final String markdown = _report(
    cells: cells,
    comparable: comparable,
    legacySchema: legacySchema,
    pairs: ordered,
    pairsByKey: byKey,
  );
  final File target = File('journal/generation-v3/live-s15/matrix-s15.md');
  target.writeAsStringSync(markdown, flush: true);
  stdout.writeln(markdown);
}

String _report({
  required List<S15Cell> cells,
  required List<S15Cell> comparable,
  required List<S15Cell> legacySchema,
  required List<S15Pair> pairs,
  required Map<String, S15Pair> pairsByKey,
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('# Срез 15 — честный перемер решающих ячеек')
    ..writeln()
    ..writeln(
      'Источник — пер-ячеечные `live-s15/cells/<cellId>.json` (без повторных '
      'запросов). `cleanRate` — доля чистых от **произведённых**; '
      '`cleanRate_matched` — на сопоставимой базе, построенной из '
      '**пер-юнитных** данных: разделы, где оба пути произвели карточки. '
      '«Единиц» — единицы карты v3 внутри сопоставимых разделов: пространства '
      'id единиц у путей разные, общий ключ — раздел (Q27).',
    )
    ..writeln();
  if (legacySchema.isNotEmpty) {
    buffer
      ..writeln(
        '**legacy-schema (в сравнение не идут):** ${legacySchema.length} '
        'строк без `code_version` — ${legacySchema.map((S15Cell c) => c.cellId).join(', ')}.',
      )
      ..writeln();
  }

  buffer
    ..writeln('## Ячейки')
    ..writeln()
    ..writeln(
      '| Материал | Заказ | Путь | Статус | Принято | Произведено | '
      'absoluteClean | cleanRate | cleanRate_matched | Разделов в базе | '
      'Единиц в базе | codeVersion | Примечание |',
    )
    ..writeln('|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|');
  for (final S15Cell cell in cells) {
    final S15Pair? pair = pairsByKey[cell.pairKey];
    final MatchedUnitBase? base = pair?.base;
    final double? matchedRate = base == null
        ? null
        : (cell.path == 'legacy' ? base.legacyCleanRate : base.v3CleanRate);
    buffer.writeln(
      '| ${cell.material} | ${cell.requested} | ${cell.path} | '
      '${cell.status} | ${cell.accepted ?? '—'} | ${cell.generated ?? '—'} | '
      '${cell.hasMetrics ? cell.absoluteClean : '—'} | '
      '${_percent(cell.cleanRate)} | ${_percent(matchedRate)} | '
      '${base?.sectionCount ?? '—'} | ${base?.v3UnitCount ?? '—'} | '
      '${cell.codeVersion ?? 'legacy-schema'} | ${_note(cell, base)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Критерий флага: решающие пары')
    ..writeln()
    ..writeln(
      'Критерий (не пересматривается): `cleanRate_matched(v3) ≥ 95 %` **и** '
      '`absoluteClean(v3) ≥ absoluteClean(legacy)` на всех решающих ячейках '
      '80/150/300. Меньше 10 единиц в базе — ячейка нерешающая.',
    )
    ..writeln()
    ..writeln(
      '| Материал | Заказ | legacy absoluteClean | v3 absoluteClean | '
      'legacy cleanRate_matched | v3 cleanRate_matched | Единиц | ≥ 95 % | '
      'объём | Вердикт |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---|---|---|');
  var met = 0;
  var notMet = 0;
  var notDecisive = 0;
  for (final S15Pair pair in pairs) {
    final MatchedUnitBase? base = pair.base;
    final FlagCriterionVerdict verdict = pair.verdict;
    if (verdict == FlagCriterionVerdict.met) met++;
    if (verdict == FlagCriterionVerdict.notMet) notMet++;
    if (verdict == FlagCriterionVerdict.notDecisive) notDecisive++;
    final bool? cleanThreshold = base?.v3CleanRate == null
        ? null
        : base!.v3CleanRate! >= kFlagCleanRateThreshold;
    final bool? volume = pair.v3 == null || pair.legacy == null
        ? null
        : pair.v3!.absoluteClean >= pair.legacy!.absoluteClean;
    buffer.writeln(
      '| ${pair.material} | ${pair.requested} | '
      '${pair.legacy?.absoluteClean ?? '—'} | '
      '${pair.v3?.absoluteClean ?? '—'} | '
      '${_percent(base?.legacyCleanRate)} | ${_percent(base?.v3CleanRate)} | '
      '${base?.v3UnitCount ?? '—'} | ${_bool(cleanThreshold)} | '
      '${_bool(volume)} | ${_verdict(verdict)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'Пар: ${pairs.length}; критерий выполнен: $met; не выполнен: $notMet; '
      'нерешающих: $notDecisive.',
    )
    ..writeln();

  final String verdictText;
  if (pairs.isEmpty) {
    verdictText =
        '**Вердикт: не выведен** — сопоставимых пар нет: перемер не выполнен.';
  } else if (notMet > 0) {
    verdictText =
        '**Вердикт: критерий НЕ выполнен** на $notMet из ${pairs.length} '
        'решающих парах — флаг `generationPipelineV3` остаётся **выключенным**; '
        'расхождения по промпту уходят в следующий срез как работа над промптом.';
  } else if (notDecisive > 0) {
    verdictText =
        '**Вердикт: критерий не выведен** — $notDecisive из ${pairs.length} '
        'решающих пар нерешающие (меньше $kMinMatchedUnits единиц в '
        'сопоставимой базе). Флаг остаётся **выключенным**: включать на '
        'неполном наборе ячеек — подмена решения.';
  } else {
    verdictText =
        '**Вердикт: критерий выполнен** на $met из ${pairs.length} решающих '
        'парах — `generationPipelineV3` включается по умолчанию; legacy '
        'остаётся доступен выключением флага.';
  }
  buffer
    ..writeln(verdictText)
    ..writeln()
    ..writeln('## Прогон')
    ..writeln();
  final List<String> versions = <String>{
    for (final S15Cell cell in comparable)
      if (cell.codeVersion != null) cell.codeVersion!,
  }.toList()..sort();
  final List<String> prompts = <String>{
    for (final S15Cell cell in comparable)
      for (final MapEntry<String, String> entry in cell.promptVersions.entries)
        '${entry.key}=${entry.value}',
  }.toList()..sort();
  buffer
    ..writeln(
      '- Ячеек снято: ${cells.length}; с `code_version`: '
      '${comparable.length}; legacy-schema: ${legacySchema.length}.',
    )
    ..writeln(
      '- `code_version`: ${versions.isEmpty ? '—' : versions.join(', ')}.',
    )
    ..writeln('- Промпты: ${prompts.isEmpty ? '—' : prompts.join(', ')}.')
    ..writeln(
      '- Суммарная длительность ячеек: '
      '${cells.fold<int>(0, (int sum, S15Cell cell) => sum + (cell.durationMs ?? 0)) ~/ 1000} с.',
    );
  return buffer.toString();
}

String _note(S15Cell cell, MatchedUnitBase? base) {
  if (cell.status != 'ran') {
    final String reason = cell.reason ?? '';
    final String code = cell.errorCode == null ? '' : ' (${cell.errorCode})';
    return '$reason$code'.trim();
  }
  if (base == null) return 'нет пары';
  return 'база ${base.sectionCount} разд. / ${base.v3UnitCount} ед.';
}

String _percent(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

String _bool(bool? value) => value == null ? '—' : (value ? 'да' : 'нет');

String _verdict(FlagCriterionVerdict verdict) => switch (verdict) {
  FlagCriterionVerdict.met => 'выполнен',
  FlagCriterionVerdict.notMet => 'не выполнен',
  FlagCriterionVerdict.notDecisive => 'нерешающая',
};
