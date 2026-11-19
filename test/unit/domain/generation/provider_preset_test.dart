import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Итерация 7.5, шаг 2 (ADR-020): статический каталог провайдеров.
void main() {
  group('Каталог провайдеров', () {
    test(
      'содержит девять предустановленных провайдеров в заданном порядке',
      () {
        expect(kProviderPresets, hasLength(9));
        expect(
          kProviderPresets.map((ProviderPreset preset) => preset.id).toList(),
          <String>[
            'deepseek',
            'openai',
            'anthropic',
            'gemini',
            'openrouter',
            'moonshot',
            'minimax',
            'groq',
            'ollama',
          ],
        );
      },
    );

    test('у каждого пресета непустые адрес, модели и протокол', () {
      for (final ProviderPreset preset in kProviderPresets) {
        expect(preset.baseUrl.trim(), isNotEmpty, reason: preset.id);
        expect(preset.models, isNotEmpty, reason: preset.id);
        expect(preset.label.trim(), isNotEmpty, reason: preset.id);
        for (final ProviderPresetModel model in preset.models) {
          expect(model.id.trim(), isNotEmpty, reason: preset.id);
          expect(model.label.trim(), isNotEmpty, reason: preset.id);
          expect(model.contextTokens, greaterThan(0), reason: preset.id);
        }
      }
    });

    test('DeepSeek — OpenAI-совместимый протокол и адрес api.deepseek.com', () {
      final ProviderPreset deepseek = providerPresetById('deepseek')!;
      expect(deepseek.label, 'DeepSeek');
      expect(deepseek.protocol, ProviderProtocol.openaiCompletions);
      expect(
        deepseek.protocol.adapterProvider,
        GenerationProvider.openaiCompatible,
      );
      expect(deepseek.baseUrl, 'https://api.deepseek.com');
      // Актуальные id моделей DeepSeek (проверено 2026-11-19): flash — модель
      // по умолчанию, legacy-имена остаются для сохранённых аккаунтов.
      expect(deepseek.defaultModel.id, 'deepseek-flash');
      expect(deepseek.defaultModel.contextTokens, 1000000);
      expect(deepseek.defaultModel.supportsVision, isTrue);
      expect(deepseek.modelById('deepseek-v4-pro')?.contextTokens, 1000000);
      expect(deepseek.modelById('deepseek-v4-pro')?.supportsVision, isFalse);
      expect(deepseek.modelById('deepseek-chat')?.contextTokens, 128000);
      expect(deepseek.modelById('deepseek-reasoner'), isNotNull);
      expect(deepseek.requiresApiKey, isTrue);
    });

    test('нативные протоколы: OpenAI, Anthropic, Gemini', () {
      expect(providerPresetById('openai')!.protocol, ProviderProtocol.openai);
      expect(
        providerPresetById('anthropic')!.protocol.wireName,
        'anthropic-messages',
      );
      expect(
        providerPresetById('gemini')!.protocol,
        ProviderProtocol.geminiGenerateContent,
      );
    });

    test('Ollama — локальный сервер без ключа', () {
      final ProviderPreset ollama = providerPresetById('ollama')!;
      expect(ollama.requiresApiKey, isFalse);
      expect(ollama.baseUrl, 'http://localhost:11434/v1');
      expect(ollama.protocol, ProviderProtocol.openaiCompletions);
    });

    test('неизвестный пресет — null', () {
      expect(providerPresetById('unknown'), isNull);
    });

    test('поиск пресета по базовому адресу нормализует хвостовые слеши', () {
      expect(
        providerPresetByBaseUrl('https://api.deepseek.com/')?.id,
        'deepseek',
      );
      expect(
        providerPresetByBaseUrl('  https://api.deepseek.com  ')?.id,
        'deepseek',
      );
      expect(providerPresetByBaseUrl('https://example.com'), isNull);
      expect(providerPresetByBaseUrl(''), isNull);
    });

    test('модель пресета ищется по id', () {
      final ProviderPreset gemini = providerPresetById('gemini')!;
      expect(gemini.modelById('gemini-2.5-flash')?.label, 'Gemini 2.5 Flash');
      expect(gemini.modelById('nope'), isNull);
      expect(gemini.defaultModel.id, 'gemini-2.0-flash');
    });

    test('дефолты supportsVision: vision-модели true, текстовые false', () {
      final Map<String, bool> vision = <String, bool>{
        for (final ProviderPreset preset in kProviderPresets)
          for (final ProviderPresetModel model in preset.models)
            '${preset.id}/${model.id}': model.supportsVision,
      };

      expect(vision['openai/gpt-4o'], isTrue);
      expect(vision['openai/gpt-4o-mini'], isTrue);
      expect(vision['gemini/gemini-2.0-flash'], isTrue);
      expect(vision['gemini/gemini-2.5-flash'], isTrue);
      expect(vision['anthropic/claude-3-5-haiku-latest'], isTrue);
      expect(vision['anthropic/claude-3-5-sonnet-latest'], isTrue);
      expect(vision['openrouter/openai/gpt-4o-mini'], isTrue);
      expect(vision['openrouter/anthropic/claude-3.5-sonnet'], isTrue);

      expect(vision['deepseek/deepseek-flash'], isTrue);
      expect(vision['deepseek/deepseek-v4-pro'], isFalse);
      expect(vision['deepseek/deepseek-chat'], isFalse);
      expect(vision['deepseek/deepseek-reasoner'], isFalse);
      expect(vision['openrouter/deepseek/deepseek-chat'], isFalse);
      expect(vision['moonshot/moonshot-v1-8k'], isFalse);
      expect(vision['minimax/MiniMax-Text-01'], isFalse);
      expect(vision['groq/llama-3.3-70b-versatile'], isFalse);
      expect(vision['ollama/llama3.1'], isFalse);
      expect(vision['ollama/qwen2.5'], isFalse);
    });

    test('PDF-vision — только Anthropic и Gemini', () {
      expect(ProviderProtocol.anthropicMessages.supportsPdfAttachments, isTrue);
      expect(
        ProviderProtocol.geminiGenerateContent.supportsPdfAttachments,
        isTrue,
      );
      expect(ProviderProtocol.openai.supportsPdfAttachments, isFalse);
      expect(
        ProviderProtocol.openaiCompletions.supportsPdfAttachments,
        isFalse,
      );
    });

    test('протоколы для пользовательской модели поддерживают свой адрес', () {
      expect(ProviderProtocol.customProtocols, hasLength(3));
      expect(
        ProviderProtocol.customProtocols,
        isNot(contains(ProviderProtocol.openai)),
      );
      expect(
        ProviderProtocol.openaiCompletions.defaultBaseUrl,
        isEmpty,
        reason: 'Для OpenAI-совместимого адрес обязан вводить пользователь',
      );
      expect(
        ProviderProtocol.anthropicMessages.defaultBaseUrl,
        'https://api.anthropic.com',
      );
    });

    test('протокол разбирается из wire-имени и отвергает мусор', () {
      expect(
        ProviderProtocol.fromWire('gemini-generate-content'),
        ProviderProtocol.geminiGenerateContent,
      );
      expect(() => ProviderProtocol.fromWire('grpc'), throwsFormatException);
    });
  });
}
