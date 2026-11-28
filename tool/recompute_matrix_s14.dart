/// Пересчёт существующей матрицы среза 12 по правилам среза 14 (TASK, часть 2–3).
///
/// Вход — **существующие** записи `journal/generation-v3/live-s12/matrix.jsonl`
/// (новых платных прогонов не делается). Выход — `matrix-s14.md` рядом:
/// 1) `absoluteClean` — число чистых карточек рядом с `cleanRate`: доля без
///    объёма вводит в заблуждение (73 против 292 — разные величины);
/// 2) `cleanRate_matched` — доля чистых от произведённых на сопоставимой базе:
///    при `coverage == 1` у пути нет единиц без произведённой карточки, значит
///    из базы не выпадает ни одна карточка (`matched = произведено`); при
///    неполном покрытии пер-юнитная база из агрегатов невосстановима — `null`,
///    а не догадка;
/// 3) критерий флага (TASK п. 8): `cleanRate_matched` v3 ≥ 95 % **и**
///    `absoluteClean(v3) ≥ absoluteClean(legacy)` на всех решающих ячейках
///    80/150/300. Вердикт — явный, без «продолжаем наблюдать».
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/recompute_matrix_s14.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/matrix_comparison.dart';

/// Одна ячейка матрицы из `matrix.jsonl`.
class RecomputeCell {
  /// Создаёт ячейку.
  const RecomputeCell({
    required this.material,
    required this.requested,
    required this.path,
    required this.status,
    required this.stage,
    required this.accepted,
    required this.generated,
    required this.cleanAccepted,
    required this.coverage,
  });

  /// Имя материала.
  final String material;

  /// Заказ карточек.
  final int requested;

  /// Путь: `legacy` или `v3`.
  final String path;

  /// Статус ячейки (`ran`/`not_run`/`failed`).
  final String status;

  /// Терминальный этап отчёта.
  final String? stage;

  /// Принято карточек.
  final int accepted;

  /// Произведено моделью (принято + отброшено + дубли).
  final int generated;

  /// Принято без пометок (число чистых).
  final int cleanAccepted;

  /// Доля единиц с произведённой карточкой (`null` — данных нет).
  final double? coverage;

  /// Абсолютное число чистых карточек (срез 14, п. 6).
  int get absoluteClean => cleanAccepted;

  /// cleanRate на сопоставимой базе (по агрегатам покрытия).
  double? get cleanRateMatched => cleanRateMatchedFromCoverage(
    clean: cleanAccepted,
    generated: generated,
    coverage: coverage,
  );

  /// Ключ пары «материал + заказ».
  String get pairKey => '$material\u0000$requested';

  /// Разбор строки JSONL; `null` — строка без метрик (not_run/failed).
  static RecomputeCell? fromJson(Map<String, Object?> json) {
    final Object? metrics = json['metrics'];
    if (metrics is! Map<String, Object?>) return null;
    int? number(Object? value) => value is num ? value.toInt() : null;
    final int? accepted = number(metrics['accepted']);
    final int? generated = number(metrics['generated']);
    final int? cleanAccepted = number(metrics['clean_accepted']);
    if (accepted == null || generated == null || cleanAccepted == null) {
      return null;
    }
    final Object? coverage = metrics['coverage'];
    return RecomputeCell(
      material: json['material']! as String,
      requested: (json['requested']! as num).toInt(),
      path: json['path']! as String,
      status: json['status']! as String,
      stage: json['stage'] as String?,
      accepted: accepted,
      generated: generated,
      cleanAccepted: cleanAccepted,
      coverage: coverage is num ? coverage.toDouble() : null,
    );
  }
}

void main() {
  final File source = File('journal/generation-v3/live-s12/matrix.jsonl');
  if (!source.existsSync()) {
    stderr.writeln('Нет файла ${source.path}');
    exitCode = 1;
    return;
  }
  final List<RecomputeCell> cells = <RecomputeCell>[
    for (final String line in source.readAsLinesSync())
      if (line.trim().isNotEmpty)
        if (RecomputeCell.fromJson(jsonDecode(line) as Map<String, Object?>)
            case final RecomputeCell cell)
          cell,
  ];

  final String markdown = _report(cells);
  final File output = File('journal/generation-v3/live-s12/matrix-s14.md');
  output.writeAsStringSync(markdown, flush: true);
  stdout.write(markdown);
  stdout.writeln('Записано: ${output.path}');
}

