/// Разбор нестрогих JSON-ответов провайдеров картинок (итерация 7.14).
///
/// API Commons/Openverse/Pixabay/Pexels отдают разные типы и вложенность;
/// общие безопасные аксессоры держим в одном месте, чтобы провайдеры не
/// дублировали приведение типов.
library;

/// Строка из JSON без пустых значений; `null` — поля нет/пусто.
String? asString(Object? value) {
  if (value is! String) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Целое из JSON; `null` — не число/не положительное.
int? asPositiveInt(Object? value) {
  final num? number = value is num
      ? value
      : value is String
      ? num.tryParse(value)
      : null;
  if (number == null) return null;
  final int result = number.round();
  return result > 0 ? result : null;
}

/// Убирает HTML-теги и раскрывает основные сущности (атрибуция Commons).
String? stripHtml(Object? value) {
  if (value is! String) return null;
  final String text = value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? null : text;
}

/// Собирает строку атрибуции из непустых частей через ` · `.
String? joinAttribution(List<String?> parts) {
  final List<String> present = <String>[
    for (final String? part in parts)
      if (part != null && part.trim().isNotEmpty) part.trim(),
  ];
  return present.isEmpty ? null : present.join(' · ');
}
