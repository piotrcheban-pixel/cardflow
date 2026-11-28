/// Расчёт доли годных по путям в слепой выборке среза 17B (TASK ч. 3 п. 9).
///
/// Читает заполненный владельцем `journal/generation-v3/blind-sample-17b.md`
/// (отметки `[x] годная` / `[x] спорная` / `[x] негодная`) и ключ
/// `journal/generation-v3/blind-key-17b.json` (номер → путь/ячейка/индекс), а из
/// ячеек `journal/generation-v3/live-s17b/cells/*.json` берёт **автометрику**
/// путей в замороженных определениях ADR-054.
///
/// Пишет `journal/generation-v3/blind-score-17b.md`:
/// - доля годных (и спорных/негодных) по путям;
/// - сравнение с автометрикой `cleanRate` — по агрегату, а не по карточкам:
///   в сохранённых ячейках у карточки нет метки «чистая/дубль», поэтому
///   поштучное сопоставление было бы выдумкой;
/// - `not_measured` с причиной, если разметки нет.
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/blind_score_s17b.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/generation_path.dart';

/// Заполненная выборка.
const String kSamplePath = 'journal/generation-v3/blind-sample-17b.md';

/// Ключ соответствия.
const String kKeyPath = 'journal/generation-v3/blind-key-17b.json';

/// Ячейки замера (автометрика путей).
const String kCellsDir = 'journal/generation-v3/live-s17b/cells';

/// Куда пишется расчёт.
const String kOutputPath = 'journal/generation-v3/blind-score-17b.md';

/// Оценка одной карточки владельцем.
enum BlindVerdict {
  /// Годная.
  good('годная'),

  /// Спорная.
  disputed('спорная'),

  /// Негодная.
  bad('негодная'),

  /// Отметки нет.
  missing('—');

  const BlindVerdict(this.label);

  /// Подпись в файле выборки.
  final String label;

  /// Оценка по строке `[x] …`; `null` — строки оценок нет.
  static BlindVerdict? fromMarkedLine(String line) {
    final String lower = line.toLowerCase();
    if (!lower.contains('[x]')) return null;
    for (final BlindVerdict verdict in <BlindVerdict>[
      BlindVerdict.good,
      BlindVerdict.disputed,
      BlindVerdict.bad,
    ]) {
      if (lower.contains('[x] ${verdict.label}')) return verdict;
    }
    return null;
  }
}

/// Итоги разметки по одному пути.
class PathScore {
  /// Создаёт пустой итог.
  PathScore(this.path);

  /// Путь генерации.
  final GenerationPath path;

  /// Число карточек каждого вердикта.
  final Map<BlindVerdict, int> counts = <BlindVerdict, int>{
    for (final BlindVerdict verdict in BlindVerdict.values) verdict: 0,
  };

  /// Размечено (любая оценка).
  int get marked =>
      counts[BlindVerdict.good]! +
      counts[BlindVerdict.disputed]! +
      counts[BlindVerdict.bad]!;

  /// Всего карточек пути в выборке.
  int get total => marked + (counts[BlindVerdict.missing] ?? 0);

  /// Доля годных среди размеченных; `null` — разметки нет.
  double? get goodShare =>
      marked <= 0 ? null : counts[BlindVerdict.good]! / marked;
}

/// Разбор файла выборки: номер → вердикт.
Map<int, BlindVerdict> parseSample(String text) {
  final Map<int, BlindVerdict> verdicts = <int, BlindVerdict>{};
  int? current;
  for (final String line in const LineSplitter().convert(text)) {
    final RegExpMatch? header = RegExp(r'^###\s+(\d+)\s*$').firstMatch(line);
    if (header != null) {
      current = int.parse(header.group(1)!);
      continue;
    }
    if (current == null) continue;
    final BlindVerdict? verdict = BlindVerdict.fromMarkedLine(line);
    if (verdict != null) {
      verdicts[current] = verdict;
      current = null;
    }
  }
  return verdicts;
}

/// Автометрика ячейки: `cleanRate` в замороженных определениях ADR-054.
final class CellAutometrics {
  /// Создаёт запись.
  const CellAutometrics({required this.unique, required this.clean});

  /// Уникальных принятых.
  final int unique;

  /// Чистых (без пометок).
  final int clean;

  /// `clean / unique`.
  double? get cleanRate => unique <= 0 ? null : clean / unique;
}

/// Читает автометрику ячеек по пути.
Map<GenerationPath, CellAutometrics> readAutometrics() {
  final Map<GenerationPath, CellAutometrics> result =
      <GenerationPath, CellAutometrics>{};
  final Directory dir = Directory(kCellsDir);
  if (!dir.existsSync()) return result;
  for (final FileSystemEntity entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final Map<String, Object?> json = (jsonDecode(
      File(entity.path).readAsStringSync(),
    ) as Map).cast<String, Object?>();
    if (json['status'] != 'ran') continue;
    final Object? metricsRaw = json['metrics'];
    if (metricsRaw is! Map) continue;
    final Map<String, Object?> metrics = metricsRaw.cast<String, Object?>();
    int intOf(String key) => (metrics[key] as num?)?.toInt() ?? 0;
    final GenerationPath path = json['path'] == GenerationPath.legacy.wireName
        ? GenerationPath.legacy
        : GenerationPath.v3;
    final CellAutometrics previous =
        result[path] ?? const CellAutometrics(unique: 0, clean: 0);
    result[path] = CellAutometrics(
      unique: previous.unique + intOf('unique'),
      clean: previous.clean + intOf('clean'),
    );
  }
  return result;
}

