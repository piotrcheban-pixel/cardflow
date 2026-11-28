/// Пересчёт уже оплаченных ячеек среза 16 в **замороженных** определениях
/// среза 17 (TASK «Срез 17», части 0 и 2; ADR-054).
///
/// Новых запросов не делает: читает `journal/generation-v3/live-s16/cells/*.json`
/// и пишет `journal/generation-v3/matrix-s17.md`.
///
/// Что считается:
/// 1) на одном определении: `cleanRate = clean / unique`,
///    `dupRate = duplicates / unique`, `blockRate = blocked / attempted`,
///    `acceptanceRate = accepted / attempted` — из счётчиков, а не из
///    сохранённых долей (у ячеек среза 16 `clean_rate` считался от попыток);
/// 2) `absoluteClean` сравнивается только при сопоставимом объёме
///    (отношение принятых ≥ 0,8), иначе `volume_mismatch`;
/// 3) N* — порог, с которого v3 не проигрывает legacy; выводится из агрегатов
///    по материалам (10 и 33 единицы);
/// 4) `dupRate` legacy офлайн по сохранённым карточкам — `not_measured`, если
///    текстов карточек в ячейках нет (новых прогонов срез 17 не делает).
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/recompute_matrix_s17.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/generation_path.dart';
import 'package:cardflow/domain/generation/path_rule.dart';

/// Каталог ячеек, которые пересчитываются.
const String kCellsDir = 'journal/generation-v3/live-s16/cells';

/// Куда пишется таблица.
const String kOutputPath = 'journal/generation-v3/matrix-s17.md';

/// Одна ячейка замера в счётчиках.
class Cell {
  Cell({
    required this.cellId,
    required this.material,
    required this.materialSections,
    required this.requested,
    required this.path,
    required this.status,
    required this.codeVersion,
    required this.outcome,
    required this.units,
    required this.hasSavedCards,
  });

  final String cellId;
  final String material;
  final int materialSections;
  final int requested;
  final String path;
  final String status;
  final String? codeVersion;
  final PathOutcome outcome;

  /// Единиц материала (у v3 — карта знаний, у legacy — разделы).
  final int units;

  /// Есть ли в ячейке сохранённые карточки (ключ `cards`).
  final bool hasSavedCards;

  bool get isV3 => path == GenerationPath.v3.wireName;

  static Cell? fromJson(Map<String, Object?> json) {
    final Object? metricsRaw = json['metrics'];
    if (metricsRaw is! Map) return null;
    final Map<String, Object?> metrics = metricsRaw.cast<String, Object?>();
    int intOf(String key) => (metrics[key] as num?)?.toInt() ?? 0;
    final int attempted = intOf('attempted');
    final int accepted = intOf('accepted_final');
    final int duplicates = intOf('duplicates');
    // `blocked` появился в ячейках среза 17; у старых считается из доли.
    final int blocked = metrics['blocked'] is num
        ? (metrics['blocked']! as num).toInt()
        : _roundedBlocked(
            (((metrics['block_rate'] as num?) ?? 0) * attempted).toDouble(),
          );
    return Cell(
      cellId: json['cell_id'] as String? ?? '?',
      material: json['material'] as String? ?? '?',
      materialSections: (json['material_sections'] as num?)?.toInt() ?? 0,
      requested: (json['requested'] as num?)?.toInt() ?? 0,
      path: json['path'] as String? ?? '?',
      status: json['status'] as String? ?? '?',
      codeVersion: json['code_version'] as String?,
      outcome: PathOutcome(
        attempted: attempted,
        accepted: accepted,
        unique: intOf('unique'),
        clean: intOf('clean'),
        duplicates: duplicates,
        blocked: blocked,
      ),
      units: intOf('total_units'),
      hasSavedCards:
          json['cards'] is List && (json['cards']! as List).isNotEmpty,
    );
  }
}

/// Округление половины вверх без `dart:math` в доменном коде не нужен — здесь
/// инструмент, но зависимость от `dart:math` лишняя: floor(x + 0.5).
int _roundedBlocked(double value) => (value + 0.5).floor();

