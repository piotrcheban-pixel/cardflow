import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_v3_path.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/prompts/cards_prompt.dart';
import 'package:cardflow/api/prompts/understanding_prompt.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_run_store.dart';
import 'package:cardflow/data/generation/drift_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../helpers/generation_fakes.dart';

/// Срез 11, часть 3: production-проводка пути v3 на реальной drift-БД и
/// фейковом HTTP-транспорте (без сети). Проверяет п. 7–9:
/// - второй прогон того же материала **не делает запросов Understanding**
///   (кэш карты в БД подключён к проводке, а не только к сервису);
/// - отчёт [GenerationRunResult.report] доезжает до результата прогона.
void main() {
  late AppDatabase database;
  late _RoutingTransport transport;

  setUp(() {
    database = AppDatabase.inMemory();
    transport = _RoutingTransport();
  });

  tearDown(() async {
    await database.close();
  });

  GenerationV3PathRunner runner() => GenerationV3PathRunner(
    apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': 'sk-test'}),
    transport: transport,
    runStore: DriftGenerationRunStore(database),
    knowledgeMapCache: DriftKnowledgeMapCache(database),
    importer: (String runId, String? deckId, String deckName) async => 0,
    clock: const _FixedClock(),
  );

  GenerationRunRequest requestOf() {
    const String text =
        'Момент силы равен произведению силы на плечо.\n'
        'Импульс тела равен произведению массы на скорость.';
    return GenerationRunRequest(
      documents: <ParsedDocument>[
        ParsedDocument(
          format: DocumentFormat.txt,
          fileName: 'лекция.txt',
          text: text,
          sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
        ),
      ],
      account: testProviderAccount(modelId: 'deepseek-chat'),
      deckName: 'Колода',
      requestedCards: 1,
    );
  }

  test(
    'второй прогон не платит за Understanding, отчёт в результате',
    () async {
      final GenerationV3PathRunner path = runner();

      final GenerationRunResult first = await path.run(
        requestOf(),
        runId: 'run-v3-1',
        cancellation: GenerationCancellation(),
      );

      expect(transport.mapCalls, 1, reason: 'первый прогон понимает материал');
      expect(transport.cardCalls, 1);
      expect(first.report, isNotNull, reason: 'отчёт доезжает до результата');
      expect(first.report!.requested, 1);
      expect(first.report!.accepted, 1);
      expect(first.report!.isComplete, isTrue);
      expect(first.cards, hasLength(1));
      expect(
        first.report!.tokensByStage.keys,
        contains(GenerationStage.understanding),
        reason: 'usage Understanding в отчёте',
      );

      final GenerationRunResult second = await path.run(
        requestOf(),
        runId: 'run-v3-2',
        cancellation: GenerationCancellation(),
      );

      expect(
        transport.mapCalls,
        1,
        reason: 'повторный материал берёт карту из кэша БД',
      );
      expect(transport.cardCalls, 2, reason: 'генерация снова просит карточки');
      expect(second.report, isNotNull);
      expect(second.report!.accepted, 1);
    },
  );
}

/// Транспорт без сети: отвечает на Understanding и Generation по промпту.
class _RoutingTransport implements GenerationTransport {
  int mapCalls = 0;
  int cardCalls = 0;

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    final List<Object?> messages = request.body['messages']! as List<Object?>;
    final String system =
        (messages.first! as Map<String, Object?>)['content']! as String;
    if (system == understandingSystemPromptGenMapV1) {
      mapCalls++;
      return _openAiResponse(_mapJson(messages));
    }
    cardCalls++;
    expect(system, cardsSystemPromptGenCardsV3);
    return _openAiResponse(_cardsJson(messages));
  }

  static Map<String, Object?> _openAiResponse(String content) =>
      <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': content},
            'finish_reason': 'stop',
          },
        ],
        'usage': <String, Object?>{
          'prompt_tokens': 50,
          'completion_tokens': 25,
          'total_tokens': 75,
        },
      };

  /// Карта: одна единица на первый блок раздела.
  static String _mapJson(List<Object?> messages) {
    final String user =
        (messages[1]! as Map<String, Object?>)['content']! as String;
    final RegExpMatch first = RegExp('<block id="([^"]+)">([^<]+)</block>')
        .firstMatch(user)!;
    return jsonEncode(<String, Object?>{
      'units': <Map<String, Object?>>[
        <String, Object?>{
          'section_id': null,
          'topic': 'тема',
          'kind': 'fact',
          'statement': first.group(2),
          'anchors': <Map<String, Object?>>[
            <String, Object?>{
              'block_id': first.group(1),
              'quote': first.group(2),
            },
          ],
          'salience': 0.9,
          'splittable': false,
        },
      ],
    });
  }

  /// Карточки: по одной на каждую строку `<card unit_id="…" angle="…"/>`.
  static String _cardsJson(List<Object?> messages) {
    final String user =
        (messages[1]! as Map<String, Object?>)['content']! as String;
    final RegExpMatch statement = RegExp('<statement>([^<]+)</statement>')
        .firstMatch(user)!;
    final List<Map<String, Object?>> cards = <Map<String, Object?>>[
      for (final RegExpMatch card in RegExp(
        '<card unit_id="([^"]+)" angle="([^"]+)"',
      ).allMatches(user))
        <String, Object?>{
          'front': 'Вопрос по утверждению: что известно?',
          'back': statement.group(1),
          'card_type': 'basic',
          'unit_id': card.group(1),
          'angle': card.group(2),
          'quote_ref': statement.group(1),
        },
    ];
    return jsonEncode(<String, Object?>{'cards': cards});
  }
}

/// Фиксированные часы прогона.
class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2026, 11, 28, 12);
}
