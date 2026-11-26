// Диагностический скрипт пайплайна генерации карточек.
//
// Делает **реальный** запрос к DeepSeek тем же системным промптом и с теми же
// параметрами, что приложение: тема «трансформаторы», 10 карточек, strict-схема
// A8.4, `max_tokens=8192`, лестница совместимости ADR-021 (strict → без
// `response_format`). Печатает статус-код и сырое тело ответа, затем разбирает
// его тем же экстрактором и схемой, что production-путь.
//
// Ключ читается только из окружения (`DEEPSEEK_API_KEY`) и нигде не печатается.
//
// Запуск:
//   $env:DEEPSEEK_API_KEY = [Environment]::GetEnvironmentVariable(
//     'DEEPSEEK_API_KEY', 'User')
//   fvm dart run tool/debug_generation.dart
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/cards_json_extractor.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';

Future<void> main() async {
  final String? key = Platform.environment['DEEPSEEK_API_KEY'];
  if (key == null || key.trim().isEmpty) {
    stderr.writeln(
      'DEEPSEEK_API_KEY отсутствует в окружении — запуск невозможен.',
    );
    exitCode = 1;
    return;
  }

  const String model = 'deepseek-flash';
  const String baseUrl = 'https://api.deepseek.com';
  const int maxOutputTokens = 8192;
  const int limit = 10;
  const String topic = 'трансформаторы';

  final String userContent = buildGenerationUserContent(
    materialsText: '',
    wishes: topic,
    limit: limit,
  );
  print('=== запрос приложения: тема="$topic", карточек=$limit ===');
  print('system prompt: $systemPromptVersion');
  print('userContent:\n$userContent');

  final OpenAiCompatibleAdapter adapter = const OpenAiCompatibleAdapter();
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 180),
    ),
  );

  final List<({String label, bool strictSchema})> attempts =
      <({String label, bool strictSchema})>[
        (label: 'strict + max_tokens', strictSchema: true),
        (label: 'без response_format + max_tokens', strictSchema: false),
      ];

  for (final attempt in attempts) {
    final ProviderRequest request = adapter.buildRequest(
      apiKey: key.trim(),
      model: model,
      systemPrompt: systemPromptGenRuV9,
      userContent: userContent,
      maxOutputTokens: maxOutputTokens,
      baseUrl: baseUrl,
      strictSchema: attempt.strictSchema,
      sendMaxTokens: true,
    );
    final String body = jsonEncode(request.body);
    print('\n=== попытка: ${attempt.label} ===');
    print('POST ${request.uri}');
    print('bytes=${utf8.encode(body).length} max_tokens=$maxOutputTokens');

    final Stopwatch stopwatch = Stopwatch()..start();
    final Response<dynamic> response = await dio.postUri<dynamic>(
      request.uri,
      data: body,
      options: Options(
        headers: request.headers,
        responseType: ResponseType.plain,
        validateStatus: (int? status) => status != null && status < 600,
      ),
    );
    stopwatch.stop();
    final String raw = '${response.data ?? ''}';
    print(
      'status=${response.statusCode} elapsed=${stopwatch.elapsedMilliseconds}ms '
      'bytes=${raw.length}',
    );
    print('RAW BODY:\n$raw');

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        print('\n--- ответ 400: пробуем следующий шаг лестницы ---');
        continue;
      }
      return;
    }

    // Тело ответа провайдера → content модели → JSON карточек → схема A8.4.
    final Map<String, Object?> envelope =
        jsonDecode(raw) as Map<String, Object?>;
    final ProviderRawResponse parsed;
    try {
      parsed = adapter.parseResponse(envelope);
    } on Object catch (error) {
      print('\nРАЗБОР: ошибка ответа провайдера: ${error.runtimeType}: $error');
      return;
    }
    print('\nMODEL CONTENT:\n${parsed.cardsJson}');

    final Object? decoded;
    try {
      decoded = const CardsJsonExtractor().decode(
        parsed.cardsJson,
        tolerant: true,
      );
    } on Object catch (error) {
      print('\nРАЗБОР: ошибка JSON: ${error.runtimeType}: $error');
      return;
    }
    final CardPayloadValidation payload = CardResponseSchema().splitValid(
      decoded,
    );
    print(
      '\nРАЗБОР: cards=${payload.cards.length} '
      'rejected=${payload.rejectedCards} rootInvalid=${payload.rootInvalid}',
    );
    for (final Object? card in payload.cards.take(2)) {
      final String json = jsonEncode(card);
      final String short = json.length <= 200
          ? json
          : '${json.substring(0, 200)}…';
      print('  карточка: $short');
    }
    return;
  }
}
