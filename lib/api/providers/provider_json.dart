/// Разбор JSON-ответов провайдеров без `dynamic`: безопасные приведения,
/// общие для адаптеров OpenAI / Gemini / Anthropic.
library;

import 'package:cardflow/domain/generation/generation_error.dart';

/// Приводит [value] к объекту со строковыми ключами.
///
/// Возвращает `null`, если [value] — не JSON-объект или у него нестроковый
/// ключ. Возвращаемая копия не меняет исходный ответ.
Map<String, Object?>? jsonObjectOrNull(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) return null;
    result[key] = entry.value;
  }
  return result;
}

/// Приводит [value] к списку значений; `null`, если это не JSON-массив.
List<Object?>? jsonListOrNull(Object? value) =>
    value is List ? List<Object?>.of(value) : null;

/// Число из JSON в `int`; `null` для отсутствующего/нечислового значения.
///
/// Нечисловые и неконечные значения (`Infinity`/`NaN`, которые может дать
/// `1e999` в недоверенном JSON) не бросают `UnsupportedError`, а дают `null`.
int? jsonIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite) return value.toInt();
  return null;
}

/// Ошибка «невалидный ответ провайдера» (`invalidResponse`).
///
/// [provider] — имя провайдера для диагностики, [details] — что именно не
/// разобралось; ни то, ни другое не попадает в UI.
GenerationException invalidProviderResponse(String provider, String details) =>
    GenerationException(
      GenerationErrorCode.invalidResponse,
      details: '$provider: $details',
    );
