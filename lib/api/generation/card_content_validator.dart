/// Локальная валидация карточек поверх схемы (SPEC A8.4).
///
/// Карточку не отбрасывает: правила качества ставят машинные пометки
/// `CardIssueCode`, чтобы предпросмотр (итерация 3c) показал их и дал
/// отредактировать.
library;

import 'package:cardflow/domain/generation/generated_card.dart';

/// Валидатор контентных правил A8.4.
class CardContentValidator {
  /// Создаёт валидатор.
  ///
  /// [latexChecker] — инъекция проверки LaTeX (по умолчанию `latexIsValid`
  /// из `latex_checker.dart`); в тестах можно подменить.
  const CardContentValidator({this.latexChecker});

  /// Проверка LaTeX-разметки текста; `null` — использовать `latexIsValid`.
  final bool Function(String text)? latexChecker;

  /// Валидирует декодированный ответ модели (уже прошедший проверку схемы).
  ///
  /// [sourceText] — исходный текст материалов для проверки `source_excerpt`.
  List<GeneratedCard> validateResponse(
    Object? json, {
    required String sourceText,
  }) {
    throw UnimplementedError('CardContentValidator.validateResponse');
  }
}
