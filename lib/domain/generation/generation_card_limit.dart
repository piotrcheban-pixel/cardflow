/// Разбор числа карточек из пожеланий пользователя (итерация fix-gen).
///
/// Если пользователь указал в пожеланиях общее число карточек («20 карточек»),
/// приложение передаёт его планировщику как заказ. Здесь **нет** продуктового
/// потолка в 200: заказ сохраняется как есть, а выполнимость проверяет план
/// (число запросов, бюджет вывода, `maxChunks`). Молчаливый срез запрещён:
/// расхождение «запрошено/достижимо» видно в `GenerationPlan` и в UI.
///
/// Техническая защита — только от переполнения `int`: число разбирается через
/// `BigInt`, а значение выше `int.max` превращается в `int.max`, после чего
/// планировщик честно сообщает, что заказ невыполним (`tooManyChunks`/
/// `requestedAbovePlan`), вместо переполнения или тихого усечения.
/// Чистые правила без Flutter.
library;

/// Максимальное значение `int` (64-bit): граница представления заказа.
///
/// Не продуктовый лимит количества карточек: всё, что выше, не помещается в
/// `int` и получает `int.max`, чтобы план мог явно отказать.
const int kMaxRepresentableRequestedCards = 9223372036854775807;

/// Общее число карточек, указанное в пожеланиях; `null` — не указано.
///
/// Понимает «20 карточек», «сделайте 20 карточек», «около 15 карт», «20 cards»,
/// «500 карточек», «1000 карточек». Числа без слова «карточк*» не считаются
/// количеством: «глава 3» не означает три карточки. Значение **не** режется
/// до 200 (бывший `kMaxRequestedCards`): политику выполнимости определяет
/// `GenerationPlan`.
int? requestedCardCount(String? wishes) {
  final String text = wishes?.trim() ?? '';
  if (text.isEmpty) return null;
  final List<RegExp> patterns = <RegExp>[
    RegExp(
      r'(\d+)\s*(?:шт\.?\s*)?(?:карточ|карт(?=\s|$|[,.;:!?])|карт[аыу])',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(?:карточ\w*|cards?)\s*[:=\-—]?\s*(\d+)',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(\d+)\s*cards?(?=\s|$|[,.;:!?])',
      caseSensitive: false,
      unicode: true,
    ),
  ];
  for (final RegExp pattern in patterns) {
    final Match? match = pattern.firstMatch(text);
    if (match == null) continue;
    final BigInt? value = BigInt.tryParse(match.group(1)!);
    if (value == null || value <= BigInt.zero) continue;
    final BigInt limit = BigInt.from(kMaxRepresentableRequestedCards);
    if (value > limit) return kMaxRepresentableRequestedCards;
    return value.toInt();
  }
  return null;
}
