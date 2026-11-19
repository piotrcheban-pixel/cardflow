/// Набор адаптеров провайдеров генерации (SPEC A8.2, ADR-013/ADR-020).
///
/// Один список для production-проводки и live-испытаний: если тест собирает
/// адаптеры сам, он может проверять не тот код, который работает у
/// пользователя. Файл не зависит от Flutter и Riverpod.
library;

import 'package:cardflow/api/providers/anthropic_adapter.dart';
import 'package:cardflow/api/providers/gemini_adapter.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';

/// Адаптеры провайдеров для сервиса генерации (по одному на протокол).
///
/// Порядок не важен: поиск идёт по [GenerationProviderAdapter.provider].
const List<GenerationProviderAdapter> generationAdapters =
    <GenerationProviderAdapter>[
      OpenAiAdapter(),
      GeminiAdapter(),
      AnthropicAdapter(),
      OpenAiCompatibleAdapter(),
    ];
