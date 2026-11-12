/// Максимальная длина имени колоды в имени файла (без `.zip`).
const int _maxBaseLength = 80;

/// Недопустимые для файловой системы Windows/macOS/Linux символы.
final RegExp _invalidFileNameChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

/// Последовательности пробельных символов (включая табы/переводы строк).
final RegExp _whitespace = RegExp(r'\s+');

/// Имя файла для экспорта колоды в ZIP-архив.
///
/// Берёт название колоды, убирает недопустимые для файловой системы символы
/// (`\ / : * ? " < > |` и управляющие), схлопывает пробелы и добавляет
/// расширение `.zip`. Пустое/непригодное название заменяется запасным из ARB.
String deckArchiveFileName(String deckName, {required String fallbackName}) {
  String base = _sanitize(deckName);
  if (base.isEmpty) {
    base = _sanitize(fallbackName);
  }
  if (base.isEmpty) {
    base = 'колода';
  }
  if (base.length > _maxBaseLength) {
    base = base.substring(0, _maxBaseLength).trim();
  }
  return '$base.zip';
}

String _sanitize(String value) {
  return value
      .replaceAll(_invalidFileNameChars, ' ')
      .replaceAll(_whitespace, ' ')
      .trim();
}
