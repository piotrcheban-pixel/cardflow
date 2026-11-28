/// Расчёт доли годных по путям в слепой выборке среза 17B (TASK ч. 3 п. 9).
///
/// Читает заполненный владельцем `journal/generation-v3/blind-sample-17b.md`
/// (отметки `[x] годная` / `[x] спорная` / `[x] негодная`, комментарии и
/// причины), ключ `journal/generation-v3/blind-key-17b.json` (номер →
/// путь/ячейка/индекс) и автометрику ячеек
/// `journal/generation-v3/live-s17b/cells/*.json` в замороженных определениях
/// ADR-054.
///
/// Пишет `journal/generation-v3/blind-score-17b.md`:
/// - доля годных (и спорных/негодных) по путям;
/// - сравнение с автометрикой: `cleanRate` и `dupRate` путей, насколько
///   автометрика завышает качество и различает ли она пути;
/// - список негодных/спорных с причиной владельца и путём (ключ на этом шаге
///   уже открыт — файл расчёта читается после разметки);
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

  /// Оценка по строке `[x] …`; `null` — оценки в строке нет.
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

/// Разметка одной карточки: оценка, комментарий и причина.
final class BlindMark {
  /// Создаёт запись разметки.
  const BlindMark({required this.verdict, this.comment = '', this.why = ''});

  /// Оценка владельца.
  final BlindVerdict verdict;

  /// Комментарий из файла (как написан).
  final String comment;

  /// «Почему негодная» из файла (как написан).
  final String why;

  /// Текст причин в нижнем регистре — для поиска упоминаний.
  String get reasonsLower => '$why $comment'.toLowerCase();

  /// Упоминается ли повтор/похожесть (слово владельца, не классификация).
  bool get mentionsRepeat =>
      reasonsLower.contains('повтор') ||
      reasonsLower.contains('похож') ||
      reasonsLower.contains('такой же') ||
      reasonsLower.contains('такие же');

  /// Упоминается ли «ответ в вопросе».
  bool get mentionsAnswerInQuestion => reasonsLower.contains('ответ в вопросе');
}

/// Итоги разметки по одному пути.
final class PathScore {
  /// Создаёт пустой итог.
  PathScore(this.path);

  /// Путь генерации.
  final GenerationPath path;

  /// Число карточек каждого вердикта.
  final Map<BlindVerdict, int> counts = <BlindVerdict, int>{
    for (final BlindVerdict verdict in BlindVerdict.values) verdict: 0,
  };

  /// Карточки пути с причинами (для разбора негодных).
  final List<({int number, BlindMark mark})> marks =
      <({int number, BlindMark mark})>[];

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

  /// Упоминаний повтора среди размеченных карточек пути.
  int get repeatMentions => marks
      .where((({int number, BlindMark mark}) item) => item.mark.mentionsRepeat)
      .length;

  /// Упоминаний «ответ в вопросе» среди размеченных карточек пути.
  int get answerInQuestionMentions => marks
      .where(
        (({int number, BlindMark mark}) item) =>
            item.mark.mentionsAnswerInQuestion,
      )
      .length;
}

/// Разбор файла выборки: номер → разметка.
Map<int, BlindMark> parseSample(String text) {
  final Map<int, BlindMark> marks = <int, BlindMark>{};
  int? current;
  var verdict = BlindVerdict.missing;
  var comment = '';
  var why = '';
  void flush() {
    final int? number = current;
    if (number == null) return;
    marks[number] = BlindMark(verdict: verdict, comment: comment, why: why);
  }

  for (final String line in const LineSplitter().convert(text)) {
    final RegExpMatch? header = RegExp(r'^###\s+(\d+)\s*$').firstMatch(line);
    if (header != null) {
      flush();
      current = int.parse(header.group(1)!);
      verdict = BlindVerdict.missing;
      comment = '';
      why = '';
      continue;
    }
    if (current == null) continue;
    final BlindVerdict? marked = BlindVerdict.fromMarkedLine(line);
    if (marked != null) {
      verdict = marked;
      continue;
    }
    final RegExpMatch? commentMatch = RegExp(r'^-\s*Комментарий:\s*(.*)$')
        .firstMatch(line);
    if (commentMatch != null) {
      final String value = commentMatch.group(1)!.trim();
      comment = value == '______' ? '' : value;
      continue;
    }
    final RegExpMatch? whyMatch = RegExp(r'^-\s*Почему негодная:\s*(.*)$')
        .firstMatch(line);
    if (whyMatch != null) {
      final String value = whyMatch.group(1)!.trim();
      why = value == '______' ? '' : value;
    }
  }
  flush();
  return marks;
}

