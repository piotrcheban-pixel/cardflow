/// Запрос на генерацию карточек (SPEC A8.5 шаги 4–7, итерация 3b: один фрагмент).
library;

import 'package:cardflow/domain/generation/generation_provider.dart';

/// Параметры одного вызова модели (без чанкинга — он в итерации 3c).
class GenerationRequest {
  /// Создаёт запрос.
  const GenerationRequest({
    required this.provider,
    required this.model,
    required this.materialsText,
    required this.limit,
    this.wishes,
  });

  /// Провайдер.
  final GenerationProvider provider;

  /// Модель провайдера (выбор — итерация 7, здесь параметр).
  final String model;

  /// Текст фрагмента материалов (из парсеров A8.3).
  final String materialsText;

  /// Максимальное число карточек в ответе (`<limit>`, A8.1).
  final int limit;

  /// Необязательные пожелания пользователя по содержанию (A6.8).
  final String? wishes;
}
