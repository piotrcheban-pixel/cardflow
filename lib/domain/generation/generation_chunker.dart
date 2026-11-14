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
  List<GenerationChunk> chunkDocuments(
    List<ParsedDocument> documents, {
    required int maxInputTokens,
  }) {
    return const <GenerationChunk>[];
  }

  /// Делит фрагмент пополам (для повторного `truncated`); `null` — нельзя.
  List<GenerationChunk>? splitInHalf(GenerationChunk chunk) {
    return null;
  }
}
