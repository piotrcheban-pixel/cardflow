/// Слепая человеческая выборка из **сохранённых** карточек (TASK «Срез 17»,
/// часть 1; ADR-054).
///
/// Задача — проверить автоматическую метрику человеком, не подсказывая, какой
/// путь произвёл карточку. Поэтому:
/// - карточки берутся только из сохранённых ячеек (`cells/*.json`, ключ `cards`),
///   новых прогонов нет;
/// - отбирается не больше [buildBlindSample] `perPath` карточек на путь,
///   порядок перемешивается seed-ом;
/// - в файле выборки ([BlindEntry]) есть только номер и тексты сторон — **ни
///   пути, ни id, ни ячейки**;
/// - соответствие «номер → путь/ячейка/индекс» — отдельный [BlindKeyEntry],
///   его владелец открывает после заполнения.
library;

import 'package:cardflow/domain/generation/generation_path.dart';

/// Карточка, сохранённая в ячейке живого замера.
final class BlindSourceCard {
  /// Создаёт карточку источника.
  const BlindSourceCard({
    required this.cellId,
    required this.path,
    required this.front,
    required this.back,
  });

  /// Ячейка, из которой взята карточка (в выборку не попадает).
  final String cellId;

  /// Путь, которым карточка произведена (в выборку не попадает).
  final GenerationPath path;

  /// Вопрос (лицевая сторона).
  final String front;

  /// Ответ (обратная сторона).
  final String back;
}

/// Карточка в файле выборки: только номер и тексты, без пути и id.
final class BlindEntry {
  /// Создаёт запись выборки.
  const BlindEntry({
    required this.number,
    required this.front,
    required this.back,
  });

  /// Номер в перемешанном списке (1..N) — по нему владелец ставит оценку.
  final int number;

  /// Вопрос.
  final String front;

  /// Ответ.
  final String back;

  @override
  String toString() => 'BlindEntry($number)';
}

/// Ключ соответствия: номер → путь, ячейка и индекс карточки в источнике.
final class BlindKeyEntry {
  /// Создаёт запись ключа.
  const BlindKeyEntry({
    required this.number,
    required this.path,
    required this.cellId,
    required this.cardIndex,
  });

  /// Номер в файле выборки.
  final int number;

  /// Путь, которым карточка произведена.
  final GenerationPath path;

  /// Ячейка источника.
  final String cellId;

  /// Индекс карточки внутри ячейки (уникальность источника).
  final int cardIndex;
}

/// Результат сборки выборки.
final class BlindSample {
  /// Создаёт результат.
  const BlindSample({
    required this.entries,
    required this.key,
    required this.requestedPerPath,
    required this.v3Available,
    required this.legacyAvailable,
    required this.v3Sampled,
    required this.legacySampled,
    required this.notMeasuredReason,
  });

  /// Карточки в перемешанном порядке — то, что видит владелец.
  final List<BlindEntry> entries;

  /// Ключ соответствия номеров.
  final List<BlindKeyEntry> key;

  /// Сколько карточек на путь просили (30 по TASK).
  final int requestedPerPath;

  /// Сколько карточек v3 было доступно в сохранённом.
  final int v3Available;

  /// Сколько карточек legacy было доступно в сохранённом.
  final int legacyAvailable;

  /// Сколько карточек v3 попало в выборку.
  final int v3Sampled;

  /// Сколько карточек legacy попало в выборку.
  final int legacySampled;

  /// Причина `not_measured`; `null` — выборка состоялась.
  final String? notMeasuredReason;

  /// true — выборку можно отдавать владельцу.
  bool get measured => notMeasuredReason == null;

  /// Сколько карточек не хватило до `2 × requestedPerPath`.
  int get shortfall => requestedPerPath * 2 - entries.length;
}

/// Причина `not_measured` для сохранённого без текстов карточек.
const String kBlindNoSavedCardsReason =
    'cells/*.json среза 16 несут только метрики — текстов сохранённых карточек '
    'в них нет; живые стенды до среза 17 карточки не писали, а новых платных '
    'прогонов срез 17 не делает: выборка измеряется следующим замером';

