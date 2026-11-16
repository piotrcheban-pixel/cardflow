/// Ключи необязательных провайдеров картинок (итерация 7.14).
///
/// Ключи не хранятся в коде и не коммитятся: только `--dart-define` при сборке
/// или переменные окружения процесса (`Platform.environment` на десктопе).
/// Без ключа провайдер пропускается — цепочка продолжает работу без него.
library;

import 'dart:io';

/// Pexels API-ключ из окружения; `null` — провайдер выключен.
String? pexelsApiKeyFromEnvironment() => _fromEnvironment(
  define: const String.fromEnvironment('PEXELS_API_KEY'),
  variable: 'PEXELS_API_KEY',
);

/// Pixabay API-ключ из окружения; `null` — провайдер выключен.
String? pixabayApiKeyFromEnvironment() => _fromEnvironment(
  define: const String.fromEnvironment('PIXABAY_API_KEY'),
  variable: 'PIXABAY_API_KEY',
);

/// Значение из `--dart-define`, иначе из переменной окружения процесса.
String? _fromEnvironment({required String define, required String variable}) {
  if (define.trim().isNotEmpty) return define.trim();
  try {
    final String? value = Platform.environment[variable];
    if (value != null && value.trim().isNotEmpty) return value.trim();
  } on Object {
    // Платформа без dart:io-окружения — ключа нет, провайдер выключен.
  }
  return null;
}
