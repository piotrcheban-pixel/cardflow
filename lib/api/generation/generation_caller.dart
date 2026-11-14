/// Узкий контракт вызова модели для пайплайна (ADR-015).
///
/// `CardGenerationService` (слой 3b) реализует его как есть; пайплайн не
/// зависит от конкретных адаптеров, HTTP и ключей.
library;

import 'package:dio/dio.dart';

import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

/// Вызов модели на один фрагмент материалов.
abstract interface class GenerationCaller {
  /// Генерирует карточки; ошибки — `GenerationException`.
  Future<GenerationResult> generate(
    GenerationRequest request, {
    CancelToken? cancelToken,
  });
}
