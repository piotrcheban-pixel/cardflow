/// Реализация порта [CardGate] поверх существующего [CardValidator]
/// (TASK «Срез 11», часть 1).
///
/// Новой логики проверок здесь нет: гейт вызывает тот же `validate` с тем же
/// контекстом (материал, единицы партии, единицы без якорей), что и срез 10,
/// и переводит вердикты валидатора в три вердикта порта:
/// - `blocked` — жёсткий дефект (`CardVerdict.blocked`) или структурно
///   отброшенная запись (`RejectedCard`): карточка не идёт в заказ;
/// - `warning` — `CardVerdict.warning`: карточка принимается с пометками;
/// - `accepted` — без пометок.
///
/// Заблокированные карточки собираются в [blockedCards] (по одной на прогон —
/// гейт создаётся на прогон), чтобы предпросмотр мог показать «отброшенные»,
/// не теряя сам факт блокировки.
library;

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/validation/card_validator.dart';
import 'package:cardflow/domain/generation/card_gate.dart';
import 'package:cardflow/domain/generation/generated_card.dart';

/// Гейт карточки на существующем [CardValidator].
class CardValidatorGate implements CardGate {
  /// Создаёт гейт; контекст проверки тот же, что у валидатора ответа.
  CardValidatorGate({
    required this.validator,
    required this.document,
    Set<String> knownUnitIds = const <String>{},
    Set<String> unanchoredUnitIds = const <String>{},
  }) : knownUnitIds = Set<String>.unmodifiable(knownUnitIds),
       unanchoredUnitIds = Set<String>.unmodifiable(unanchoredUnitIds);

  /// Проверки A8.4 (структура, цитата по offsets, язык, LaTeX).
  final CardValidator validator;

  /// Материал для проверки цитаты по offsets; `null` — цитата не проверяется.
  final Document? document;

  /// id единиц плана (id вне набора — `unitUnknown`).
  final Set<String> knownUnitIds;

  /// Единицы без якорей (prompt-only) — вход проверки «без источника».
  final Set<String> unanchoredUnitIds;

  final List<GeneratedCard> _blocked = <GeneratedCard>[];

  /// Заблокированные карточки в порядке проверки (для отчёта и предпросмотра).
  List<GeneratedCard> get blockedCards =>
      List<GeneratedCard>.unmodifiable(_blocked);

  @override
  CardGateVerdict evaluate(GeneratedCard card) {
    final CardValidationReport report = validator.validate(
      <String, Object?>{
        'cards': <Object?>[responseJson(card)],
      },
      document: document,
      knownUnitIds: knownUnitIds,
      unanchoredUnitIds: unanchoredUnitIds,
    );
    if (report.blockedCount > 0 || report.rejected.isNotEmpty) {
      _blocked.add(card);
      return CardGateVerdict.blocked;
    }
    if (report.warningCount > 0) return CardGateVerdict.warning;
    return CardGateVerdict.accepted;
  }

  /// Карточка домена в форме ответа модели (A8.4 + поля v3).
  ///
  /// Та же форма, что проверял фасад до среза 11: поля `unit_id`/`angle`/
  /// `quote_ref`/`section_id` нужны валидатору для проверок привязки и цитаты.
  static Map<String, Object?> responseJson(GeneratedCard card) =>
      <String, Object?>{
        'front': card.front,
        'back': card.back,
        'card_type': card.cardType.wireName,
        'hint': card.hint,
        'tags': card.tags,
        'unit_id': card.unitId,
        'angle': card.angle,
        'quote_ref': card.quoteRef,
        'section_id': card.sectionId,
        'source_excerpt': card.sourceExcerpt,
      };
}