String _report(List<RecomputeCell> cells) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('# Срез 14 — сопоставимая база и вердикт по флагу')
    ..writeln()
    ..writeln(
      'Источник — существующие `live-s12/matrix.jsonl` (новых платных '
      'прогонов не делалось). Две величины рядом: **absoluteClean** — число '
      'чистых карточек (доля без объёма вводит в заблуждение: 100 % из 15 и '
      '97 % из 189 — разное) и **cleanRate_matched** — чистые / произведённые '
      'на сопоставимой базе.',
    )
    ..writeln()
    ..writeln(
      'Сопоставимая база: единицы, где **оба** пути произвели хотя бы одну '
      'карточку. В `matrix.jsonl` нет пер-юнитных карточек, но есть '
      '`coverage`; у обоих путей во всех решающих ячейках `coverage = 100 %` — '
      'единиц без карточки нет, значит из базы не выпадает ни одна '
      'произведённая карточка (`matched = произведено`). При неполном '
      'покрытии база из агрегатов **невосстановима** — там было бы `—`, а не '
      'догадка. «Топ-80 по salience» для ячеек 150/300 требует пер-карточных '
      'значимостей, которых матрица не сохранила; это ограничение L230, а не '
      'подмена.',
    )
    ..writeln()
    ..writeln(
      '| Материал | Заказ | Путь | Статус | Принято | Произведено | '
      'absoluteClean | cleanRate_matched | coverage | Решающая |',
    )
    ..writeln('|---|---:|---|---|---:|---:|---:|---:|---:|---|');
  for (final RecomputeCell cell in cells) {
    buffer.writeln(
      '| ${cell.material} | ${cell.requested} | ${cell.path} | '
      '${cell.status} | ${cell.accepted} | ${cell.generated} | '
      '${cell.absoluteClean} | ${_percent(cell.cleanRateMatched)} | '
      '${_percent(cell.coverage)} | '
      '${isDecisiveCell(cell.requested) ? 'да' : 'нет (n мал)'} |',
    );
  }

  final Map<String, List<RecomputeCell>> pairs =
      <String, List<RecomputeCell>>{};
  for (final RecomputeCell cell in cells) {
    pairs.putIfAbsent(cell.pairKey, () => <RecomputeCell>[]).add(cell);
  }

  buffer
    ..writeln()
    ..writeln('## Критерий флага по решающим ячейкам (80/150/300)')
    ..writeln()
    ..writeln(
      'Критерий (TASK п. 8, окончательный): v3 `cleanRate_matched` ≥ '
      '${(kFlagCleanRateThreshold * 100).toStringAsFixed(0)} % **и** '
      '`absoluteClean(v3) ≥ absoluteClean(legacy)` на всех решающих ячейках.',
    )
    ..writeln()
    ..writeln(
      '| Материал | Заказ | legacy absoluteClean | v3 absoluteClean | '
      'v3 cleanRate_matched | ≥ 95 % | объём | Вердикт |',
    )
    ..writeln('|---|---:|---:|---:|---:|---|---|---|');
  var compared = 0;
  var met = 0;
  var notMet = 0;
  final List<String> notMetRows = <String>[];
  final List<String> pairKeys = pairs.keys.toList()..sort();
  for (final String key in pairKeys) {
    final List<RecomputeCell> pair = pairs[key]!;
    final RecomputeCell? legacy = _ofPath(pair, 'legacy');
    final RecomputeCell? v3 = _ofPath(pair, 'v3');
    if (legacy == null || v3 == null) continue;
    final int requested = legacy.requested;
    final FlagCriterionVerdict verdict = flagCriterion(
      requested: requested,
      v3CleanRateMatched: v3.cleanRateMatched,
      v3AbsoluteClean: v3.absoluteClean,
      legacyAbsoluteClean: legacy.absoluteClean,
    );
    if (verdict == FlagCriterionVerdict.notDecisive) continue;
    compared++;
    if (verdict == FlagCriterionVerdict.met) {
      met++;
    } else {
      notMet++;
      notMetRows.add(
        '$legacy.material $requested: v3 '
        '${_percent(v3.cleanRateMatched)} / $v3.absoluteClean чистых '
        'против legacy $legacy.absoluteClean',
      );
    }
    final bool cleanOk =
        v3.cleanRateMatched != null &&
        v3.cleanRateMatched! >= kFlagCleanRateThreshold;
    final bool volumeOk = v3.absoluteClean >= legacy.absoluteClean;
    buffer.writeln(
      '| ${legacy.material} | $requested | ${legacy.absoluteClean} | '
      '${v3.absoluteClean} | ${_percent(v3.cleanRateMatched)} | '
      '${cleanOk ? 'да' : 'нет'} | ${volumeOk ? 'да' : 'нет'} | '
      '${verdict == FlagCriterionVerdict.met ? 'выполнен' : '**не выполнен**'} |',
    );
  }

  final bool criterionMet = compared > 0 && notMet == 0;
  buffer
    ..writeln()
    ..writeln(
      'Сравнено решающих пар: **$compared**, критерий выполнен на **$met**, '
      'не выполнен на **$notMet**.',
    )
    ..writeln()
    ..writeln(
      criterionMet
          ? '**Критерий выполнен.** v3 `cleanRate_matched` ≥ 95 % и '
                '`absoluteClean` не меньше legacy на всех решающих ячейках — '
                '`generationPipelineV3` включается по умолчанию, legacy '
                'остаётся доступен выключением флага в настройках.'
          : '**Критерий не выполнен.** Флаг остаётся выключенным; расхождения '
                'списком уходят в S15 как работа над промптом.',
    );
  if (notMetRows.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Расхождения:')
      ..writeln(notMetRows.map((String row) => '- $row').join('\n'));
  }
  buffer
    ..writeln()
    ..writeln('## Разбор 188/300 после среза 14')
    ..writeln()
    ..writeln(
      'В старых записях статьи заказ 300 дал 188 принятых при `stage = ready`: '
      'план повторял слоты `unit_id + angle` сверх четырёх на единицу. Срез 14 '
      'запрещает такие слоты конструктором плана: `planned = capacity = 188`, '
      '`requested` остаётся 300, план помечен `materialLimited`; итог прогона — '
      '`partial` с причиной `exhausted_material` и числом 188, добор не делает '
      'ни одного запроса (свободных слотов нет). Числа таблицы выше — из '
      'прогонов S12 (новых платных не было), поэтому строка «ready» в них ещё '
      'старая; при следующем живом прогоне ячейка придёт как `partial`.',
    );
  return buffer.toString();
}

/// Ячейка пути [path] из пары; `null` — пути в паре нет.
RecomputeCell? _ofPath(List<RecomputeCell> pair, String path) {
  for (final RecomputeCell cell in pair) {
    if (cell.path == path) return cell;
  }
  return null;
}

String _percent(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';
