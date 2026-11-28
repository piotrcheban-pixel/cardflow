/// Сборка слепой человеческой выборки среза 17 из **сохранённых** карточек
/// (`journal/generation-v3/live-s16/cells/*.json`, ключ `cards`).
///
/// Новых платных запросов не делает. Пишет два файла:
/// - `journal/generation-v3/blind-sample-17.md` — 60 карточек (30 v3 + 30
///   legacy) в случайном порядке, **без пути и без id**, с полями оценки
///   ([ ] годная / [ ] спорная / [ ] негодная), комментарием и строкой
///   «почему негодная»;
/// - `journal/generation-v3/blind-key-17.json` — ключ «номер → путь/ячейка/
///   индекс», владелец открывает его ПОСЛЕ заполнения.
///
/// Если в ячейках нет текстов карточек (стенд среза 16 писал только метрики),
/// оба файла пишутся со статусом `not_measured` и причиной: пустая выборка не
/// выдаётся за измерение, а догадки о карточках не делаются.
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/blind_sample_s17.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/blind_sample.dart';
import 'package:cardflow/domain/generation/generation_path.dart';

/// Каталог ячеек с сохранёнными карточками.
const String kCellsDir = 'journal/generation-v3/live-s16/cells';

/// Файл выборки для владельца.
const String kSamplePath = 'journal/generation-v3/blind-sample-17.md';

/// Ключ соответствия — открывать после заполнения.
const String kKeyPath = 'journal/generation-v3/blind-key-17.json';

/// Сколько карточек на путь (TASK: 30 v3 + 30 legacy).
const int kPerPath = 30;

/// Seed перемешивания: зафиксирован, чтобы файл можно было пересобрать.
const int kSeed = 17;

void main() {
  final Directory dir = Directory(kCellsDir);
  if (!dir.existsSync()) {
    stderr.writeln('Нет каталога ячеек: $kCellsDir');
    exit(2);
  }
  final List<BlindSourceCard> cards = <BlindSourceCard>[];
  for (final FileSystemEntity entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final Map<String, Object?> json = (jsonDecode(
      File(entity.path).readAsStringSync(),
    ) as Map).cast<String, Object?>();
    if (json['status'] != 'ran') continue;
    final String? pathWire = json['path'] as String?;
    final GenerationPath path = pathWire == GenerationPath.legacy.wireName
        ? GenerationPath.legacy
        : GenerationPath.v3;
    final String cellId = json['cell_id'] as String? ?? '?';
    final Object? rawCards = json['cards'];
    if (rawCards is! List) continue;
    for (final Object? raw in rawCards) {
      if (raw is! Map) continue;
      final Map<String, Object?> card = raw.cast<String, Object?>();
      final Object? front = card['front'];
      final Object? back = card['back'];
      if (front is! String || back is! String) continue;
      if (front.isEmpty || back.isEmpty) continue;
      cards.add(
        BlindSourceCard(cellId: cellId, path: path, front: front, back: back),
      );
    }
  }

  final BlindSample sample = buildBlindSample(
    cards: cards,
    perPath: kPerPath,
    seed: kSeed,
  );

  File(kSamplePath).parent.createSync(recursive: true);
  File(kSamplePath).writeAsStringSync(_markdown(sample), flush: true);
  File(kKeyPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(_keyJson(sample)),
    flush: true,
  );
  stdout
    ..writeln(
      'Выборка: ${sample.entries.length} карточек '
      '(v3 ${sample.v3Sampled}, legacy ${sample.legacySampled}); '
      'статус ${sample.measured ? 'измерено' : 'not_measured'}',
    )
    ..writeln('Записано: $kSamplePath и $kKeyPath');
}

String _markdown(BlindSample sample) {
  final StringBuffer out = StringBuffer();
  if (!sample.measured) {
    out
      ..writeln('# Слепая выборка среза 17 — `not_measured`')
      ..writeln()
      ..writeln('**Статус:** `not_measured`. ${sample.notMeasuredReason}.')
      ..writeln()
      ..writeln(
        '**Что нужно, чтобы измерить:** один замер, где стенд пишет карточки '
        '(`cells/<cellId>.json` → ключ `cards`, уже реализован в `S12Bench`); '
        'после него повторить '
        '`dart run tool/blind_sample_s17.dart` — файл заполнится 60 '
        'карточками 30/30 автоматически, ключ останется отдельным.',
      )
      ..writeln()
      ..writeln(
        '**Чего здесь нет и почему:** текстов карточек в сохранённых ячейках '
        'нет, а придумать их — значит выдать вымысел за измерение '
        '(протокол §8, TASK «Не делать»: всё из `cells/*.json`).',
      );
    return out.toString();
  }
  out
    ..writeln('# Слепая выборка среза 17 — 60 карточек')
    ..writeln()
    ..writeln(
      '**Как заполнять:** по каждой карточке отметить **одну** оценку — '
      '`[x] годная`, `[x] спорная` или `[x] негодная`; для негодной — одна '
      'строка «почему негодная». Путь, из которого пришла карточка, здесь '
      'не указан: ключ — в отдельном файле `blind-key-17.json`, открывать '
      'после заполнения.',
    )
    ..writeln()
    ..writeln(
      'Карточек: **${sample.entries.length}** (запрошено '
      '${sample.requestedPerPath * 2}; доступно v3 — ${sample.v3Available}, '
      'legacy — ${sample.legacyAvailable}; недобор — ${sample.shortfall}). '
      'Порядок перемешан seed-ом $kSeed.',
    )
    ..writeln();
  for (final BlindEntry entry in sample.entries) {
    out
      ..writeln('### ${entry.number}')
      ..writeln()
      ..writeln('**Вопрос.** ${entry.front}')
      ..writeln()
      ..writeln('**Ответ.** ${entry.back}')
      ..writeln()
      ..writeln('- [ ] годная  [ ] спорная  [ ] негодная')
      ..writeln('- Комментарий: ______')
      ..writeln('- Почему негодная: ______')
      ..writeln();
  }
  return out.toString();
}

Map<String, Object?> _keyJson(BlindSample sample) => <String, Object?>{
  'schema': 's17',
  'status': sample.measured ? 'measured' : 'not_measured',
  if (sample.notMeasuredReason != null)
    'not_measured_reason': sample.notMeasuredReason,
  'seed': kSeed,
  'per_path': sample.requestedPerPath,
  'available': <String, int>{
    'v3': sample.v3Available,
    'legacy': sample.legacyAvailable,
  },
  'sampled': <String, int>{
    'v3': sample.v3Sampled,
    'legacy': sample.legacySampled,
  },
  'entries': <Map<String, Object?>>[
    for (final BlindKeyEntry entry in sample.key)
      <String, Object?>{
        'number': entry.number,
        'path': entry.path.wireName,
        'cell': entry.cellId,
        'card_index': entry.cardIndex,
      },
  ],
};
