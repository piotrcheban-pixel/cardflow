import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../helpers/generation_fakes.dart';

/// Срез 9, п. 4: те же 4 сценария на старом и новом пути.
///
/// Пути отличаются флагом `pipelineV3` на **одной** проводке пайплайна: старый
/// отбрасывает почти-дубли и выводит статус прежними правилами, новый помечает
/// дубли, считает вердикт по журналу и собирает метрики. Числа таблицы — факт
/// прогона, они же источник `journal/iteration-8/summary.md`.
void main() {
  ParsedDocument docOf(String text) {
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: 'лекция.txt',
      text: text,
      sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
    );
  }

  GenerationResult resultOf(
    List<GeneratedCard> cards, {
    int promptTokens = 1000,
    int completionTokens = 500,
  }) => GenerationResult(
    provider: GenerationProvider.openai,
    model: 'test',
    promptVersion: systemPromptVersion,
    cards: cards,
    usage: TokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: promptTokens + completionTokens,
    ),
  );

  // Короткие и непохожие факты: почти-дубль по триграммам здесь не возникает
  // (правило пайплайна: стороны короче 12 букв не сравниваются), поэтому
  // сценарии различают именно точные дубли и намеренную почти-пару.
  const List<String> facts = <String>[
    'Атом',
    'Молекула',
    'Давление',
    'Температура',
    'Энергия',
    'Импульс',
    'Масса',
    'Сила',
    'Работа',
    'Мощность',
    'Плотность',
    'Объём',
    'Скорость',
    'Ускорение',
    'Траектория',
    'Частота',
    'Период',
    'Амплитуда',
    'Волна',
    'Фотон',
    'Заряд',
    'Ток',
    'Напряжение',
    'Сопротивление',
    'Ёмкость',
    'Индукция',
    'Поток',
    'Поле',
    'Вакуум',
    'Газ',
    'Жидкость',
    'Твёрдое',
    'Кристалл',
    'Изотоп',
    'Протон',
    'Нейтрон',
    'Электрон',
    'Квант',
    'Спектр',
    'Лазер',
  ];

  GeneratedCard card(int ordinal) => GeneratedCard(
    front: facts[ordinal % facts.length],
    back: 'Ответ ',
    cardType: CardType.basic,
  );

  final String materials = List<String>.generate(
    40,
    (int index) => 'Строка материала $index с содержательным утверждением',
  ).join('\n');

  /// Сценарий: имя, заказ, сколько карточек вернуть на запрос, [failSecond].
  final List<_Scenario> scenarios = <_Scenario>[
    _Scenario(
      name: 'заказ 20, материала достаточно',
      requested: 20,
      perCall: 20,
    ),
    _Scenario(
      name: 'заказ 40, модель отдаёт меньше',
      requested: 40,
      perCall: 9,
    ),
    _Scenario(
      name: 'заказ 20, дубли и почти-дубли',
      requested: 20,
      perCall: 4,
      duplicates: true,
    ),
    _Scenario(
      name: 'заказ 20, сбой второго запроса',
      requested: 20,
      perCall: 4,
      failSecond: true,
    ),
  ];

  for (final _Scenario scenario in scenarios) {
    test('${scenario.name}: было → стало', () async {
      final List<String> rows = <String>[];
      for (final bool v3 in <bool>[false, true]) {
        final FakeGenerationCaller caller = FakeGenerationCaller();
        caller.onGenerate = (GenerationRequest request, int call) async {
          if (scenario.failSecond && call == 2) {
            throw StateError('provider down');
          }
          final List<GeneratedCard> cards = <GeneratedCard>[
            for (var index = 0; index < scenario.perCall; index++)
              card((call - 1) * scenario.perCall + index),
          ];
          if (scenario.duplicates && call == 1) {
            // Точный дубль и намеренная почти-пара в одном ответе.
            cards.add(cards.first);
            cards.add(
              const GeneratedCard(
                front: 'Что такое интервальное повторение карточек',
                back: 'Метод с растущими интервалами',
                cardType: CardType.basic,
              ),
            );
            cards.add(
              const GeneratedCard(
                front: 'Что такое интервальное повторение карточек?',
                back: 'Повторение по расписанию',
                cardType: CardType.basic,
              ),
            );
          }
          return resultOf(cards);
        };
        final GenerationPipeline pipeline = GenerationPipeline(
          caller: caller,
          jobRepository: FakeGenerationJobRepository(),
          cardStore: FakeGenerationCardStore(),
          now: () => DateTime.utc(2026, 11, 28, 10),
          jobIdFactory: () => v3 ? 'job-v3' : 'job-v1',
          pipelineV3: v3,
        );
        final GenerationRunResult result = await pipeline.run(
          GenerationRunRequest(
            documents: <ParsedDocument>[docOf(materials)],
            account: testProviderAccount(modelId: 'deepseek-chat'),
            deckName: 'Колода',
            requestedCards: scenario.requested,
          ),
        );
        rows.add(
          '${v3 ? 'v3' : 'v1'}: status=${result.status.name}, '
          'accepted=${result.cards.length}/${scenario.requested}, '
          'marked=${result.possibleDuplicates}, '
          'dupsDropped=${result.duplicatesRemoved}, '
          'done=${result.verdict?.isDone ?? 'n/a'}, '
          'yield1k=${result.metrics.yieldPerThousandInputTokens.toStringAsFixed(2)}, '
          'accept=${result.metrics.acceptanceRate?.toStringAsFixed(2) ?? '-'}, '
          'dupRate=${result.metrics.duplicateRate?.toStringAsFixed(2) ?? '-'}, '
          'req10=${result.metrics.requestsPerTenCards?.toStringAsFixed(2) ?? '-'}, '
          'p50=${result.metrics.p50BatchDuration?.inMilliseconds}ms',
        );
        if (!v3) {
          // Старый путь не знает пометок: всё, что почти-дубль, отброшено.
          if (scenario.duplicates) {
            expect(result.possibleDuplicates, 0);
            expect(result.duplicatesRemoved, greaterThan(0));
            expect(
              result.cards.where(
                (GeneratedCard value) =>
                    value.issues.contains(CardIssueCode.possibleDuplicate),
              ),
              isEmpty,
            );
          }
        } else {
          // Новый путь: пометка вместо удаления и вердикт по журналу.
          if (scenario.duplicates) {
            expect(result.possibleDuplicates, greaterThan(0));
            expect(
              result.cards
                  .where(
                    (GeneratedCard value) =>
                        value.issues.contains(CardIssueCode.possibleDuplicate),
                  )
                  .isNotEmpty,
              isTrue,
            );
          }
          if (result.cards.length < scenario.requested) {
            expect(result.verdict?.isDone, isFalse);
            expect(result.status, GenerationJobStatus.partial);
            expect(result.verdict?.shortfall, greaterThan(0));
          }
        }
      }
      // ignore: avoid_print — таблица отчёта снимается из вывода теста.
      print('СЦЕНАРИЙ «${scenario.name}»\n  ${rows.join('\n  ')}');
    });
  }
}

class _Scenario {
  const _Scenario({
    required this.name,
    required this.requested,
    required this.perCall,
    this.duplicates = false,
    this.failSecond = false,
  });

  final String name;
  final int requested;
  final int perCall;
  final bool duplicates;
  final bool failSecond;
}
