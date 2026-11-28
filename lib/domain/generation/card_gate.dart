/// Гейт карточки: одно место, где решается, идёт ли карточка в заказ
/// (TASK «Срез 11», часть 1, ARCH §2 этап 5; срез 12 — коды причин).
///
/// Порт намеренно узкий — один метод [CardGate.evaluate]: этап Generation
/// (первый проход) и этап Replenish (добор) спрашивают **один и тот же** гейт,
/// поэтому заблокированная карточка не может закрыть слот в обход проверки.
/// Правила проверок живут в существующем `CardValidator`; реализация порта —
/// адаптер `CardValidatorGate` в `lib/api/generation/validation/`, новая логика
/// проверок не пишется.
///
/// Вердиктов три, как в TASK: [CardGateVerdict.accepted] — карточка принимается
/// без пометок, [CardGateVerdict.warning] — принимается с пометкой,
/// [CardGateVerdict.blocked] — в заказ не идёт (и в журнал «принято» не
/// попадает), но не исчезает: вызывающий слой хранит её для «показать
/// отброшенные».
///
/// С среза 12 [CardGateResult] несёт и **коды причин** ([CardReasonCode]):
/// пометки принятой карточки доезжают до отчёта (`cleanRate`) и предпросмотра,
/// а не теряются на границе порта.
library;

import 'package:cardflow/domain/generation/card_reason_code.dart';
import 'package:cardflow/domain/generation/generated_card.dart';

/// Вердикт гейта по одной карточке.
enum CardGateVerdict {
  /// Карточка годна без пометок.
  accepted,

  /// Карточка годна с пометками качества (A8.4: не отбрасывать молча).
  warning,

  /// Жёсткий дефект: в заказ и колоду карточка не идёт.
  blocked,
}

/// Итог проверки одной карточки: вердикт и коды причин.
class CardGateResult {
  /// Создаёт итог; список кодов копируется и становится неизменяемым.
  CardGateResult({
    required this.verdict,
    List<CardReasonCode> reasons = const <CardReasonCode>[],
  }) : reasons = List<CardReasonCode>.unmodifiable(reasons);

  /// Вердикт гейта.
  final CardGateVerdict verdict;

  /// Причины вердикта (TASK «Срез 12», п. 1): у `accepted` пусто, у `warning`
  /// пометки качества, у `blocked` — жёсткий дефект или код отбрасывания.
  final List<CardReasonCode> reasons;

  /// true — карточка идёт в заказ (accepted или warning).
  bool get isImportable => verdict != CardGateVerdict.blocked;

  @override
  String toString() =>
      'CardGateResult(${verdict.name}, '
      '${reasons.map((CardReasonCode code) => code.wireName).join(',')})';
}

/// Порт проверки карточки перед приёмом в заказ.
abstract interface class CardGate {
  /// Проверяет [card] и возвращает вердикт с кодами причин.
  ///
  /// Реализация не бросает исключений на содержательные дефекты: они —
  /// вердикт [CardGateVerdict.blocked], а не сбой прогона.
  CardGateResult evaluate(GeneratedCard card);
}
