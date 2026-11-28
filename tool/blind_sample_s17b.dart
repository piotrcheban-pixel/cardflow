/// Сборка слепой человеческой выборки среза 17B из **сохранённых** карточек
/// замера 17B (`journal/generation-v3/live-s17b/cells/*.json`, ключ `cards`).
///
/// Новых запросов не делает. Пишет два файла:
/// - `journal/generation-v3/blind-sample-17b.md` — 60 карточек (30 v3 + 30
///   legacy) в случайном порядке, **без пути и без id**, с полями оценки,
///   комментарием и строкой «почему негодная»;
/// - `journal/generation-v3/blind-key-17b.json` — ключ «номер → путь/ячейка/
///   индекс», владелец открывает его ПОСЛЕ заполнения.
///
/// Если в ячейках нет текстов карточек, оба файла пишутся со статусом
/// `not_measured` и причиной: пустая выборка не выдаётся за измерение.
///
/// Запуск: `.fvm\versions\3.47.9\bin\dart.bat run tool/blind_sample_s17b.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/cards/cloze_markup.dart';
import 'package:cardflow/domain/generation/blind_sample.dart';
import 'package:cardflow/domain/generation/generation_path.dart';

/// Каталог ячеек замера 17B с сохранёнными карточками.
const String kCellsDir = 'journal/generation-v3/live-s17b/cells';

/// Файл выборки для владельца.
const String kSamplePath = 'journal/generation-v3/blind-sample-17b.md';

/// Ключ соответствия — открывать после заполнения.
const String kKeyPath = 'journal/generation-v3/blind-key-17b.json';

/// Сколько карточек на путь (TASK ч. 3 п. 7: 30 v3 + 30 legacy).
const int kPerPath = 30;

/// Seed перемешивания: зафиксирован, чтобы файл можно было пересобрать.
const int kSeed = 17;

/// Причина `not_measured`, если стенд не записал карточки.
const String kNoSavedCardsReason =
    'в ячейках замера 17B нет текстов карточек (ключ cards пуст или '
    'отсутствует): карточки не выдумываются, выборка не заполняется';

/// Флаг перезаписи уже размеченной выборки.
const String kForceFlag = '--force';

/// Переопределения путей для проверки инструмента (каталог-проба, не замер).
const String kCellsDirVariable = 'CARDFLOW_BLIND_CELLS';
const String kSamplePathVariable = 'CARDFLOW_BLIND_SAMPLE';
const String kKeyPathVariable = 'CARDFLOW_BLIND_KEY';

void main(List<String> args) {
  final Map<String, String> env = Platform.environment;
  // Пути переопределяемы, чтобы проверить сборку на копии ячеек, не задевая
  // размеченный файл замера.
  final String cellsDir = env[kCellsDirVariable] ?? kCellsDir;
  final String samplePath = env[kSamplePathVariable] ?? kSamplePath;
  final String keyPath = env[kKeyPathVariable] ?? kKeyPath;
  final bool force = args.contains(kForceFlag);
  final File sampleFile = File(samplePath);
  // Разметка владельца — данные, а не шаблон: пересборка по умолчанию её не
  // затирает. Замер 17B показал цену ошибки: 3 из 5 «негодных» v3 оказались
  // cloze-карточками, у которых в файле была видна сырая разметка `{{c1::…}}`.
  if (!force && sampleFile.existsSync()) {
    final String existing = sampleFile.readAsStringSync();
    if (RegExp(r'\[x\]', caseSensitive: false).hasMatch(existing)) {
      stderr
        ..writeln(
          'Выборка уже размечена владельцем: $samplePath. Пересборка '
          'затрёт оценки.',
        )
        ..writeln(
          'Если это осознанно — повторить с $kForceFlag '
          '(`.fvm\\versions\\3.47.9\\bin\\dart.bat run '
          'tool/blind_sample_s17b.dart $kForceFlag`).',
        );
      exit(3);
    }
  }
  final Directory dir = Directory(cellsDir);
  if (!dir.existsSync()) {
    stderr.writeln('Нет каталога ячеек: $cellsDir');
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

  File(samplePath).parent.createSync(recursive: true);
  File(samplePath).writeAsStringSync(_markdown(sample), flush: true);
  File(keyPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(_keyJson(sample)),
    flush: true,
  );
  stdout
    ..writeln(
      'Выборка: ${sample.entries.length} карточек '
      '(v3 ${sample.v3Sampled}, legacy ${sample.legacySampled}); '
      'статус ${sample.measured ? 'измерено' : 'not_measured'}',
    )
    ..writeln('Записано: $samplePath и $keyPath');
}

String _markdown(BlindSample sample) {
  final StringBuffer out = StringBuffer();
  if (!sample.measured) {
    out
      ..writeln('# Слепая выборка среза 17B — `not_measured`')
      ..writeln()
      ..writeln('**Статус:** `not_measured`. $kNoSavedCardsReason.')
      ..writeln()
      ..writeln(
        '**Что нужно, чтобы измерить:** замер, где стенд пишет карточки '
        '(`cells/<cellId>.json` → ключ `cards`); после него повторить '
        '`dart run tool/blind_sample_s17b.dart` — файл заполнится 60 '
        'карточками 30/30 автоматически, ключ останется отдельным.',
      )
      ..writeln()
      ..writeln(
        '**Чего здесь нет и почему:** выдуманные карточки выдали бы вымысел '
        'за измерение (протокол §8; TASK «Не делать»).',
      );
    return out.toString();
  }
  out
    ..writeln('# Слепая выборка среза 17B — 60 карточек')
    ..writeln()
    ..writeln(
      '**Как заполнять:** по каждой карточке отметить **одну** оценку — '
      '`[x] годная`, `[x] спорная` или `[x] негодная`; для негодной — одна '
      'строка «почему негодная». Путь, из которого пришла карточка, здесь '
      'не указан: ключ — в отдельном файле `blind-key-17b.json`, открывать '
      'после заполнения.',
    )
    ..writeln()
    ..writeln(
      '**Что оценивается:** карточка годна, если вопрос однозначен, ответ '
      'верен материалу, проверяется одна мысль и нет смыслового повтора '
      'другой карточки набора.',
    )
    ..writeln()
    ..writeln(
      '**Cloze.** У cloze-карточек вопрос показан так, как его видно при '
      'повторении: пропуск заменён на `[…]`, ответ под ним — это и есть '
      'пропущенный термин. Сырая разметка `{{c1::…}}` в вопрос не попадает.',
    )
    ..writeln()
    ..writeln(
      '**Про повторы.** В наборе две выборки карточек по **одному и тому же** '
      'материалу (30 + 30). Поэтому похожий вопрос может прийти из второй '
      'выборки: оценивая повтор, отметь его как «негодная», но знай, что '
      'внутри одной выборки это могло быть единственным вопросом о факте.',
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
      ..writeln('**Вопрос.** ${clozeQuestionText(entry.front)}')
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
  'schema': 's17b',
  'status': sample.measured ? 'measured' : 'not_measured',
  if (!sample.measured) 'not_measured_reason': kNoSavedCardsReason,
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
