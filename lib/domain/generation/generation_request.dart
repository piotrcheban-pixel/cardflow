/// Запрос на генерацию карточек (SPEC A8.5 шаги 4–7).
///
/// Один вызов модели на один фрагмент; аккаунт провайдера несёт протокол,
/// адрес, модель и id для ключа (ADR-020).
library;

import 'package:cardflow/domain/generation/provider_account.dart';

/// Параметры одного вызова модели (чанкинг — в пайплайне).
class GenerationRequest {
  /// Создаёт запрос.
  const GenerationRequest({
    required this.account,
    required this.materialsText,
    required this.limit,
    this.wishes,
  });

  /// Провайдер: протокол, адрес, модель и id ключа.
  final ProviderAccount account;

  /// Текст фрагмента материалов (из парсеров A8.3).
  final String materialsText;

  /// Максимальное число карточек в ответе (`<limit>`, A8.1).
  final int limit;

  /// Необязательные пожелания пользователя по содержанию (A6.8).
  final String? wishes;
}
