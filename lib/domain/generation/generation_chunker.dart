/// Нарезка материалов генерации на фрагменты по бюджету модели (SPEC A8.5 шаг 5,
/// ADR-015). Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/token_estimator.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Максимальное число карточек в одном запросе (`<limit>`).
const int kMaxCardsPerChunk = 20;

/// Один фрагмент материалов для вызова модели.
class GenerationChunk {
  /// Создаёт фрагмент.
  const GenerationChunk({
    required this.index,
    required this.materialsText,
    required this.sourceFiles,
    required this.limit,
    this.splitAttempted = false,
  });

  /// Порядковый номер фрагмента (с 1) для прогресса «фрагмент K из M».
  final int index;

  /// Текст материалов фрагмента.
  final String materialsText;

  /// Имена файлов, из которых собран фрагмент.
  final List<String> sourceFiles;

  /// Максимальное число карточек в ответе.
  final int limit;

  /// Фрагмент уже дробился после `truncated` (дробить можно только раз).
  final bool splitAttempted;

  /// Оценка токенов фрагмента (для тестов и отладочного вывода).
  int estimatedTokens([TokenEstimator estimator = const TokenEstimator()]) =>
      estimator.estimate(materialsText);

  /// Копия с изменёнными полями.
  GenerationChunk copyWith({
    int? index,
    String? materialsText,
    List<String>? sourceFiles,
    int? limit,
    bool? splitAttempted,
  }) {
    return GenerationChunk(
      index: index ?? this.index,
      materialsText: materialsText ?? this.materialsText,
      sourceFiles: sourceFiles ?? this.sourceFiles,
      limit: limit ?? this.limit,
      splitAttempted: splitAttempted ?? this.splitAttempted,
    );
  }

  @override
  String toString() =>
      'GenerationChunk($index, ${materialsText.length} символов, '
      'limit: $limit, split: $splitAttempted)';
}

/// Делит текст на фрагменты, укладывающиеся в бюджет модели.
class GenerationChunker {
  /// Создаёт чанкер.
  const GenerationChunker({
    this.estimator = const TokenEstimator(),
    this.maxCardsPerChunk = kMaxCardsPerChunk,
  });

  /// Оценщик токенов.
  final TokenEstimator estimator;

  /// Максимум карточек на фрагмент.
  final int maxCardsPerChunk;

  /// Режет документы на фрагменты не больше [maxInputTokens] токенов.
  ///
  /// Границы разделов `ParsedDocument` сохраняются: раздел не смешивается с
  /// частью другого раздела, пока помещается целиком. Слишком большой раздел
  /// делится по абзацам, затем по строкам, затем жёстко по символам.
  List<GenerationChunk> chunkDocuments(
    List<ParsedDocument> documents, {
    required int maxInputTokens,
  }) {
    final int budget = maxInputTokens < 1 ? 1 : maxInputTokens;
    final List<_MaterialSegment> segments = <_MaterialSegment>[];
    for (final ParsedDocument document in documents) {
      for (final ParsedSection section in document.sections) {
        final String text = document.text
            .substring(section.start, section.end)
            .trim();
        if (text.isEmpty) continue;
        for (final String part in _splitOversized(text, budget)) {
          segments.add(
            _MaterialSegment(text: part, fileName: document.fileName),
          );
        }
      }
    }
    if (segments.isEmpty) return const <GenerationChunk>[];

    // Жадно упаковываем сегменты: между разделами ровно пустая строка.
    final List<List<_MaterialSegment>> groups = <List<_MaterialSegment>>[];
    var current = <_MaterialSegment>[];
    for (final _MaterialSegment segment in segments) {
      if (current.isEmpty) {
        current.add(segment);
        continue;
      }
      final String candidate = _join(current, segment);
      if (estimator.estimate(candidate) <= budget) {
        current.add(segment);
      } else {
        groups.add(current);
        current = <_MaterialSegment>[segment];
      }
    }
    if (current.isNotEmpty) groups.add(current);

    return <GenerationChunk>[
      for (var i = 0; i < groups.length; i++)
        GenerationChunk(
          index: i + 1,
          materialsText: groups[i].map((segment) => segment.text).join('\n\n'),
          sourceFiles: _uniqueFiles(groups[i]),
          limit: maxCardsPerChunk,
        ),
    ];
  }