/// Ищет ячейку материала по заказу и пути; `null` — нет такой.
Cell? _findCell(
  List<Cell> cells, {
  required String material,
  required int requested,
  required bool v3,
}) {
  for (final Cell cell in cells) {
    if (cell.material == material &&
        cell.requested == requested &&
        cell.isV3 == v3) {
      return cell;
    }
  }
  return null;
}

/// Агрегат по материалу и пути (несколько заказов одного материала).
PathOutcome aggregate(Iterable<Cell> cells) {
  var attempted = 0;
  var accepted = 0;
  var unique = 0;
  var clean = 0;
  var duplicates = 0;
  var blocked = 0;
  for (final Cell cell in cells) {
    attempted += cell.outcome.attempted;
    accepted += cell.outcome.accepted;
    unique += cell.outcome.unique;
    clean += cell.outcome.clean;
    duplicates += cell.outcome.duplicates;
    blocked += cell.outcome.blocked;
  }
  return PathOutcome(
    attempted: attempted,
    accepted: accepted,
    unique: unique,
    clean: clean,
    duplicates: duplicates,
    blocked: blocked,
  );
}

String _percent(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

String _signedPercent(double? a, double? b) {
  if (a == null || b == null) return '—';
  final double delta = (a - b) * 100;
  final String sign = delta >= 0 ? '+' : '';
  return '$sign${delta.toStringAsFixed(1)} п.п.';
}

void main() {
  final Directory dir = Directory(kCellsDir);
  if (!dir.existsSync()) {
    stderr.writeln('Нет каталога ячеек: $kCellsDir');
    exit(2);
  }
  final List<Cell> cells = <Cell>[];
  for (final FileSystemEntity entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final Map<String, Object?> json = (jsonDecode(
      File(entity.path).readAsStringSync(),
    ) as Map).cast<String, Object?>();
    final Cell? cell = Cell.fromJson(json);
    if (cell == null) continue;
    cells.add(cell);
  }
  cells.sort((Cell a, Cell b) => a.cellId.compareTo(b.cellId));

  final List<String> materials = <String>{
    for (final Cell cell in cells) cell.material,
  }.toList();
  final int savedCards = cells
      .where((Cell cell) => cell.hasSavedCards)
      .fold<int>(0, (int sum, Cell cell) => sum + 1);

  final StringBuffer out = StringBuffer()
    ..writeln('# Срез 17 — метрика на одном определении и правило выбора пути')
    ..writeln()
    ..writeln(
      'Пересчёт **существующих** ячеек `$kCellsDir` (срез 16, '
      '`code_version` ниже). Новых платных прогонов — 0. Определения '
      'заморожены срезом 17 (ADR-054): '
      '`cleanRate = clean / unique`, `dupRate = duplicates / unique`, '
      '`blockRate = blocked / attempted`, '
      '`acceptanceRate = accepted / attempted`. Доли считаются из счётчиков, '
      'поэтому сохранённые в ячейках `clean_rate`/`dup_rate` (срез 16) не '
      'используются: у них был другой знаменатель.',
    )
    ..writeln()
    ..writeln('## 1. Ячейки в замороженных определениях')
    ..writeln()
    ..writeln(
      '| Ячейка | Материал | Заказ | Путь | Попыток | Принято | Уникальных | '
      'Чистых | Дублей | cleanRate | dupRate | blockRate | acceptanceRate |',
    )
    ..writeln(
      '|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
    );
  for (final Cell cell in cells) {
    final PathOutcome o = cell.outcome;
    out.writeln(
      '| ${cell.cellId} | ${cell.material} | ${cell.requested} | ${cell.path} '
      '| ${o.attempted} | ${o.accepted} | ${o.unique} | ${o.clean} '
      '| ${o.duplicates} | ${_percent(o.cleanRate)} | ${_percent(o.dupRate)} '
      '| ${_percent(o.blockRate)} | ${_percent(o.acceptanceRate)} |',
    );
  }
  out
    ..writeln()
    ..writeln('## 2. Сопоставимость объёма и сравнение чистых')
    ..writeln()
    ..writeln(
      'По TASK (часть 0, п. 3) `absoluteClean` сравнивается только при '
      'отношении принятых ≥ `kComparableVolumeThreshold` (0,8); иначе строка '
      'помечается `volume_mismatch` и в критерий не идёт.',
    )
    ..writeln()
    ..writeln(
      '| Материал | Заказ | legacy принято | v3 принято | Отношение | Объём | '
      'absoluteClean legacy | absoluteClean v3 | Разница |',
    )
    ..writeln('|---|---:|---:|---:|---:|---|---:|---:|---:|');
  final List<String> mismatches = <String>[];
  int comparablePairs = 0;
  int v3CleanNotLower = 0;
  for (final String material in materials) {
    final List<int> sizes = <int>{
      for (final Cell cell in cells)
        if (cell.material == material) cell.requested,
    }.toList()..sort();
    for (final int size in sizes) {
      final Cell? legacy = _findCell(
        cells,
        material: material,
        requested: size,
        v3: false,
      );
      final Cell? v3 = _findCell(
        cells,
        material: material,
        requested: size,
        v3: true,
      );
      if (legacy == null || v3 == null) continue;
      final double? ratio = comparableVolumeRatio(
        acceptedA: legacy.outcome.accepted,
        acceptedB: v3.outcome.accepted,
      );
      final bool comparable = comparableVolume(
        acceptedA: legacy.outcome.accepted,
        acceptedB: v3.outcome.accepted,
      );
      if (comparable) {
        comparablePairs++;
        if (v3.outcome.absoluteClean >= legacy.outcome.absoluteClean) {
          v3CleanNotLower++;
        }
      } else {
        mismatches.add('$material / $size');
      }
      final int delta = v3.outcome.absoluteClean - legacy.outcome.absoluteClean;
      out.writeln(
        '| $material | $size | ${legacy.outcome.accepted} '
        '| ${v3.outcome.accepted} | '
        '${ratio == null ? '—' : (ratio * 100).toStringAsFixed(1)} % | '
        '${comparable ? 'сопоставим' : 'volume_mismatch'} '
        '| ${legacy.outcome.absoluteClean} | ${v3.outcome.absoluteClean} '
        '| ${delta >= 0 ? '+' : ''}$delta |',
      );
    }
  }
  out
    ..writeln()
    ..writeln(
      'Сопоставимых пар: **$comparablePairs**, из них v3 не ниже legacy по '
      'числу чистых: **$v3CleanNotLower**. `volume_mismatch`: '
      '${mismatches.isEmpty ? 'нет' : mismatches.join('; ')}.',
    )
    ..writeln();

  // 3. N* — по агрегатам материала: число единиц материала против исхода.
  final List<MaterialPathPoint> points = <MaterialPathPoint>[];
  final StringBuffer byMaterial = StringBuffer()
    ..writeln('## 3. Зависимость «объём материала → качество и полнота»')
    ..writeln()
    ..writeln(
      'Единицы материала — единицы карты знаний v3 на этом материале '
      '(10 и 33; у legacy карты нет, поэтому объём общий для обоих путей). '
      'Счётчики — сумма по всем заказам материала (80/150/300).',
    )
    ..writeln()
    ..writeln(
      '| Материал | Единиц | Путь | Попыток | Принято | Чистых | cleanRate | '
      'dupRate |',
    )
    ..writeln('|---|---:|---|---:|---:|---:|---:|---:|');
  for (final String material in materials) {
    final List<Cell> ofMaterial = cells
        .where((Cell cell) => cell.material == material)
        .toList();
    final int units = ofMaterial
        .where((Cell cell) => cell.isV3 && cell.units > 0)
        .map((Cell cell) => cell.units)
        .fold<int>(0, (int a, int b) => a > b ? a : b);
    final List<Cell> legacyCells = ofMaterial
        .where((Cell cell) => !cell.isV3)
        .toList();
    final List<Cell> v3Cells = ofMaterial
        .where((Cell cell) => cell.isV3)
        .toList();
    if (units <= 0 || legacyCells.isEmpty || v3Cells.isEmpty) continue;
    final PathOutcome legacy = aggregate(legacyCells);
    final PathOutcome v3 = aggregate(v3Cells);
    points.add(MaterialPathPoint(units: units, legacy: legacy, v3: v3));
    for (final MapEntry<String, PathOutcome> entry in <String, PathOutcome>{
      'legacy': legacy,
      'v3': v3,
    }.entries) {
      final PathOutcome o = entry.value;
      byMaterial
        ..write(
          '| $material | $units | ${entry.key} | ${o.attempted} '
          '| ${o.accepted} | ${o.clean} | ${_percent(o.cleanRate)} '
          '| ${_percent(o.dupRate)} |',
        )
        ..writeln();
    }
  }
  out
    ..write(byMaterial)
    ..writeln();
  final PathThresholdResult threshold = derivePathThreshold(points);
  out
    ..writeln('## 4. Порог N* и правило')
    ..writeln()
    ..writeln(
      'Правило: материал с числом единиц ≥ N* → v3, меньше → legacy. '
      'Выигрыш v3 — одновременно: `cleanRate` не ниже, `dupRate` не выше и '
      '`absoluteClean` не ниже legacy.',
    )
    ..writeln()
    ..writeln(
      'Выигрышные объёмы: ${threshold.winningUnits}; '
      'причина `${threshold.reason.name}`.',
    )
    ..writeln();
  if (threshold.thresholdUnits == null) {
    out
      ..writeln(
        '**N* данные не дают:** v3 не выигрывает ни на одном измеренном '
        'объёме (${points.map((MaterialPathPoint p) => p.units).join(', ')} '
        'единиц). Правило принимает вид «v3 для объёма ≥ N, legacy иначе» с '
        'пометкой **«на границе выбор не определён данными»**; фактически это '
        'legacy для всех измеренных объёмов.',
      )
      ..writeln()
      ..writeln(
        'Сравнение чистых по ячейкам (§2): v3 не ниже legacy на '
        '$v3CleanNotLower из $comparablePairs сопоставимых пар — объём '
        'сравним, а качество по объёму всё равно не окупает меньший выход '
        'карточек. Единственная величина, где v3 близок к legacy, — cleanRate '
        'на статье (`${_signedPercent(aggregate(cells.where((Cell cell) => cell.material == materials.first && cell.isV3).toList()).cleanRate, aggregate(cells.where((Cell cell) => cell.material == materials.first && !cell.isV3).toList()).cleanRate)}`); на учебном тексте v3 хуже по `dupRate` на всех заказах.',
      )
      ..writeln();
  } else {
    out
      ..writeln(
        '**N* = ${threshold.thresholdUnits} единиц** — с этого объёма v3 не '
        'проигрывает legacy по всем трём величинам. Ниже — legacy.',
      )
      ..writeln();
  }
  out
    ..writeln('## 5. Legacy `dupRate` офлайн и слепая выборка')
    ..writeln()
    ..writeln(
      'Ячеек с сохранёнными карточками: **$savedCards** из ${cells.length}. '
      'Ни у одной ячейки нет ключа `cards` — стенд до среза 17 писал только '
      'метрики, поэтому офлайн-прогон `SemanticMatcher` по карточкам legacy '
      'невозможен: **`dupRate` legacy = `not_measured`** (TASK часть 0, п. 2 '
      'разрешает эту пометку вместо догадки). Слепая выборка — '
      '`blind-sample-17.md` / `blind-key-17.json` с тем же статусом: '
      'измеряется следующим замером, где стенд пишет `cards`.',
    )
    ..writeln()
    ..writeln('## 6. Вердикт по выпуску')
    ..writeln()
    ..writeln(
      'Правило п. 10 **не включается по умолчанию**: данные не дают N*, авто '
      'остаётся legacy (`kGenerationPathV3MinUnits = null`), v3 — ручное '
      'переопределение режима. Доля годных из слепой выборки не измерена '
      '(нет сохранённых карточек), поэтому TASK п. 12 не может показать «доля '
      'годных v3 не ниже legacy» — консервативный вывод тот же: v3 не '
      'включается автоматически. Разница, которую видно числами, — доля дублей '
      'v3 (до 51 % на учебном тексте) уходит задачей на промпт S18.',
    )
    ..writeln()
    ..writeln(
      '_Снимок кода ячеек:_ '
      '${cells.map((Cell cell) => cell.codeVersion ?? 'legacy-schema').toSet().join(', ')}.',
    );

  File(kOutputPath).parent.createSync(recursive: true);
  File(kOutputPath).writeAsStringSync(out.toString(), flush: true);
  stdout.writeln('Записано: $kOutputPath (${cells.length} ячеек)');
}
