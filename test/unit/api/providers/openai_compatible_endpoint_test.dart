import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/providers/openai_compatible_endpoint.dart';

/// Разбор и нормализация `base_url` OpenAI-совместимого сервера (ADR-013).
void main() {
  Uri validUri(String input) {
    final endpoint = OpenAiCompatibleEndpoint.parse(input);
    expect(endpoint.error, isNull, reason: 'input=$input');
    return endpoint.uri!;
  }

  OpenAiCompatibleEndpointError errorOf(String input) {
    final endpoint = OpenAiCompatibleEndpoint.parse(input);
    expect(endpoint.uri, isNull, reason: 'input=$input');
    return endpoint.error!;
  }

  group('валидные адреса', () {
    test('облачный сервер без завершающего слеша', () {
      expect(
        validUri('https://api.deepseek.com').toString(),
        'https://api.deepseek.com/chat/completions',
      );
    });

    test('завершающий слеш не даёт двойного слеша', () {
      expect(
        validUri('https://api.deepseek.com/').toString(),
        'https://api.deepseek.com/chat/completions',
      );
    });

    test('локальный сервер с /v1 сохраняет версию API', () {
      expect(
        validUri('http://localhost:11434/v1').toString(),
        'http://localhost:11434/v1/chat/completions',
      );
      expect(
        validUri('http://localhost:1234/v1/').toString(),
        'http://localhost:1234/v1/chat/completions',
      );
    });

    test('префикс пути сохраняется', () {
      expect(
        validUri('https://proxy.example.com/openai/v1').toString(),
        'https://proxy.example.com/openai/v1/chat/completions',
      );
    });

    test('полный endpoint /chat/completions не дублируется', () {
      expect(
        validUri('https://api.example.com/v1/chat/completions').toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        validUri('https://api.example.com/chat/completions/').toString(),
        'https://api.example.com/chat/completions',
      );
    });

    test('пробелы вокруг адреса обрезаются, порт сохраняется', () {
      expect(
        validUri('  http://127.0.0.1:8080/v1  ').toString(),
        'http://127.0.0.1:8080/v1/chat/completions',
      );
    });
  });

  group('невалидные адреса', () {
    test('пустой/пробельный адрес — empty', () {
      expect(errorOf(''), OpenAiCompatibleEndpointError.empty);
      expect(errorOf('   '), OpenAiCompatibleEndpointError.empty);
    });

    test('без схемы/невалидный URI — unsupportedScheme или invalid', () {
      expect(
        errorOf('api.example.com/v1'),
        OpenAiCompatibleEndpointError.unsupportedScheme,
      );
      expect(errorOf('https://'), OpenAiCompatibleEndpointError.invalid);
      expect(errorOf('://плохо'), OpenAiCompatibleEndpointError.invalid);
    });

    test('не http/https — unsupportedScheme', () {
      for (final input in <String>[
        'ftp://example.com',
        'file:///tmp/model',
        'ws://localhost:1234/v1',
      ]) {
        expect(
          errorOf(input),
          OpenAiCompatibleEndpointError.unsupportedScheme,
          reason: input,
        );
      }
    });

    test('userinfo в URL запрещён — credentials', () {
      expect(
        errorOf('https://user:secret@example.com/v1'),
        OpenAiCompatibleEndpointError.credentials,
      );
    });

    test('query и fragment запрещены — invalid', () {
      expect(
        errorOf('https://example.com/v1?key=secret'),
        OpenAiCompatibleEndpointError.invalid,
      );
      expect(
        errorOf('https://example.com/v1#fragment'),
        OpenAiCompatibleEndpointError.invalid,
      );
    });
  });

  test('isValid согласован с error', () {
    expect(OpenAiCompatibleEndpoint.parse('https://x.test').isValid, isTrue);
    expect(OpenAiCompatibleEndpoint.parse('').isValid, isFalse);
  });
}
