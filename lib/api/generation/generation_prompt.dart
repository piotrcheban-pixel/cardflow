/// Сборка пользовательского сообщения для модели (SPEC A8.1, A8.5).
library;

/// Собирает сообщение пользователя из блоков `<materials>`, `<wishes>` и `<limit>`.
///
/// Пожелания передаются отдельным блоком `<wishes>` (A8.1: промпт одинаков для
/// всех фрагментов и может кэшироваться провайдером); пустые пожелания блок не
/// добавляют. [limit] — максимум карточек в ответе (A8.1 правило 13).
///
/// Пустые [materialsText] допустимы: это режим «генерация по теме», где тема
/// и требования заданы в `<wishes>` (итерация 7.10, ADR-024); блок
/// `<materials>` всё равно передаётся пустым.
String buildGenerationUserContent({
  required String materialsText,
  String? wishes,
  required int limit,
}) {
  final materials = materialsText.trim();
  if (limit < 1) {
    throw ArgumentError.value(limit, 'limit', 'Лимит карточек должен быть ≥ 1');
  }

  final StringBuffer buffer = StringBuffer()..write('<materials>\n');
  if (materials.isNotEmpty) buffer.write('$materials\n');
  buffer.write('</materials>');

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
