/// Настройки OpenAI-совместимого сервера (ADR-013).
///
/// Хранятся в `app_settings` одним JSON-значением: адрес сервера и модель.
/// Ключ API здесь отсутствует by design — он живёт только в secure storage
/// (`ApiKeyStore`) и опционален для локальных серверов.
library;

/// Адрес и модель OpenAI-совместимого сервера.
class OpenAiCompatibleSettings {
  /// Создаёт настройки; по умолчанию пустые (сервер не настроен).
  const OpenAiCompatibleSettings({this.baseUrl = '', this.model = ''});

  /// Базовый адрес сервера (например `https://api.deepseek.com` или
  /// `http://localhost:11434/v1`); может быть пустым.
  final String baseUrl;

  /// Имя модели на сервере; может быть пустым.
  final String model;

  /// true, если заданы и адрес, и модель (после trim).
  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// Возвращает копию с изменёнными полями.
  OpenAiCompatibleSettings copyWith({String? baseUrl, String? model}) {
    return OpenAiCompatibleSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }

  /// Разбирает настройки из JSON; мусор и нестроковые поля — пустые значения.
  factory OpenAiCompatibleSettings.fromJson(Object? json) {
    if (json is! Map) return const OpenAiCompatibleSettings();
    final Object? baseUrl = json['baseUrl'];
    final Object? model = json['model'];
    return OpenAiCompatibleSettings(
      baseUrl: baseUrl is String ? baseUrl : '',
      model: model is String ? model : '',
    );
  }

  /// Представление для `app_settings.value_json`.
  Map<String, Object?> toJson() => <String, Object?>{
    'baseUrl': baseUrl,
    'model': model,
  };

  @override
  bool operator ==(Object other) {
    return other is OpenAiCompatibleSettings &&
        other.baseUrl == baseUrl &&
        other.model == model;
  }

  @override
  int get hashCode => Object.hash(baseUrl, model);

  @override
  String toString() =>
      'OpenAiCompatibleSettings(baseUrl: $baseUrl, model: $model)';
}
