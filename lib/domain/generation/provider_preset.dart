/// Каталог предустановленных провайдеров (ADR-020).
///
/// Статические данные приложения, как каталог моделей в DSH: адрес сервера,
/// протокол, популярные модели с окном контекста и обязательность ключа.
/// Пользователь выбирает провайдера из каталога — адрес и модель заполняются
/// автоматически; «Пользовательская модель API» задаёт их вручную.
/// Домен не зависит от Flutter; названия брендов не переводятся (SPEC 3.1).
library;

import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Популярная модель провайдера: id для запроса, подпись и окно контекста.
class ProviderPresetModel {
  /// Создаёт описание модели.
  const ProviderPresetModel({
    required this.id,
    required this.label,
    required this.contextTokens,
    this.supportsVision = false,
  });

  /// Идентификатор модели в запросе провайдеру.
  final String id;

  /// Отображаемое имя (бренд модели, латиница допустима).
  final String label;

  /// Окно контекста модели, токенов (для нарезки фрагментов).
  final int contextTokens;

  /// Принимает ли модель изображения (Vision).
  final bool supportsVision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderPresetModel &&
          other.id == id &&
          other.label == label &&
          other.contextTokens == contextTokens &&
          other.supportsVision == supportsVision;

  @override
  int get hashCode => Object.hash(id, label, contextTokens, supportsVision);

  @override
  String toString() => 'ProviderPresetModel($id)';
}

/// Предустановленный провайдер: адрес, протокол и популярные модели.
class ProviderPreset {
  /// Создаёт пресет.
  const ProviderPreset({
    required this.id,
    required this.label,
    required this.protocol,
    required this.baseUrl,
    required this.models,
    required this.requiresApiKey,
  });

  /// Стабильный идентификатор пресета (=== id аккаунта при первом добавлении).
  final String id;

  /// Отображаемое имя (бренд).
  final String label;

  /// Протокол API.
  final ProviderProtocol protocol;

  /// Базовый адрес сервера.
  final String baseUrl;

  /// Популярные модели (первая — по умолчанию); не пусто.
  final List<ProviderPresetModel> models;

  /// Нужен ли ключ доступа (локальному серверу — нет).
  final bool requiresApiKey;

  /// Модель по умолчанию.
  ProviderPresetModel get defaultModel => models.first;

  /// Модель пресета по id или `null`.
  ProviderPresetModel? modelById(String modelId) {
    for (final ProviderPresetModel model in models) {
      if (model.id == modelId) return model;
    }
    return null;
  }

  @override
  String toString() => 'ProviderPreset($id)';
}