/// Собирает выборку из сохранённых карточек.
///
/// [cards] — все сохранённые карточки (оба пути). Случайность — `Random(seed)`
/// без времени: повторный вызов с тем же seed даёт тот же порядок (файл можно
/// пересобрать и сверить).
BlindSample buildBlindSample({
  required List<BlindSourceCard> cards,
  int perPath = 30,
  int seed = 17,
}) {
  final List<BlindSourceCard> v3 = <BlindSourceCard>[
    for (final BlindSourceCard card in cards)
      if (card.path == GenerationPath.v3) card,
  ];
  final List<BlindSourceCard> legacy = <BlindSourceCard>[
    for (final BlindSourceCard card in cards)
      if (card.path == GenerationPath.legacy) card,
  ];
  if (v3.isEmpty || legacy.isEmpty) {
    return BlindSample(
      entries: const <BlindEntry>[],
      key: const <BlindKeyEntry>[],
      requestedPerPath: perPath,
      v3Available: v3.length,
      legacyAvailable: legacy.length,
      v3Sampled: 0,
      legacySampled: 0,
      notMeasuredReason: kBlindNoSavedCardsReason,
    );
  }

  final _SeededPicker picker = _SeededPicker(seed);
  final List<BlindSourceCard> sampledV3 = picker.take(v3, perPath);
  final List<BlindSourceCard> sampledLegacy = picker.take(legacy, perPath);
  final List<_NumberedSource> mixed = <_NumberedSource>[
    for (var index = 0; index < sampledV3.length; index++)
      _NumberedSource(sampledV3[index], index),
    for (var index = 0; index < sampledLegacy.length; index++)
      _NumberedSource(sampledLegacy[index], index),
  ];
  picker.shuffle(mixed);

  final List<BlindEntry> entries = <BlindEntry>[];
  final List<BlindKeyEntry> key = <BlindKeyEntry>[];
  for (var index = 0; index < mixed.length; index++) {
    final int number = index + 1;
    final _NumberedSource item = mixed[index];
    entries.add(
      BlindEntry(number: number, front: item.card.front, back: item.card.back),
    );
    key.add(
      BlindKeyEntry(
        number: number,
        path: item.card.path,
        cellId: item.card.cellId,
        cardIndex: item.indexInSource,
      ),
    );
  }
  return BlindSample(
    entries: List<BlindEntry>.unmodifiable(entries),
    key: List<BlindKeyEntry>.unmodifiable(key),
    requestedPerPath: perPath,
    v3Available: v3.length,
    legacyAvailable: legacy.length,
    v3Sampled: sampledV3.length,
    legacySampled: sampledLegacy.length,
    notMeasuredReason: null,
  );
}

final class _NumberedSource {
  const _NumberedSource(this.card, this.indexInSource);

  final BlindSourceCard card;

  final int indexInSource;
}

/// Детерминированный отбор: без зависимости от `dart:math` в вызывающем коде.
class _SeededPicker {
  _SeededPicker(int seed) : _state = seed * 31 + 17;

  int _state;

  /// Берёт до [count] разных карточек; порядок задан seed-ом.
  List<BlindSourceCard> take(List<BlindSourceCard> items, int count) {
    final List<BlindSourceCard> copy = List<BlindSourceCard>.of(items);
    shuffle(copy);
    return copy.take(count).toList(growable: false);
  }

  /// Перемешивание Фишера — Йетса на LCG; состояние живёт между вызовами,
  /// поэтому v3 и legacy не перемешиваются одинаково.
  void shuffle<T>(List<T> items) {
    for (var index = items.length - 1; index > 0; index--) {
      _state = _state * 1103515245 + 12345;
      final int normalized = _state & 0x7FFFFFFF;
      final int swapWith = normalized % (index + 1);
      final T temp = items[index];
      items[index] = items[swapWith];
      items[swapWith] = temp;
    }
  }
}