  /// Имена файлов группы без дублей, в порядке появления.
  List<String> _uniqueFiles(List<_MaterialSegment> group) {
    final List<String> names = <String>[];
    for (final _MaterialSegment segment in group) {
      if (!names.contains(segment.fileName)) names.add(segment.fileName);
    }
    return List<String>.unmodifiable(names);
  }

  /// Делит фрагмент пополам (для повторного `truncated`); `null` — нельзя.
  ///
  /// Точка деления выбирается у границы абзаца/строки ближе к середине;
  /// обе половины помечаются `splitAttempted`, чтобы пайплайн не дробил их
  /// повторно (A8.5 шаг 8).
  List<GenerationChunk>? splitInHalf(GenerationChunk chunk) {
    final String text = chunk.materialsText;
    if (text.runes.length < 2) return null;
    final int middle = text.length ~/ 2;
    final List<int> points = <int>[
      ...RegExp(r'\n\s*\n').allMatches(text).map((match) => match.start),
      ...RegExp(r'\n').allMatches(text).map((match) => match.start),
      middle,
    ]..sort();
    int splitAt = points.first;
    for (final int point in points) {
      if (point <= 0 || point >= text.length) continue;
      if ((point - middle).abs() < (splitAt - middle).abs()) splitAt = point;
    }
    final String left = text.substring(0, splitAt).trim();
    final String right = text.substring(splitAt).trim();
    if (left.isEmpty || right.isEmpty) return null;
    return <GenerationChunk>[
      chunk.copyWith(
        index: chunk.index,
        materialsText: left,
        splitAttempted: true,
      ),
      chunk.copyWith(
        index: chunk.index + 1,
        materialsText: right,
        splitAttempted: true,
      ),
    ];
  }

  /// Текст группы сегментов плюс новый сегмент (проверка бюджета).
  String _join(List<_MaterialSegment> group, _MaterialSegment next) {
    return <String>[
      for (final _MaterialSegment segment in group) segment.text,
      next.text,
    ].join('\n\n');
  }

  /// Режет слишком большой раздел до бюджета, не теряя текст.
  List<String> _splitOversized(String text, int budget) {
    if (estimator.estimate(text) <= budget) return <String>[text];

    final List<String> paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (paragraphs.length > 1) {
      return _splitPieces(paragraphs, budget, separator: '\n\n');
    }

    final List<String> lines = text
        .split('\n')
        .map((part) => part.trimRight())
        .where((part) => part.isNotEmpty)
        .toList();
    if (lines.length > 1) {
      return _splitPieces(lines, budget, separator: '\n');
    }

    return _hardSplit(text, budget);
  }

  /// Упаковывает абзацы/строки в группы до бюджета; oversized-часть режется.
  List<String> _splitPieces(
    List<String> pieces,
    int budget, {
    required String separator,
  }) {
    final List<String> result = <String>[];
    var current = <String>[];
    void flush() {
      if (current.isEmpty) return;
      result.add(current.join(separator));
      current = <String>[];
    }

    for (final String piece in pieces) {
      final List<String> parts = estimator.estimate(piece) <= budget
          ? <String>[piece]
          : _hardSplit(piece, budget);
      for (final String part in parts) {
        if (current.isEmpty) {
          current.add(part);
        } else if (estimator.estimate(
              <String>[...current, part].join(separator),
            ) <=
            budget) {
          current.add(part);
        } else {
          flush();
          current.add(part);
        }
      }
    }
    flush();
    return result;
  }

  /// Жёсткое деление по символам с запасом 20 % от бюджета.
  List<String> _hardSplit(String text, int budget) {
    final int targetChars = (budget * estimator.charsPerToken * 0.8).floor();
    final int size = targetChars < 1 ? 1 : targetChars;
    final List<int> runes = text.runes.toList(growable: false);
    final List<String> result = <String>[];
    var start = 0;
    while (start < runes.length) {
      final int end = (start + size) < runes.length
          ? start + size
          : runes.length;
      result.add(String.fromCharCodes(runes.sublist(start, end)));
      start = end;
    }
    return result;
  }
}

/// Кусок материала с именем файла-источника.
class _MaterialSegment {
  const _MaterialSegment({required this.text, required this.fileName});

  final String text;
  final String fileName;
}
