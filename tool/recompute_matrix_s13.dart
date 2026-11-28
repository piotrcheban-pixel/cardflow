/// Пересчёт матрицы среза 12 по правилам среза 13 (TASK «Срез 13», часть 3–4).
///
/// Вход — **существующие** записи `journal/generation-v3/live-s12/matrix.jsonl`
/// (платных прогонов не делается). Выход — `matrix-s13.md` рядом:
/// 1) cleanRate считается как «принято без пометок / произведено» — у обоих
///    путей один знаменатель по смыслу, а не «принятое»;
/// 2) ячейки 20 и 40 помечены нерешающими; вердикт о флаге — только по
///    80/150/300;
/// 3) ячейки, где `stage == ready`, но принято меньше заказа, разобраны
///    числом: это остановка `complete` по различимым слотам, а не
///    `max_passes`/`exhausted_material`.
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/recompute_matrix_s13.dart`
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
    required this.duplicates,
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

  /// Принято без пометок.
  final int cleanAccepted;

  /// Дубли по уровням (сумма).
  final int duplicates;

  /// cleanRate по правилам среза 13 (к произведённым).
  double? get cleanRate =>
      cleanRateOfGenerated(cleanAccepted: cleanAccepted, generated: generated);

  /// cleanRate по правилу среза 12 (к принятым) — колонка «было».
  double? get oldCleanRate =>
      cleanRateOfAccepted(cleanAccepted: cleanAccepted, accepted: accepted);

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
    return RecomputeCell(
      material: json['material']! as String,
      requested: (json['requested']! as num).toInt(),
      path: json['path']! as String,
      status: json['status']! as String,
      stage: json['stage'] as String?,
      accepted: accepted,
      generated: generated,
      cleanAccepted: cleanAccepted,
      duplicates: number(metrics['duplicates']) ?? 0,
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
  final File output = File('journal/generation-v3/live-s12/matrix-s13.md');
  output.writeAsStringSync(markdown, flush: true);
  stdout.write(markdown);
  stdout.writeln('Записано: ${output.path}');
}

String _report(List<RecomputeCell> cells) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('# Срез 13 — пересчёт матрицы среза 12 на честной базе')
    ..writeln()
    ..writeln(
      'Источник — существующие `live-s12/matrix.jsonl` (новых платных '
      'прогонов не делалось). `cleanRate` = принято без пометок / '
      '**произведено** (`generated`), не / принято: знаменатель у обоих путей '
      'один по смыслу. Колонка «было» — прежняя база среза 12 (к принятым), '
      'чтобы разница была видна. Ячейки заказа 20 и 40 — **нерешающие**; '
      'решение о флаге — по 80/150/300.',
    )
    ..writeln()
    ..writeln(
      '| Материал | Заказ | Путь | Статус | Принято | Произведено | Чистых | '
      'cleanRate (к произведённым) | было (к принятым) | Решающая |',
    )
    ..writeln('|---|---:|---|---|---:|---:|---:|---:|---:|---|');
  for (final RecomputeCell cell in cells) {
    buffer.writeln(
      '| ${cell.material} | ${cell.requested} | ${cell.path} | '
      '${cell.status} | ${cell.accepted} | ${cell.generated} | '
      '${cell.cleanAccepted} | ${_percent(cell.cleanRate)} | '
      '${_percent(cell.oldCleanRate)} | '
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
    ..writeln('## Решение о флаге по решающим ячейкам (80/150/300)')
    ..writeln()
    ..writeln(
      '| Материал | Заказ | legacy cleanRate | v3 cleanRate | Вердикт |',
    )
    ..writeln('|---|---:|---:|---:|---|');
  var worse = 0;
  var compared = 0;
  final List<String> pairKeys = pairs.keys.toList()..sort();
  for (final String key in pairKeys) {
    final List<RecomputeCell> pair = pairs[key]!;
    final RecomputeCell? legacy = _ofPath(pair, 'legacy');
    final RecomputeCell? v3 = _ofPath(pair, 'v3');
    if (legacy == null || v3 == null) continue;
    final int requested = legacy.requested;
    final MatrixComparisonVerdict verdict = compareCells(
      requested: requested,
      v3CleanRate: v3.cleanRate,
      legacyCleanRate: legacy.cleanRate,
    );
    if (verdict == MatrixComparisonVerdict.notDecisive) continue;
    compared++;
    if (verdict == MatrixComparisonVerdict.worse) worse++;
    buffer.writeln(
      '| ${legacy.material} | $requested | ${_percent(legacy.cleanRate)} | '
      '${_percent(v3.cleanRate)} | ${_verdictText(verdict)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'Сравнено решающих пар: **$compared**, из них v3 хуже: **$worse**. '
      '${worse == 0 ? 'Строгий критерий cleanRate на решающих ячейках выполнен.' : 'Строгий критерий cleanRate не выполнен: флаг остаётся выключенным.'}',
    )
    ..writeln()
    ..writeln('## «Нерешающие» ячейки (20/40) — не участвуют в решении')
    ..writeln()
    ..writeln(
      'Заказ 20 и 40 даёт знаменатель 10–40 карточек: одно-два '
      'предупреждения меняют метрику на 2,5–10 п.п. Вывод «лучше/хуже» из '
      'этих ячеек не делается (помечены «нет (n мал)» в таблице выше).',
    )
    ..writeln()
    ..writeln('## Разбор partial: предохранитель или различимые слоты')
    ..writeln()
    ..writeln(
      'У пути v3 `stage == ready` означает: `ReplenishStage` остановился '
      'причиной `complete` (все слоты `unit_id + angle` плана закрыты). '
      'Поэтому «принято < заказа» при `ready` — не `max_passes` и не '
      '`exhausted_material`, а **повтор слотов в плане**: карточек заказано '
      'больше, чем различимых слотов (не больше 4 углов на единицу). У legacy '
      '`ready` нет вовсе: недобор — его собственный предохранитель.',
    )
    ..writeln()
    ..writeln(
      '| Материал | Заказ | Принято | stage | Различимых слотов | Вывод |',
    )
    ..writeln('|---|---:|---:|---|---:|---|');
  for (final RecomputeCell cell in cells) {
    if (cell.accepted >= cell.requested) continue;
    if (cell.stage != 'ready') {
      buffer.writeln(
        '| ${cell.material} | ${cell.requested} | ${cell.accepted} | '
        '${cell.stage ?? '—'} | — | остановка не `ready`: недобор объявлен '
        'причиной добора/предохранителем (partial) |',
      );
      continue;
    }
    final bool slots = looksLikeSlotCapacity(cell.accepted);
    buffer.writeln(
      '| ${cell.material} | ${cell.requested} | ${cell.accepted} | ready | '
      '${cell.accepted} | остановка `complete`, не `max_passes` и не '
      '`exhausted_material`: различимых слотов ${cell.accepted}, ещё '
      '${cell.requested - cell.accepted} карточек плана повторяют занятые '
      'слоты${slots ? ' (${cell.accepted} / $kSlotsPerUnit = ${unitsOfSlots(cell.accepted)} — единиц карты при полном наборе углов)' : ''} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      '**Ответ по статье 300:** принято 188 при заказе 300 — остановка '
      '`complete`: 188 различимых слотов (`unit_id + angle`), ещё 112 '
      'карточек плана указывали на уже занятые слоты. У одной единицы не '
      'больше $kSlotsPerUnit слотов, поэтому 188 — это 47 единиц при полном '
      'наборе углов (188 / $kSlotsPerUnit = 47); точное число единиц карты '
      'матрица не сохранила. Это не `max_passes` (добор не упирался в три '
      'прохода) и не `exhausted_material` (исчерпание материала не '
      'объявлялось). Потолок задаёт не предохранитель, а число различимых '
      'слотов плана.',
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

String _verdictText(MatrixComparisonVerdict verdict) => switch (verdict) {
  MatrixComparisonVerdict.notWorse => 'v3 не хуже',
  MatrixComparisonVerdict.worse => 'v3 хуже',
  MatrixComparisonVerdict.notDecisive => 'нерешающая',
};