String _percent(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

void main() {
  final File sampleFile = File(kSamplePath);
  final File keyFile = File(kKeyPath);
  final StringBuffer out = StringBuffer()
    ..writeln('# Слепая выборка среза 17B — расчёт доли годных')
    ..writeln();

  final Map<int, BlindVerdict> verdicts = sampleFile.existsSync()
      ? parseSample(sampleFile.readAsStringSync())
      : <int, BlindVerdict>{};
  final Map<String, Object?> key = keyFile.existsSync()
      ? (jsonDecode(keyFile.readAsStringSync()) as Map).cast<String, Object?>()
      : const <String, Object?>{};
  final Object? entries = key['entries'];

  if (verdicts.isEmpty || entries is! List || entries.isEmpty) {
    out
      ..writeln('**Статус:** `not_measured`.')
      ..writeln()
      ..writeln(
        !sampleFile.existsSync()
            ? 'Файл выборки `$kSamplePath` не собран — сборка: '
                  '`dart run tool/blind_sample_s17b.dart`.'
            : 'В выборке нет ни одной отметки `[x] …` — владелец её ещё не '
                  'заполнил. Доля годных по путям не считается, числа не '
                  'додумываются (протокол §8).',
      )
      ..writeln()
      ..writeln(
        '**Что нужно:** заполнить `$kSamplePath` (по одной оценке на '
        'карточку), затем повторить этот инструмент. Ключ `$kKeyPath` '
        'открывать после заполнения.',
      );
    File(kOutputPath).parent.createSync(recursive: true);
    File(kOutputPath).writeAsStringSync(out.toString(), flush: true);
    stdout.writeln('Записано: $kOutputPath (not_measured)');
    return;
  }

  final Map<GenerationPath, PathScore> scores = <GenerationPath, PathScore>{
    for (final GenerationPath path in GenerationPath.values)
      path: PathScore(path),
  };
  var unknownNumbers = 0;
  for (final Object? raw in entries) {
    if (raw is! Map) continue;
    final Map<String, Object?> entry = raw.cast<String, Object?>();
    final int? number = (entry['number'] as num?)?.toInt();
    if (number == null) continue;
    final GenerationPath path = entry['path'] == GenerationPath.legacy.wireName
        ? GenerationPath.legacy
        : GenerationPath.v3;
    final BlindVerdict verdict = verdicts[number] ?? BlindVerdict.missing;
    if (verdict == BlindVerdict.missing) unknownNumbers++;
    scores[path]!.counts[verdict] = scores[path]!.counts[verdict]! + 1;
  }

  final Map<GenerationPath, CellAutometrics> auto = readAutometrics();
  out
    ..writeln(
      'Разметка: ${verdicts.length} карточек из ${entries.length}; '
      'без оценки — $unknownNumbers.',
    )
    ..writeln()
    ..writeln('## 1. Доля годных по путям')
    ..writeln()
    ..writeln(
      '| Путь | Карточек | Размечено | Годных | Спорных | Негодных '
      '| Доля годных | cleanRate (автометрика) |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|');

  for (final PathScore score in scores.values) {
    out.writeln(
      '| ${score.path.wireName} | ${score.total} | ${score.marked} '
      '| ${score.counts[BlindVerdict.good]} '
      '| ${score.counts[BlindVerdict.disputed]} '
      '| ${score.counts[BlindVerdict.bad]} '
      '| ${_percent(score.goodShare)} '
      '| ${_percent(auto[score.path]?.cleanRate)} |',
    );
  }
  out.writeln();

  final PathScore v3 = scores[GenerationPath.v3]!;
  final PathScore legacy = scores[GenerationPath.legacy]!;
  final double? v3Share = v3.goodShare;
  final double? legacyShare = legacy.goodShare;
  final String better = v3Share == null || legacyShare == null
      ? 'не сравнить'
      : v3Share > legacyShare
      ? 'v3'
      : v3Share < legacyShare
      ? 'legacy'
      : 'равно';

  // Совпадение с автометрикой — по агрегату: метки «чистая/дубль» у отдельных
  // карточек в ячейках не сохранены, поштучное сопоставление было бы выдумкой.
  final double? v3Clean = auto[GenerationPath.v3]?.cleanRate;
  final double? legacyClean = auto[GenerationPath.legacy]?.cleanRate;
  final String autoOrder = v3Clean == null || legacyClean == null
      ? 'не сравнить'
      : v3Clean > legacyClean
      ? 'v3'
      : v3Clean < legacyClean
      ? 'legacy'
      : 'равно';

  out
    ..writeln('## 2. Совпадение с автометрикой')
    ..writeln()
    ..writeln(
      'По агрегату: выше доля годных у **$better**, выше `cleanRate` у '
      '**$autoOrder** → ${better == autoOrder ? 'порядок путей совпадает' : 'порядок путей расходится'}.',
    )
    ..writeln()
    ..writeln(
      'Поштучное сопоставление «человек vs пометка дубля» невозможно: в '
      'сохранённых карточках ячейки (`cards`) нет метки `clean/duplicate`, а '
      'придумывать её задним числом — значит выдать выдумку за измерение. '
      'Поэтому совпадение считается порядком путей и разницей долей.',
    )
    ..writeln()
    ..writeln(
      '**Итог:** доля годных v3 ${_percent(v3Share)} против legacy '
      '${_percent(legacyShare)}; `cleanRate` автометрики — '
      '${_percent(v3Clean)} против ${_percent(legacyClean)}.',
    )
    ..writeln()
    ..writeln('_Ключ:_ `$kKeyPath` — открыт после расчёта, не входит в файл.');

  File(kOutputPath).parent.createSync(recursive: true);
  File(kOutputPath).writeAsStringSync(out.toString(), flush: true);
  stdout.writeln('Записано: $kOutputPath');
}
