/// Сборка пользовательского сообщения для модели (SPEC A8.1, A8.5).
library;

/// Собирает сообщение пользователя из блоков `<materials>`, `<wishes>` и `<limit>`.
///
/// Пожелания передаются отдельным блоком `<wishes>` (A8.1: промпт одинаков для
/// всех фрагментов и может кэшироваться провайдером); пустые пожелания блок не
/// добавляют. [limit] — максимум карточек в ответе (A8.1 правило 13).
String buildGenerationUserContent({
  required String materialsText,
  String? wishes,
  required int limit,
}) {
  throw UnimplementedError('buildGenerationUserContent');
}
