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
      expect(deepseek.defaultModel.id, 'deepseek-chat');
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