/// Каталог предустановленных провайдеров (ADR-020).
const List<ProviderPreset> kProviderPresets = <ProviderPreset>[
  ProviderPreset(
    id: 'deepseek',
    label: 'DeepSeek',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.deepseek.com',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'deepseek-chat',
        label: 'DeepSeek Chat',
        contextTokens: 128000,
      ),
      ProviderPresetModel(
        id: 'deepseek-reasoner',
        label: 'DeepSeek Reasoner',
        contextTokens: 128000,
      ),
    ],
    requiresApiKey: true,
  ),
  ProviderPreset(
    id: 'openai',
    label: 'OpenAI',
    protocol: ProviderProtocol.openai,
    baseUrl: 'https://api.openai.com/v1',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'gpt-4o-mini',
        label: 'GPT-4o mini',
        contextTokens: 128000,
        supportsVision: true,
      ),
      ProviderPresetModel(
        id: 'gpt-4o',
        label: 'GPT-4o',
        contextTokens: 128000,
        supportsVision: true,
      ),
    ],
    requiresApiKey: true,
  ),
  ProviderPreset(
    id: 'anthropic',
    label: 'Anthropic',
    protocol: ProviderProtocol.anthropicMessages,
    baseUrl: 'https://api.anthropic.com',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'claude-3-5-haiku-latest',
        label: 'Claude 3.5 Haiku',
        contextTokens: 200000,
        supportsVision: true,
      ),
      ProviderPresetModel(
        id: 'claude-3-5-sonnet-latest',
        label: 'Claude 3.5 Sonnet',
        contextTokens: 200000,
        supportsVision: true,
      ),
    ],
    requiresApiKey: true,
  ),
  ProviderPreset(
    id: 'gemini',
    label: 'Gemini',
    protocol: ProviderProtocol.geminiGenerateContent,
    baseUrl: 'https://generativelanguage.googleapis.com',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'gemini-2.0-flash',
        label: 'Gemini 2.0 Flash',
        contextTokens: 1048576,
        supportsVision: true,
      ),
      ProviderPresetModel(
        id: 'gemini-2.5-flash',
        label: 'Gemini 2.5 Flash',
        contextTokens: 1048576,
        supportsVision: true,
      ),
    ],
    requiresApiKey: true,
  ),
  ProviderPreset(
    id: 'openrouter',
    label: 'OpenRouter',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://openrouter.ai/api/v1',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'openai/gpt-4o-mini',
        label: 'GPT-4o mini',
        contextTokens: 128000,
        supportsVision: true,
      ),
      ProviderPresetModel(
        id: 'anthropic/claude-3.5-sonnet',
        label: 'Claude 3.5 Sonnet',
        contextTokens: 200000,
        supportsVision: true,
      ),
      ProviderPresetModel(
        id: 'deepseek/deepseek-chat',
        label: 'DeepSeek Chat',
        contextTokens: 128000,
      ),
    ],
    requiresApiKey: true,
  ),
  ProviderPreset(
    id: 'moonshot',
    label: 'Moonshot (Kimi)',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.moonshot.ai/v1',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'kimi-latest',
        label: 'Kimi Latest',
        contextTokens: 128000,
      ),
      ProviderPresetModel(
        id: 'moonshot-v1-8k',
        label: 'Moonshot v1 8K',
        contextTokens: 8000,
      ),
    ],
    requiresApiKey: true,
  ),
  ProviderPreset(
    id: 'minimax',
    label: 'MiniMax',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.minimax.io/v1',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'MiniMax-Text-01',
        label: 'MiniMax Text 01',
        contextTokens: 128000,
      ),
      ProviderPresetModel(
        id: 'abab6.5s-chat',
        label: 'abab6.5s chat',
        contextTokens: 32000,
      ),
    ],
    requiresApiKey: true,
  ),
  ProviderPreset(
    id: 'groq',
    label: 'Groq',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.groq.com/openai/v1',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'llama-3.3-70b-versatile',
        label: 'Llama 3.3 70B',
        contextTokens: 131072,
      ),
      ProviderPresetModel(
        id: 'llama-3.1-8b-instant',
        label: 'Llama 3.1 8B',
        contextTokens: 131072,
      ),
    ],
    requiresApiKey: true,
  ),
  ProviderPreset(
    id: 'ollama',
    label: 'Ollama (Local)',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'http://localhost:11434/v1',
    models: <ProviderPresetModel>[
      ProviderPresetModel(
        id: 'llama3.1',
        label: 'Llama 3.1',
        contextTokens: 131072,
      ),
      ProviderPresetModel(
        id: 'qwen2.5',
        label: 'Qwen 2.5',
        contextTokens: 32768,
      ),
    ],
    requiresApiKey: false,
  ),
];

/// Пресет по id или `null`.
ProviderPreset? providerPresetById(String presetId) {
  for (final ProviderPreset preset in kProviderPresets) {
    if (preset.id == presetId) return preset;
  }
  return null;
}

/// Пресет по базовому адресу (для миграции старых настроек) или `null`.
///
/// Сравнение по `scheme://host[:port]` + пути без хвостовых слешей: старые
/// настройки могли сохранить адрес как `https://api.deepseek.com/`.
ProviderPreset? providerPresetByBaseUrl(String baseUrl) {
  final String normalized = _normalizeBaseUrl(baseUrl);
  if (normalized.isEmpty) return null;
  for (final ProviderPreset preset in kProviderPresets) {
    if (_normalizeBaseUrl(preset.baseUrl) == normalized) return preset;
  }
  return null;
}

/// Приводит адрес к сравнимому виду: нижний регистр, без хвостовых слешей.
String _normalizeBaseUrl(String value) {
  var normalized = value.trim().toLowerCase();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