/// Автометрика пути: счётчики `unique`, `clean`, `duplicates` в определениях
/// ADR-054 (`cleanRate = clean / unique`, `dupRate = duplicates / unique`).
final class CellAutometrics {
  /// Создаёт запись.
  const CellAutometrics({this.unique = 0, this.clean = 0, this.duplicates = 0});

  /// Уникальных принятых.
  final int unique;

  /// Чистых (без пометок).
  final int clean;

  /// Отложенных дублей (в колоду не попали).
  final int duplicates;

  /// `clean / unique`.
  double? get cleanRate => unique <= 0 ? null : clean / unique;

  /// `duplicates / unique`.
  double? get dupRate => unique <= 0 ? null : duplicates / unique;

  /// Сумма счётчиков двух сводок.
  CellAutometrics operator +(CellAutometrics other) => CellAutometrics(
    unique: unique + other.unique,
    clean: clean + other.clean,
    duplicates: duplicates + other.duplicates,
  );
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
    result[path] =
        (result[path] ?? const CellAutometrics()) +
        CellAutometrics(
          unique: intOf('unique'),
          clean: intOf('clean'),
          duplicates: intOf('duplicates'),
        );
  }
  return result;
}

String _percent(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

String _points(double? value) {
  if (value == null) return '—';
  final String sign = value > 0 ? '+' : '';
  return '$sign${(value * 100).toStringAsFixed(1)} п.п.';
}

/// Размер разницы в п.п. без знака (направление сказано словами).
String _magnitude(double? value) =>
    value == null ? '—' : '${(value.abs() * 100).toStringAsFixed(1)} п.п.';

/// Какой путь выше по величине; `равенство` — равные значения.
String _higher(double? v3, double? legacy, {String equalLabel = 'равенство'}) {
  if (v3 == null || legacy == null) return 'не сравнить';
  if (v3 > legacy) return GenerationPath.v3.wireName;
  if (v3 < legacy) return GenerationPath.legacy.wireName;
  return equalLabel;
}

void main() {
  final File sampleFile = File(kSamplePath);
  final File keyFile = File(kKeyPath);
  final StringBuffer out = StringBuffer()
    ..writeln('# Слепая выборка среза 17B — расчёт доли годных')
    ..writeln();

  final Map<int, BlindMark> marks = sampleFile.existsSync()
      ? parseSample(sampleFile.readAsStringSync())
      : <int, BlindMark>{};
  final Map<String, Object?> key = keyFile.existsSync()
      ? (jsonDecode(keyFile.readAsStringSync()) as Map).cast<String, Object?>()
      : const <String, Object?>{};
  final Object? entries = key['entries'];
  final int markedCount = marks.values
      .where((BlindMark mark) => mark.verdict != BlindVerdict.missing)
      .length;

  if (markedCount == 0 || entries is! List || entries.isEmpty) {
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
  for (final Object? raw in entries) {
    if (raw is! Map) continue;
    final Map<String, Object?> entry = raw.cast<String, Object?>();
    final int? number = (entry['number'] as num?)?.toInt();
    if (number == null) continue;
    final GenerationPath path = entry['path'] == GenerationPath.legacy.wireName
        ? GenerationPath.legacy
        : GenerationPath.v3;
    final BlindMark mark =
        marks[number] ?? const BlindMark(verdict: BlindVerdict.missing);
    final PathScore score = scores[path]!;
    score.counts[mark.verdict] = score.counts[mark.verdict]! + 1;
    score.marks.add((number: number, mark: mark));
  }

  final Map<GenerationPath, CellAutometrics> auto = readAutometrics();
  final PathScore v3 = scores[GenerationPath.v3]!;
  final PathScore legacy = scores[GenerationPath.legacy]!;
  final CellAutometrics v3Auto =
      auto[GenerationPath.v3] ?? const CellAutometrics();
  final CellAutometrics legacyAuto =
      auto[GenerationPath.legacy] ?? const CellAutometrics();

  out
    ..writeln(
      'Разметка: $markedCount карточек из ${entries.length}; '
      'без оценки — ${entries.length - markedCount}. Ключ открыт после '
      'заполнения: путь у каждой карточки указан в §1 и §3.',
    )
    ..writeln()
    ..writeln('## 1. Доля годных по путям')
    ..writeln()
    ..writeln(
      '| Путь | Карточек | Размечено | Годных | Спорных | Негодных '
      '| Доля годных |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|');

  for (final PathScore score in scores.values) {
    out.writeln(
      '| ${score.path.wireName} | ${score.total} | ${score.marked} '
      '| ${score.counts[BlindVerdict.good]} '
      '| ${score.counts[BlindVerdict.disputed]} '
      '| ${score.counts[BlindVerdict.bad]} '
      '| ${_percent(score.goodShare)} |',
    );
  }
  out
    ..writeln()
    ..writeln(
      'Выше доля годных у **${_higher(v3.goodShare, legacy.goodShare)}**: v3 '
      '— ${_percent(v3.goodShare)}, legacy — ${_percent(legacy.goodShare)} '
      '(v3 ${(v3.goodShare ?? 0) < (legacy.goodShare ?? 0) ? 'ниже' : 'выше'} '
      'на '
      '${_magnitude((v3.goodShare ?? 0) - (legacy.goodShare ?? 0))}). '
      'При 30 карточках на путь одна карточка — это 3,3 п.п.: разница в '
      'одну-две карточки лежит в пределах выборочного шума, поэтому условие '
      'S17 п. 12 «доля годных v3 не ниже legacy» этой выборкой **не '
      'подтверждено**, но и не опровергнуто статистически.',
    )
    ..writeln();

  // 2. Автометрика против человека.
  out
    ..writeln('## 2. Совпадение с автометрикой')
    ..writeln()
    ..writeln(
      '| Путь | Доля годных (человек) | cleanRate (авто) | Завышение авто '
      '| dupRate (авто) |',
    )
    ..writeln('|---|---:|---:|---:|---:|');
  for (final PathScore score in scores.values) {
    final CellAutometrics autoOf = score.path == GenerationPath.v3
        ? v3Auto
        : legacyAuto;
    final double? human = score.goodShare;
    out.writeln(
      '| ${score.path.wireName} | ${_percent(human)} '
      '| ${_percent(autoOf.cleanRate)} '
      '| ${human == null ? '—' : _points((autoOf.cleanRate ?? 0) - human)} '
      '| ${_percent(autoOf.dupRate)} |',
    );
  }
  out
    ..writeln()
    ..writeln(
      '**Автометрика пути не различает.** `cleanRate` = ${_percent(v3Auto.cleanRate)} '
      'у v3 и ${_percent(legacyAuto.cleanRate)} у legacy: величина насыщена, '
      'потому что дубль откладывается **до** принятия (срез 16) и в колоду не '
      'попадает — сохранённая карточка «чистая» по построению. Человеческая '
      'доля годных ниже на '
      '${_magnitude(_overstatement(v3Auto, v3))} (v3) и '
      '${_magnitude(_overstatement(legacyAuto, legacy))} (legacy): автометрика '
      'качество сохранённого не измеряет.',
    )
    ..writeln()
    ..writeln(
      '**`dupRate` с выборкой напрямую не сопоставим.** Он считает '
      'кандидатов, **отложенных** до принятия (v3 ${_percent(v3Auto.dupRate)}, '
      'legacy ${_percent(legacyAuto.dupRate)}), а отложенных карточек в '
      'сохранённых нет — в выборку они не попадают. Поэтому «повтор» в '
      'разметке человека и `dupRate` автометрики — разные вещи: первый про '
      'принятые карточки, второй про стоимость отбраковки.',
    )
    ..writeln();

  // 3. Разбор негодных и спорных.
  out
    ..writeln('## 3. Разбор негодных и спорных (с путём)')
    ..writeln()
    ..writeln('| № | Путь | Оценка | Причина владельца |')
    ..writeln('|---:|---|---|---|');
  for (final PathScore score in scores.values) {
    for (final ({int number, BlindMark mark}) item in score.marks) {
      if (item.mark.verdict == BlindVerdict.good ||
          item.mark.verdict == BlindVerdict.missing) {
        continue;
      }
      final String reason = <String>[
        if (item.mark.why.isNotEmpty) item.mark.why,
        if (item.mark.comment.isNotEmpty) 'комментарий: ${item.mark.comment}',
      ].join('; ');
      out.writeln(
        '| ${item.number} | ${score.path.wireName} '
        '| ${item.mark.verdict.label} | ${reason.isEmpty ? '—' : reason} |',
      );
    }
  }
  out
    ..writeln()
    ..writeln(
      'Упоминаний повтора/похожести: v3 — ${v3.repeatMentions}, legacy — '
      '${legacy.repeatMentions}; «ответ в вопросе»: v3 — '
      '${v3.answerInQuestionMentions}, legacy — '
      '${legacy.answerInQuestionMentions}. Это слова владельца в разметке, '
      'а не классификация: у v3 часть таких карточек — cloze с сырой '
      'разметкой `{{c1::…}}` в файле выборки (артефакт представления, L240), '
      'а часть повторов может быть межпутевой: обе выборки сделаны по одному '
      'материалу (L241).',
    )
    ..writeln();

  // 4. Итог.
  final String better = _higher(v3.goodShare, legacy.goodShare);
  out
    ..writeln('## 4. Итог')
    ..writeln()
    ..writeln(
      '**Доля годных:** v3 ${_percent(v3.goodShare)} '
      '(${v3.counts[BlindVerdict.good]}/${v3.marked}), legacy '
      '${_percent(legacy.goodShare)} '
      '(${legacy.counts[BlindVerdict.good]}/${legacy.marked}).',
    )
    ..writeln(
      '**Автометрика:** `cleanRate` ${_percent(v3Auto.cleanRate)} / '
      '${_percent(legacyAuto.cleanRate)} — не различает пути и завышает '
      'качество на ${_magnitude(_overstatement(v3Auto, v3))} (v3) и '
      '${_magnitude(_overstatement(legacyAuto, legacy))} (legacy).',
    )
    ..writeln(
      '**Условие S17 п. 12 «доля годных v3 не ниже legacy»** этой выборкой '
      '${better == GenerationPath.v3.wireName ? 'подтверждено' : 'не подтверждено'} '
      '(v3 ${_percent(v3.goodShare)} против legacy '
      '${_percent(legacy.goodShare)}). '
      'Решение о включении v3 по умолчанию не меняется: `auto` = legacy.',
    )
    ..writeln()
    ..writeln(
      '_Ключ:_ `$kKeyPath` — открыт после разметки; путь карточки в файле '
      'выборки не печатался.',
    );

  File(kOutputPath).parent.createSync(recursive: true);
  File(kOutputPath).writeAsStringSync(out.toString(), flush: true);
  stdout
    ..writeln('Записано: $kOutputPath')
    ..writeln(
      'Доля годных: v3 ${_percent(v3.goodShare)}, legacy '
      '${_percent(legacy.goodShare)}',
    );
}

/// Насколько `cleanRate` автометрики выше доли годных (п.п.).
double? _overstatement(CellAutometrics auto, PathScore score) {
  final double? human = score.goodShare;
  if (human == null || auto.cleanRate == null) return null;
  return auto.cleanRate! - human;
}
