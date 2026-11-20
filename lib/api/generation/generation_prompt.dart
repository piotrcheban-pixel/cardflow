/// Сборка пользовательского сообщения для модели (`gen-ru-v8`, ADR-040 §7).
///
/// Порядок блоков выбран так, чтобы **неизменный префикс** был одинаковым во
/// всех запросах одного запуска (кэширование префикса у провайдеров):
///
/// ```
/// <materials>…</materials>
/// <images>…</images>
/// <outline>…</outline>          (только если есть)
/// <wishes>…</wishes>
/// ────────── изменяемый хвост ──────────
/// <task>
///   <part>k из n</part>
///   <focus>s1, s2</focus>
///   <cards>N</cards>
///   <context_only>…</context_only>
///   <already_created>…</already_created>
/// </task>
/// ```
library;

/// Собирает сообщение пользователя.
///
/// [materialsText] — материалы части (у файлов уже есть строка `Файл: <имя>`;
/// разделы начинаются с `## [sN] Заголовок`). Пустой блок — одной строкой:
/// это режим «генерация по теме» (ADR-024).
/// [imagesCatalog] — строки `id | файл | подпись | контекст`.
/// [outline] — компактное оглавление (только при дроблении).
/// [partIndexHint]/[partCountHint] — «часть k из n»; `null` — одна часть.
/// [focusSectionIds] — короткие id разделов, по которым делать карточки.
/// [contextOnly] — перекрытие с предыдущей частью (без карточек).
/// [alreadyCreated] — компактный дайджест уже принятых карточек.
/// [limit] — сколько карточек запрошено в этом ответе (`<cards>`).
String buildGenerationUserContent({
  required String materialsText,
  String? wishes,
  required int limit,
  String? imagesCatalog,
  String? outline,
  int? partIndexHint,
  int? partCountHint,
  List<String> focusSectionIds = const <String>[],
  String? contextOnly,
  String? alreadyCreated,
}) {
  if (limit < 1) {
    throw ArgumentError.value(limit, 'limit', 'Лимит карточек должен быть ≥ 1');
  }
  final String materials = materialsText.trim();
  final String trimmedWishes = wishes?.trim() ?? '';
  final String catalog = imagesCatalog?.trim() ?? '';
  final String trimmedOutline = outline?.trim() ?? '';

  final StringBuffer buffer = StringBuffer();
  if (materials.isEmpty) {
    buffer.write('<materials></materials>');
  } else {
    buffer
      ..write('<materials>\n')
      ..write(materials)
      ..write('\n</materials>');
  }
  buffer.write('\n<images>');
  if (catalog.isNotEmpty) {
    buffer
      ..write('\n')
      ..write(catalog)
      ..write('\n');
  }
  buffer.write('</images>');
  if (trimmedOutline.isNotEmpty) {
    buffer
      ..write('\n<outline>\n')
      ..write(trimmedOutline)
      ..write('\n</outline>');
  }
  buffer.write('\n<wishes>');
  if (trimmedWishes.isNotEmpty) {
    buffer
      ..write('\n')
      ..write(trimmedWishes)
      ..write('\n');
  }
  buffer.write('</wishes>');
  // Изменяемый хвост: единственное, что различается между запросами.
  buffer.write('\n<task>');
  if (partIndexHint != null && partCountHint != null) {
    buffer
      ..write('\n<part>')
      ..write(partIndexHint)
      ..write(' из ')
      ..write(partCountHint)
      ..write('</part>');
  }
  final String focus = <String>[
    for (final String id in focusSectionIds)
      if (id.trim().isNotEmpty) id.trim(),
  ].join(', ');
  if (focus.isNotEmpty) {
    buffer
      ..write('\n<focus>')
      ..write(focus)
      ..write('</focus>');
  }
  buffer
    ..write('\n<cards>')
    ..write(limit)
    ..write('</cards>');
  final String overlap = contextOnly?.trim() ?? '';
  if (overlap.isNotEmpty) {
    buffer
      ..write('\n<context_only>\n')
      ..write(overlap)
      ..write('\n</context_only>');
  }
  final String digest = alreadyCreated?.trim() ?? '';
  if (digest.isNotEmpty) {
    buffer
      ..write('\n<already_created>\n')
      ..write(digest)
      ..write('\n</already_created>');
  }
  buffer.write('\n</task>');
  return buffer.toString();
}

/// Неизменный префикс сообщения (до `<task>`): для проверки кэширования.
String generationUserContentPrefix(String content) {
  final int index = content.indexOf('\n<task>');
  return index < 0 ? content : content.substring(0, index);
}
