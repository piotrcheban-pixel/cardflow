import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/openai_compatible_settings.dart';

/// Настройки OpenAI-совместимого сервера (ADR-013): модель, сериализация,
/// устойчивость к битым данным.
void main() {
  group('OpenAiCompatibleSettings', () {
    test('по умолчанию пустые и не настроены', () {
      const settings = OpenAiCompatibleSettings();
      expect(settings.baseUrl, isEmpty);
      expect(settings.model, isEmpty);
      expect(settings.isConfigured, isFalse);
    });

    test('isConfigured требует непустые (после trim) адрес и модель', () {
      expect(
        const OpenAiCompatibleSettings(
          baseUrl: 'https://api.example.com/v1',
          model: 'model-1',
        ).isConfigured,
        isTrue,
      );
      expect(
        const OpenAiCompatibleSettings(
          baseUrl: '   ',
          model: 'model-1',
        ).isConfigured,
        isFalse,
      );
      expect(
        const OpenAiCompatibleSettings(
          baseUrl: 'https://api.example.com',
          model: '  ',
        ).isConfigured,
        isFalse,
      );
    });

    test('copyWith меняет только заданные поля', () {
      const original = OpenAiCompatibleSettings(
        baseUrl: 'http://localhost:11434/v1',
        model: 'qwen',
      );
      final changed = original.copyWith(model: 'llama');
      expect(changed.baseUrl, original.baseUrl);
      expect(changed.model, 'llama');
      expect(original.model, 'qwen');
    });

    test('равенство и hashCode по полям', () {
      const first = OpenAiCompatibleSettings(
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-chat',
      );
      const same = OpenAiCompatibleSettings(
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-chat',
      );
      const other = OpenAiCompatibleSettings(
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-reasoner',
      );
      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(other));
    });

    test('toJson/fromJson: полный round-trip', () {
      const settings = OpenAiCompatibleSettings(
        baseUrl: 'http://localhost:1234/v1',
        model: 'local-model',
      );
      final restored = OpenAiCompatibleSettings.fromJson(settings.toJson());
      expect(restored, settings);
      expect(settings.toJson(), <String, Object?>{
        'baseUrl': 'http://localhost:1234/v1',
        'model': 'local-model',
      });
    });

    test('fromJson терпит мусор: null, не-объект, не-строки, лишние поля', () {
      for (final payload in <Object?>[null, 42, 'строка', <Object?>[]]) {
        expect(
          OpenAiCompatibleSettings.fromJson(payload),
          const OpenAiCompatibleSettings(),
          reason: 'payload=$payload',
        );
      }
      expect(
        OpenAiCompatibleSettings.fromJson(<String, Object?>{
          'baseUrl': 7,
          'model': <String, Object?>{},
          'apiKey': 'не хранится здесь',
        }),
        const OpenAiCompatibleSettings(),
      );
      expect(
        OpenAiCompatibleSettings.fromJson(<String, Object?>{
          'baseUrl': 'https://api.example.com',
          'model': 'm',
          'extra': true,
        }),
        const OpenAiCompatibleSettings(
          baseUrl: 'https://api.example.com',
          model: 'm',
        ),
      );
    });
  });
}
