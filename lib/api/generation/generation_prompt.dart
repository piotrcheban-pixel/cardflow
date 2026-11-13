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
  final materials = materialsText.trim();
  if (materials.isEmpty) {
    throw ArgumentError.value(
      materialsText,
      'materialsText',
      'Материалы для генерации не должны быть пустыми',
    );
  }
  if (limit < 1) {
    throw ArgumentError.value(limit, 'limit', 'Лимит карточек должен быть ≥ 1');
  }

  final buffer = StringBuffer()
    ..write('<materials>\n')
    ..write(materials)
    ..write('\n</materials>');

  final trimmedWishes = wishes?.trim();
  if (trimmedWishes != null && trimmedWishes.isNotEmpty) {
    buffer
      ..write('\n<wishes>\n')
      ..write(trimmedWishes)
      ..write('\n</wishes>');
  }

  buffer
    ..write('\n<limit>')
    ..write(limit)
    ..write('</limit>');
  return buffer.toString();
}
