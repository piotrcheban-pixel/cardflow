/// Сборка пользовательского сообщения для модели (SPEC A8.1, A8.5).
library;

/// Собирает сообщение пользователя из блоков `<materials>`, `<wishes>`,
/// `<limit>` и `<images>` (промпт `gen-ru-v5`).
///
/// [materialsText] — материалы фрагмента; у каждого файла уже есть строка
/// `Файл: <имя>` (чанкер). Пустой блок пишется как `<materials></materials>`:
/// это режим «генерация по теме», тема — в `<wishes>` (ADR-024).
/// [imagesCatalog] — строки `id | файл | подпись | окружающий текст`
/// (пустой каталог — `<images></images>`).
/// [limit] — максимум карточек в ответе (A8.1: жёсткий лимит).
String buildGenerationUserContent({
  required String materialsText,
  String? wishes,
  required int limit,
  String? imagesCatalog,
}) {
  final materials = materialsText.trim();
  if (limit < 1) {
    throw ArgumentError.value(limit, 'limit', 'Лимит карточек должен быть ≥ 1');
  }
  final String trimmedWishes = wishes?.trim() ?? '';
  final String catalog = imagesCatalog?.trim() ?? '';

  final StringBuffer buffer = StringBuffer();
  if (materials.isEmpty) {
    buffer.write('<materials></materials>');
  } else {
    buffer
      ..write('<materials>\n')
      ..write(materials)
      ..write('\n</materials>');
  }

  buffer.write('\n<wishes>');
  if (trimmedWishes.isNotEmpty) {
    buffer
      ..write('\n')
      ..write(trimmedWishes)
      ..write('\n');
  }
  buffer.write('</wishes>');

  buffer
    ..write('\n<limit>')
    ..write(limit)
    ..write('</limit>');

  buffer.write('\n<images>');
  if (catalog.isNotEmpty) {
    buffer
      ..write('\n')
      ..write(catalog)
      ..write('\n');
  }
  buffer.write('</images>');
  return buffer.toString();
}
